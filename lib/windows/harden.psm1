# ccdc-cli: hardening module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1, undo.psm1

# ── Usage ──

function Show-CcdcHardenUsage {
    Write-Host ""
    Write-Host "ccdc harden - System hardening" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  ssh                  Harden sshd_config (if OpenSSH installed)"
    Write-Host "  ssh-remove           Remove OpenSSH Server"
    Write-Host "  smb                  Disable SMBv1"
    Write-Host "  cron                 Disable non-Microsoft scheduled tasks"
    Write-Host "  banner               Set login warning banner (registry)"
    Write-Host "  revshell-check       Scan for suspicious processes/tasks (read-only)"
    Write-Host "  anon-login           Fix anonymous login registry keys"
    Write-Host "  defender             Enable and configure Windows Defender"
    Write-Host "  gpo                  Apply password/lockout/audit policy"
    Write-Host "  updates              Fix Windows Update service"
    Write-Host "  kerberos             Fix preauth disabled accounts (DC only)"
    Write-Host "  tls                  Enforce TLS 1.2 strong crypto"
    Write-Host "  rdp                  Disable RDP, PS Remoting, WinRM"
    Write-Host "  spooler              Disable Print Spooler service"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --undo               Undo the last run of a command"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc hrd smb                    Disable SMBv1"
    Write-Host "  ccdc hrd defender               Enable Defender"
    Write-Host "  ccdc hrd banner                 Set login banner"
    Write-Host "  ccdc hrd rdp                    Disable RDP + WinRM"
    Write-Host "  ccdc hrd gpo                    Apply password policy"
}

# ── SSH Harden ──

function Invoke-CcdcHardenSsh {
    $sshdConfig = "$env:ProgramData\ssh\sshd_config"
    if (-not (Test-Path $sshdConfig)) {
        $sshdConfig = "$env:SystemRoot\System32\OpenSSH\sshd_config_default"
    }

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "ssh"
        if ($snapshotDir -and (Test-Path (Join-Path $snapshotDir "sshd_config"))) {
            Copy-Item (Join-Path $snapshotDir "sshd_config") $sshdConfig -Force
            Restart-Service sshd -ErrorAction SilentlyContinue
            Write-CcdcLog "sshd_config restored (undo)" -Level Success
        }
        return
    }

    if (-not (Test-Path $sshdConfig)) {
        Write-CcdcLog "OpenSSH not installed, nothing to harden" -Level Info
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "ssh"
    Copy-Item $sshdConfig (Join-Path $snapshotDir "sshd_config") -Force

    Write-CcdcLog "Hardening SSH configuration..." -Level Info

    $content = Get-Content $sshdConfig
    $settings = @{
        'PermitRootLogin' = 'no'
        'MaxAuthTries' = '3'
        'X11Forwarding' = 'no'
        'AllowTcpForwarding' = 'no'
        'PermitEmptyPasswords' = 'no'
    }

    foreach ($key in $settings.Keys) {
        $content = $content -replace "(?i)^\s*#?\s*$key\s+.*", "# $key (ccdc-disabled)"
    }
    $content += ""
    $content += "# === CCDC Hardening ==="
    foreach ($key in $settings.Keys) {
        $content += "$key $($settings[$key])"
    }

    Set-Content -Path $sshdConfig -Value $content -Force
    Restart-Service sshd -ErrorAction SilentlyContinue

    Write-CcdcLog "SSH hardened (PermitRootLogin=no, MaxAuthTries=3)" -Level Success
    Add-CcdcUndoLog "harden ssh -- hardened sshd_config, snapshot at $snapshotDir"
}

# ── SSH Remove ──

function Invoke-CcdcHardenSshRemove {
    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Re-installing OpenSSH Server..." -Level Info
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction SilentlyContinue
        Start-Service sshd -ErrorAction SilentlyContinue
        Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue
        Write-CcdcLog "OpenSSH Server re-installed (undo)" -Level Success
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "ssh-remove"

    Write-CcdcLog "Removing OpenSSH Server..." -Level Info
    Stop-Service sshd -Force -ErrorAction SilentlyContinue
    Remove-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction SilentlyContinue

    Write-CcdcLog "OpenSSH Server removed" -Level Success
    Add-CcdcUndoLog "harden ssh-remove -- removed OpenSSH Server, snapshot at $snapshotDir"
}

