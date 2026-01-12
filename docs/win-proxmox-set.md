## After Installing ISO
### SPICE Guest Tools + QEMU Guest Agent (and ideally VirtIO drivers)

---

1) Switch the VM to SPICE-friendly display (Proxmox UI)

- On Proxmox for that Windows VM:
  - Shutdown the Windows VM (not reboot). 
  - Go to VM → Hardware → Display 
    - Set Graphic card to VirtIO-GPU (or QXL if VirtIO-GPU isn’t available/working). 
    - Set Console to SPICE. 
  - Go to VM → Options 
    - Ensure QEMU Guest Agent = Enabled (you already enabled agent, good).

- Start the VM again and open console using Console → SPICE (better than noVNC for resizing).

2) Mount VirtIO driver ISO (Proxmox UI)

- Your screenshot shows the Windows ISO is still mounted as CD Drive (D:). 
  - VM → Hardware → CD/DVD Drive 
  - Click Edit 
  - Select virtio-win.iso (upload it first to local → ISO Images if you don’t have it there)
  - Check “Connected” 
  - OK

- Now Windows will see a new CD with VirtIO content.

3) Install the tools inside Windows

- Inside Windows Explorer, open the VirtIO CD and run:
  - virtio-win-guest-tools.exe ✅ (this is the easiest “one installer”)

- That typically installs:
  - VirtIO drivers (storage/network depending)
  - QEMU Guest Agent 
  - Often SPICE agent components (depends on bundle)

- Reboot Windows after installation.

4) If full screen still doesn’t auto-resize

- Install SPICE Guest Tools (this is what gives smooth resize + better mouse integration):
  - Download/install spice-guest-tools inside Windows (it includes spice-vdagent). 
  - Reboot again.

- After that, when using SPICE console, your resolution should auto-resize and full-screen will work properly.

5) Quick checks

- In Windows:
  - Open Services → confirm QEMU Guest Agent service is running. 
  - If using SPICE tools, confirm SPICE vdagent is running.

- In Proxmox:
  - VM → Summary should start showing the VM IP and clean shutdowns when agent works.

#### After reboot, do this checklist

- Reboot Windows 
- In Proxmox, open the VM with Console → SPICE (not noVNC)
- If resize still doesn’t follow your window size:
  - Install SPICE Guest Tools / spice-vdagent (that’s the part that really does dynamic resize)
  - Reboot once more

#### SPICE connection file (`pve-spice.vv`) for full-screen + auto-resize.

- Click Open for pve-spice.vv 
- If Windows asks “open with what?” → choose Remote Viewer (virt-viewer)
  - If you don’t have it installed yet: install [virt-viewer](https://virt-manager.org/download.html) for Windows (often called Remote Viewer).

- When it opens, you’ll be connected via SPICE.

- Then enable auto-resize / full screen

- Inside the Remote Viewer window:
  - Go to View → Scale Display (enable it)
  - Then View → Full Screen 
  - Also check: View → Auto resize guest (wording can differ slightly)

- If it still doesn’t resize after that

- That means the guest-side resize agent isn’t active yet.

- Do this in the Windows VM:
  - Confirm QEMU Guest Agent is installed/running (you installed virtio guest tools, good)
  - Install SPICE Guest Tools (this includes spice-vdagent)
  - Reboot Windows VM

- Why this works 
  - noVNC is limited for dynamic resolution. 
  - SPICE + virt-viewer + spice-vdagent is the “full experience” (resize, clipboard, better mouse).

#### Issue Pinging Windowa VM
- Quick PowerShell test (run as Admin):
```shell
Get-NetConnectionProfile
```
- If it shows NetworkCategory : Public, switch to Private:
```shell
Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
```
- If it’s still blocked, explicitly allow ICMP ping in firewall
```shell
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
Enable-NetFirewallRule -Name FPS-ICMP4-ERQ-In
```
- If the second command errors, no problem — the first one usually enables the needed ICMP rules depending on language/edition.)

- You can also list the ICMP rules:
```shell
Get-NetFirewallRule | ? DisplayName -match "Echo Request|ICMP"
```
- Quick “prove it” test (temporarily disable firewall for Private only)
```shell
Set-NetFirewallProfile -Profile Private -Enabled False
```
- Ping from jumpbox. If it works now, the issue is 100% firewall rules/profile.

- Re-enable right after:
```shell
Set-NetFirewallProfile -Profile Private -Enabled True
```
- If you cannot switch off Public (policy / weird adapter state)

- Then just allow ping on Public too (temporary test):
```shell
Set-NetFirewallProfile -Profile Public -Enabled False
```
- Ping test, then re-enable:
```shell
Set-NetFirewallProfile -Profile Public -Enabled True
```

#### SSH from jumpbox to the Windows VM
- Install + start OpenSSH Server on Windows (PowerShell as Admin)
```shell
# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start + enable at boot
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Optional (recommended): ensure ssh-agent is enabled (useful for keys)
Start-Service ssh-agent
Set-Service -Name ssh-agent -StartupType Automatic

# Allow SSH through Windows Firewall
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```
- Verify its listening
```shell
Get-Service sshd
netstat -ano | findstr :22
```
- SSH from jumpbox

- Use the Windows local account format. Since your `whoami` is:

`win-qq4dg1qav0l\administrator`
```shell
ssh administrator@<WINDOWS_IP>
```
- Prefer key-based login (recommended)

- On jumpbox:
```shell
ssh-keygen -t ed25519 -C "jumpbox"
ssh-copy-id administrator@<WINDOWS_IP>
```
- If ssh-copy-id isn’t available, do it manually:
```shell
cat ~/.ssh/id_ed25519.pub
```
- On Windows (PowerShell), create the authorized_keys:
```shell
mkdir $env:ProgramData\ssh -Force | Out-Null
notepad $env:ProgramData\ssh\administrators_authorized_keys
```
- Paste the public key on one line, save.

- Then set permissions (important):
```shell
icacls $env:ProgramData\ssh\administrators_authorized_keys /inheritance:r
icacls $env:ProgramData\ssh\administrators_authorized_keys /grant "Administrators:F"
icacls $env:ProgramData\ssh\administrators_authorized_keys /grant "SYSTEM:F"
```
- Restart SSH:
```shell
Restart-Service sshd
```
- Now from Jumpbox
```shell
ssh administrator@<WINDOWS_IP>
```
#### Tailscale Recommended
- Edit `/etc/samba/smb.conf` inside `fileserver01`:
```shell
[global]
interfaces = lo tailscale0
bind interfaces only = yes

# Optional hardening:
server min protocol = SMB2
client min protocol = SMB2
```
- Restart Samba:
```shell
systemctl restart smbd
```
- Firewalld: allow Samba only on trusted (tailscale)

If `trusted` already applies to `tailscale0`, then just ensure Samba is allowed in that zone:
```shell
firewall-cmd --permanent --zone=trusted --add-service=samba
firewall-cmd --reload
```
- Confirm Samba is NOT reachable on LAN (good)

- From Windows VM:
```shell
Test-NetConnection 192.168.0.51 -Port 445   # should FAIL (if you want tailscale-only)
Test-NetConnection 100.x.x.x -Port 445      # should PASS
```
- still want LAN access, do it securely (NOT /24 trusted)
```shell
# Allow only the Windows VM IP to connect to SMB
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.179/32" port protocol="tcp" port="445" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.179/32" port protocol="tcp" port="139" accept'
firewall-cmd --reload
```

