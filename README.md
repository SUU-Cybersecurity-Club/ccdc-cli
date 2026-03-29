# ccdc-cli

A modular CLI toolkit for CCDC (Collegiate Cyber Defense Competition) hardening, defense, and monitoring. Built for speed under pressure — `git clone`, run, harden, defend.

**Bash on Linux. PowerShell on Windows. No dependencies. No internet required after clone.**

---

## Quick Start

### Linux — Fastest (one-liner, paste and go)

```bash
curl -sL https://github.com/SUU-Cybersecurity-Club/ccdc-cli/archive/refs/heads/main.tar.gz | tar xz && cd ccdc-cli-main && sudo ./ccdc.sh comp-start
```

### Linux — With git

```bash
git clone https://github.com/SUU-Cybersecurity-Club/ccdc-cli.git
cd ccdc-cli
sudo ./ccdc.sh comp-start
```

### Windows — Fastest (paste into Admin PowerShell)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest https://github.com/SUU-Cybersecurity-Club/ccdc-cli/archive/refs/heads/main.zip -OutFile ccdc.zip; Expand-Archive ccdc.zip .; cd ccdc-cli-main; .\ccdc.ps1 comp-start
```

### Windows — With git

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
git clone https://github.com/SUU-Cybersecurity-Club/ccdc-cli.git
cd ccdc-cli
.\ccdc.ps1 comp-start
```

### Step-by-step (if you want to review before running)

```bash
# Linux
curl -sL https://github.com/SUU-Cybersecurity-Club/ccdc-cli/archive/refs/heads/main.tar.gz | tar xz
cd ccdc-cli-main
sudo ./ccdc.sh config init          # Auto-detect OS, pkg manager, firewall — saves to .ccdc.conf
sudo ./ccdc.sh config show          # Verify detection, edit if needed
sudo ./ccdc.sh comp-start           # Run full 30-minute checklist
```

```powershell
# Windows (PowerShell as Administrator)
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Invoke-WebRequest https://github.com/SUU-Cybersecurity-Club/ccdc-cli/archive/refs/heads/main.zip -OutFile ccdc.zip
Expand-Archive ccdc.zip .
cd ccdc-cli-main
.\ccdc.ps1 config init              # Auto-detect and save
.\ccdc.ps1 config show              # Verify
.\ccdc.ps1 comp-start               # Run full 30-minute checklist
```

After downloading, firewall off outbound internet. Everything runs offline from here.

---

## Design Principles

- **Every command has an undo** — in competition, mistakes happen fast. Every function can be reversed
- **Modular** — each command is a standalone function. `comp-start` chains them, but you can run any command individually
- **Cross-platform** — same command names on Linux (bash) and Windows (PowerShell). The CLI detects the OS and runs the right script
- **Auto-detect with persistent overrides** — OS, package manager, firewall backend, and init system are detected automatically. Run `ccdc config` once to create an override file instead of passing flags every time
- **No internet required** — backup binaries and installers are bundled in the repo for offline use
- **Checklist-driven** — mirrors the 30-minute competition checklist so nothing gets missed

---

## CLI Structure

```
ccdc <category> <command> [options]
ccdc comp-start                    # Run full first-30-minutes hardening (auto-detects OS)
ccdc <command> --undo              # Undo any command
ccdc <command> --help              # Help for any command
```

### Command Categories

Commands use full names with short aliases:

| Category | Alias | Platform | Description |
|----------|-------|----------|-------------|
| `passwd` | `pw` | Linux + Windows | Password management |
| `backup` | `bak` | Linux + Windows | Backup and restore |
| `discover` | `disc` | Linux + Windows | System discovery and recon |
| `service` | `svc` | Linux + Windows | Service management |
| `firewall` | `fw` | Linux + Windows + Firewall appliances | Firewall configuration |
| `harden` | `hrd` | Linux + Windows | System hardening |
| `siem` | `siem` | Linux + Windows | SIEM/monitoring setup |
| `install` | `inst` | Linux + Windows | Package and tool installation |
| `net` | `net` | Linux + Windows | Firewall-aware downloads (open, download, close) |
| `copy-paster` | `cp` | Host machine (Win/Mac/Linux) | Clipboard auto-typer for paste-blocked VMs |
| `config` | `cfg` | Linux + Windows | Persistent config overrides (OS, pkg, firewall, etc.) |