# ── SMB ──

function Invoke-CcdcHardenSmb {
    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "smb"
        if ($snapshotDir) {
            $wasEnabled = Get-Content (Join-Path $snapshotDir "smb1_enabled") -ErrorAction SilentlyContinue
            if ($wasEnabled -eq 'True') {
                Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
            }
            Write-CcdcLog "SMB settings restored (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "smb"

    # Save current state
    $smb1 = (Get-SmbServerConfiguration -ErrorAction SilentlyContinue).EnableSMB1Protocol
    "$smb1" | Out-File (Join-Path $snapshotDir "smb1_enabled")

    Write-CcdcLog "Disabling SMBv1..." -Level Info
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue

    # Also try disabling via feature
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null

    Write-CcdcLog "SMBv1 disabled" -Level Success
    Add-CcdcUndoLog "harden smb -- disabled SMBv1, snapshot at $snapshotDir"
}

# ── Cron (Scheduled Tasks) ──

function Invoke-CcdcHardenCron {
    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "cron"
        if ($snapshotDir) {
            $disabled = Get-Content (Join-Path $snapshotDir "disabled_tasks.txt") -ErrorAction SilentlyContinue
            foreach ($taskName in $disabled) {
                $taskName = $taskName.Trim()
                if ($taskName) {
                    Enable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
                }
            }
            Write-CcdcLog "Scheduled tasks re-enabled (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "cron"

    Write-CcdcLog "Disabling non-Microsoft scheduled tasks..." -Level Info

    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne 'Disabled' -and $_.Author -notmatch 'Microsoft' -and $_.TaskPath -notmatch '\\Microsoft\\' }

    $disabledList = @()
    foreach ($task in $tasks) {
        try {
            Disable-ScheduledTask -TaskName $task.TaskName -ErrorAction SilentlyContinue | Out-Null
            $disabledList += $task.TaskName
            Write-CcdcLog "Disabled task: $($task.TaskName)" -Level Info
        } catch {
            Write-CcdcLog "Could not disable: $($task.TaskName)" -Level Warn
        }
    }

    $disabledList | Out-File (Join-Path $snapshotDir "disabled_tasks.txt")

    Write-CcdcLog "Disabled $($disabledList.Count) non-Microsoft scheduled tasks" -Level Success
    Add-CcdcUndoLog "harden cron -- disabled $($disabledList.Count) tasks, snapshot at $snapshotDir"
}

# ── Banner ──

function Invoke-CcdcHardenBanner {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "banner"
        if ($snapshotDir) {
            $caption = Get-Content (Join-Path $snapshotDir "caption") -ErrorAction SilentlyContinue
            $text = Get-Content (Join-Path $snapshotDir "text") -Raw -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $regPath -Name 'legalnoticecaption' -Value ($caption -join '') -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $regPath -Name 'legalnoticetext' -Value ($text -join '') -ErrorAction SilentlyContinue
            Write-CcdcLog "Login banner restored (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "banner"

    # Save current values
    $current = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if ($current) {
        $current.legalnoticecaption | Out-File (Join-Path $snapshotDir "caption")
        $current.legalnoticetext | Out-File (Join-Path $snapshotDir "text")
    }

    Write-CcdcLog "Setting login banner..." -Level Info
    Set-ItemProperty -Path $regPath -Name 'legalnoticecaption' -Value 'AUTHORIZED USE ONLY'
    Set-ItemProperty -Path $regPath -Name 'legalnoticetext' -Value 'This system is for authorized users only. All activity is monitored and logged. Unauthorized access will be prosecuted to the full extent of the law.'

    Write-CcdcLog "Login banner set" -Level Success
    Add-CcdcUndoLog "harden banner -- set login banner, snapshot at $snapshotDir"
}

# ── Reverse Shell Check ──

function Invoke-CcdcHardenRevshellCheck {
    Write-CcdcLog "Scanning for suspicious processes and tasks..." -Level Info
    Write-Host ""

    $found = 0
    $suspiciousPatterns = @('nc\.exe', 'ncat', 'netcat', 'powercat', 'Invoke-PowerShellTcp', 'reverse', 'shell', 'meterpreter', 'payload', 'beacon', 'cobalt', 'mimikatz', 'rubeus')

    Write-Host "=== Suspicious Processes ===" -ForegroundColor Cyan
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and ($suspiciousPatterns | Where-Object { $_.CommandLine -match $_ }) }
    if ($procs) {
        $procs | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize
        $found++
    } else {
        Write-Host "  (none found)"
    }
    Write-Host ""

    Write-Host "=== Suspicious Scheduled Tasks ===" -ForegroundColor Cyan
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.Author -notmatch 'Microsoft' -and $_.State -ne 'Disabled' }
    if ($tasks) {
        $tasks | Select-Object TaskName, Author, State | Format-Table -AutoSize
        $found++
    } else {
        Write-Host "  (none found)"
    }
    Write-Host ""

    Write-Host "=== Startup Registry Entries ===" -ForegroundColor Cyan
    $startupKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($key in $startupKeys) {
        Write-Host "  --- $key ---"
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                Write-Host "    $($_.Name) = $($_.Value)"
            }
        } catch { Write-Host "    (not accessible)" }
    }
    Write-Host ""

    if ($found -gt 0) {
        Write-CcdcLog "Found $found categories of suspicious items - review above" -Level Warn
    } else {
        Write-CcdcLog "No obvious suspicious items found" -Level Success
    }
    Write-CcdcLog "Note: this is a basic scan. Sophisticated backdoors may not be detected." -Level Info
}

