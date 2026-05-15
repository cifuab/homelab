# OPNsense Firewall Setup

## 1. Purpose

This document describes the step-by-step setup of **OPNsense** as the firewall/router layer for the homelab environment.

The goal is to provide:

- Central firewall and routing control
- LAN/WAN separation
- DHCP and DNS services
- VLAN-ready network design
- Secure management access
- Foundation for monitoring and future automation

---

## 2. Target Architecture

```text
                    Internet / ISP Router
                            |
                            |
                         WAN NIC
                      +-------------+
                      |  OPNsense   |
                      |  Firewall   |
                      +-------------+
                         LAN NIC
                            |
                            |
                      Homelab Switch
                            |
        ------------------------------------------------
        |                    |                         |
     Jumpbox              Proxmox                 Kubernetes Nodes
  192.168.30.x        192.168.30.x              192.168.30.x
```

---

## 3. Assumptions

This guide assumes:

- OPNsense is already installed
- OPNsense has at least two interfaces:
  - `WAN`
  - `LAN`
- The LAN network uses:

```text
LAN subnet: 192.168.30.0/24
OPNsense LAN IP: 192.168.30.1
```

Adjust the IP addresses if your environment uses a different subnet.

---

## 4. Initial Access

After installation, access the OPNsense web UI from a machine on the LAN:

```text
https://192.168.30.1
```

Default login:

```text
Username: root
Password: opnsense
```

> Change the default password immediately after first login.

---

## 5. Change Admin Password

Go to:

```text
System → Access → Users
```

Edit the `root` user and set a strong password.

Recommended password rules:

- Minimum 16 characters
- Uppercase and lowercase letters
- Numbers
- Special characters
- Store in a password manager

---

## 6. Configure LAN Interface

Go to:

```text
Interfaces → LAN
```

Recommended LAN settings:

```text
Enable interface: Yes
IPv4 Configuration Type: Static IPv4
IPv4 Address: 192.168.30.1/24
IPv6 Configuration Type: None or DHCPv6 if required
```

Save and apply changes.

---

## 7. Configure WAN Interface

Go to:

```text
Interfaces → WAN
```

Common WAN options:

### Option A: WAN via ISP Router DHCP

```text
IPv4 Configuration Type: DHCP
```

Use this if OPNsense receives an IP address from your home router.

### Option B: WAN Static IP

```text
IPv4 Configuration Type: Static IPv4
IPv4 Address: <WAN-IP>
Gateway: <ISP-GATEWAY>
```

Use this only if your ISP or upstream router provides static addressing.

Save and apply changes.

---

## 8. Configure DHCP for LAN

Go to:

```text
Services → ISC DHCPv4 → LAN
```

Enable DHCP on LAN:

```text
Enable DHCP server on LAN interface: Yes
```

Example DHCP range:

```text
From: 192.168.30.100
To:   192.168.30.200
```

Recommended static/manual IP range:

```text
192.168.30.2   - 192.168.30.49    Infrastructure
192.168.30.50  - 192.168.30.99    Servers / Kubernetes / Proxmox
192.168.30.100 - 192.168.30.200   DHCP clients
192.168.30.201 - 192.168.30.254   Reserved / future use
```

Save and apply.

---

## 9. Suggested IP Plan

| Component | Example IP | Notes |
|---|---:|---|
| OPNsense LAN | `192.168.30.1` | Default gateway |
| Proxmox host | `192.168.30.10` | Virtualization host |
| Jumpbox | `192.168.30.20` | Admin machine |
| Talos control plane 1 | `192.168.30.31` | Kubernetes control plane |
| Talos control plane 2 | `192.168.30.32` | Kubernetes control plane |
| Talos control plane 3 | `192.168.30.33` | Kubernetes control plane |
| Talos worker 1 | `192.168.30.41` | Kubernetes worker |
| Talos worker 2 | `192.168.30.42` | Kubernetes worker |

---

