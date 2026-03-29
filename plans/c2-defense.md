# Plan: C2 (Command and Control) Defense

## Goal

Add `ccdc discover c2` and `ccdc harden c2` commands to detect and block C2 beacons and persistence mechanisms.

## Why

Red team plants C2 implants during CCDC. These beacon out to attacker infrastructure on regular intervals. Common C2 frameworks used in CCDC:
- Cobalt Strike
- Sliver
- Metasploit/Meterpreter
- Empire/Starkiller
- Custom reverse shells (bash, Python, PowerShell)

If you don't find and kill C2, the red team gets back in every time you kick them out.

## Detection Approach

### Network-Based Detection

1. **Beacon hunting** — look for repeated connections to the same IP at regular intervals
2. **DNS beaconing** — repeated queries to unusual domains
3. **Unusual outbound ports** — C2 commonly uses 4444, 5555, 8080, 1337, 9001, 443 (blending with HTTPS)
4. **Outbound to non-scored IPs** — anything connecting out that isn't the scoring engine or known infrastructure

### Host-Based Detection

1. **Processes** — unknown processes, processes with suspicious parent chains
2. **Persistence** — cron, systemd timers, scheduled tasks, registry run keys, startup folders
3. **Rev shells** — `/etc/profile.d/`, `~/.bashrc`, `~/.bash_profile`, cron entries
4. **Unusual binaries** — files in /tmp, /dev/shm, writable dirs
5. **Network connections per process** — which process is making outbound connections

## CLI Commands

- `ccdc discover c2` / `ccdc disc c2` — scan for C2 indicators (network + host)
- `ccdc harden c2` / `ccdc hrd c2` — block known C2 patterns (outbound firewall, kill suspicious processes)
- `ccdc harden c2 --undo` — restore (re-allow outbound traffic)

## Detection Scripts to Build

### Linux

```bash
# Outbound connections to non-local IPs
ss -tunp | grep -v '127.0.0.1\|::1' | grep ESTAB

# Processes with network connections
ss -tunp | awk '{print $NF}' | sort -u

# Files in suspicious locations
find /tmp /dev/shm /var/tmp -type f -executable 2>/dev/null

# Recently modified binaries
find /usr/bin /usr/sbin -mtime -1 -type f 2>/dev/null

# Cron persistence
for user in $(getent passwd | cut -d: -f1); do crontab -l -u $user 2>/dev/null; done

# Systemd timer persistence
systemctl list-timers --all

# Profile persistence
grep -r "nc \|ncat \|bash -i\|/dev/tcp\|python.*socket\|curl.*|\|wget.*|" /etc/profile.d/ ~/.bashrc ~/.bash_profile 2>/dev/null
```

### Windows

```powershell
# Outbound connections with process names
Get-NetTCPConnection -State Established |
    Select-Object LocalPort, RemoteAddress, RemotePort, OwningProcess,
    @{N='Process';E={(Get-Process -Id $_.OwningProcess).ProcessName}} |
    Where-Object { $_.RemoteAddress -notmatch '^(127\.|10\.|172\.(1[6-9]|2|3[01])\.|192\.168\.)' }

# Scheduled tasks (persistence)
Get-ScheduledTask | Where-Object {$_.State -eq "Ready"} | Select TaskName, TaskPath

# Run keys (persistence)
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"

# Startup folder
Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
```

## Integration with SIEM

- Feed C2 detection results into Wazuh/Splunk alerts
- Suricata rules for known C2 signatures (ET rules already cover many)
- Zeek conn.log beacon analysis (top talkers, regular intervals)

## Tasks

- [ ] Build `ccdc disc c2` for Linux — check processes, cron, profiles, /tmp, network
- [ ] Build `ccdc disc c2` for Windows — check tasks, run keys, startup, network
- [ ] Build `ccdc hrd c2` — outbound firewall lockdown (only allow scored ports out)
- [ ] Integrate beacon detection with Zeek conn.log analysis
- [ ] Test against common C2 frameworks in lab
- [ ] Write docs section

## Key Insight

The single most effective C2 defense is **outbound firewall lockdown**. If you default-deny outbound and only allow traffic to the scoring engine and necessary services, most C2 beacons die immediately. This should be part of `comp-start`.
