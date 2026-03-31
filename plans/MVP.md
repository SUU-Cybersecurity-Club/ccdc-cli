# MVP Plan — ccdc-cli

The MVP is everything needed to replace the "30 Minute Checklist" with a working CLI that a team member can `git clone` and run on any competition machine.

**Two entry points. Same commands. No dependencies.**
- `ccdc.sh` (bash) on Linux
- `ccdc.ps1` (PowerShell) on Windows

---

## Research Summary — What We Learned from Existing Tools

Research was done across 3 internal repos (CCDC-Scripts, Security-Scripts, public-ccdc-resources), 10+ other CCDC team repos, and open-source hardening tools. Key takeaways that shaped this plan:

### Patterns to Adopt

| Pattern | Source | How We Use It |
|---------|--------|---------------|
| 5-level OS detection fallback | CCDC-Scripts, Security-Scripts | Phase 0.2 — `/etc/os-release` > `lsb_release` > `/etc/lsb-release` > `/etc/debian_version` > `uname` |
| Firewall backup/restore with `{} \|\| { restore; }` | Security-Scripts `lib/firewall.sh` | Phase 0.4 — every destructive command wraps in error-handling block |
| `chattr +u +a +i` on backups (immutable) | Security-Scripts `lib/utility.sh` | Phase 2 — prevent red team from deleting our backups |
| Typo filenames for backups (`ettc`, `httml`) | CCDC-Scripts | Phase 2 — make backup files harder for attackers to find/delete |
| Dual logging: `exec 1> >(tee -a "$LOG")` | public-ccdc-resources | Phase 0.5 — all output goes to stdout AND log file |
| Three-layer undo (original baseline + per-run snapshots + drift detection) | DCAT WindowsDefenderHardening | Phase 0.4 — upgraded undo framework |
| Fallback install chain (pkg manager > bundled binary > manual extract) | CCDC-Scripts | Phase 8 — if apt/dnf fails, install from bundled .deb/.rpm |
| Non-interactive mode flag | public-ccdc-resources (Ansible mode) | `--no-prompt` flag — same concept without requiring Ansible |
| Firewall framework cleanup (disable competing backends) | Security-Scripts, public-ccdc-resources | Phase 4 — disable ufw/firewalld/nft before configuring chosen one |
| tmux parallel task execution | CCDC-Scripts/Useful-Scripts `first30.sh` | Phase 0.5 — install tmux, use for parallel comp-start tasks |
| Wazuh + Suricata log integration | Useful-Scripts `2016-Software.ps1` | Phase 6 — configure Wazuh to ingest Suricata eve.json automatically |
| Try/catch local vs AD user creation | Useful-Scripts `2016-Main.ps1` | Phase 1 — try local admin group, catch and fallback to Domain Admins |
| TLS 1.2 .NET strong crypto registry | Useful-Scripts `2016-Prelims.ps1` | Phase 5 — set SchUseStrongCrypto=1 for both 32/64-bit registry paths |

### Anti-Patterns to Avoid

| Anti-Pattern | Source | Our Fix |
|--------------|--------|---------|
| No undo/rollback at all | CCDC-Scripts, most CCDC teams | Every command has `--undo` from day one |
| Manual backup recovery only | CCDC-Scripts | `ccdc backup restore` automates it |
| No Windows backup capability | CCDC-Scripts | Phase 2 covers Windows registry export + service snapshots |
| Hard-coded download URLs | public-ccdc-resources Splunk script | Bundle everything in `bin/`, no network calls during comp |
| Organize by OS instead of function | Every other CCDC team | We organize by function (`passwd`, `fw`, `harden`) — better for CLI |
| No checksums on bundled binaries | CCDC-Scripts | Phase 8 — SHA256 manifest for all bundled files |

### Competitive Landscape

- **No existing tool unifies ufw/firewalld/nft/iptables behind one CLI** — `ccdc fw allow-only-in` is novel
- **Most CCDC teams have zero undo** — our undo framework is ahead of the field
- **UCI uses Go (73%)** — compiled portability, but requires build step. Our bash+PS1 approach is better for competition (no runtime needed)
- **bokkisec wrote infinite firewall re-enable loops during live competition** — validates designing for adversarial conditions

---

## Build Order

Work is grouped into phases. Each phase builds on the last. A phase is "done" when every command in it works with `--help` and `--undo` on at least one Debian-based distro, one RHEL-based distro, and Windows Server 2019.

---

## Phase 0: Skeleton and Config

Build the CLI framework before any real commands. Everything else depends on this.

### 0.1 — Entry points and argument router

- [ ] `ccdc.sh` — bash entry point, parses `ccdc <category> <command> [options]`, routes to `lib/linux/<module>.sh`
- [ ] `ccdc.ps1` — PowerShell entry point, same routing to `lib/windows/<module>.psm1`
- [ ] Alias support: map short names (fw, pw, bak, etc.) to full category names
- [ ] `--help` flag: every category prints its command list, every command prints usage
- [ ] `--undo` flag: passes through to the command's undo function

### 0.2 — Detection engine (`lib/linux/detect.sh`, `lib/windows/detect.psm1`)

- [ ] Linux: detect OS with 5-level fallback hierarchy:
  1. `/etc/os-release` (freedesktop standard — Ubuntu 18+, Fedora 19+, CentOS 7+)
  2. `lsb_release -si` / `lsb_release -sr` (legacy LSB command)
  3. `/etc/lsb-release` file (old Debian/Ubuntu without lsb_release binary)
  4. `/etc/debian_version` (very old Debian)
  5. `uname -s` / `uname -r` (universal fallback)
- [ ] Linux: normalize OS names (lowercase, strip `.04` from Ubuntu versions, map `ID_LIKE` for derivatives)
- [ ] Linux: detect package manager with command existence checks: `apt` > `dnf` > `yum` > `zypper` > `pacman`
- [ ] Linux: detect **all available** firewall backends (store in array), pick best: `firewalld` (if RHEL) > `ufw` (if Debian) > `nft` > `iptables`
- [ ] Windows: detect OS version, detect if domain controller (`Get-ADDomain` / AD module present)
- [ ] Export variables: `$CCDC_OS`, `$CCDC_OS_FAMILY`, `$CCDC_OS_VERSION`, `$CCDC_PKG`, `$CCDC_FW_BACKEND`

### 0.3 — Config system (`lib/linux/config.sh`, `lib/windows/config.psm1`)

- [ ] `ccdc config init` — run detection, write results to `.ccdc.conf` in repo dir
- [ ] `ccdc config set <key> <value>` — update a single key in `.ccdc.conf`
- [ ] `ccdc config show` — print current config (file values + auto-detected fallbacks)
- [ ] `ccdc config reset` — delete `.ccdc.conf`
- [ ] `ccdc config edit` — open `.ccdc.conf` in `$EDITOR` / notepad
- [ ] All other modules: load `.ccdc.conf` first, fall back to detect if no file
- [ ] `.gitignore` — add `.ccdc.conf`

### 0.4 — Undo framework (`lib/linux/undo.sh`, `lib/windows/undo.psm1`)

Three-layer undo system (inspired by DCAT WindowsDefenderHardening):

**Layer 1: Original baseline** (created once during `config init`, never overwritten)
- [ ] `<backup_dir>/.ccdc-undo/original/` — snapshot of initial state before any ccdc-cli changes
- [ ] Captures: firewall rules, /etc/shadow hashes, sshd_config, crontabs, registry keys, service list
- [ ] Immutable: set `chattr +i` (Linux) / read-only attribute (Windows) after creation
- [ ] Purpose: worst-case full rollback to pre-tool state

**Layer 2: Per-command snapshots** (created before every destructive command)
- [ ] `<backup_dir>/.ccdc-undo/<category>/<command>/<timestamp>/` — state before this specific run
- [ ] `--undo` reads the latest snapshot for that command and reverts
- [ ] Each command defines its own `_undo()` function
- [ ] Wrap destructive operations: `{ backup; do_thing; } || { restore; return 1; }`

**Layer 3: Undo log** (append-only record of everything done)
- [ ] `<backup_dir>/.ccdc-undo/undo.log` — timestamped log of every command run and its undo path
- [ ] `ccdc undo log` / `ccdc undo show` — print the log so the user can see what was changed
- [ ] Enables `comp-start --undo` to walk the log in reverse order

### 0.5 — Common helpers (`lib/linux/common.sh`, `lib/windows/common.psm1`)

