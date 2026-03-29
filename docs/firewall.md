# Firewall Reference Guide

Quick reference for all firewall backends in CCDC. Covers Linux (iptables, ufw, nft, firewalld), Windows Firewall, Palo Alto, and Cisco FTD.

> The `ccdc firewall` commands auto-detect the backend. This doc is the manual reference.

---

## Which Firewall Am I Using?

### Linux — Detect Backend

```bash
# Check what's installed/active
which ufw && ufw status 2>/dev/null
which firewall-cmd && firewall-cmd --state 2>/dev/null
which nft && nft list ruleset 2>/dev/null
which iptables && iptables -L -n 2>/dev/null
```

| Distro | Common Default |
|--------|---------------|
| Ubuntu/Debian | ufw (wraps iptables/nft) |
| Fedora/CentOS/RHEL/Oracle | firewalld (wraps nft) |
| Older CentOS/Debian | iptables directly |
| Newer kernels | nftables (nft) |

### Windows

```powershell
Get-NetFirewallProfile | Select Name, Enabled
```

### Appliances

- **Palo Alto** — Web GUI, policies-based
- **Cisco FTD** — Web GUI, zone-based
- **VyOS** — CLI, zone/rule-based

---

## iptables

### View Rules

```bash
iptables-save                          # Full dump of all tables/rules
iptables -L -n -v                      # List default table (filter)
iptables -t [table] -L -n -v           # List specific table (nat, mangle, raw)
iptables -L --line-numbers             # Rules with line numbers
```

### Default Policy

```bash
iptables -P INPUT DROP                 # Default deny inbound
iptables -P OUTPUT ACCEPT              # Default allow outbound
iptables -P FORWARD DROP               # Default deny forwarding
```

### Allow Inbound Port

```bash
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -j ACCEPT
```

### Essential Rules (always add before DROP policy)

```bash
iptables -A INPUT -i lo -j ACCEPT                                    # Loopback
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT  # Return traffic
```

### Block Outbound Port

```bash
iptables -A OUTPUT -p tcp --dport 443 -j DROP
```

### Block IP

```bash
iptables -A INPUT -s [IP_ADDRESS] -j DROP
```

### Allow Only Specific Inbound Ports (full example)

```bash
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT     # SSH (if needed)
iptables -A INPUT -p tcp --dport 80 -j ACCEPT     # HTTP
iptables -A INPUT -p tcp --dport 53 -j ACCEPT     # DNS TCP
iptables -A INPUT -p udp --dport 53 -j ACCEPT     # DNS UDP
iptables -P INPUT DROP                             # Drop everything else
```

### Insert / Replace / Delete

```bash
iptables -I INPUT [rule]               # Insert at top (position 1)
iptables -I INPUT [number] [rule]      # Insert at specific position
iptables -R INPUT [number] [new_rule]  # Replace rule at position
iptables -D INPUT [number]             # Delete by line number
iptables -F                            # Flush all rules (careful!)
```

### NAT

```bash
iptables -t nat -A POSTROUTING -o [interface] -j MASQUERADE
```

### Persist Rules

```bash
# Debian/Ubuntu
apt install iptables-persistent
netfilter-persistent save              # Save current rules
netfilter-persistent start             # Load saved rules
systemctl enable netfilter-persistent  # Auto-load on boot
```

### Undo

```bash
# Restore from backup
iptables-restore < /ccdc-backups/iptables.txt
```

---

## ufw

### View Rules

```bash
ufw status verbose                     # Active rules with policy
ufw status numbered                    # Rules with line numbers
ufw show raw                           # Raw netfilter rules
```

### Enable / Disable

```bash
ufw enable                             # Enable (auto-starts on boot)
ufw disable                            # Disable
ufw reset                              # Flush all rules and disable
ufw reload                             # Reload after config changes
```

### Default Policy

```bash
ufw default deny incoming              # Default deny inbound
ufw default allow outgoing             # Default allow outbound
```

### Allow Inbound Port

```bash
ufw allow 80/tcp
ufw allow 53/udp
ufw allow 22/tcp                       # SSH (if needed)
```

### Block Port

```bash
ufw deny 445/tcp                       # Block SMB inbound
```

### Block IP

```bash
ufw deny from [IP_ADDRESS]
```

### Full Rule Syntax

```bash
ufw [allow/deny/reject] [in/out] [proto tcp/udp] [from address] [to address] port [port]
```

### Insert / Delete

```bash
ufw insert 1 [rule]                    # Insert at top
ufw insert [number] [rule]             # Insert at position
ufw delete [number]                    # Delete by number
```

### Allow Specific Interface