## 10. Configure DNS Resolver

Go to:

```text
Services → Unbound DNS → General
```

Enable Unbound:

```text
Enable Unbound: Yes
Listen Port: 53
Network Interfaces: LAN
```

Recommended options:

```text
Register DHCP leases: Yes
Register DHCP static mappings: Yes
```

This allows DHCP hostnames to be resolved locally.

Example:

```bash
ping proxmox.local
ping jumpbox.local
```

---

## 11. Configure System DNS

Go to:

```text
System → Settings → General
```

Recommended DNS servers:

```text
1.1.1.1
8.8.8.8
```

Or use privacy-focused resolvers:

```text
9.9.9.9
1.1.1.1
```

Recommended setting:

```text
Allow DNS server list to be overridden by DHCP/PPP on WAN: No
```

---

## 12. LAN Firewall Rules

Go to:

```text
Firewall → Rules → LAN
```

Default LAN rule usually allows LAN clients to access any destination.

Example default LAN rule:

```text
Action: Pass
Interface: LAN
Protocol: Any
Source: LAN net
Destination: Any
Description: Allow LAN to any
```

This is acceptable for the initial homelab setup.

Later, this can be hardened into:

- Admin VLAN
- Server VLAN
- Kubernetes VLAN
- Guest VLAN
- IoT VLAN

---

## 13. WAN Firewall Rules

Go to:

```text
Firewall → Rules → WAN
```

By default, inbound WAN traffic should be blocked.

Recommended baseline:

```text
No public inbound access unless explicitly required.
```

Avoid exposing:

- OPNsense Web UI
- Proxmox UI
- Kubernetes API
- SSH
- Grafana
- Longhorn UI

If remote access is required, use VPN instead.

---

## 14. Enable SSH Access to OPNsense

Go to:

```text
System → Settings → Administration
```

Enable SSH only if needed:

```text
Enable Secure Shell: Yes
Permit root user login: No
Password login: No, if using SSH keys
Listen Interfaces: LAN only
```

Recommended:

```text
Allow SSH only from jumpbox/admin machine.
```

Example firewall rule:

```text
Action: Pass
Interface: LAN
Protocol: TCP
Source: Jumpbox IP
Destination: This Firewall
Destination Port: 22
Description: Allow SSH from Jumpbox to OPNsense
```

---

## 15. Secure Web UI Access

Go to:

```text
System → Settings → Administration
```

Recommended:

```text
Protocol: HTTPS
TCP Port: 443
Listen Interfaces: LAN
```

Do not expose the web UI on WAN.

Optional hardening:

```text
Disable web GUI redirect rule: Yes
Session timeout: 15-30 minutes
```

---

## 16. Configure Static DHCP Mappings

Go to:

```text
Services → ISC DHCPv4 → LAN
```

Under DHCP leases, add static mappings for important systems.

Recommended static mappings:

| Host | IP |
|---|---:|
| `proxmox` | `192.168.30.10` |
| `jumpbox` | `192.168.30.20` |
| `talos-cp1` | `192.168.30.31` |
| `talos-cp2` | `192.168.30.32` |
| `talos-cp3` | `192.168.30.33` |
| `talos-w1` | `192.168.30.41` |
| `talos-w2` | `192.168.30.42` |

This makes the network easier to document, troubleshoot, and monitor.

---

## 17. Basic Connectivity Validation

From the jumpbox or any LAN machine:

### Check local gateway

```bash
ping -c 4 192.168.30.1
```

Expected result:

```text
Replies from OPNsense LAN IP
```

### Check internet connectivity

```bash
ping -c 4 1.1.1.1
```

Expected result:

```text
Internet routing works
```

### Check DNS resolution

```bash
nslookup google.com
```

Or:

```bash
dig google.com
```

Expected result:

```text
DNS resolves successfully
```

### Check default route

```bash
ip route
```

Expected default route:

```text
default via 192.168.30.1 dev <interface>
```

Example:

```text
default via 192.168.30.1 dev ens18
```

---

## 18. Validate OPNsense Interfaces

From the OPNsense web UI:

```text
Interfaces → Overview
```

Verify:

| Interface | Expected Status |
|---|---|
| WAN | Up |
| LAN | Up |
| WAN IP | Assigned |
| LAN IP | `192.168.30.1/24` |

---

## 19. Validate DHCP Leases

Go to:

```text
Services → ISC DHCPv4 → Leases
```

Check that LAN devices receive IP addresses from the configured DHCP range.

Expected:

```text
Clients receive 192.168.30.100 - 192.168.30.200
Gateway is 192.168.30.1
DNS is 192.168.30.1 or configured resolver
```

---

## 20. Validate Firewall Logs

Go to:

```text
Firewall → Log Files → Live View
```

Useful filters:

```text
Source IP: 192.168.30.x
Destination port: 53
Destination port: 443
Action: Block
```

Use this during troubleshooting to verify whether traffic is being passed or blocked.

---

## 21. Recommended First Firewall Hardening

After basic connectivity works, begin tightening access.

### Allow LAN to Internet

```text
Source: LAN net
Destination: Any
Protocol: Any
Action: Pass
```

### Allow Admin Access to Firewall

```text
Source: Jumpbox IP
Destination: This Firewall
Ports: 22, 443
Action: Pass
```

### Block Other Access to Firewall Management

```text
Source: LAN net
Destination: This Firewall
Ports: 22, 443
Action: Block
```

Place allow rules above block rules.

---

## 22. Optional: VLAN Design

Future VLAN design:

| VLAN | Name | Example Subnet | Purpose |
|---:|---|---|---|
| 10 | Management | `192.168.10.0/24` | Proxmox, OPNsense, switches |
| 20 | Servers | `192.168.20.0/24` | Linux servers |
| 30 | Kubernetes | `192.168.30.0/24` | Talos/Kubernetes nodes |
| 40 | Monitoring | `192.168.40.0/24` | Grafana, Prometheus, Loki |
| 50 | Guest | `192.168.50.0/24` | Guest devices |
| 60 | IoT | `192.168.60.0/24` | Cameras, smart devices |

Recommended security direction:

```text
Management VLAN can access all required systems.
Server/Kubernetes VLANs have restricted access.
Guest and IoT VLANs cannot access management systems.
```

---

## 23. Optional: Install Useful OPNsense Plugins

Go to:

```text
System → Firmware → Plugins
```

Recommended plugins:

| Plugin | Purpose |
|---|---|
| `os-theme-cicada` | Optional UI theme |
| `os-net-snmp` | SNMP monitoring |
| `os-telegraf` | Metrics export to InfluxDB/Prometheus-style stacks |
| `os-nginx` | Reverse proxy use cases |
| `os-acme-client` | Let's Encrypt certificates |
| `os-wireguard` | VPN access |
| `os-ddclient` | Dynamic DNS |

For the homelab, the most useful first plugins are:

```text
os-net-snmp
os-telegraf
os-wireguard
```

---

## 24. Optional: Enable SNMP for Monitoring

Install plugin:

```text
System → Firmware → Plugins → os-net-snmp
```

Then configure:

```text
Services → Net-SNMP
```

Recommended:

```text
Enable SNMP: Yes
Listen Interface: LAN
Community: <strong-community-string>
```

Restrict access to monitoring server only.

Example firewall rule:

```text
Action: Pass
Interface: LAN
Protocol: UDP
Source: Monitoring Server IP
Destination: This Firewall
Destination Port: 161
Description: Allow SNMP from monitoring server
```

---

## 25. Optional: Enable Telegraf Metrics

Install plugin:

```text
System → Firmware → Plugins → os-telegraf
```

Use this if exporting OPNsense metrics into a monitoring stack.

Possible metrics:

- CPU usage
- Memory usage
- Interface traffic
- Packet drops
- Firewall states
- Disk usage
- Gateway status

