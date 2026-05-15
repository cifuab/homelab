# OPNsense + Proxmox VLAN Lab Validation Runbook

## 1. Purpose

This runbook is used after building the Proxmox + OPNsense VLAN lab.

Use it to validate that every layer works:

```text
Proxmox bridge
OPNsense interfaces
VLAN tagging
DHCP
DNS
Firewall rules
NAT
Internet access
Inter-VLAN access
Guest isolation
Management access
```

This document is intentionally practical. It is designed as a checklist you can follow during troubleshooting or interview preparation.

---

## 2. Expected VLAN State

| VLAN | Name | Subnet | Gateway | Example device |
|---:|---|---|---|---|
| 10 | MGMT | `192.168.10.0/24` | `192.168.10.1` | Admin VM / admin laptop |
| 20 | SERVERS | `192.168.20.0/24` | `192.168.20.1` | Windows Server |
| 30 | CLIENTS | `192.168.30.0/24` | `192.168.30.1` | Windows 11 |
| 40 | GUEST | `192.168.40.0/24` | `192.168.40.1` | Guest VM / test client |
| untagged | LAN | `192.168.1.0/24` | `192.168.1.1` | Emergency OPNsense access |

---

## 3. Expected Proxmox Configuration

### OPNsense VM

| NIC | Bridge | VLAN tag | Purpose |
|---|---|---:|---|
| net0 | `vmbr0` | empty | WAN |
| net1 | `vmbr1` | empty | LAN trunk |

### Windows Server VM

| NIC | Bridge | VLAN tag | Purpose |
|---|---|---:|---|
| netX | `vmbr1` | `20` | SERVERS VLAN |

### Windows 11 VM

| NIC | Bridge | VLAN tag | Purpose |
|---|---|---:|---|
| netX | `vmbr1` | `30` | CLIENTS VLAN |

### Guest VM

| NIC | Bridge | VLAN tag | Purpose |
|---|---|---:|---|
| netX | `vmbr1` | `40` | GUEST VLAN |

### Proxmox bridge `vmbr1`

`vmbr1` must be VLAN-aware:

```text
auto vmbr1
iface vmbr1 inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094
```

Apply changes without reboot:

```bash
ifreload -a
```

---

## 4. Layer-by-Layer Validation Model

Use this order when troubleshooting:

```text
Layer 1: VM NIC attached to correct Proxmox bridge
Layer 2: VLAN tag correct
Layer 3: DHCP address correct
Layer 4: Gateway reachable
Layer 5: Firewall rule allows traffic
Layer 6: DNS works
Layer 7: Internet/application access works
```

Do not start with browser testing. Start with IP, gateway, and DNS.

---

## 5. Validation Checklist: SERVERS VLAN 20

Run on Windows Server:

```cmd
ipconfig /all
```

Expected:

```text
IPv4 Address:    192.168.20.x
Subnet Mask:     255.255.255.0
Default Gateway: 192.168.20.1
DHCP Server:     192.168.20.1
DNS Server:      192.168.20.1 or 192.168.20.10
```

Test gateway:

```cmd
ping 192.168.20.1
```

Test internet routing:

```cmd
ping 8.8.8.8
```

Test DNS:

```cmd
nslookup google.com
```

---

## 6. Validation Checklist: CLIENTS VLAN 30

Run on Windows 11:

```cmd
ipconfig /all
```

Expected:

```text
IPv4 Address:    192.168.30.x
Subnet Mask:     255.255.255.0
Default Gateway: 192.168.30.1
DHCP Server:     192.168.30.1
DNS Server:      192.168.30.1 or 192.168.20.10
```

Test gateway:

```cmd
ping 192.168.30.1
```

Test internet routing:

```cmd
ping 8.8.8.8
```

Test DNS:

```cmd
nslookup google.com
```

Test Windows Server access:

```powershell
Test-NetConnection 192.168.20.10 -Port 53
Test-NetConnection 192.168.20.10 -Port 445
Test-NetConnection 192.168.20.10 -Port 3389
```

---

## 7. Validation Checklist: GUEST VLAN 40

Run on guest test machine:

```cmd
ipconfig /all
```

Expected:

```text
IPv4 Address:    192.168.40.x
Subnet Mask:     255.255.255.0
Default Gateway: 192.168.40.1
DHCP Server:     192.168.40.1
DNS Server:      192.168.40.1
```

Allowed tests:

```cmd
ping 192.168.40.1
ping 8.8.8.8
nslookup google.com
```

Blocked tests:

```cmd
ping 192.168.20.10
ping 192.168.30.1
ping 192.168.10.1
```

Expected:

```text
Guest should reach internet.
Guest should not reach internal VLANs.
```

---

## 8. OPNsense UI Access Rules

Use the gateway IP of the network you are currently on:

| Your client IP | OPNsense UI |
|---|---|
| `192.168.1.x` | `https://192.168.1.1` |
| `192.168.10.x` | `https://192.168.10.1` |
| `192.168.20.x` | `https://192.168.20.1` |
| `192.168.30.x` | `https://192.168.30.1` |
| `192.168.40.x` | `https://192.168.40.1` |

If the UI does not open:

1. Check your IP.
2. Ping the gateway.
3. Check firewall rule on that VLAN.
4. Use LAN emergency access if locked out.

---

## 9. Common Problems and Diagnosis

### Problem: `169.254.x.x`