```bash
ufw allow in on eth0
ufw allow in on lo                     # Loopback (auto-handled but explicit is fine)
```

### Undo

```bash
# ufw tracks rules by number
ufw status numbered
ufw delete [number]
```

---

## nftables (nft)

### View Rules

```bash
nft list ruleset                       # Full dump
nft list table [family] [table]        # Specific table
nft list ruleset -n                    # Numeric format
nft list table [family] [table] -n -a  # With handles (for insert/delete)
```

### Create Table and Chain

```bash
nft add table inet my_filter
nft add chain inet my_filter INPUT { type filter hook input priority 0 \; policy drop \; }
nft add chain inet my_filter OUTPUT { type filter hook output priority 0 \; policy accept \; }
```

### Allow Inbound Port

```bash
nft add rule inet my_filter INPUT tcp dport 80 accept
nft add rule inet my_filter INPUT udp dport 53 accept
```

### Essential Rules

```bash
nft add rule inet my_filter INPUT iif lo accept                              # Loopback
nft add rule inet my_filter INPUT ct state established,related accept        # Return traffic
```

### Block IP

```bash
nft add rule inet my_filter INPUT ip saddr [IP_ADDRESS] drop
```

### Block Outbound Port

```bash
nft add rule inet my_filter OUTPUT tcp dport 443 drop
```

### Insert / Delete

```bash
nft insert rule inet my_filter INPUT position [handle] [rule]   # Insert before handle
nft delete rule inet my_filter INPUT handle [handle]            # Delete by handle
nft flush chain inet my_filter INPUT                            # Flush chain
nft flush ruleset                                               # Flush everything
```

### Persist

```bash
nft list ruleset > /etc/nftables.conf
systemctl enable nftables
```

### Undo

```bash
# Restore from backup
nft -f /ccdc-backups/nft.txt
```

---

## firewalld

### View Rules

```bash
firewall-cmd --state                                    # Is it running?
firewall-cmd --list-all                                 # Default zone rules
firewall-cmd --list-all-zones                           # All zones
firewall-cmd --get-active-zones                         # Active zones and interfaces
firewall-cmd --zone=public --list-ports                 # Ports in zone
firewall-cmd --zone=public --list-services              # Services in zone
```

### Enable / Start

```bash
systemctl enable --now firewalld
```

### Allow Inbound Port

```bash
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-port=53/udp --permanent
firewall-cmd --reload
```

### Allow Inbound Service

```bash
firewall-cmd --zone=public --add-service=http --permanent
firewall-cmd --zone=public --add-service=dns --permanent
firewall-cmd --reload
```

### Remove Port / Service

```bash
firewall-cmd --zone=public --remove-port=445/tcp --permanent
firewall-cmd --zone=public --remove-service=cockpit --permanent
firewall-cmd --reload
```

### Block IP

```bash
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="[IP]" reject'
firewall-cmd --reload
```

### Set Default Zone to Drop

```bash
firewall-cmd --set-default-zone=drop
# Then add back only what you need
firewall-cmd --zone=drop --add-port=80/tcp --permanent
firewall-cmd --reload
```

### Undo

```bash
# Remove specific rule
firewall-cmd --zone=public --remove-port=80/tcp --permanent
firewall-cmd --reload

# Or restore config from backup
cp /ccdc-backups/firewalld/* /etc/firewalld/
firewall-cmd --reload
```

---

## Windows Firewall

### Enable Firewall

```powershell
Set-NetFirewallProfile Domain,Public,Private -Enabled True
```

### View Rules

```powershell
Get-NetFirewallRule | Select-Object DisplayName, Enabled, Direction, Action, Profile
```

### Allow Inbound Port

```powershell
New-NetFirewallRule `
    -DisplayName "Allow HTTP Inbound" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow
```

### Block Inbound Port

```powershell
New-NetFirewallRule `
    -DisplayName "Block SMB Inbound" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 445 `
    -Action Block
```

### Block Outbound Port

```powershell
New-NetFirewallRule `
    -DisplayName "Block TCP 443 Outbound" `
    -Direction Outbound `
    -Protocol TCP `
    -RemotePort 443 `
    -Action Block
```

### Block Port Range

```powershell
New-NetFirewallRule `
    -DisplayName "Block 5000-6000 Inbound" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5000-6000 `
    -Action Block
```

### Block Specific IP

```powershell
New-NetFirewallRule `
    -DisplayName "Block IP 192.168.1.50" `
    -Direction Inbound `
    -RemoteAddress 192.168.1.50 `
    -Protocol TCP `
    -Action Block
