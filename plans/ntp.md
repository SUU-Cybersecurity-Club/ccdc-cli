# Plan: NTP Setup and Hardening

## Goal

Add `ccdc harden ntp` command to configure and secure time synchronization across all competition machines.

## Why

Accurate time is critical for:
- **Log correlation** — Splunk/Wazuh logs from different machines must have matching timestamps
- **Kerberos** — AD authentication fails if clocks drift more than 5 minutes
- **Forensics** — incident response needs accurate timelines
- **Scoring** — some scoring engines check NTP as a service

Attackers may tamper with NTP to break Kerberos or make log analysis harder.

## Recommended Approach

### Linux

1. Use `chrony` (modern, default on RHEL) or `systemd-timesyncd` (default on Ubuntu)
2. Point all machines to the AD/DNS server as NTP source (or pool.ntp.org if internet is available)
3. Harden: restrict who can query, disable monlist (NTP amplification), set authentication

### Windows

1. Configure Windows Time Service (`w32tm`)
2. AD domain controller should be the authoritative NTP source for all domain members
3. DC syncs to external source (pool.ntp.org or competition-provided)

## CLI Commands

- `ccdc harden ntp` / `ccdc hrd ntp` — configure NTP client pointing to specified server
- `ccdc harden ntp --server` — configure machine as NTP server
- `ccdc harden ntp --undo` — restore previous NTP config

## Tasks

- [ ] Detect chrony vs systemd-timesyncd vs ntpd on Linux
- [ ] Write chrony.conf template with hardened settings
- [ ] Write w32tm configuration for Windows
- [ ] Test Kerberos with NTP configured vs broken
- [ ] Write `lib/linux/ntp.sh` and `lib/windows/ntp.psm1`
- [ ] Add to docs

## Example Config (chrony)

```
# /etc/chrony.conf
server [AD_SERVER_IP] iburst prefer
server 0.pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow [local_subnet]
deny all
```

## Example Config (Windows w32tm)

```powershell
w32tm /config /manualpeerlist:"[NTP_SERVER_IP]" /syncfromflags:manual /reliable:YES /update
Restart-Service w32time
w32tm /resync
```
