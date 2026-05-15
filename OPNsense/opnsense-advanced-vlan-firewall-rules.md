# Advanced OPNsense Firewall Rules for Proxmox VLAN Lab

## 1. Purpose

This document extends the basic OPNsense VLAN lab into a more realistic **enterprise-style firewall policy design**.

It covers firewall rules for:

- **MGMT VLAN 10**
- **SERVERS VLAN 20**
- **CLIENTS VLAN 30**
- **GUEST VLAN 40**
- Optional **LAN / emergency access network**
- Internet access
- Inter-VLAN access
- DNS/DHCP behavior
- Management access
- Guest isolation
- Server protection
- Client-to-server access
- Rule ordering
- Troubleshooting

The goal is to move from:

```text
Allow everything
```

to:

```text
Allow only what is needed
Block what should not be reachable
Keep management protected
Allow internet safely
Make the network easy to explain in interviews
```

---

## 2. Target VLAN Design

| VLAN | Name | Subnet | Gateway | Purpose |
|---:|---|---|---|---|
| 10 | MGMT | `192.168.10.0/24` | `192.168.10.1` | Admin devices, Proxmox, OPNsense management, infrastructure access |
| 20 | SERVERS | `192.168.20.0/24` | `192.168.20.1` | Windows Server, DNS, AD DS, file services, internal apps |
| 30 | CLIENTS | `192.168.30.0/24` | `192.168.30.1` | Windows 11 clients / normal user devices |
| 40 | GUEST | `192.168.40.0/24` | `192.168.40.1` | Guest devices, internet only |
| 1 / untagged | LAN | `192.168.1.0/24` | `192.168.1.1` | Temporary/emergency lab access only |

---

## 3. High-Level Network Architecture

```text
                           Internet
                              |
                              |
                    FritzBox / Home Router
                         192.168.0.1
                              |
                              |
                        Proxmox vmbr0
                    WAN / Home Network Side
                              |
                              |
                    OPNsense WAN - vtnet0
                         192.168.0.57
                              |
                              |
                    +-------------------+
                    |     OPNsense      |
                    | Firewall / Router |
                    | DHCP / DNS / NAT  |
                    +-------------------+
                              |
                              |
                    OPNsense LAN - vtnet1
                    Proxmox vmbr1 VLAN trunk
                              |
        ------------------------------------------------
        |                  |              |             |
      VLAN 10            VLAN 20        VLAN 30       VLAN 40
      MGMT               SERVERS        CLIENTS       GUEST
  192.168.10.0/24   192.168.20.0/24 192.168.30.0/24 192.168.40.0/24
        |                  |              |             |
   Admin device       Windows Server   Windows 11     Guest device
   Proxmox admin      AD / DNS / SMB   User client    Internet only
```

---

## 4. Traffic Flow Concept

### 4.1 Client to Internet

```text
Windows 11
192.168.30.x
    |
    | enters OPNsense on CLIENTS interface
    v
OPNsense CLIENTS gateway
192.168.30.1
    |
    | firewall rule allows CLIENTS net to internet
    v
OPNsense WAN
192.168.0.57
    |
    | NAT
    v
FritzBox
192.168.0.1
    |
    v
Internet
```

Rule location:

```text
Firewall → Rules → CLIENTS
Direction: in
```

---

### 4.2 Client to Server

```text
Windows 11
192.168.30.x
    |
    | enters OPNsense on CLIENTS
    v
OPNsense routes to SERVERS
    |
    v
Windows Server
192.168.20.10
```

Rule location:

```text
Firewall → Rules → CLIENTS
Direction: in
```

Why?

Because traffic from the client enters OPNsense through the CLIENTS interface.

---

### 4.3 Server to Internet

```text
Windows Server
192.168.20.x
    |
    | enters OPNsense on SERVERS
    v
OPNsense WAN
    |
    v
Internet
```

Rule location:

```text
Firewall → Rules → SERVERS
Direction: in
```

---

### 4.4 Guest to Internet

```text
Guest device
192.168.40.x
    |
    | enters OPNsense on GUEST
    v
OPNsense WAN
    |
    v
Internet
```

Rule location:

```text
Firewall → Rules → GUEST
Direction: in
```

Guest must **not** reach:

```text
MGMT
SERVERS
CLIENTS
LAN
Proxmox
OPNsense management
```

---

## 5. Important Firewall Rule Logic

### 5.1 Rules are evaluated top to bottom

OPNsense checks firewall rules in order.

```text
Rule 1 checked first
Rule 2 checked second
Rule 3 checked third
...
First match wins
```

So place specific allow/block rules above broad allow rules.

Example:

```text
1. Block GUEST to private networks
2. Allow GUEST to internet
```

If you reverse the order:

```text
1. Allow GUEST to any
2. Block GUEST to private networks
```

the block rule may never be reached.

---

### 5.2 Most interface rules use direction `in`

Even when traffic is going to the internet, the packet first enters OPNsense through the VLAN interface.

So for normal VLAN rules use:

```text
Direction: in
```

Examples:

| Traffic | Rule interface | Direction |
|---|---|---|
| CLIENTS → Internet | CLIENTS | in |
| CLIENTS → SERVERS | CLIENTS | in |
| SERVERS → Internet | SERVERS | in |
| GUEST → Internet | GUEST | in |
| MGMT → Proxmox | MGMT | in |

---

### 5.3 `network` vs `address`

In OPNsense dropdowns:

| Option | Meaning |
|---|---|
| `CLIENTS address` | Only the firewall IP on that interface, e.g. `192.168.30.1` |
| `CLIENTS network` | The whole subnet, e.g. `192.168.30.0/24` |
| `SERVERS address` | Only `192.168.20.1` |
| `SERVERS network` | Whole server subnet `192.168.20.0/24` |

For normal source rules, use:

```text
CLIENTS network
SERVERS network
MGMT network
GUEST network
```

---

## 6. Recommended Aliases

Before building complex firewall rules, create aliases.

Go to:

```text
Firewall → Aliases
```

Aliases make rules easier to read and maintain.

---

### 6.1 RFC1918 Private Networks Alias

Create alias:

```text
Name: RFC1918_NETWORKS
Type: Network(s)
```

Content:

```text
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
```

Purpose:

```text
Block guest access to all private/internal networks.
```

---

### 6.2 Internal VLAN Networks Alias

Create alias:

```text
Name: INTERNAL_VLANS
Type: Network(s)
```

Content:

```text
192.168.10.0/24
192.168.20.0/24
192.168.30.0/24
192.168.40.0/24
192.168.1.0/24
```

Purpose:

```text
Represent all internal lab networks.
```

---

### 6.3 Management Hosts Alias

Create alias:

```text
Name: MGMT_HOSTS
Type: Host(s)
```

Example content:

```text
192.168.10.10
192.168.10.11
```

Use this for trusted admin machines.

---

### 6.4 Infrastructure Hosts Alias

Create alias:

```text
Name: INFRA_HOSTS
Type: Host(s)
```

Example content:

```text
192.168.10.2      # Proxmox
192.168.10.1      # OPNsense MGMT gateway
192.168.20.10     # Windows Server / Domain Controller
```

Adjust IPs based on your actual setup.

---

### 6.5 Windows Server Alias

Create alias:

```text
Name: WINDOWS_SERVER
Type: Host(s)
```

Content:

```text
192.168.20.10
```

If your Windows Server currently gets DHCP like `192.168.20.162`, either:

1. Create a static DHCP reservation, or
2. Set a static IP on the server

Recommended final server IP:

```text
192.168.20.10
```

---

### 6.6 Admin Ports Alias

Create alias:

```text
Name: ADMIN_PORTS
Type: Port(s)
```

Content:

```text
22
443
8006
3389
```

Meaning:

| Port | Purpose |
|---:|---|
| 22 | SSH |
| 443 | HTTPS |
| 8006 | Proxmox Web UI |
| 3389 | RDP |

---

### 6.7 AD Required Ports Alias