---

## Commands Reference

### passwd / pw — Password Management

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc passwd change-all` | `ccdc pw chg` | Change all user passwords (interactive) |
| `ccdc passwd change <user>` | `ccdc pw chg <user>` | Change specific user password |
| `ccdc passwd backup-user` | `ccdc pw bak` | Create backup admin user (default: "printer") |
| `ccdc passwd root` | `ccdc pw root` | Change root/Administrator password |
| `ccdc passwd ad-change <user>` | `ccdc pw ad <user>` | Change AD account password (Windows) |
| `ccdc passwd dsrm` | `ccdc pw dsrm` | Reset DSRM password (Windows AD) |

### backup / bak — Backup and Restore

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc backup etc` | `ccdc bak etc` | Backup /etc (Linux) or registry hives (Windows) |
| `ccdc backup services` | `ccdc bak svc` | Snapshot running services list |
| `ccdc backup web` | `ccdc bak web` | Backup /var/www/html, /opt, or IIS wwwroot |
| `ccdc backup binaries` | `ccdc bak bin` | Backup critical binaries (/usr/bin, /usr/sbin) |
| `ccdc backup db` | `ccdc bak db` | mysqldump all databases |
| `ccdc backup full` | `ccdc bak full` | Run all backups |
| `ccdc backup restore <archive>` | `ccdc bak rest` | Restore from a backup archive |

### discover / disc — System Discovery

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc discover network` | `ccdc disc net` | Show IPs, MACs, gateway, routes |
| `ccdc discover ports` | `ccdc disc ports` | List listening ports with process info (ss/netstat) |
| `ccdc discover users` | `ccdc disc users` | List users, groups, sudoers/admins |
| `ccdc discover processes` | `ccdc disc ps` | Process tree, look for rev shells |
| `ccdc discover cron` | `ccdc disc cron` | List all cron jobs and scheduled tasks |
| `ccdc discover services` | `ccdc disc svc` | List running/enabled services |
| `ccdc discover firewall` | `ccdc disc fw` | Dump current firewall rules |
| `ccdc discover integrity` | `ccdc disc intg` | Run debsums/rpm -Va package integrity check |
| `ccdc discover all` | `ccdc disc all` | Run all discovery, save to files |

### service / svc — Service Management

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc service list` | `ccdc svc ls` | List all running services |
| `ccdc service stop <name>` | `ccdc svc stop` | Stop a service |
| `ccdc service disable <name>` | `ccdc svc off` | Stop and disable a service |
| `ccdc service enable <name>` | `ccdc svc on` | Enable and start a service |
| `ccdc service cockpit` | `ccdc svc cockpit` | Stop, disable, remove Cockpit |

### firewall / fw — Firewall Configuration

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc firewall on` | `ccdc fw on` | Enable firewall (auto-detects backend) |
| `ccdc firewall allow-in <port> [proto]` | `ccdc fw in` | Allow inbound port |
| `ccdc firewall block-in <port> [proto]` | `ccdc fw bin` | Block inbound port |
| `ccdc firewall allow-out <port> [proto]` | `ccdc fw out` | Allow outbound port |
| `ccdc firewall block-out <port> [proto]` | `ccdc fw bout` | Block outbound port |
| `ccdc firewall drop-all-in` | `ccdc fw dai` | Default deny inbound, keep allowed ports |
| `ccdc firewall drop-all-out` | `ccdc fw dao` | Default deny outbound, keep allowed ports |
| `ccdc firewall allow-only-in <ports>` | `ccdc fw aoi` | Drop all inbound except listed ports |
| `ccdc firewall block-ip <ip>` | `ccdc fw blk` | Block all traffic from IP |
| `ccdc firewall status` | `ccdc fw st` | Show current firewall rules |
| `ccdc firewall save` | `ccdc fw save` | Persist rules across reboot |
| `ccdc firewall allow-internet` | `ccdc fw inet` | Temporarily open outbound for downloads |
| `ccdc firewall block-internet` | `ccdc fw noinet` | Close outbound back down |

### net — Network Utilities (firewall-aware)

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc net wget <url> [output]` | `ccdc net wget` | Open firewall, download file, close firewall automatically |
| `ccdc net curl <url>` | `ccdc net curl` | Open firewall, curl URL, close firewall automatically |

### harden / hrd — System Hardening

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc harden ssh` | `ccdc hrd ssh` | Harden or disable SSH/OpenSSH |
| `ccdc harden smb` | `ccdc hrd smb` | Disable SMBv1, optionally disable SMBv2 |
| `ccdc harden cron` | `ccdc hrd cron` | Nuke all cron jobs (backup first) |
| `ccdc harden banner` | `ccdc hrd banner` | Set login banner (/etc/issue, registry) |
| `ccdc harden anon-login` | `ccdc hrd anon` | Fix anonymous login registry keys (Windows) |
| `ccdc harden gpo` | `ccdc hrd gpo` | Apply password policy, lockout, audit via PowerShell |
| `ccdc harden defender` | `ccdc hrd def` | Enable and configure Windows Defender |
| `ccdc harden updates` | `ccdc hrd upd` | Fix Windows Update service if broken |
| `ccdc harden mysql` | `ccdc hrd mysql` | Run mysql_secure_installation, change root pw |
| `ccdc harden kerberos` | `ccdc hrd krb` | Fix Kerberos preauth (Windows AD) |
| `ccdc harden revshell-check` | `ccdc hrd rev` | Check .bashrc, profile.d, cron for rev shells |

### siem — SIEM and Monitoring

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc siem wazuh-server` | `ccdc siem ws` | Install Wazuh server/indexer |
| `ccdc siem wazuh-agent` | `ccdc siem wa` | Install Wazuh agent, connect to server |
| `ccdc siem splunk-server` | `ccdc siem ss` | Install Splunk indexer |
| `ccdc siem splunk-agent` | `ccdc siem sa` | Install Splunk Universal Forwarder |
| `ccdc siem suricata` | `ccdc siem sur` | Install and configure Suricata IDS |
| `ccdc siem zeek` | `ccdc siem zeek` | Install and configure Zeek |
| `ccdc siem snoopy` | `ccdc siem snoop` | Install Snoopy command logger |
| `ccdc siem auditd` | `ccdc siem aud` | Install and configure auditd with rules |
| `ccdc siem sysmon` | `ccdc siem sysm` | Install and configure Sysmon (Windows) |

### install / inst — Package and Tool Installation

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc install malwarebytes` | `ccdc inst mwb` | Install Malwarebytes (Windows) |
| `ccdc install nmap` | `ccdc inst nmap` | Install nmap |
| `ccdc install tmux` | `ccdc inst tmux` | Install tmux (Linux, used for parallel comp-start) |
| `ccdc install aide` | `ccdc inst aide` | Install AIDE file integrity monitor |

### copy-paster / cp — Clipboard Auto-Typer (for non-competition machines)

Standalone utility for typing clipboard content into VMs or machines that block paste. Runs on the host/operator machine, not the competition box. Works on Windows, macOS, and Linux (Wayland + X11).

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc copy-paster` | `ccdc cp` | Type clipboard content with 5-second countdown |
| `ccdc copy-paster --delay <sec>` | `ccdc cp -d` | Custom countdown delay |
| `ccdc copy-paster --speed <ms>` | `ccdc cp -s` | Set typing speed (ms per char, default: 10) |