```

### Remove Rule

```powershell
Remove-NetFirewallRule -DisplayName "[rule name]"
```

### Undo

```powershell
# Remove by display name
Remove-NetFirewallRule -DisplayName "[name you set]"
```

---

## Palo Alto (Web GUI)

### Password Management

- [ ] **Change admin password:** `Device > Administrators > click [username] > change password > Commit`
- [ ] **Change local user password:** `Device > Local User Database > Users > click [username] > edit > Commit`
- [ ] **Add backup admin:** `Device > Administrators > Add (bottom right) > Commit`

### Backup and Restore

- [ ] **Export config:** `Device > Setup > Operations > Export named configuration snapshot > running-config.xml`
- [ ] **Import config:** `Device > Setup > Operations > Import named configuration snapshot`
- [ ] **Export page as PDF/CSV:** Any policy page > bottom area > PDF/CSV export

### Discovery

- [ ] **Check users:** `Device > Administrators` and `Device > Local User Database > Users`
- [ ] **Check interfaces:** `Network > Interfaces` and `Network > Interface Mgmt`
- [ ] **Check NAT:** `Policies > NAT`
- [ ] **Check security rules:** `Policies > Security`
- [ ] **Check permissions:** `Device > Administrators` > look at roles

### Rules

```
Inbound:  Source: untrust > Destination: trust > Application/Service > Action: Allow/Deny/Drop
Outbound: Source: trust > Destination: untrust > Application/Service > Action: Allow/Deny/Drop
Block IP: Source: [address] > Destination: Any > Service: Any > Action: Deny/Drop
```

### Restrict Management Access

`Network > Network Profiles > Interface Mgmt > Add > add allowed IP addresses`

### DNS and NTP

`Device > Setup > Services`
- Update Server: `updates.paloaltonetworks.com`
- Primary NTP: `0.pool.ntp.org`

---

## Cisco FTD (Web GUI)

### Password Management

- [ ] **Change admin password:** Top right > Profile > Password

### Backup and Restore

- [ ] **Download config:** `Device > Device Administration > Download Configuration` (JSON)
- [ ] **Create backup:** `Device > Backup and Restore > Configure`
- [ ] **Upload backup:** `Device > Backup and Restore > Upload`

### Discovery

- [ ] **Check interfaces:** `Device > Interfaces`

### Rules

```
Inbound:  Source zone: outside_zone > Destination zone: inside_zone
Outbound: Source zone: inside_zone > Destination zone: outside_zone
Block IP: Source Networks > create new network > enter IP > set rule to BLOCK
```

### Restrict Management Access

`Device > System Settings > Management Access > Management Interface > add IPs to Allowed Networks`

---

## Quick Comparison: Allow Inbound TCP 80

| Backend | Command |
|---------|---------|
| iptables | `iptables -A INPUT -p tcp --dport 80 -j ACCEPT` |
| ufw | `ufw allow 80/tcp` |
| nft | `nft add rule inet my_filter INPUT tcp dport 80 accept` |
| firewalld | `firewall-cmd --zone=public --add-port=80/tcp --permanent && firewall-cmd --reload` |
| Windows | `New-NetFirewallRule -DisplayName "Allow 80" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow` |
| Palo Alto | `Policies > Security > Add rule > Source:untrust Dest:trust Service:tcp/80 Action:Allow > Commit` |
| Cisco FTD | `Policies > Access Control > Add rule > Source:outside Dest:inside Port:80 Action:Allow > Deploy` |

## Quick Comparison: Default Deny Inbound

| Backend | Command |
|---------|---------|
| iptables | `iptables -P INPUT DROP` |
| ufw | `ufw default deny incoming` |
| nft | `nft add chain inet filter INPUT { type filter hook input priority 0 \; policy drop \; }` |
| firewalld | `firewall-cmd --set-default-zone=drop` |
| Windows | Set default inbound to Block via `Set-NetFirewallProfile -DefaultInboundAction Block` |
| Palo Alto | Default deny-all rule at bottom of security policies |
| Cisco FTD | Default deny-all rule at bottom of access control policies |

## Quick Comparison: Block IP

| Backend | Command |
|---------|---------|
| iptables | `iptables -A INPUT -s [IP] -j DROP` |
| ufw | `ufw deny from [IP]` |
| nft | `nft add rule inet filter INPUT ip saddr [IP] drop` |
| firewalld | `firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="[IP]" reject'` |
| Windows | `New-NetFirewallRule -DisplayName "Block [IP]" -Direction Inbound -RemoteAddress [IP] -Action Block` |
| Palo Alto | `Policies > Security > Source:[IP] Dest:Any Service:Any Action:Deny > Commit` |
| Cisco FTD | `Source Networks > create network [IP] > set rule BLOCK > Deploy` |
