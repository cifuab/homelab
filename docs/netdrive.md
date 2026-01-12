### Samba Troubleshooting steps

1) First: prove which path works (LAN vs Tailscale) for SMB (port 445)

You already saw something weird: ping to 192.168.0.51 works, but nc says “No route to 
host” on 445 → that almost always means 445 is blocked (firewall) or Samba isn’t listening on that interface.

Run these two checks from the jumpbox:
```shell
nc -vz 192.168.0.51 445
nc -vz 100.85.211.128 445
```
- If Tailscale 100.85… works, mount via Tailscale.

- If both fail, fix Samba/firewall on fileserver first (see step 3).

2) Mount it again (recommended mount options)
- If port 445 works on LAN (192.168.0.51)
```shell
sudo mkdir -p /mnt/data
sudo mount -t cifs //192.168.0.51/data /mnt/data \
  -o username=smbuser,vers=3.0,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0664,dir_mode=0775,noperm
```
- If port 445 works on Tailscale (100.85.211.128)
```shell
sudo mkdir -p /mnt/data
sudo mount -t cifs //100.85.211.128/data /mnt/data \
  -o username=smbuser,vers=3.0,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0664,dir_mode=0775,noperm
```
- If it prompts for a password and you want it non-interactive, use a credentials file:
```shell
cat > ~/.smbcredentials <<'EOF'
username=smbuser
password=YOUR_PASSWORD_HERE
EOF
chmod 600 ~/.smbcredentials
```
- Then mount with:
```shell
sudo mount -t cifs //192.168.0.51/data /mnt/data \
  -o credentials=/home/jumpbox/.smbcredentials,vers=3.0,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0664,dir_mode=0775,noperm
```
- After mounting, verify:
```shell
mount | grep -i cifs
ls -la /mnt/data
touch /mnt/data/test_from_jumpbox.txt
```
3) If 445 is failing: fix fileserver (most likely cause)

- On fileserver01 (container/VM), check:
```shell
sudo ss -lntp | grep ':445'
sudo systemctl status smbd --no-pager -l
sudo ufw status || true
```
What you want:

- ss shows Samba listening on 0.0.0.0:445 (or at least on 192.168.0.51:445 and/or 100.85...:445)

- firewall allows 445

If Samba is only listening on the Tailscale IP, your smb.conf may be binding interfaces. Look for something like:

- interfaces = ...

- bind interfaces only = yes

If you find that, either include the LAN IP/interface too, or remove the restriction, then restart Samba:
```shell
sudo systemctl restart smbd
```
4) Make it survive reboots (optional but recommended)

- Once mount works, add an /etc/fstab entry (example for LAN + credentials):
```shell
sudo nano /etc/fstab
```
- Add:
```shell
//192.168.0.51/data  /mnt/data  cifs  credentials=/home/jumpbox/.smbcredentials,vers=3.0,uid=1000,gid=1000,iocharset=utf8,file_mode=0664,dir_mode=0775,noperm,_netdev,x-systemd.automount,nofail  0  0
```
- Then:
```shell
sudo systemctl daemon-reload
sudo mount -a
```