---

## 26. Backup OPNsense Configuration

Go to:

```text
System → Configuration → Backups
```

Download a backup after major changes.

Recommended naming:

```text
opnsense-backup-YYYY-MM-DD.xml
```

Example:

```text
opnsense-backup-2026-05-15.xml
```

Store backups securely.

---

## 27. Troubleshooting Checklist

### Problem: LAN client cannot reach OPNsense

Check:

```bash
ip addr
ip route
ping -c 4 192.168.30.1
```

Possible causes:

- Wrong IP subnet
- Wrong interface
- Cable/switch issue
- LAN interface down
- Duplicate IP address

### Problem: LAN client can reach OPNsense but not internet

Check:

```bash
ping -c 4 192.168.30.1
ping -c 4 1.1.1.1
ip route
```

Check in OPNsense:

```text
Interfaces → Overview
System → Routes → Status
Firewall → Log Files → Live View
```

Possible causes:

- WAN interface has no IP
- Missing default gateway
- NAT issue
- Firewall rule blocking traffic
- Upstream router issue

### Problem: Internet works by IP but DNS fails

Check:

```bash
ping -c 4 1.1.1.1
nslookup google.com
dig google.com
```

Check in OPNsense:

```text
Services → Unbound DNS → General
System → Settings → General
Firewall → Rules → LAN
```

Possible causes:

- DNS resolver disabled
- Wrong DNS server
- Firewall blocking port 53
- Client using wrong DNS server

### Problem: Cannot access OPNsense Web UI

Check:

```bash
ping -c 4 192.168.30.1
curl -k https://192.168.30.1
```

Possible causes:

- Web UI listening on another port
- Access restricted by firewall rule
- Client not on allowed network
- Browser certificate warning

### Problem: Device gets wrong IP address

Check:

```bash
ip addr
ip route
cat /etc/resolv.conf
```

On OPNsense:

```text
Services → ISC DHCPv4 → Leases
```

Possible causes:

- Another DHCP server exists on the network
- Static IP configured on the client
- DHCP range misconfigured
- Client connected to wrong network/VLAN

---

## 28. Useful Linux Validation Commands

### Interface and IP check

```bash
ip addr
```

### Routing check

```bash
ip route
```

### Gateway test

```bash
ping -c 4 192.168.30.1
```

### Internet test

```bash
ping -c 4 1.1.1.1
```

### DNS test

```bash
dig google.com
```

### Trace route

```bash
traceroute 1.1.1.1
```

If traceroute is not installed:

```bash
sudo apt update
sudo apt install traceroute -y
```

### Check listening services

```bash
ss -tulpen
```

### Check ARP/neighbour table

```bash
ip neigh
```

---

## 29. Operational Notes

Recommended operating model:

```text
Change → Validate → Document → Backup
```

For every firewall or network change:

1. Record what changed
2. Validate connectivity
3. Check logs
4. Update documentation
5. Export OPNsense backup

---

## 30. Next Steps

Recommended next improvements:

- Add VLANs for management, servers, Kubernetes, guest, and IoT
- Add WireGuard VPN for secure remote access
- Add SNMP or Telegraf monitoring
- Send firewall logs to Loki/OpenSearch
- Build Grafana dashboards for firewall health and network traffic
- Document firewall rules as part of infrastructure runbooks
- Add configuration backups to a secure Git/private storage workflow

---

## 31. Summary

OPNsense is now the central network security and routing layer for the homelab.

Current baseline:

```text
OPNsense LAN IP: 192.168.30.1
LAN subnet:      192.168.30.0/24
DHCP:            Enabled
DNS Resolver:    Enabled
WAN:             DHCP or static, depending on upstream router
Firewall:        LAN allowed outbound, WAN inbound blocked
```

This setup provides the foundation for a more enterprise-style network design with VLANs, VPN, monitoring, logging, and controlled access between infrastructure zones.
