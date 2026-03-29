# Windows Reference Guide

Quick reference for CCDC Windows hardening. Covers local machines and Active Directory (AD).

> All commands run in PowerShell as Administrator. On Server Core (CMD only), type `powershell` first.

---

## Password Change

- [ ] **Change local user password**

```powershell
$Password = Read-Host "Enter password" -AsSecureString
Set-LocalUser -Name "[username]" -Password $Password
```

- [ ] **Change local Administrator password**

```powershell
$Password = Read-Host "Enter password" -AsSecureString
Set-LocalUser -Name "Administrator" -Password $Password
```

- [ ] **Change AD account password**

```powershell
Set-ADAccountPassword -Identity [username] -Reset -NewPassword `
(Read-Host -AsSecureString "Enter password")
```

- [ ] **Change AD Administrator password**

```powershell
Set-ADAccountPassword -Identity Administrator -Reset -NewPassword `
(Read-Host -AsSecureString "Enter password")
```

- [ ] **Reset DSRM password** (run each line separately)

```
ntdsutil
set dsrm password
reset password on server null
Quit
Quit
```

---

## Backup User

- [ ] **Create AD backup admin user**

```powershell
$Password = Read-Host "Enter password for new admin" -AsSecureString

New-ADUser `
    -Name "printer" `
    -SamAccountName "printer" `
    -UserPrincipalName "printer@[domain-name]" `
    -AccountPassword $Password `
    -Enabled $true `
    -Path "OU=Admins,DC=domain,DC=local"

Add-ADGroupMember -Identity "Domain Admins" -Members "printer"
```

- [ ] **Create local backup admin user**

```powershell
$Password = Read-Host "Enter password for local user" -AsSecureString

New-LocalUser `
    -Name "printer" `
    -Password $Password `
    -FullName "printer" `
    -Description "backup admin account"

Add-LocalGroupMember `
    -Group "Administrators" `
    -Member "printer"
```

---

## Backups

- [ ] **Backup services list**

```powershell
$BackupPath = "C:\ccdc-backups"
New-Item -ItemType Directory -Path $BackupPath -Force

Get-CimInstance Win32_Service |
Select-Object `
    Name,
    DisplayName,
    State,
    StartMode,
    StartName,
    PathName |
Export-Csv "$BackupPath\Services_Backup.csv" -NoTypeInformation
```

- [ ] **Backup files/folders**

```powershell
# Single file
Compress-Archive -Path "[path to file]" -DestinationPath "C:\ccdc-backups\file.zip"

# Directory
Compress-Archive -Path "[path to directory]" -DestinationPath "C:\ccdc-backups\dir.zip"

# Time-stamped backup
$Date = Get-Date -Format "yyyy-MM-dd_HHmm"
Compress-Archive -Path "C:\inetpub\wwwroot" -DestinationPath "C:\ccdc-backups\wwwroot_$Date.zip"
```

- [ ] **Backup database (MariaDB/MySQL on Windows)**

```powershell
# If MySQL is installed on Windows
mysql -u root -p -e "SHOW DATABASES;"
mysqldump -u root -p --all-databases > C:\ccdc-backups\all-databases.sql
```

---

## Discovery

- [ ] **Network (IPs, gateway, domain)**

```powershell
ipconfig /all
```

- [ ] **Ports and services**

```powershell
Get-NetTCPConnection | Sort-Object LocalPort

# Nmap (Server 2022+)
winget install --id Insecure.Nmap -e
nmap -sV -T4 -p- localhost
```

> Server 2019 and earlier: no native nmap install from PowerShell. Use `Get-NetTCPConnection` only.

- [ ] **Local users and admins**

```powershell
# Local admins
net localgroup administrators

# Local users
net localgroup users
```

- [ ] **AD users and admins** (Domain Controller only)

```powershell
# Domain Admins
Get-ADGroupMember "Domain Admins" -Recursive |
Select Name, SamAccountName, ObjectClass