Meaning:

```text
DHCP failed.
```

Check:

```text
VM NIC VLAN tag
vmbr1 VLAN-aware
OPNsense VLAN parent = vtnet1
DHCP range exists
Dnsmasq listens on VLAN interface
Proxmox firewall checkbox is unchecked
Correct Windows adapter is active
```

### Problem: Can ping gateway but not internet

Meaning:

```text
VLAN and DHCP work.
Routing/NAT/firewall may be wrong.
```

Check:

```text
Firewall rule on VLAN interface
Outbound NAT
OPNsense WAN gateway
FritzBox connectivity
```

### Problem: Can ping 8.8.8.8 but cannot browse

Meaning:

```text
Internet routing works.
DNS is broken.
```

Check:

```cmd
nslookup google.com
```

Check DHCP DNS server:

```cmd
ipconfig /all
```

Check OPNsense DNS service:

```text
Services → Dnsmasq DNS & DHCP
Services → Unbound DNS
```

### Problem: Cannot access OPNsense UI

Use the gateway IP for your current VLAN:

| Client IP | OPNsense UI |
|---|---|
| `192.168.1.x` | `https://192.168.1.1` |
| `192.168.10.x` | `https://192.168.10.1` |
| `192.168.20.x` | `https://192.168.20.1` |
| `192.168.30.x` | `https://192.168.30.1` |
| `192.168.40.x` | `https://192.168.40.1` |

If the firewall blocks it, use LAN/emergency access and add rules.

---

## 10. Firewall Log Troubleshooting

Go to:

```text
Firewall → Log Files → Live View
```

Filter by source IP:

```text
192.168.30.193
192.168.20.10
192.168.40.x
```

Look for:

```text
blocked
pass
interface
destination
port
```

If you see traffic blocked on `CLIENTS`, create or adjust rules under:

```text
Firewall → Rules → CLIENTS
```

If blocked on `SERVERS`, adjust:

```text
Firewall → Rules → SERVERS
```

---

## 11. Recommended Troubleshooting Flow

When something fails, ask:

```text
1. What IP does the client have?
2. Is it the expected VLAN subnet?
3. Can it ping its own gateway?
4. Does OPNsense have a DHCP lease for it?
5. Does the firewall live log show blocked traffic?
6. Does DNS resolve?
7. Does NAT allow internet?
8. Is another Windows adapter taking priority?
```

---

## 12. Windows Multi-NIC Warning

Windows may have multiple adapters:

```text
Ethernet          → FritzBox / 192.168.0.x
Ethernet 2        → 169.254.x.x
Ethernet 3        → VLAN lab / 192.168.30.x
Tailscale         → 100.x.x.x
```

For clean testing, disable unused adapters.

Show adapters:

```powershell
Get-NetAdapter
```

Disable direct FritzBox adapter:

```powershell
Disable-NetAdapter -Name "Ethernet" -Confirm:$false
```

Enable it again:

```powershell
Enable-NetAdapter -Name "Ethernet" -Confirm:$false
```

---

## 13. Minimal Working Rules for Lab Testing

### CLIENTS

```text
Action: Pass
Interface: CLIENTS
Direction: in
Protocol: any
Source: CLIENTS network
Destination: any
Description: Allow CLIENTS to any
```

### SERVERS

```text
Action: Pass
Interface: SERVERS
Direction: in
Protocol: any
Source: SERVERS network
Destination: any
Description: Allow SERVERS to any
```

### GUEST

```text
Rule 1:
Action: Block
Interface: GUEST
Direction: in
Protocol: any
Source: GUEST network
Destination: RFC1918_NETWORKS
Description: Block GUEST to internal networks

Rule 2:
Action: Pass
Interface: GUEST
Direction: in
Protocol: any
Source: GUEST network
Destination: any
Description: Allow GUEST to internet
```

### MGMT

```text
Action: Pass
Interface: MGMT
Direction: in
Protocol: any
Source: MGMT network
Destination: any
Description: Allow MGMT to any
```

After this works, tighten rules.

---

## 14. Final Validation Table

| Test | Expected |
|---|---|
| Windows Server gets `192.168.20.x` | DHCP on VLAN 20 works |
| Windows 11 gets `192.168.30.x` | DHCP on VLAN 30 works |
| Guest gets `192.168.40.x` | DHCP on VLAN 40 works |
| Server pings `192.168.20.1` | Server gateway works |
| Client pings `192.168.30.1` | Client gateway works |
| Guest pings `192.168.40.1` | Guest gateway works |
| Client pings `8.8.8.8` | Client internet routing/NAT works |
| Client resolves `google.com` | DNS works |
| Guest cannot ping server | Guest isolation works |
| Client cannot reach MGMT | Management protection works |
| MGMT reaches Proxmox | Admin access works |

---

## 15. Interview Story

You can explain this runbook like this:

> I validated the network layer by layer instead of guessing. First I confirmed that Proxmox VLAN tagging and bridge VLAN-awareness worked. Then I checked DHCP leases per VLAN, gateway reachability, OPNsense interface status, firewall logs, DNS resolution, NAT, and finally application access. This helped me separate problems such as DHCP failure, DNS failure, firewall blocking, NAT issues, and Windows multi-adapter routing confusion.

---

## 16. One-Line Mental Model

```text
Correct VLAN IP → ping gateway → DNS works → firewall allows → NAT works → application works
```