- [ ] **Dual logging** — `exec 1> >(tee -a "$CCDC_LOG")` so all output goes to terminal AND `<backup_dir>/ccdc.log`
- [ ] `ccdc_log()` — print with timestamp, color by severity (ERROR=red, WARN=yellow, INFO=blue, SUCCESS=green)
- [ ] `ccdc_confirm()` — y/n prompt (skipped with `--no-prompt`)
- [ ] `ccdc_install_pkg()` — cross-distro package install using `$CCDC_PKG`, with fallback chain:
  1. Try package manager (`apt install` / `dnf install`)
  2. Try bundled binary from `bin/linux/` or `bin/windows/`
  3. Try manual extract (`dpkg -x` / `rpm2cpio | cpio`)
- [ ] `ccdc_remove_pkg()` — cross-distro package remove
- [ ] `ccdc_backup_file()` — copy file to undo dir before modifying, set immutable attrs (`chattr +i`)
- [ ] `ccdc_run()` — run command, log it, check exit code, wrap in `{} || { restore; }` pattern
- [ ] `ccdc_download()` — try wget first, fall back to curl (for bundled binary install scripts)
- [ ] Windows equivalents for all of the above

---

## Phase 1: Passwords and Backup User

The very first thing done in competition. Must work before anything else.

### 1.1 — passwd module (`lib/linux/passwd.sh`, `lib/windows/passwd.psm1`)

- [ ] `ccdc passwd change-all` — list users with login shells, prompt for new password, change all
  - Linux: `getent passwd | grep /bin/bash`, `chpasswd` or loop `passwd`
  - Windows: `Get-LocalUser`, `Set-LocalUser -Password`
  - Undo: store old password hashes from `/etc/shadow` or SAM, restore on undo
- [ ] `ccdc passwd <user>` — change single user password
- [ ] `ccdc passwd root` — change root (Linux) or Administrator (Windows)
- [ ] `ccdc passwd backup-user` — create "printer" user with sudo/admin
  - Linux (Debian): `adduser printer && usermod -aG sudo printer`
  - Linux (RHEL): `useradd -m printer && passwd printer && usermod -aG wheel printer`
  - Windows (local): `New-LocalUser` + `Add-LocalGroupMember Administrators`
  - Windows (AD): `New-ADUser` + `Add-ADGroupMember "Domain Admins"`
  - Undo: remove the user
- [ ] `ccdc passwd ad-change <user>` — `Set-ADAccountPassword` (Windows only)
- [ ] `ccdc passwd dsrm` — ntdsutil DSRM password reset (Windows AD only)
- [ ] `ccdc passwd localuser list` — windows list local users show if have admins(windows only)
- [ ] `ccdc passwd localuser admin` — windows changes local administrator user passwd(windows only)

---

## Phase 2: Backups

Must happen early — everything after this can be undone by restoring backups.

### Anti-tamper measures (apply to all backups)

- [ ] Use **obfuscated filenames** — typo-based names like `ettc`, `httml`, `oppt` so `find / -name "*.tar" | grep backup` doesn't catch them
- [ ] Set **immutable attributes** — `chattr +u +a +i` on Linux, read-only + hidden on Windows
- [ ] Store in **non-obvious location** — default `/ccdc-backups` but configurable, avoid `/root/backups`
- [ ] **SHA256 manifest** — `sha256sum` of each backup file stored alongside for integrity verification

### 2.1 — backup module (`lib/linux/backup.sh`, `lib/windows/backup.psm1`)

- [ ] `ccdc backup etc` — `tar -cpf` /etc (Linux), export registry hives (Windows)
  - Undo: `tar -xpf` restore, `reg import` restore
- [ ] `ccdc backup binaries` — tar /usr/bin, /usr/sbin, **plus firewall binaries** (Linux), backup Windows Defender/firewall binaries + service DLLs (Windows)
  - Undo: restore from tar
- [ ] `ccdc backup web` — tar /var/www/html and /opt web content (Linux), compress IIS wwwroot (Windows)
  - Also check /opt for web apps
  - Undo: restore from tar/zip
- [ ] `ccdc backup services` — save service list to CSV/text
  - Linux: `systemctl list-units --type=service`
  - Windows: `Get-CimInstance Win32_Service | Export-Csv`