# ── Anonymous Login ──

function Invoke-CcdcHardenAnonLogin {
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "anon-login"
        if ($snapshotDir) {
            $values = Get-Content (Join-Path $snapshotDir "values.txt") -ErrorAction SilentlyContinue
            foreach ($line in $values) {
                $parts = $line -split '='
                if ($parts.Count -eq 2) {
                    Set-ItemProperty -Path $regPath -Name $parts[0].Trim() -Value ([int]$parts[1].Trim()) -ErrorAction SilentlyContinue
                }
            }
            # Also restore EveryoneIncludesAnonymous
            $evPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
            $evVal = Get-Content (Join-Path $snapshotDir "everyone.txt") -ErrorAction SilentlyContinue
            if ($evVal) {
                Set-ItemProperty -Path $evPath -Name 'EveryoneIncludesAnonymous' -Value ([int]$evVal.Trim()) -ErrorAction SilentlyContinue
            }
            Write-CcdcLog "Anonymous login settings restored (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "anon-login"

    # Save current values
    $current = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    $saveLines = @()
    $saveLines += "RestrictAnonymous=$($current.RestrictAnonymous)"
    $saveLines += "RestrictAnonymousSAM=$($current.RestrictAnonymousSAM)"
    $saveLines | Out-File (Join-Path $snapshotDir "values.txt")
    "$($current.EveryoneIncludesAnonymous)" | Out-File (Join-Path $snapshotDir "everyone.txt")

    Write-CcdcLog "Fixing anonymous login registry keys..." -Level Info
    Set-ItemProperty -Path $regPath -Name 'RestrictAnonymous' -Value 1
    Set-ItemProperty -Path $regPath -Name 'RestrictAnonymousSAM' -Value 1
    Set-ItemProperty -Path $regPath -Name 'EveryoneIncludesAnonymous' -Value 0

    Write-CcdcLog "Anonymous login restricted (RestrictAnonymous=1, EveryoneIncludesAnonymous=0)" -Level Success
    Add-CcdcUndoLog "harden anon-login -- fixed anonymous login, snapshot at $snapshotDir"
}

# ── Windows Defender ──

function Invoke-CcdcHardenDefender {
    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Defender undo: disabling real-time monitoring" -Level Info
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Write-CcdcLog "Real-time monitoring disabled (undo)" -Level Success
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "defender"

    Write-CcdcLog "Enabling and configuring Windows Defender..." -Level Info

    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBlockAtFirstSeen $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisablePrivacyMode $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableScriptScanning $false -ErrorAction SilentlyContinue
        Set-MpPreference -MAPSReporting 2 -ErrorAction SilentlyContinue
        Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction SilentlyContinue
        Set-MpPreference -PUAProtection 1 -ErrorAction SilentlyContinue

        Write-CcdcLog "Updating Defender signatures..." -Level Info
        Update-MpSignature -ErrorAction SilentlyContinue
    } catch {
        Write-CcdcLog "Some Defender settings could not be applied: $_" -Level Warn
    }

    Write-CcdcLog "Windows Defender enabled and configured" -Level Success
    Add-CcdcUndoLog "harden defender -- enabled all protections, snapshot at $snapshotDir"
}

