# Linux Reference Guide

Quick reference for CCDC Linux hardening. Debian/Ubuntu and RHEL/Fedora/CentOS/Oracle side by side.

> All commands assume root or sudo. Checkboxes for tracking during competition.

---

## Password Change

- [ ] **Change current user password**

```bash
passwd
```

- [ ] **Change another user's password**

```bash
sudo passwd [username]
```

- [ ] **Change all non-root user passwords (one by one)**

```bash
# List users with login shells
getent passwd | grep -E '/bin/(bash|sh|zsh)' | cut -d: -f1

# Change each
sudo passwd [username]
```

---

## Backup User

- [ ] **Create backup admin user**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo adduser printer` | `sudo useradd -m printer` |
| `sudo usermod -aG sudo printer` | `passwd printer` |
| | `sudo usermod -aG wheel printer` |

---

## Backups

- [ ] **Backup /etc**

```bash
mkdir -p /ccdc-backups
cd /
sudo tar -cpf /ccdc-backups/etc-backup.tar /etc
```

- [ ] **Backup critical binaries**

```bash
sudo tar -cpf /ccdc-backups/usr-bin.tar /usr/bin
sudo tar -cpf /ccdc-backups/usr-sbin.tar /usr/sbin
```

- [ ] **Backup /opt** (if Splunk or other services live here)

```bash
sudo tar -cpf /ccdc-backups/opt.tar /opt
```

- [ ] **Backup /srv** (if not empty)

```bash
sudo tar -cpf /ccdc-backups/srv.tar /srv
```

- [ ] **Backup web content**

```bash
sudo tar -cpf /ccdc-backups/www.tar /var/www/html
```

- [ ] **Backup database (MariaDB/MySQL)**

```bash
# List databases
mysql -u root -p -e "SHOW DATABASES;"

# Dump all databases
mysqldump -u root -p --all-databases > /ccdc-backups/all-databases.sql

# Dump single database
mysqldump -u root -p [database_name] > /ccdc-backups/[database_name].sql

# Dump single table
mysqldump -u root -p [database_name] [table_name] > /ccdc-backups/[table_name].sql
```

- [ ] **Restore from backup**

```bash
# Restore tar archive
sudo tar -xpf /ccdc-backups/etc-backup.tar -C /

# Restore database
mysql -u root -p [database_name] < /ccdc-backups/[database_name].sql

# Overwrite database from backup
mysql -u root -p -e "DROP DATABASE IF EXISTS [name]; CREATE DATABASE [name];"
mysql -u root -p [name] < /ccdc-backups/[name].sql
```

---

## Discovery

Run all of these and save output to files for reference.

- [ ] **Network (IPs, MACs, gateway)**

```bash
ip a > /ccdc-backups/ips.txt
ip r > /ccdc-backups/routes.txt

# Newer systems
nmcli device show > /ccdc-backups/nmcli.txt

# Older systems
ifconfig > /ccdc-backups/ifconfig.txt
route -n > /ccdc-backups/routes.txt
```

- [ ] **Ports and services**

```bash
sudo ss -autpn > /ccdc-backups/ports.txt

# Alternative
sudo netstat -tulnp > /ccdc-backups/ports.txt

# Check specific port
sudo ss -tulnp | grep :[port]
lsof -i :[port]
```

- [ ] **Users and groups**

```bash
# Users with login shells
getent passwd | grep -E '/bin/(bash|sh|zsh)'

# All groups with members
getent group > /ccdc-backups/groups.txt

# Check sudo/wheel membership
getent group sudo
getent group wheel

# Current user info
id [username]