### config / cfg — Persistent Configuration

Instead of passing `--os`, `--pkg`, `--fw-backend` flags on every command, run `ccdc config` once to create an override file. All future commands read from this file automatically.

| Command | Alias | Description |
|---------|-------|-------------|
| `ccdc config init` | `ccdc cfg init` | Auto-detect everything, write to config file |
| `ccdc config set <key> <value>` | `ccdc cfg set` | Set a single override value |
| `ccdc config show` | `ccdc cfg show` | Show current config (detected + overrides) |
| `ccdc config reset` | `ccdc cfg reset` | Delete config file, go back to auto-detect |
| `ccdc config edit` | `ccdc cfg edit` | Open config file in editor |

**Config file location:**
- Linux: `<ccdc-cli-dir>/.ccdc.conf`
- Windows: `<ccdc-cli-dir>\.ccdc.conf`

The file lives in the repo directory so each machine gets its own config. It is gitignored.

**Example usage:**

```bash
# Auto-detect and save (run once per machine)
ccdc config init

# Override if detection is wrong
ccdc config set os oracle
ccdc config set pkg dnf
ccdc config set fw_backend firewalld

# Check what's set
ccdc config show
```

**Config file format** (plain key=value, easy to hand-edit):

```ini
# ccdc-cli config — auto-generated, safe to edit
# Delete this file to go back to auto-detect (or run: ccdc config reset)

os=oracle
os_family=rhel
os_version=9
pkg=dnf
fw_backend=firewalld
backup_dir=/ccdc-backups
wazuh_server_ip=172.20.242.20
splunk_server_ip=172.25.24.9
scored_ports_tcp=80,21,53,25,110
scored_ports_udp=53,123
```

**Available config keys:**

| Key | Values | Description |
|-----|--------|-------------|
| `os` | ubuntu, debian, fedora, centos, rocky, alma, oracle | OS name |
| `os_family` | debian, rhel | OS family (auto-set from os) |
| `os_version` | e.g. 24.04, 9, 42 | OS version |
| `pkg` | apt, dnf, yum, zypper, pacman | Package manager |
| `fw_backend` | iptables, ufw, nft, firewalld | Firewall backend |
| `backup_dir` | any path | Backup directory (default: /ccdc-backups or C:\ccdc-backups) |
| `wazuh_server_ip` | IP address | Wazuh server for agent connection |
| `splunk_server_ip` | IP address | Splunk indexer for forwarder connection |
| `scored_ports_tcp` | comma-separated ports | TCP ports to allow inbound |
| `scored_ports_udp` | comma-separated ports | UDP ports to allow inbound |

**How detection works with config:**
1. On any command, check if `.ccdc.conf` exists
2. If yes, load values from file (overrides win over auto-detect)
3. If no, auto-detect everything at runtime
4. `ccdc config init` runs auto-detect and saves results so you can review/edit

---

## comp-start — Competition Quick Start

`ccdc comp-start` auto-detects the OS and runs the first-30-minutes checklist:

### Linux comp-start sequence:
1. Change all user passwords (interactive)
2. Create backup user
3. Backup /etc, /usr/bin, /usr/sbin, web dirs, databases
4. Discovery: network, ports, users, processes, cron, services
5. Disable Cockpit
6. Harden SSH (or remove if not scored)
7. Nuke cron jobs
8. Check for rev shells in profiles/.bashrc
9. Firewall: allow only scored inbound ports, drop all else
10. Run debsums/rpm -Va integrity check
11. Install Snoopy + auditd
12. Install Wazuh agent (if server IP provided)
13. Set login banner

### Windows comp-start sequence:
1. Change all local + AD user passwords (interactive)
2. Create backup admin user
3. Backup services list, registry, web dirs, databases
4. Discovery: network, ports, users, services
5. Enable and configure Windows Defender
6. Disable SMBv1
7. Fix anonymous login registry keys
8. Enable Windows Firewall, allow only scored ports
9. Set login banner via registry
10. Apply GPO: password policy, lockout, audit logging
11. Install Sysmon
12. Install Wazuh agent (if server IP provided)
13. Fix Windows Update service if broken