# ── GPO (Password/Lockout/Audit Policy) ──

function Invoke-CcdcHardenGpo {
    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "gpo"
        if ($snapshotDir -and (Test-Path (Join-Path $snapshotDir "auditpol.csv"))) {
            Write-CcdcLog "Restoring audit policy..." -Level Info
            auditpol /restore /file:(Join-Path $snapshotDir "auditpol.csv") 2>$null
            Write-CcdcLog "Audit policy restored (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "gpo"

    # Save current audit policy
    auditpol /backup /file:(Join-Path $snapshotDir "auditpol.csv") 2>$null

    Write-CcdcLog "Applying password and lockout policy..." -Level Info

    # Password policy
    net accounts /minpwlen:12 /maxpwage:90 /minpwage:1 /uniquepw:5 2>$null
    Write-CcdcLog "Password policy: minlen=12, maxage=90, minage=1, history=5" -Level Info

    # Lockout policy
    net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 2>$null
    Write-CcdcLog "Lockout policy: threshold=5, duration=30min, window=30min" -Level Info

    # Audit policy
    Write-CcdcLog "Applying audit policy..." -Level Info
    auditpol /set /subcategory:'Logon' /success:enable /failure:enable 2>$null
    auditpol /set /subcategory:'Logoff' /success:enable 2>$null
    auditpol /set /subcategory:'Special Logon' /success:enable /failure:enable 2>$null
    auditpol /set /subcategory:'Kerberos Authentication Service' /success:enable /failure:enable 2>$null
    auditpol /set /subcategory:'Kerberos Service Ticket Operations' /success:enable /failure:enable 2>$null
    auditpol /set /subcategory:'Account Lockout' /success:enable /failure:enable 2>$null
    auditpol /set /subcategory:'User Account Management' /success:enable /failure:enable 2>$null
    auditpol /set /subcategory:'Computer Account Management' /success:enable /failure:enable 2>$null

    Write-CcdcLog "Password, lockout, and audit policies applied" -Level Success
    Add-CcdcUndoLog "harden gpo -- applied policies, snapshot at $snapshotDir"
}

# ── Windows Update ──

function Invoke-CcdcHardenUpdates {
    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Windows Update undo not needed (service was already fixed)" -Level Info
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "updates"

    Write-CcdcLog "Fixing Windows Update service..." -Level Info

    # Ensure wuauserv exists and is set to auto
    Set-Service -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue

    # Also fix BITS
    Set-Service -Name BITS -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name BITS -ErrorAction SilentlyContinue

    # Fix Windows Defender service
    Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name WinDefend -ErrorAction SilentlyContinue

    Write-CcdcLog "Windows Update (wuauserv), BITS, and Defender services running" -Level Success
    Add-CcdcUndoLog "harden updates -- fixed update services, snapshot at $snapshotDir"
}

# ── Kerberos ──

function Invoke-CcdcHardenKerberos {
    if (-not $global:CCDC_IS_DC) {
        Write-CcdcLog "Not a Domain Controller - kerberos hardening skipped" -Level Info
        return
    }

    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Kerberos undo: unlikely to want to re-disable preauth" -Level Warn
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "kerberos"

    Write-CcdcLog "Checking for accounts with preauth disabled..." -Level Info

    try {
        $vulnerable = Get-ADUser -Filter { DoesNotRequirePreAuth -eq $true } -Properties DoesNotRequirePreAuth
        if ($vulnerable) {
            $vulnerable.SamAccountName | Out-File (Join-Path $snapshotDir "preauth_disabled.txt")
            foreach ($user in $vulnerable) {
                Set-ADAccountControl -Identity $user -DoesNotRequirePreAuth $false
                Write-CcdcLog "Fixed preauth for: $($user.SamAccountName)" -Level Info
            }
            Write-CcdcLog "Fixed $($vulnerable.Count) accounts with preauth disabled" -Level Success
        } else {
            Write-CcdcLog "No accounts with preauth disabled found" -Level Success
        }
    } catch {
        Write-CcdcLog "AD query failed: $_" -Level Error
    }

    Add-CcdcUndoLog "harden kerberos -- fixed preauth, snapshot at $snapshotDir"
}

# ── TLS ──

function Invoke-CcdcHardenTls {
    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "tls"
        if ($snapshotDir) {
            Write-CcdcLog "Removing TLS hardening registry keys..." -Level Info
            # Remove SchUseStrongCrypto keys
            Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -ErrorAction SilentlyContinue
            Write-CcdcLog "TLS settings removed (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "tls"

    Write-CcdcLog "Enforcing TLS 1.2 strong crypto..." -Level Info

    # .NET strong crypto (64-bit)
    $path64 = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
    if (-not (Test-Path $path64)) { New-Item -Path $path64 -Force | Out-Null }
    Set-ItemProperty -Path $path64 -Name 'SchUseStrongCrypto' -Value 1 -Type DWord

    # .NET strong crypto (32-bit on 64-bit OS)
    $path32 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'
    if (-not (Test-Path $path32)) { New-Item -Path $path32 -Force | Out-Null }
    Set-ItemProperty -Path $path32 -Name 'SchUseStrongCrypto' -Value 1 -Type DWord

    # Disable TLS 1.0
    $tls10 = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'
    if (-not (Test-Path $tls10)) { New-Item -Path $tls10 -Force | Out-Null }
    Set-ItemProperty -Path $tls10 -Name 'Enabled' -Value 0 -Type DWord
    Set-ItemProperty -Path $tls10 -Name 'DisabledByDefault' -Value 1 -Type DWord

    # Disable TLS 1.1
    $tls11 = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'
    if (-not (Test-Path $tls11)) { New-Item -Path $tls11 -Force | Out-Null }
    Set-ItemProperty -Path $tls11 -Name 'Enabled' -Value 0 -Type DWord
    Set-ItemProperty -Path $tls11 -Name 'DisabledByDefault' -Value 1 -Type DWord

    Write-CcdcLog "TLS 1.2 enforced, TLS 1.0/1.1 disabled, SchUseStrongCrypto=1" -Level Success
    Add-CcdcUndoLog "harden tls -- enforced TLS 1.2, snapshot at $snapshotDir"
}

# ── RDP ──

function Invoke-CcdcHardenRdp {
    $tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "rdp"
        if ($snapshotDir) {
            $wasDeny = Get-Content (Join-Path $snapshotDir "fDenyTSConnections") -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -Value ([int]$wasDeny.Trim()) -ErrorAction SilentlyContinue

            # Re-enable WinRM
            Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service WinRM -ErrorAction SilentlyContinue
            Enable-PSRemoting -Force -ErrorAction SilentlyContinue

            # Re-enable RDP firewall rules
            Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue

            Write-CcdcLog "RDP, WinRM, PS Remoting re-enabled (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "rdp"

    # Save current state
    $current = Get-ItemProperty -Path $tsPath -ErrorAction SilentlyContinue
    "$($current.fDenyTSConnections)" | Out-File (Join-Path $snapshotDir "fDenyTSConnections")

    Write-CcdcLog "Disabling RDP, PS Remoting, WinRM..." -Level Info

    # Disable RDP
    Set-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -Value 1
    Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue

    # Disable PS Remoting
    Disable-PSRemoting -Force -ErrorAction SilentlyContinue

    # Disable WinRM
    Stop-Service WinRM -Force -ErrorAction SilentlyContinue
    Set-Service WinRM -StartupType Disabled -ErrorAction SilentlyContinue

    Write-CcdcLog "RDP disabled (fDenyTSConnections=1), WinRM stopped, PS Remoting disabled" -Level Success
    Add-CcdcUndoLog "harden rdp -- disabled RDP+WinRM+PSRemoting, snapshot at $snapshotDir"
}

# ── Spooler ──

function Invoke-CcdcHardenSpooler {
    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "harden" -Command "spooler"
        if ($snapshotDir) {
            $wasStartType = Get-Content (Join-Path $snapshotDir "was_starttype") -ErrorAction SilentlyContinue
            if ($wasStartType) {
                Set-Service -Name Spooler -StartupType $wasStartType.Trim() -ErrorAction SilentlyContinue
                Start-Service -Name Spooler -ErrorAction SilentlyContinue
            }
            Write-CcdcLog "Print Spooler restored (undo)" -Level Success
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "spooler"

    $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if ($svc) {
        $svc.StartType | Out-File (Join-Path $snapshotDir "was_starttype")
    }

    Write-CcdcLog "Disabling Print Spooler..." -Level Info
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Set-Service -Name Spooler -StartupType Disabled

    Write-CcdcLog "Print Spooler stopped and disabled" -Level Success
    Add-CcdcUndoLog "harden spooler -- disabled Print Spooler, snapshot at $snapshotDir"
}

# ── MySQL ──

function Invoke-CcdcHardenMysql {
    if ($global:CCDC_UNDO) {
        Write-CcdcLog "MySQL undo is limited - restore from database backup if needed" -Level Warn
        return
    }

    # Check if MySQL is installed
    $mysql = Get-Command mysql -ErrorAction SilentlyContinue
    if (-not $mysql) {
        Write-CcdcLog "MySQL not installed, nothing to harden" -Level Info
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "harden" -Command "mysql"

    Write-CcdcLog "Securing MySQL..." -Level Info
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>$null
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>$null
    mysql -e "DROP DATABASE IF EXISTS test;" 2>$null
    mysql -e "FLUSH PRIVILEGES;" 2>$null

    Write-CcdcLog "MySQL secured (anonymous users removed, remote root removed, test db dropped)" -Level Success
    Add-CcdcUndoLog "harden mysql -- secured, snapshot at $snapshotDir"
}

# ── Handler ──

function Invoke-CcdcHarden {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcHardenUsage
        return
    }

    switch ($Command) {
        'ssh' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden ssh"; Write-Host "Harden sshd_config"; return }
            Invoke-CcdcHardenSsh
        }
        'ssh-remove' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden ssh-remove"; Write-Host "Remove OpenSSH Server"; return }
            Invoke-CcdcHardenSshRemove
        }
        'smb' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden smb"; Write-Host "Disable SMBv1"; return }
            Invoke-CcdcHardenSmb
        }
        'cron' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden cron"; Write-Host "Disable non-Microsoft scheduled tasks"; return }
            Invoke-CcdcHardenCron
        }
        'banner' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden banner"; Write-Host "Set login warning banner"; return }
            Invoke-CcdcHardenBanner
        }
        'revshell-check' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden revshell-check"; Write-Host "Scan for suspicious activity (read-only)"; return }
            Invoke-CcdcHardenRevshellCheck
        }
        'anon-login' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden anon-login"; Write-Host "Fix anonymous login registry keys"; return }
            Invoke-CcdcHardenAnonLogin
        }
        'defender' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden defender"; Write-Host "Enable and configure Windows Defender"; return }
            Invoke-CcdcHardenDefender
        }
        'gpo' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden gpo"; Write-Host "Apply password/lockout/audit policy"; return }
            Invoke-CcdcHardenGpo
        }
        'updates' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden updates"; Write-Host "Fix Windows Update service"; return }
            Invoke-CcdcHardenUpdates
        }
        'kerberos' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden kerberos"; Write-Host "Fix preauth disabled accounts (DC only)"; return }
            Invoke-CcdcHardenKerberos
        }
        'tls' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden tls"; Write-Host "Enforce TLS 1.2 strong crypto"; return }
            Invoke-CcdcHardenTls
        }
        'rdp' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden rdp"; Write-Host "Disable RDP, PS Remoting, WinRM"; return }
            Invoke-CcdcHardenRdp
        }
        'spooler' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden spooler"; Write-Host "Disable Print Spooler service"; return }
            Invoke-CcdcHardenSpooler
        }
        'mysql' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc harden mysql"; Write-Host "Secure MySQL installation"; return }
            Invoke-CcdcHardenMysql
        }
        '' { Show-CcdcHardenUsage }
        default {
            Write-CcdcLog "Unknown harden command: $Command" -Level Error
            Show-CcdcHardenUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcHarden
