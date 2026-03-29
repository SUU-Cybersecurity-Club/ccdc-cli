# Plan: IPv6 Setup and Hardening

## Goal

Add `ccdc harden ipv6` command to properly configure or disable IPv6 on competition machines.

## Why

IPv6 is often overlooked in CCDC. Attackers can:
- Use IPv6 to bypass IPv4-only firewall rules
- Exploit link-local addresses for lateral movement
- Use IPv6 tunnels (6to4, Teredo) to exfiltrate data past firewalls
- Perform neighbor discovery attacks (IPv6 equivalent of ARP spoofing)

If the competition doesn't score IPv6 services, disable it. If it does, harden it.

## Two Modes

### Mode 1: Disable IPv6 (if not scored)

Quick lockdown — remove the entire attack surface.

### Mode 2: Harden IPv6 (if scored)

Configure IPv6 firewall rules that mirror IPv4 rules, disable unnecessary features.

## CLI Commands

- `ccdc harden ipv6 --disable` — disable IPv6 system-wide
- `ccdc harden ipv6 --secure` — harden IPv6 (firewall rules, disable router advertisements)
- `ccdc harden ipv6 --undo` — restore previous IPv6 config

## Tasks

### Disable IPv6

- [ ] Linux: `sysctl -w net.ipv6.conf.all.disable_ipv6=1` + persist in `/etc/sysctl.d/`
- [ ] Windows: disable via registry and adapter settings
- [ ] Firewall appliances: disable IPv6 on interfaces

### Harden IPv6

- [ ] Add ip6tables / nft rules mirroring IPv4 rules
- [ ] Windows Firewall: add IPv6 rules
- [ ] Disable router advertisements acceptance (prevent rogue RA attacks)
- [ ] Disable 6to4 and Teredo tunneling
- [ ] Palo Alto / Cisco: check for IPv6 policies

### Linux Disable Example

```bash
# Immediate
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# Persistent
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-disable-ipv6.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.d/99-disable-ipv6.conf
sysctl --system
```

### Windows Disable Example

```powershell
# Disable IPv6 on all adapters
Get-NetAdapter | ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 }

# Registry (survives reboot)
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" /v DisabledComponents /t REG_DWORD /d 0xFF /f
```

## Dependencies

- Must verify scored services don't require IPv6 before disabling
- Some AD features may use IPv6 link-local — test before disabling on DC