- [ ] `ccdc backup ip` — save ip a and ipconfig esc stuff routes too
- [ ] `ccdc backup ports` — save ports via ss, netstat etc.
- [ ] `ccdc backup db` — mysqldump all databases
  - Prompt for MySQL root password or read from config
  - Dump each database individually + `--all-databases`
  - Undo: restore from dump (`mysql < dump.sql`)
- [ ] `ccdc backup full` — run all above in sequence
- [ ] `ccdc backup restore <archive>` — restore a specific backup by path
  - Detect type (tar, zip, sql) and restore accordingly

---

## Phase 3: Discovery

Saves output to `<backup_dir>/discovery/`. Run after backups so you have a baseline.

### 3.1 — discover module (`lib/linux/discover.sh`, `lib/windows/discover.psm1`)

- [ ] `ccdc discover network` — `ip a`, `ip r` (Linux) / `ipconfig /all` (Windows), save to file
- [ ] `ccdc discover ports` — `ss -autpn` (Linux) / `Get-NetTCPConnection` (Windows), save to file
- [ ] `ccdc discover users` — users, groups, sudo/wheel/admin membership, sudoers files
  - Linux: `getent passwd`, `getent group`, `cat /etc/sudoers`, `cat /etc/sudoers.d/*`
  - Windows: `net localgroup administrators`, `Get-ADGroupMember` (if AD)
- [ ] `ccdc discover processes` — `ps -eaf --forest` (Linux) / `Get-Process` (Windows), save to file
- [ ] `ccdc discover cron` — all crontabs, /etc/cron.d/*, profile.d, .bashrc (Linux) / Scheduled Tasks (Windows)
- [ ] `ccdc discover services` — running + enabled services
- [ ] `ccdc discover firewall` — dump current rules (auto-detect backend)
- [ ] `ccdc discover integrity` — `debsums -s` or `rpm -Va` (Linux, runs in background), save to file
- [ ] `ccdc discover all` — run all above, print summary of findings

---

## Phase 4: Firewall

The biggest time-saver. `allow-only-in` with scored ports is the single highest-impact command.

### 4.1 — firewall module (`lib/linux/firewall.sh`, `lib/windows/firewall.psm1`)

- [ ] `ccdc firewall on` — enable firewall (detect backend: ufw/firewalld/nft/iptables/Windows)
  - **Disable competing backends first** (e.g., if using firewalld, mask ufw/nft/netfilter-persistent)
  - Add loopback + ESTABLISHED,RELATED as foundation rules
  - Undo: disable firewall
- [ ] `ccdc firewall allow-in <port> [proto]` — allow inbound port (default proto: tcp)
  - Must work on all 4 Linux backends + Windows
  - Undo: remove the rule
- [ ] `ccdc firewall block-in <port> [proto]` — block inbound port
  - Undo: remove the rule
- [ ] `ccdc firewall allow-out <port> [proto]` — allow outbound port
- [ ] `ccdc firewall block-out <port> [proto]` — block outbound port
- [ ] `ccdc firewall drop-all-in` — set default policy to deny/drop inbound
  - **Always** add loopback and ESTABLISHED,RELATED rules first
  - Undo: set default policy back to accept
- [ ] `ccdc firewall drop-all-out` — set default policy to deny/drop outbound
  - Undo: set default policy back to accept
- [ ] `ccdc firewall allow-only-in <ports>` — drop all inbound except listed ports
  - Reads `scored_ports_tcp` and `scored_ports_udp` from `.ccdc.conf` if no args given
  - Adds loopback + ESTABLISHED,RELATED automatically
  - This is the **key command** for competition
  - Undo: flush rules, restore from backup
- [ ] `ccdc firewall block-ip <ip>` — block all traffic from IP
  - Undo: remove the block rule
- [ ] `ccdc firewall status` — show current rules (human-readable)
- [ ] `ccdc firewall save` — persist rules across reboot (iptables-persistent, nft save, etc.)
- [ ] `ccdc firewall allow-internet` — temporarily open outbound HTTP/HTTPS (80, 443, 53) for downloads
  - Undo: `ccdc firewall block-internet`
- [ ] `ccdc firewall block-internet` — close outbound back down

### 4.2 — net module (`lib/linux/net.sh`, `lib/windows/net.psm1`)

Firewall-aware download commands. Opens outbound, downloads, closes automatically.

- [ ] `ccdc net wget <url> [output]` — open firewall outbound, wget/curl the URL, close outbound
  - Linux: try wget, fallback curl
  - Windows: `Invoke-WebRequest` with TLS 1.2
  - Automatically closes firewall after download completes (even on error)
  - Undo: not needed (firewall state is restored automatically)
- [ ] `ccdc net curl <url>` — same as wget but for quick API/text fetches

---

## Phase 5: Hardening

Core hardening commands from the 30-minute checklist.

### 5.1 — service module (`lib/linux/service.sh`, `lib/windows/service.psm1`)

- [ ] `ccdc service list` — list running services
- [ ] `ccdc service stop <name>` — stop a service (undo: start it)
- [ ] `ccdc service disable <name>` — stop + disable (undo: enable + start)
- [ ] `ccdc service enable <name>` — enable + start (undo: stop + disable)
- [ ] `ccdc service cockpit` — stop, disable, remove Cockpit + block port 9090
  - Undo: reinstall cockpit (if package cached)

### 5.2 — harden module (`lib/linux/harden.sh`, `lib/windows/harden.psm1`)

- [ ] `ccdc harden ssh` — disable or harden SSH
  - Option: remove openssh-server entirely (if not scored)
  - Option: harden sshd_config (no root login, set banner)
  - Undo: reinstall or restore sshd_config from backup
- [ ] `ccdc harden smb` — disable SMBv1 (and optionally SMBv2)
  - Linux: check if samba running
  - Windows: `Set-SmbServerConfiguration -EnableSMB1Protocol $false`
  - Undo: re-enable
- [ ] `ccdc harden cron` — backup all cron jobs, then comment out /etc/crontab, delete user crontabs
  - Undo: restore from backup
- [ ] `ccdc harden banner` — set login banner
  - Linux: write /etc/issue, /etc/issue.net, configure sshd Banner
  - Windows: set registry legalnoticecaption + legalnoticetext
  - Undo: restore original files/keys
- [ ] `ccdc harden revshell-check` — scan for rev shells in profiles, bashrc, cron, /tmp, /dev/shm
  - Print findings, don't auto-delete (too risky)
  - No undo needed (read-only)
- [ ] `ccdc harden anon-login` — fix anonymous login registry keys (Windows)
  - Set RestrictAnonymous=1, RestrictAnonymousSAM=1, EveryoneIncludesAnonymous=0
  - Undo: restore original values
- [ ] `ccdc harden defender` — enable and configure Windows Defender (Windows)
  - Install feature if missing, enable all protections, update signatures
  - Undo: not really — just disable realtime if needed
- [ ] `ccdc harden gpo` — apply password policy, lockout, audit policy via PowerShell (Windows)
  - auditpol commands for Kerberos, logon, special logon
  - Undo: restore previous auditpol settings
- [ ] `ccdc harden updates` — fix Windows Update service if broken/deleted (Windows)
  - Recreate service via sc.exe and registry
  - Also fix Windows Defender service if broken
  - Undo: not really needed
- [ ] `ccdc harden mysql` — run mysql_secure_installation, change root password
  - Undo: restore root password from backup
- [ ] `ccdc harden kerberos` — find and fix accounts with preauth disabled (Windows AD)
  - `Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true}`, then fix
  - Undo: re-disable preauth (unlikely to want this)
- [ ] `ccdc harden tls` — enforce TLS 1.2 strong crypto (Windows)
  - Set `SchUseStrongCrypto = 1` in both 32-bit and 64-bit .NET registry paths
  - Undo: remove registry keys
- [ ] `ccdc harden rdp` — disable RDP, PS Remoting, WinRM (Windows, interactive prompts)
  - Set `fDenyTSConnections = 1` in registry
  - `Disable-PSRemoting -Force`, `Configure-SMremoting.exe -disable`
  - Stop and disable WinRM service, disable firewall rules
  - Undo: re-enable each
- [ ] `ccdc harden spooler` — disable Print Spooler service (Windows)
  - Undo: re-enable

---

## Phase 6: SIEM and Monitoring

Deployed after hardening is done. These are install-and-configure, not quick toggles.

### 6.1 — siem module (`lib/linux/siem.sh`, `lib/windows/siem.psm1`)

- [ ] `ccdc siem wazuh-server` — install Wazuh server/indexer on designated machine
  - Linux only (runs on Splunk/monitoring box)
  - Download or use bundled installer from `bin/linux/`
  - Configure to receive agents
  - Undo: stop and remove wazuh
- [ ] `ccdc siem wazuh-agent` — install Wazuh agent, connect to server IP from `.ccdc.conf`
  - Linux: apt/dnf install
  - Windows: msi installer from `bin/windows/`
  - Undo: stop and remove agent
- [ ] `ccdc siem splunk-server` — install Splunk indexer (alternative to Wazuh)
  - Linux only
  - Undo: stop and remove splunk
- [ ] `ccdc siem splunk-agent` — install Splunk Universal Forwarder
  - Linux and Windows
  - Connect to server IP from `.ccdc.conf`
  - Undo: stop and remove forwarder
- [ ] `ccdc siem suricata` — install and configure Suricata IDS
  - Linux: apt/dnf install, configure suricata.yaml (HOME_NET, interface from `ip -o -4 route show to default`)
  - Windows: requires Npcap + msi, configure pcap interface (auto-detect via ipconfig)
  - Download rules (suricata-update or bundled ET Open)
  - **Auto-integrate with Wazuh**: append Suricata eve.json to ossec.conf localfile monitoring
  - Undo: stop and remove, remove Wazuh integration
- [ ] `ccdc siem zeek` — install and configure Zeek
  - Linux: apt/dnf install, configure node.cfg and networks.cfg
  - Undo: stop and remove
- [ ] `ccdc siem snoopy` — install Snoopy command logger
  - Linux only
  - Undo: remove snoopy
- [ ] `ccdc siem auditd` — install auditd, deploy audit rules (99-custom.conf)
  - Linux only
  - Bundle the rule file in repo
  - Undo: remove custom rules, restart auditd
- [ ] `ccdc siem sysmon` — install and configure Sysmon (Windows only)
  - Bundle Sysmon + config xml in `bin/windows/`
  - Undo: uninstall sysmon

---

## Phase 6.5: Utilities

### 6.5.1 — tmux install (`lib/linux/install.sh`)

tmux is used by `comp-start` on Linux to run hardening tasks in parallel (password changes in one pane, backups in another, etc.).

- [ ] `ccdc install tmux` — cross-distro tmux install (apt/dnf/zypper/pacman)
  - Fallback: install from bundled .deb/.rpm in `bin/linux/`
  - Undo: remove tmux

### 6.5.2 — copy-paster (`lib/copy-paster/`)

Standalone utility for the **operator's machine** (not the competition box). Types clipboard content into VMs that block paste. Must work on Windows, macOS, and Linux (Wayland + X11).

**This is NOT a bash/PowerShell script** — it needs GUI automation. Options:

| Platform | Approach | Dependency |
|----------|----------|------------|
| Windows | PowerShell `SendKeys` or bundled AutoHotKey script | None / AHK portable .exe |
| macOS | `osascript` AppleScript keystroke simulation | None (built-in) |
| Linux X11 | `xdotool type` | xdotool (apt/dnf install) |
| Linux Wayland | `wtype` or `ydotool` | wtype/ydotool (apt/dnf install) |

- [ ] `ccdc copy-paster` / `ccdc cp` — 5-second countdown, then type clipboard at 10ms per character
- [ ] `ccdc cp --delay <sec>` — custom countdown (default: 5)
- [ ] `ccdc cp --speed <ms>` — typing speed per character (default: 10ms)
- [ ] Auto-detect display server (Wayland vs X11 vs macOS vs Windows) and use correct backend
- [ ] **No Python dependency** — the existing copy-paster.py uses pyautogui+tkinter, rewrite using native tools:
  - Windows: `Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait()`
  - macOS: `osascript -e 'tell application "System Events" to keystroke "<text>"'`
  - Linux X11: `xclip -o | xdotool type --clearmodifiers --delay 10 --file -`
  - Linux Wayland: `wl-paste | wtype -d 10 -`
- [ ] Bundle in `lib/copy-paster/` as separate scripts per platform (not in lib/linux or lib/windows since this runs on the operator's machine)

---

## Phase 7: comp-start

The chain command. Only build this after phases 0-6 are individually working.

### 7.1 — comp-start orchestration

- [ ] `ccdc comp-start` — detect OS, run the right sequence:
  - **Linux sequence:** config init > passwd change-all > passwd backup-user > backup full > discover all > service cockpit > harden ssh > harden cron > harden revshell-check > firewall allow-only-in > firewall save > discover integrity > siem snoopy > siem auditd > siem wazuh-agent > harden banner
  - **Windows sequence:** config init > passwd change-all > passwd backup-user > passwd ad-change (if AD) > backup full > discover all > harden defender > harden smb > harden anon-login > firewall allow-only-in > firewall save > harden banner > harden gpo > siem sysmon > siem wazuh-agent > harden updates > harden kerberos (if AD)
- [ ] Prompt for scored ports if not in `.ccdc.conf`
- [ ] Prompt for Wazuh server IP if not in `.ccdc.conf`
- [ ] Print summary at end: what was done, what failed, what needs manual follow-up
- [ ] `ccdc comp-start --undo` — run undo for every command in reverse order

---

## Phase 8: Bundled Binaries

Package offline installers so nothing needs internet after git clone.

### 8.1 — bin/ directory

- [ ] `bin/linux/` — pre-download .deb and .rpm packages:
  - Snoopy (deb + rpm)
  - Wazuh agent (deb + rpm)
  - Suricata (deb + rpm)
  - Zeek (deb + rpm, or build instructions)
  - auditd (usually pre-installed, but bundle just in case)
  - debsums (deb)
  - Suricata rules tarball (ET Open)
- [ ] `bin/windows/` — pre-download installers:
  - Wazuh agent .msi
  - Splunk Universal Forwarder .msi
  - Sysmon .zip + config xml
  - Npcap .exe
  - Suricata .msi
  - Malwarebytes installer (if redistributable)
- [ ] `bin/audit/` — auditd rules file (99-custom.conf)
- [ ] `bin/suricata/` — ET Open rules tarball
- [ ] `bin/SHA256SUMS` — checksum manifest for all bundled files (verify integrity before install)
- [ ] `scripts/update-bins.sh` — refresh all binaries (run before competition with internet):
  - Downloads latest versions of all bundled packages
  - Regenerates SHA256SUMS
  - Tests each package installs cleanly on Docker (Ubuntu + Fedora)

---

## What is NOT MVP

These are all in `plans/` for later. Do not build these until the above is done and tested.

| Feature | Plan File | Why Deferred |
|---------|-----------|--------------|
| WAF (ModSecurity) | `plans/waf.md` | Needs Apache running, complex config |
| LibreNMS | `plans/librenmss.md` | Heavy, needs web stack, SNMP |
| NTP hardening | `plans/ntp.md` | Important but not first-30 |
| IPv6 disable/harden | `plans/ipv6.md` | Important but not first-30 |
| C2 defense/detection | `plans/c2-defense.md` | Outbound firewall covers most of this in MVP |
| Alternative firewall | `plans/alternative-firewall.md` | Backup when native broken, edge case |
| Automated testing (Docker/BATS) | `plans/automated-testing.md` | Nice to have, manual testing for MVP |
| Proxmox test environment | `plans/automated-testing.md` | Later |
| VyOS CLI commands | — | Not in scope |
| Ansible integration | — | No guaranteed Python |
| AIDE | — | Too slow, debsums/rpm -Va covers this |
| Inject manager | `plans/inject-manager.md` | Post-MVP, similar to copy-paster but for inject workflow |

---

## Testing Checklist (Manual for MVP)

Before calling MVP done, test every command on these machines:

- [ ] Ubuntu 24.04 (Debian family)
- [ ] Fedora 42 (RHEL family)
- [ ] Oracle Linux 9 (RHEL family, treated as RHEL-like)
- [ ] Windows Server 2019 (with AD)
- [ ] Windows Server 2022 (without AD)

For each machine test:
- [ ] `ccdc config init` detects correctly
- [ ] `ccdc config set` overrides work
- [ ] `ccdc comp-start` runs end-to-end without error
- [ ] `ccdc comp-start --undo` reverts everything cleanly
- [ ] Each individual command works standalone
- [ ] Each individual `--undo` works
- [ ] Scored services still pass after hardening

---

## Suggested Work Split (4 hardware team members)

| Person | Focus | Phases |
|--------|-------|--------|
| Person 1 | CLI framework + config | Phase 0 (skeleton, detection, config, undo, common helpers) |
| Person 2 | Linux modules | Phase 1-5 Linux side (passwd, backup, discover, firewall, harden) |
| Person 3 | Windows modules | Phase 1-5 Windows side (passwd, backup, discover, firewall, harden) |
| Person 4 | SIEM + binaries | Phase 6 (Wazuh, Splunk, Suricata, Zeek, Sysmon) + Phase 8 (bin/) |

Person 1 finishes Phase 0 first, then everyone else can build on top of it. Phase 7 (comp-start) is assembled together after phases 1-6 are working.

---

## Implementation References

Code to study/borrow from when building each phase:

| Phase | Reference | What to Learn |
|-------|-----------|---------------|
| 0.1 Entry point | Security-Scripts `harden.sh` lines 225-338 | `getopt` argument parsing with long/short options |
| 0.2 Detection | Security-Scripts `lib/initialization.sh` lines 22-173 | 5-level OS fallback, firewall array detection |
| 0.2 Detection | CCDC-Scripts `main/get_os_name_ver.sh` | Version normalization (strip `.04`, rename distros) |
| 0.4 Undo | DCAT `WindowsDefenderHardening` (GitHub) | Three-layer snapshot model, drift detection |
| 0.4 Undo | Security-Scripts `lib/firewall.sh` lines 747-886 | `backup_firewall()` / `restore_firewall()` with `{} \|\| {}` |
| 0.5 Logging | public-ccdc-resources `lib/common.sh` | `exec 1> >(tee)`, log levels, color codes |
| 0.5 Status | Security-Scripts `lib/status.sh` | Dispatcher pattern: `print_status message error "text"` |
| 0.5 Pkg install | Security-Scripts `lib/packages.sh` | Cross-distro install/remove, candidate package lists |
| 0.5 Pkg fallback | CCDC-Scripts `main/install_package.sh` | Bundled binary fallback (dpkg -x, rpm2cpio) |
| 2 Backups | Security-Scripts `lib/utility.sh` | `chattr +u +a +i`, typo filenames, tar with compression |
| 2 Backups | CCDC-Scripts `first30.sh` lines 234-238 | Versioned backups with counters |
| 4 Firewall | Security-Scripts `lib/firewall.sh` lines 3-737 | Full multi-backend init, rule building, finalization |
| 4 Firewall | public-ccdc-resources `linux/hardening/core/firewall.sh` | Competing backend cleanup, iptables persistence per-distro |
| 5 Defender | CCDC-Scripts `2016-Main.ps1` lines 78-98 | All 14 Set-MpPreference hardening flags |
| 5 Users | CCDC-Scripts `2016-Main.ps1` lines 10-40 | Try/catch for local vs AD user creation |
| 6 Splunk | public-ccdc-resources `splunk/splunk.sh` | Multi-version download, wget/curl fallback, architecture detect |
| 6 Wazuh | public-ccdc-resources `injects/wazuh.sh` | GPG key + repo setup per distro |
| 6 Auditd | Security-Scripts `lib/logging.sh` lines 4-251 | CIS benchmark audit rules, distro-specific MAC rules |

### External References

| Resource | URL | Value |
|----------|-----|-------|
| DCAT WindowsDefenderHardening | github.com/dishycentral-hub/WindowsDefenderHardening | Best undo/rollback architecture |
| WinterKnight "How to Win CCDC" | winterknight.net/how-to-win-ccdc/ | Competition strategy, inject importance |
| bokkisec "Zero to Nationals" | bokkisec.com/blog/CCDC_Journey-Zero_to_Nationals | Live competition lessons, adversarial scripting |
| CyberLions/CCDC (Penn State) | github.com/CyberLions/CCDC | PS-heavy approach, Palo Alto XML rules |
| UCI-CCDC/CCDC | github.com/UCI-CCDC/CCDC | Go-based approach (alternative architecture reference) |
| authfinder (mass remote exec) | github.com/KhaelK138/authfinder | Post-MVP: push commands to all machines at once |
| dev-sec ansible-hardening | github.com/dev-sec/ansible-collection-hardening | Variable-driven hardening patterns (reference only, no Ansible) |