# Enterprise Admins
Get-ADGroupMember "Enterprise Admins" -Recursive |
Select Name, SamAccountName, ObjectClass
```

- [ ] **Kerberos tickets** (check for extra/exploitable tickets)

```powershell
klist
# or
klist tickets
```

- [ ] **Running services**

```powershell
Get-Service | Where-Object {$_.Status -eq "Running"}
```

---

## Windows Defender

- [ ] **Install Windows Defender** (if missing, especially Server 2019)

```powershell
Install-WindowsFeature Windows-Defender
# RESTART REQUIRED after install
```

- [ ] **Check Defender status**

```powershell
Get-MpComputerStatus
```

- [ ] **Enable all Defender protections**

```powershell
# Update signatures
Start-Process powershell "echo 'Updating AV signatures...'; Update-MpSignature"

# Enable protections
Set-MpPreference -MAPSReporting Advanced
Set-MpPreference -SubmitSamplesConsent Always
Set-MpPreference -DisableBlockAtFirstSeen 0
Set-MpPreference -DisableIOAVProtection 0
Set-MpPreference -DisableRealtimeMonitoring 0
Set-MpPreference -DisableBehaviorMonitoring 0
Set-MpPreference -DisableScriptScanning 0
Set-MpPreference -DisableRemovableDriveScanning 0
Set-MpPreference -PUAProtection Enabled
Set-MpPreference -DisableArchiveScanning 0
Set-MpPreference -DisableEmailScanning 0
Set-MpPreference -CheckForSignaturesBeforeRunningScan 1
```

---

## TLS 1.2 Strong Crypto

- [ ] **Enforce TLS 1.2 for .NET applications** (prevents downgrade attacks)

```powershell
# 64-bit
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value 1
# 32-bit on 64-bit OS
Set-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value 1
```

---

## RDP, PS Remoting, WinRM

- [ ] **Disable RDP** (if not scored)

```powershell
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1
Get-NetFirewallRule -DisplayName "Remote Desktop*" | Disable-NetFirewallRule
```

- [ ] **Disable PowerShell Remoting**

```powershell
Disable-PSRemoting -Force
```

- [ ] **Disable WinRM**

```powershell
Stop-Service WinRM
Set-Service WinRM -StartupType Disabled
Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" | Disable-NetFirewallRule
```

---

## Print Spooler

- [ ] **Disable Print Spooler** (common attack vector — PrintNightmare)

```powershell
Stop-Service Spooler
Set-Service Spooler -StartupType Disabled
```

---

## SMB

- [ ] **Disable SMBv1 and SMBv2**

```powershell
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Set-SmbServerConfiguration -EnableSMB2Protocol $false -Force
```

> Only disable SMBv2 if the service doesn't need file sharing. AD environments may need SMBv2.

---

## Login Banner

- [ ] **Set login banner via registry**

```powershell
$title = "Security Notice"
$message = "Authorized access only. All activity is monitored and logged."

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "legalnoticecaption" -Value $title
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "legalnoticetext" -Value $message
```

Or manually: `regedit` > `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` > Edit `legalnoticecaption` and `legalnoticetext`.

---

## Anonymous Login Fix

- [ ] **Fix anonymous login registry keys**

In `regedit` at `HKLM\SYSTEM\CurrentControlSet\Control\Lsa`:

| Key | Value |
|-----|-------|
| `RestrictAnonymous` | `1` |
| `RestrictAnonymousSAM` | `1` |
| `EveryoneIncludesAnonymous` | `0` |

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 1
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -Value 1
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "EveryoneIncludesAnonymous" -Value 0
```

---

## Kerberos Preauth

- [ ] **Ensure Kerberos preauth is enabled for all AD accounts**

```powershell
# Find accounts with preauth disabled
Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} | Select Name, SamAccountName

# Enable preauth
Set-ADAccountControl -Identity [username] -DoesNotRequirePreAuth $false
```

---

## GPO / Group Policy (via PowerShell)

- [ ] **Password Policy**

Path: `Computer Config > Windows Settings > Security > Account > Password Policy`

| Setting | Value |
|---------|-------|
| Minimum length | 12 characters |
| Complexity | Enabled |
| Maximum age | 60 days |

- [ ] **Lockout Policy**

Path: `Computer Config > Windows Settings > Security > Account > Account Lockout`

| Setting | Value |
|---------|-------|
| Threshold | 5 attempts |
| Duration | 5 minutes |

- [ ] **Audit Policy**

Path: `Computer Config > Windows Settings > Security > Advanced Audit Policy`

| Category | Setting |
|----------|---------|
| Kerberos Authentication | Success + Failure |
| Service Ticket Operations | Success + Failure |
| Audit Logon | Success + Failure |
| Audit Special Logon | Success |

```powershell
# Apply via PowerShell
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Special Logon" /success:enable
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
```

---

## Windows Update Service Fix

- [ ] **Recreate Windows Update service** (if broken/deleted)

```powershell
sc.exe create wuauserv binPath= "C:\Windows\System32\svchost.exe -k netsvcs -p"
sc.exe config wuauserv type= share
sc.exe config wuauserv start= delayed-auto
sc.exe config wuauserv DisplayName= "Windows Update"
```

```powershell
# Registry fix
reg add "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv" /v ImagePath /t REG_EXPAND_SZ /d "%systemroot%\system32\svchost.exe -k netsvcs -p" /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv" /v Start /t REG_DWORD /d 3 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv" /v Type /t REG_DWORD /d 32 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv\Parameters" /v ServiceDll /t REG_EXPAND_SZ /d "%systemroot%\system32\wuaueng.dll" /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv\Parameters" /v ServiceDllUnloadOnStop /t REG_DWORD /d 1 /f
```

> Restart after applying.

- [ ] **Recreate Windows Defender service** (if broken/deleted)

```powershell
sc.exe create WinDefend binPath= "\"C:\Program Files\Windows Defender\MsMpEng.exe\""
sc.exe config WinDefend type= own
sc.exe config WinDefend start= auto
sc.exe config WinDefend DisplayName= "Windows Defender Antivirus Service"
sc.exe config WinDefend depend= RpcSs
```

---

## SIEM and Monitoring

### Splunk Forwarder

- [ ] **Install Splunk forwarder**

```powershell
curl https://raw.githubusercontent.com/BYU-CCDC/public-ccdc-resources/refs/heads/main/splunk/splunk.ps1 -o splunk.ps1
.\splunk.ps1 -ip [Server_IP]
# USERNAME: splunk
# PASSWORD: printer user password of this host
# REBOOT after install

# Reset password if login fails
.\splunk.ps1 -ResetPassword
```

- [ ] **Add file to monitor**

```powershell
cd "C:\Program Files\SplunkUniversalForwarder\bin"
.\splunk add monitor "C:\path\to\file" -index main
# Index options: main, web, windows, system, misc
```

### Sysmon

- [ ] **Sysmon SSH connection log script**

```powershell
$OutputFile = "C:\sysmon-ssh-logs.txt"

$Events = Get-WinEvent -FilterHashtable @{
    LogName = "Microsoft-Windows-Sysmon/Operational"
    Id      = 3
} -ErrorAction SilentlyContinue

$SSHEvents = $Events | Where-Object {
    $_.Message -match "DestinationPort:\s+22"
}

$SSHEvents | Select-Object TimeCreated, Id, Message |
    Format-List | Out-File -FilePath $OutputFile -Encoding UTF8
```

- [ ] **Multi-port Sysmon log script**

```powershell
$OutputFile = "C:\sysmon-network-logs.txt"

$Events = Get-WinEvent -FilterHashtable @{
    LogName = "Microsoft-Windows-Sysmon/Operational"
    Id      = 3
} -ErrorAction SilentlyContinue

$FilteredEvents = $Events | Where-Object {
    $_.Message -match "DestinationPort:\s+22" -or
    $_.Message -match "DestinationPort:\s+53"
}

$FilteredEvents | Select-Object TimeCreated, Id, Message |
    Format-List | Out-File -FilePath $OutputFile -Encoding UTF8
```

### Suricata (Windows)

- [ ] **Install Suricata on Windows**

1. Download and install Npcap from https://npcap.com/ (check "WinPcap API-compatible mode")
2. Download .msi from https://suricata.io/download/
3. Default install: `C:\Program Files\Suricata`

- [ ] **Configure Suricata**