---

## Global Flags

| Flag | Description |
|------|-------------|
| `--undo` | Undo the last run of this command |
| `--help`, `-h` | Show help for any command |
| `--no-prompt` | Skip confirmation prompts (use with caution) |
| `--dry-run` | Show what would be done without doing it |
| `--verbose`, `-v` | Verbose output |

> OS, package manager, firewall backend, and backup directory are **not** per-command flags.
> Use `ccdc config set <key> <value>` to override detection persistently. See [config / cfg](#config--cfg--persistent-configuration).

---

## Directory Structure

```
ccdc-cli/
|-- ccdc.sh                  # Linux entry point
|-- ccdc.ps1                 # Windows entry point
|-- .ccdc.conf               # Per-machine config overrides (gitignored, created by ccdc config init)
|-- lib/
|   |-- linux/               # Linux bash modules
|   |   |-- passwd.sh
|   |   |-- backup.sh
|   |   |-- discover.sh
|   |   |-- service.sh
|   |   |-- firewall.sh
|   |   |-- net.sh           # Firewall-aware downloads
|   |   |-- harden.sh
|   |   |-- siem.sh
|   |   |-- install.sh
|   |   |-- detect.sh        # OS/pkg/fw auto-detection
|   |   |-- undo.sh          # Undo framework
|   |   `-- common.sh        # Shared helpers
|   |-- windows/              # Windows PowerShell modules
|   |   |-- passwd.psm1
|   |   |-- backup.psm1
|   |   |-- discover.psm1
|   |   |-- service.psm1
|   |   |-- firewall.psm1
|   |   |-- net.psm1
|   |   |-- harden.psm1
|   |   |-- siem.psm1
|   |   |-- install.psm1
|   |   |-- detect.psm1
|   |   |-- undo.psm1
|   |   `-- common.psm1
|   `-- copy-paster/          # Clipboard auto-typer (runs on operator machine)
|       |-- copy-paster.sh    # Linux (X11 via xdotool, Wayland via wtype)
|       |-- copy-paster.ps1   # Windows (SendKeys)
|       `-- copy-paster.mac   # macOS (osascript)
|-- bin/                      # Bundled offline binaries/installers
|   |-- linux/
|   `-- windows/
|-- docs/
|   |-- linux.md              # Linux reference guide
|   |-- windows.md            # Windows reference guide
|   `-- firewall.md           # Firewall reference guide (all platforms)
|-- plans/                    # Future expansion plans
`-- README.md
```

---

## Supported Platforms

### Linux
- Ubuntu 20.04, 22.04, 24.04
- Debian 11, 12
- Fedora 40+
- CentOS / Rocky / AlmaLinux 8, 9
- Oracle Linux 8, 9 (treated as RHEL-like)

### Windows
- Windows Server 2019
- Windows Server 2022
- Windows 10/11

### Firewall Backends (Linux)
- iptables + iptables-persistent
- ufw
- nftables (nft)
- firewalld

### Firewall Backends (Windows)
- Windows Firewall (NetSecurity PowerShell module)

---

## Docs

- [Linux Reference Guide](docs/linux.md) — password, backup, discovery, hardening, SIEM for Debian and RHEL side by side
- [Windows Reference Guide](docs/windows.md) — password, backup, discovery, defender, AD, hardening, SIEM
- [Firewall Reference Guide](docs/firewall.md) — iptables, ufw, nft, firewalld, Windows Firewall, Palo Alto, Cisco FTD

---

## Contributing

This started as an internal tool for one CCDC team. If you find it useful:

1. Fork it
2. Add your modules to `lib/linux/` or `lib/windows/`
3. Every new command must have `--undo` and `--help`
4. Test on at least one Debian-based and one RHEL-based distro
5. PR it back

---

## License

TBD