Create alias:

```text
Name: AD_CLIENT_PORTS
Type: Port(s)
```

Content:

```text
53
88
123
135
389
445
464
636
3268
3269
```

Meaning:

| Port | Purpose |
|---:|---|
| 53 | DNS |
| 88 | Kerberos |
| 123 | NTP |
| 135 | RPC Endpoint Mapper |
| 389 | LDAP |
| 445 | SMB |
| 464 | Kerberos password change |
| 636 | LDAPS |
| 3268 | Global Catalog |
| 3269 | Global Catalog SSL |

For full AD domain join, dynamic RPC ports may also be needed.

Dynamic RPC range on modern Windows can use:

```text
49152-65535
```

For learning, you may temporarily allow CLIENTS to the Windows Server with protocol `any`, then tighten later.

---

## 7. Baseline Firewall Policy

The desired policy:

| Source | Destination | Decision |
|---|---|---|
| MGMT | All internal networks | Allow |
| MGMT | Internet | Allow |
| SERVERS | Internet | Allow limited or broad for lab |
| SERVERS | MGMT | Block |
| SERVERS | CLIENTS | Usually block unless needed |
| CLIENTS | Internet | Allow |
| CLIENTS | Windows Server | Allow required services |
| CLIENTS | MGMT | Block |
| CLIENTS | SERVERS | Restricted |
| GUEST | Internet | Allow |
| GUEST | Internal networks | Block |
| WAN | Internal networks | Block by default |

---

## 8. MGMT VLAN 10 Rules

MGMT is the trusted admin network.

Go to:

```text
Firewall → Rules → MGMT
```

Recommended rule order:

```text
1. Allow MGMT to OPNsense management
2. Allow MGMT to Proxmox management
3. Allow MGMT to SERVERS
4. Allow MGMT to CLIENTS if needed
5. Allow MGMT to internet
```

---

### Rule 1 — Allow MGMT to OPNsense Web UI

| Field | Value |
|---|---|
| Action | Pass |
| Interface | MGMT |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP |
| Source | MGMT network |
| Destination | MGMT address |
| Destination port | 443 |
| Description | Allow MGMT to OPNsense Web UI |

This allows:

```text
https://192.168.10.1
```

---

### Rule 2 — Allow MGMT to Proxmox Web UI

If Proxmox is reachable through MGMT network, for example:

```text
Proxmox IP: 192.168.10.2
```

| Field | Value |
|---|---|
| Action | Pass |
| Interface | MGMT |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP |
| Source | MGMT network |
| Destination | Single host: `192.168.10.2` |
| Destination port | 8006 |
| Description | Allow MGMT to Proxmox Web UI |

---

### Rule 3 — Allow MGMT SSH to infrastructure

| Field | Value |
|---|---|
| Action | Pass |
| Interface | MGMT |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP |
| Source | MGMT network |
| Destination | INFRA_HOSTS |
| Destination port | 22 |
| Description | Allow MGMT SSH to infrastructure |

---

### Rule 4 — Allow MGMT RDP to Windows Server

| Field | Value |
|---|---|
| Action | Pass |
| Interface | MGMT |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP |
| Source | MGMT network |
| Destination | WINDOWS_SERVER |
| Destination port | 3389 |
| Description | Allow MGMT RDP to Windows Server |

---

### Rule 5 — Allow MGMT to all internal networks

For lab convenience:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | MGMT |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | MGMT network |
| Destination | INTERNAL_VLANS |
| Description | Allow MGMT to internal VLANs |

This is acceptable because MGMT is the admin network.

---

### Rule 6 — Allow MGMT to internet

| Field | Value |
|---|---|
| Action | Pass |
| Interface | MGMT |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | MGMT network |
| Destination | any |
| Description | Allow MGMT to internet |

Place this after more specific internal rules.

---

## 9. SERVERS VLAN 20 Rules

SERVERS should be more restricted than MGMT.

Go to:

```text
Firewall → Rules → SERVERS
```

Recommended rule order:

```text
1. Allow SERVERS DNS to OPNsense
2. Allow SERVERS NTP to OPNsense or internet
3. Allow SERVERS updates to internet
4. Block SERVERS to MGMT
5. Optional allow server responses/services
6. Final allow or restricted internet rule
```

---

### Rule 1 — Allow SERVERS to OPNsense DNS

If OPNsense provides DNS:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | SERVERS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP/UDP |
| Source | SERVERS network |
| Destination | SERVERS address |
| Destination port | 53 |
| Description | Allow SERVERS DNS to OPNsense |

---

### Rule 2 — Allow SERVERS to OPNsense gateway services

For basic lab access to gateway/DNS:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | SERVERS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | ICMP |
| Source | SERVERS network |
| Destination | SERVERS address |
| Description | Allow SERVERS ping gateway |

---

### Rule 3 — Block SERVERS to MGMT

This protects the admin network.

| Field | Value |
|---|---|
| Action | Block |
| Interface | SERVERS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | SERVERS network |
| Destination | MGMT network |
| Description | Block SERVERS to MGMT |

Place this above any broad allow rule.

---

### Rule 4 — Allow SERVERS to internet

Lab-friendly broad rule:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | SERVERS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | SERVERS network |
| Destination | any |
| Description | Allow SERVERS to internet |

More restrictive version:

```text
Allow TCP 80,443 only to any
Allow UDP 123 for NTP
Allow DNS 53 to OPNsense
```

---

### Recommended SERVERS Rule Order

```text
1. Allow SERVERS DNS to OPNsense
2. Allow SERVERS ping gateway
3. Block SERVERS to MGMT
4. Allow SERVERS to internet
```

---

## 10. CLIENTS VLAN 30 Rules

CLIENTS should access internet and required server services.

Go to:

```text
Firewall → Rules → CLIENTS
```

Recommended rule order:

```text
1. Allow CLIENTS DNS to OPNsense
2. Allow CLIENTS ping gateway
3. Allow CLIENTS to Windows Server required services
4. Block CLIENTS to MGMT
5. Block CLIENTS to other internal networks if desired
6. Allow CLIENTS to internet
```

---

### Rule 1 — Allow CLIENTS DNS to OPNsense

| Field | Value |
|---|---|
| Action | Pass |
| Interface | CLIENTS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP/UDP |
| Source | CLIENTS network |
| Destination | CLIENTS address |
| Destination port | 53 |
| Description | Allow CLIENTS DNS to OPNsense |

---

### Rule 2 — Allow CLIENTS ping gateway

| Field | Value |
|---|---|
| Action | Pass |
| Interface | CLIENTS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | ICMP |
| Source | CLIENTS network |
| Destination | CLIENTS address |
| Description | Allow CLIENTS ping gateway |

---

### Rule 3 — Allow CLIENTS to Windows Server for AD/DNS

If Windows Server is a domain controller/DNS server:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | CLIENTS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP/UDP |
| Source | CLIENTS network |
| Destination | WINDOWS_SERVER |
| Destination port | AD_CLIENT_PORTS |
| Description | Allow CLIENTS to Windows Server AD services |

For full domain join, you may also need dynamic RPC:

```text
TCP 49152-65535
```

---

### Rule 4 — Allow CLIENTS RDP to Windows Server

Only if needed:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | CLIENTS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP |
| Source | CLIENTS network |
| Destination | WINDOWS_SERVER |
| Destination port | 3389 |
| Description | Allow CLIENTS RDP to Windows Server |

For a stricter enterprise design, RDP should usually come from MGMT only, not all CLIENTS.

---

### Rule 5 — Block CLIENTS to MGMT

| Field | Value |
|---|---|
| Action | Block |
| Interface | CLIENTS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | CLIENTS network |
| Destination | MGMT network |
| Description | Block CLIENTS to MGMT |

Place above internet allow rule.

---

### Rule 6 — Block CLIENTS to GUEST

Usually clients do not need guest access.

| Field | Value |
|---|---|
| Action | Block |
| Interface | CLIENTS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | CLIENTS network |
| Destination | GUEST network |
| Description | Block CLIENTS to GUEST |