# Sudoers
sudo cat /etc/sudoers
sudo cat /etc/sudoers.d/*
```

- [ ] **Processes (look for rev shells)**

```bash
ps -eaf --forest > /ccdc-backups/processes.txt
```

- [ ] **Cron jobs**

```bash
crontab -l
crontab -l -u [user]
cat /etc/crontab
ls /etc/cron.d/
ls /etc/cron.daily/
ls /etc/cron.hourly/
```

- [ ] **Rev shell hiding spots**

```bash
cat /etc/profile
ls /etc/profile.d/
cat ~/.bashrc
cat ~/.bash_profile
ls ~/.bashrc.d/
ls /etc/bash_completion.d
ls /etc/pam.d
```

- [ ] **Running services**

```bash
systemctl list-units --type=service --state=running
systemctl list-unit-files --type=service --state=enabled
```

- [ ] **Firewall rules**

```bash
# Try both
firewall-cmd --list-all-zones > /ccdc-backups/firewall.txt 2>/dev/null
iptables-save > /ccdc-backups/iptables.txt 2>/dev/null
ufw status verbose > /ccdc-backups/ufw.txt 2>/dev/null
nft list ruleset > /ccdc-backups/nft.txt 2>/dev/null
```

- [ ] **Package integrity check**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo apt update && sudo apt install -y debsums` | `sudo rpm -Va > /ccdc-backups/rpm-verify.txt 2>&1 &` |
| `sudo debsums -s > /ccdc-backups/debsums.txt 2>&1 &` | |

> These run in background. Check results after they finish.

- [ ] **Nmap scan**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo apt install nmap -y` | `sudo dnf install nmap -y` |

```bash
nmap -sV -T4 -p- localhost > /ccdc-backups/nmap.txt
```

---

## Hardening

### Cockpit (Remove Always)

- [ ] **Stop and remove Cockpit**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo systemctl stop cockpit` | `systemctl stop cockpit` |
| `sudo systemctl disable cockpit` | `systemctl disable cockpit` |
| `sudo apt remove cockpit -y` | `dnf remove cockpit -y` |

> Also block inbound TCP 9090 in firewall.

### SSH

- [ ] **Remove SSH if not scored**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo apt remove openssh-server -y` | `sudo dnf remove openssh-server -y` |
| | `sudo systemctl daemon-reload` |

> Block inbound TCP 22 in firewall.

- [ ] **Harden SSH (if keeping it)**

Edit `/etc/ssh/sshd_config`:
```
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
Banner /etc/issue.net
```

```bash
sudo systemctl restart sshd
```

### Cron Jobs

- [ ] **Nuke cron jobs** (backup first)

```bash
# Backup
crontab -l > /ccdc-backups/crontab-$(whoami).txt
for user in $(getent passwd | cut -d: -f1); do
    crontab -l -u $user 2>/dev/null > /ccdc-backups/crontab-$user.txt
done

# Nuke: comment out /etc/crontab entries
# Edit crontabs, comment out suspicious entries (don't delete, comment)
crontab -e
crontab -e -u [user]
sudo vim /etc/crontab
```

### Login Banner

- [ ] **Set login banner**

```bash
# SSH banner
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
systemctl restart sshd

# Set banner text
cat > /etc/issue.net << 'EOF'
Authorized access only. All activity is monitored and logged.
EOF

cp /etc/issue.net /etc/issue
```

### DNS

- [ ] **Force DNS** (temporary, wipes on reboot)

```bash
# Edit /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
```

### SMB

- [ ] **Disable SMBv1** (Linux rarely needs this, but check)

```bash
# Check if samba is running
systemctl status smbd 2>/dev/null || systemctl status smb 2>/dev/null
```

---

## MariaDB/MySQL Hardening

- [ ] **Secure installation**

```bash
sudo mysql_secure_installation
```

- [ ] **Change root password**

```bash
mysql -u root -p -e "ALTER USER 'root'@'%' IDENTIFIED BY 'new_password';"
```

- [ ] **List users**

```bash
mysql -u root -p -e "SELECT User, Host FROM mysql.user;"
```

- [ ] **Create user**

```bash
mysql -u root -p -e "CREATE USER 'new_user'@'localhost' IDENTIFIED BY 'password';"
```

> Block inbound TCP 3306 in firewall unless needed between specific machines.

---

## SIEM and Monitoring

### Auditd

- [ ] **Install auditd**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `apt install auditd audispd-plugins` | `dnf install audit` |

- [ ] **Configure audit rules**

Edit `/etc/audit/rules.d/99-custom.conf`:

```
# Failed file access attempts
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access

# User/group modifications
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/pam.conf -p wa -k identity
-w /etc/pam.d -p wa -k identity

# Permission changes
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat,chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=unset -F key=perm_mod

# Session tracking
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# Login tracking
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# File deletions
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -k delete

# Privileged commands
-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=1000 -F auid!=unset -k priv_comm
-a always,exit -F path=/usr/bin/passwd -F perm=x -F auid>=1000 -F auid!=unset -k priv_comm
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=unset -k priv_comm
-a always,exit -F path=/usr/bin/su -F perm=x -F auid>=1000 -F auid!=unset -k priv_comm
-a always,exit -F path=/usr/sbin/useradd -F perm=x -F auid>=1000 -F auid!=unset -k priv_comm
-a always,exit -F path=/usr/sbin/userdel -F perm=x -F auid>=1000 -F auid!=unset -k priv_comm
```

```bash
augenrules --load
```

- [ ] **Useful auditd reports**

```bash
aureport                  # Overview
aureport -i -e            # Events
aureport -i -k            # Events by key
aureport -i --comm        # Commands run
aureport -i -f            # File interactions
aureport -i -u            # User actions
aureport -i -x            # Executables ran
ausearch -a <event_ID>    # Specific event details
```

### Snoopy (Command Logger)

- [ ] **Install and check Snoopy**

```bash
snoopyctl
# Logs to /var/log/snoopy.log
# Config at /etc/snoopy.ini or via snoopyctl conf
```

### Splunk Server (Indexer)

- [ ] **Install Splunk indexer**

```bash
# Download and run install script
./splunk.sh -i
# Set user: splunk
# Logs: /opt/splunk/var/log/splunk
# Manage: systemctl start/stop/status Splunkd.service
```

### Splunk Forwarder (Agent)

- [ ] **Install Splunk forwarder**

```bash
./splunk.sh -f [Indexer_IP]
# Set user: splunkfwd
# Set password: same as printer user password of the host

# Add file to monitor
./splunk.sh -a [path]
# Index options: main, web, linux, snoopy, system, misc

# Manual start/stop
/opt/splunk/bin/splunk start
/opt/splunk/bin/splunk stop
/opt/splunk/bin/splunk status
```

### Wazuh Agent

- [ ] **Install Wazuh agent and connect to server**

> See `ccdc siem wazuh-agent` and `ccdc siem wazuh-server` commands.

### Suricata

- [ ] **Install Suricata**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo apt update && sudo apt install -y suricata` | `sudo dnf install -y epel-release && sudo dnf install -y suricata` |

- [ ] **Configure Suricata**

Edit `/etc/suricata/suricata.yaml`:
```yaml
vars:
  address-groups:
    HOME_NET: "[your_network/cidr]"

af-packet:
  - interface: eth0    # change to your interface (ip a to find it)
```

```bash
sudo suricata-update                              # Download rules
sudo suricata -T -c /etc/suricata/suricata.yaml   # Test config
sudo systemctl enable --now suricata              # Start
```

- [ ] **Suricata log locations**

| Log | Purpose |
|-----|---------|
| `/var/log/suricata/fast.log` | Quick one-line alerts (easiest to read) |
| `/var/log/suricata/eve.json` | Full JSON detail (alerts, dns, http, tls, flow) |
| `/var/log/suricata/stats.log` | Performance stats |

```bash
grep "ET MALWARE" /var/log/suricata/fast.log
grep "ET TROJAN" /var/log/suricata/fast.log
grep "ET SCAN" /var/log/suricata/fast.log
```

### Zeek

- [ ] **Install Zeek**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo apt update && sudo apt install -y zeek` | `sudo dnf install -y zeek` |

If not in default repos, add the OpenSUSE Zeek repository.

- [ ] **Configure Zeek**

```bash
# Set interface
sudo vim /opt/zeek/etc/node.cfg
# Change: interface=eth0 to your interface

# Set local networks
sudo vim /opt/zeek/etc/networks.cfg
# Example: 172.16.0.0/12    Internal range

# Start
sudo /opt/zeek/bin/zeekctl deploy
sudo /opt/zeek/bin/zeekctl status
```

- [ ] **Zeek log locations**

| Log | Purpose |
|-----|---------|
| `/opt/zeek/logs/current/conn.log` | Every connection - MOST IMPORTANT |
| `/opt/zeek/logs/current/dns.log` | DNS queries and responses |
| `/opt/zeek/logs/current/http.log` | HTTP requests, URLs, user agents |
| `/opt/zeek/logs/current/ssl.log` | TLS/SSL connections, certs, SNI |
| `/opt/zeek/logs/current/files.log` | Files on the wire: type, size, hashes |
| `/opt/zeek/logs/current/weird.log` | Protocol violations, unusual behavior |
| `/opt/zeek/logs/current/notice.log` | Built-in alerts |

```bash
# Search for suspicious domain
grep -i "suspicious-domain.com" /opt/zeek/logs/current/dns.log

# Top 20 most connected-to IPs (beacon hunting)
cat /opt/zeek/logs/current/conn.log | /opt/zeek/bin/zeek-cut id.resp_h | sort | uniq -c | sort -rn | head -20

# Top 20 source-dest pairs
cat /opt/zeek/logs/current/conn.log | /opt/zeek/bin/zeek-cut id.orig_h id.resp_h | sort | uniq -c | sort -rn | head -20

# Common suspicious ports
grep -E "\b(4444|5555|8080|1337|9001)\b" /opt/zeek/logs/current/conn.log
```

---

## Apache Web Server

- [ ] **Install Apache**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `sudo apt install apache2 -y` | `sudo dnf install httpd -y` |
| `sudo systemctl enable --now apache2` | `sudo systemctl enable --now httpd` |

- [ ] **Backup website**

```bash
sudo tar -cpf /ccdc-backups/www.tar /var/www/html
# Also check /opt for web content
```

- [ ] **Check for phpMyAdmin** (remove if found)

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `ls /etc/apache2/sites-enabled` | `ls /etc/httpd/sites-enabled` |

> Remove phpMyAdmin if present. It is a common attack vector.

---

## AIDE (File Integrity) — Optional, Slow

> debsums/rpm -Va is preferred for speed. AIDE is thorough but slow.

- [ ] **Install AIDE**

| Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|---------------|---------------------------|
| `apt install aide` | `dnf install aide` |
| `aide -i --config /etc/aide/aide.conf > aidebackup &` | `aide -i --config /etc/aide.conf > aidebackup &` |
| `mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db` | `mv /var/lib/aide.db.new.gz /var/lib/aide/aide.db.gz` |

---

## Process Management

```bash
# List all processes
ps -eaf --forest | less

# Processes by user
ps -u [username]

# Force kill
kill -9 [pid]
```

---

## Quick Reference: Package Managers

| Action | Debian/Ubuntu | RHEL/Fedora/CentOS/Oracle |
|--------|---------------|---------------------------|
| Update repos | `apt update` | `dnf upgrade --refresh` |
| Install | `apt install -y [pkg]` | `dnf install -y [pkg]` |
| Remove | `apt remove -y [pkg]` | `dnf remove -y [pkg]` |
| Search | `apt search [pkg]` | `dnf search [pkg]` |
| Upgrade all | `apt upgrade -y` | `dnf upgrade -y` |