```powershell
# Find interface name
ipconfig /all

# Edit C:\Program Files\Suricata\suricata.yaml
# Set HOME_NET:
#   vars:
#     address-groups:
#       HOME_NET: "[your_network/cidr]"
#
# Set interface (Windows uses pcap, not af-packet):
#   pcap:
#     - interface: Ethernet0
```

- [ ] **Download rules and start**

```powershell
cd "C:\Program Files\Suricata"
suricata-update                                      # May not work on all versions
suricata.exe -T -c suricata.yaml                     # Test config
suricata.exe -c suricata.yaml -i "Ethernet0"         # Start (foreground)
```

- [ ] **Run as Windows service** (if supported)

```powershell
sc create Suricata binPath= """C:\Program Files\Suricata\suricata.exe"" -c ""C:\Program Files\Suricata\suricata.yaml"" -i ""Ethernet0"" --service" start= auto
net start Suricata
```

- [ ] **Suricata log locations**

| Log | Path |
|-----|------|
| Quick alerts | `C:\Program Files\Suricata\log\fast.log` |
| Full JSON | `C:\Program Files\Suricata\log\eve.json` |
| Performance | `C:\Program Files\Suricata\log\stats.log` |
| Errors | `C:\Program Files\Suricata\log\suricata.log` |

```powershell
# Read alerts
Get-Content "C:\Program Files\Suricata\log\fast.log" -Tail 20

# Watch real-time
Get-Content "C:\Program Files\Suricata\log\fast.log" -Wait

# Search for malware
Get-Content "C:\Program Files\Suricata\log\fast.log" | Select-String "MALWARE"

# Top DNS queries (beacon hunting)
Get-Content "C:\Program Files\Suricata\log\eve.json" |
    ConvertFrom-Json |
    Where-Object { $_.event_type -eq "dns" } |
    Select-Object -ExpandProperty dns |
    Group-Object rrname |
    Sort-Object Count -Descending |
    Select-Object -First 20
```

### Wireshark / tshark

- [ ] **Capture traffic**

```powershell
# List interfaces
tshark -D

# Capture
tshark -i "Ethernet 2" -T fields -e frame.time -e ip.src -e ip.dst -e tcp.dstport -e dns.qry.name -e http.host -e tls.handshake.extensions_server_name -w capture.pcap
```

### Wazuh + Suricata Integration

- [ ] **Configure Wazuh to ingest Suricata logs**

After both Wazuh agent and Suricata are installed, add Suricata's JSON log to Wazuh monitoring:

Edit `C:\Program Files (x86)\ossec-agent\ossec.conf` and add before `</ossec_config>`:

```xml
<localfile>
    <log_format>json</log_format>
    <location>C:\Program Files\Suricata\log\eve.json</location>
</localfile>
```

```powershell
# Restart Wazuh to pick up new log source
Restart-Service WazuhSvc
```

### Connection Monitor (Live)

- [ ] **Watch for suspicious outbound connections**

```powershell
# One-shot: show established connections with process names, exclude localhost
Get-NetTCPConnection -State Established |
    Select-Object LocalPort, RemoteAddress, RemotePort, OwningProcess,
    @{N='Process';E={(Get-Process -Id $_.OwningProcess).ProcessName}} |
    Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1)' }

# Continuous monitor (every 5 seconds), filter common ports
while ($true) {
    Get-NetTCPConnection -State Established |
        Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1)' } |
        Where-Object { $_.RemotePort -notin @(80, 443) } |
        Select-Object LocalPort, RemoteAddress, RemotePort,
        @{N='Process';E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}}
    Start-Sleep -Seconds 5
}
```

---

## Quick Reference: Common Paths

| Item | Path |
|------|------|
| IIS Web Root | `C:\inetpub\wwwroot` |
| Splunk Forwarder | `C:\Program Files\SplunkUniversalForwarder\bin` |
| Suricata | `C:\Program Files\Suricata` |
| Sysmon Logs | Event Viewer > `Microsoft-Windows-Sysmon/Operational` |
| Windows Defender | `C:\Program Files\Windows Defender` |
| Group Policy Editor | `gpedit.msc` |
| Registry Editor | `regedit` |