---

### Rule 7 — Allow CLIENTS to internet

Broad lab rule:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | CLIENTS |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | CLIENTS network |
| Destination | any |
| Description | Allow CLIENTS to internet |

More restrictive version:

```text
Allow TCP 80,443 to any
Allow DNS only to OPNsense
Allow NTP only if needed
```

---

### Recommended CLIENTS Rule Order

```text
1. Allow CLIENTS DNS to OPNsense
2. Allow CLIENTS ping gateway
3. Allow CLIENTS to Windows Server AD services
4. Allow CLIENTS RDP to Windows Server only if needed
5. Block CLIENTS to MGMT
6. Block CLIENTS to GUEST
7. Allow CLIENTS to internet
```

---

## 11. GUEST VLAN 40 Rules

Guest should be internet-only.

Go to:

```text
Firewall → Rules → GUEST
```

Recommended rule order:

```text
1. Allow GUEST DNS to OPNsense
2. Allow GUEST ping gateway optional
3. Block GUEST to RFC1918 private networks
4. Allow GUEST to internet
```

---

### Rule 1 — Allow GUEST DNS to OPNsense

| Field | Value |
|---|---|
| Action | Pass |
| Interface | GUEST |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | TCP/UDP |
| Source | GUEST network |
| Destination | GUEST address |
| Destination port | 53 |
| Description | Allow GUEST DNS to OPNsense |

---

### Rule 2 — Allow GUEST ping gateway optional

Optional but useful for troubleshooting:

| Field | Value |
|---|---|
| Action | Pass |
| Interface | GUEST |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | ICMP |
| Source | GUEST network |
| Destination | GUEST address |
| Description | Allow GUEST ping gateway |

---

### Rule 3 — Block GUEST to private/internal networks

Use the alias:

```text
RFC1918_NETWORKS
```

| Field | Value |
|---|---|
| Action | Block |
| Interface | GUEST |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | GUEST network |
| Destination | RFC1918_NETWORKS |
| Description | Block GUEST to private networks |

This blocks guest access to:

```text
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
```

Important:

Place this before the allow internet rule.

---

### Rule 4 — Allow GUEST to internet

| Field | Value |
|---|---|
| Action | Pass |
| Interface | GUEST |
| Direction | in |
| TCP/IP Version | IPv4 |
| Protocol | any |
| Source | GUEST network |
| Destination | any |
| Description | Allow GUEST to internet |

Because the previous rule blocks private networks first, this rule allows public internet access only.

---

### Recommended GUEST Rule Order

```text
1. Allow GUEST DNS to OPNsense
2. Allow GUEST ping gateway optional
3. Block GUEST to RFC1918_NETWORKS
4. Allow GUEST to internet
```

---

## 12. LAN / Emergency Access Rules

The untagged LAN `192.168.1.0/24` can be kept as emergency access.

Recommended:

```text
Use LAN only for temporary OPNsense access while building VLANs.
```

Go to:

```text
Firewall → Rules → LAN
```

For learning, LAN may already have a broad allow rule:

```text
Allow LAN net to any
```

Keep it until the VLAN design is stable.

Later, restrict LAN or remove usage.

---

## 13. WAN Rules

Do not allow management from WAN.

WAN is the FritzBox/home network side.

Avoid:

```text
Allow WAN to OPNsense Web UI
Allow WAN to internal networks
```

Default WAN block behavior is good.

If you need temporary WAN management for recovery, understand the risk and remove it afterward.

---

## 14. NAT Rules

By default, OPNsense usually has automatic outbound NAT enabled.

Check:

```text
Firewall → NAT → Outbound
```

Recommended for this lab:

```text
Mode: Automatic outbound NAT rule generation
```

This should NAT:

```text
192.168.10.0/24
192.168.20.0/24
192.168.30.0/24
192.168.40.0/24
```

out through WAN.

If internet does not work but gateway ping works, check NAT.

---

## 15. DNS Design Options

### Option A — OPNsense as DNS for all VLANs

DHCP gives:

```text
DNS Server: VLAN gateway
```

Examples:

```text
SERVERS DNS: 192.168.20.1
CLIENTS DNS: 192.168.30.1
GUEST DNS: 192.168.40.1
```

OPNsense forwards DNS upstream.

This is simple and good for early lab stages.

---

### Option B — Windows Server as DNS for domain clients

If Windows Server becomes AD DS / DNS:

```text
Windows Server IP: 192.168.20.10
```

Then CLIENTS DHCP should give:

```text
DNS Server: 192.168.20.10
```

Not OPNsense.

This is needed for domain join and AD name resolution.

In this case, CLIENTS firewall must allow DNS to Windows Server:

```text
CLIENTS network → WINDOWS_SERVER → TCP/UDP 53
```

---

## 16. DHCP Design Options

### Option A — OPNsense DHCP

OPNsense provides DHCP for each VLAN.

Good for learning VLAN/firewall basics.

### Option B — Windows Server DHCP

Windows Server provides DHCP.

This is better for Microsoft infrastructure practice.

If Windows Server provides DHCP for VLAN 30, you need DHCP relay on OPNsense:

```text
Services → DHCP Relay
```

But for the current lab, keep DHCP on OPNsense first.

---

## 17. Testing Matrix

### From MGMT

```cmd
ping 192.168.10.1
ping 192.168.20.10
ping 192.168.30.x
ping 8.8.8.8
nslookup google.com
```

Expected:

```text
MGMT can reach infrastructure and internet.
```

---

### From SERVERS

```cmd
ping 192.168.20.1
ping 8.8.8.8
nslookup google.com
ping 192.168.10.1
```

Expected:

```text
Can reach own gateway.
Can reach internet.
Should not reach MGMT if block rule exists.
```

---

### From CLIENTS

```cmd
ping 192.168.30.1
ping 8.8.8.8
nslookup google.com
ping 192.168.20.10
Test-NetConnection 192.168.20.10 -Port 53
Test-NetConnection 192.168.20.10 -Port 3389
ping 192.168.10.1
```

Expected:

```text
Can reach own gateway.
Can reach internet.
Can reach Windows Server only on allowed services.
Should not reach MGMT.
```

---

### From GUEST

```cmd
ping 192.168.40.1
ping 8.8.8.8
nslookup google.com
ping 192.168.20.10
ping 192.168.30.1
ping 192.168.10.1
```

Expected:

```text
Can reach own gateway.
Can reach internet.
Cannot reach SERVERS.
Cannot reach CLIENTS.
Cannot reach MGMT.
```

---

## 18. Useful Troubleshooting Commands

### Windows

```cmd
ipconfig /all
ipconfig /release
ipconfig /renew
ipconfig /flushdns
ping 192.168.30.1
ping 8.8.8.8
nslookup google.com
```

PowerShell:

```powershell
Get-NetAdapter
Get-NetIPConfiguration
Test-NetConnection 192.168.20.10 -Port 3389
Test-NetConnection 192.168.20.10 -Port 445
```

---

### OPNsense

Check firewall live logs:

```text
Firewall → Log Files → Live View
```

Filter by:

```text
source IP
destination IP
interface
blocked
```

Check interface status:

```text
Interfaces → Overview
```

Check DHCP leases:

```text
Services → Dnsmasq DNS & DHCP → Leases
```

Check routes:

```text
System → Routes → Status
```

Check DNS:

```text
Services → Unbound DNS
Services → Dnsmasq DNS & DHCP
```

---

### Proxmox

Check bridge config:

```bash
cat /etc/network/interfaces
```

Apply bridge config:

```bash
ifreload -a
```

Correct `vmbr1`:

```text
auto vmbr1
iface vmbr1 inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094
```

---

## 19. Common Problems and Fixes

### Problem: VLAN VM gets `169.254.x.x`

Meaning:

```text
DHCP failed.
```

Check:

```text
VM VLAN tag
vmbr1 VLAN-aware
OPNsense VLAN parent
DHCP range
Dnsmasq selected interfaces
Proxmox firewall checkbox
Wrong Windows adapter
```

---

### Problem: DHCP works but internet does not

Check:

```text
Firewall rule on VLAN interface
Outbound NAT
DNS configuration
WAN gateway
```

---

### Problem: Can ping 8.8.8.8 but cannot browse

Likely DNS issue.

Check:

```text
nslookup google.com
DNS server from ipconfig /all
Dnsmasq/Unbound status
```

---

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

### Problem: Proxmox firewall checkbox blocks traffic

For this lab, keep VM NIC firewall unchecked:

```text
Proxmox VM NIC → Firewall unchecked
```

Use OPNsense firewall rules for segmentation.

---

## 20. Recommended Final Rule Summary

### MGMT

```text
Allow MGMT to OPNsense Web UI
Allow MGMT to Proxmox Web UI
Allow MGMT SSH/RDP to infrastructure
Allow MGMT to internal VLANs
Allow MGMT to internet
```

### SERVERS

```text
Allow SERVERS DNS to OPNsense
Allow SERVERS ping gateway
Block SERVERS to MGMT
Allow SERVERS to internet
```

### CLIENTS

```text
Allow CLIENTS DNS to OPNsense or Windows DNS
Allow CLIENTS ping gateway
Allow CLIENTS to Windows Server required services
Block CLIENTS to MGMT
Block CLIENTS to GUEST
Allow CLIENTS to internet
```

### GUEST

```text
Allow GUEST DNS to OPNsense
Allow GUEST ping gateway optional
Block GUEST to RFC1918 private networks
Allow GUEST to internet
```

### WAN

```text
Default block
No management access from WAN
```

---

## 21. Business / Interview Explanation

You can explain the design like this:

> I built an OPNsense firewall in Proxmox with a WAN interface to the home router and a LAN trunk interface carrying multiple VLANs. I separated management, servers, clients, and guest devices into different subnets. OPNsense provided the gateway, DHCP, DNS, NAT, and firewall enforcement for each VLAN. I implemented rules so management can administer infrastructure, clients can access only required server services and the internet, servers are protected from unnecessary lateral access, and guests are isolated from all private networks while still having internet access. During troubleshooting I validated VLAN tagging, DHCP leases, DNS behavior, NAT, firewall rule direction, and Proxmox bridge VLAN awareness.

---

## 22. Security Maturity Path

### Level 1 — Basic learning

```text
Allow SERVERS to any
Allow CLIENTS to any
Allow GUEST to any
```

### Level 2 — Segmentation

```text
Block GUEST to RFC1918
Block CLIENTS to MGMT
Block SERVERS to MGMT
```

### Level 3 — Least privilege

```text
CLIENTS can reach only required server ports
SERVERS can reach only required update/DNS/NTP endpoints
MGMT is the only admin network
```

### Level 4 — Monitoring

```text
Enable logging on block rules
Review Firewall → Live View
Create dashboards later with logs
Alert on denied MGMT access attempts
```

---

## 23. Practical Build Order

Recommended order:

```text
1. Keep LAN emergency access working
2. Create VLAN 20 SERVERS
3. Add DHCP for SERVERS
4. Add broad SERVERS allow rule
5. Test Windows Server
6. Create VLAN 30 CLIENTS
7. Add DHCP for CLIENTS
8. Add broad CLIENTS allow rule
9. Test Windows 11
10. Create VLAN 10 MGMT
11. Move admin access to MGMT
12. Create VLAN 40 GUEST
13. Block GUEST to RFC1918
14. Tighten CLIENTS to SERVERS rules
15. Remove broad allow rules gradually
```

---

## 24. Final Mental Model

```text
VLAN separates devices.
Gateway routes between networks.
Firewall rules decide what is allowed.
NAT allows private networks to reach the internet.
DHCP gives IP addresses.
DNS resolves names.
MGMT controls infrastructure.
SERVERS host services.
CLIENTS consume services.
GUEST gets internet only.
```

