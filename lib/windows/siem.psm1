# ccdc-cli: SIEM and monitoring module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1, undo.psm1

# ── Usage ──

function Show-CcdcSiemUsage {
    Write-Host ""
    Write-Host "ccdc siem - SIEM and monitoring setup" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  sysmon               Install Sysmon with ccdc config"
    Write-Host "  wazuh-agent          Install Wazuh agent (uses wazuh_server_ip)"
    Write-Host "  wazuh-server         (Linux only - N/A on Windows)"
    Write-Host "  snoopy               (Linux only - N/A on Windows)"
    Write-Host "  auditd               (Linux only - N/A on Windows)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --undo               Undo the last run of a command"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc siem sysmon"
    Write-Host "  ccdc siem sysmon --undo"
    Write-Host "  ccdc config set wazuh_server_ip 10.0.0.5; ccdc siem wazuh-agent"
}

# ── Sysmon ──

function Get-CcdcSysmonExe {
    $bundled = Join-Path $global:CCDC_DIR "bin\windows\Sysmon64.exe"
    if (Test-Path $bundled) { return $bundled }

    $tempPath = Join-Path $env:TEMP "Sysmon64.exe"
    if (Test-Path $tempPath) { return $tempPath }

    Write-CcdcLog "Bundled Sysmon64.exe not found; downloading from live.sysinternals.com..." -Level Info
    if (Invoke-CcdcDownload -Url "https://live.sysinternals.com/Sysmon64.exe" -Output $tempPath) {
        return $tempPath
    }
    return $null
}

function Invoke-CcdcSiemSysmon {
    param([string[]]$ExtraArgs)

    $configPath = Join-Path $global:CCDC_DIR "bin\windows\sysmonconfig.xml"

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "siem" -Command "sysmon"
        if (-not $snapshotDir) {
            Write-CcdcLog "No undo snapshot for siem sysmon" -Level Error
            return
        }
        $wasInstalled = Get-Content (Join-Path $snapshotDir "was_installed") -ErrorAction SilentlyContinue
        if ($wasInstalled -eq 'no') {
            $sysmonExe = Get-CcdcSysmonExe
            if ($sysmonExe) {
                & $sysmonExe -u force 2>&1 | Out-Null
                Write-CcdcLog "Sysmon uninstalled (undo)" -Level Success
            } else {
                Write-CcdcLog "Sysmon binary unavailable; cannot uninstall cleanly" -Level Warn
            }
        } else {
            Write-CcdcLog "Sysmon was already installed before; leaving in place" -Level Info
        }
        Add-CcdcUndoLog "siem sysmon -- restored"
        return
    }

    if (-not (Test-Path $configPath)) {
        Write-CcdcLog "Bundled config missing: $configPath" -Level Error
        return
    }

    $sysmonExe = Get-CcdcSysmonExe
    if (-not $sysmonExe) {
        Write-CcdcLog "Could not locate or download Sysmon64.exe" -Level Error
        return
    }

    $existing = Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue
    if (-not $existing) {
        $existing = Get-Service -Name Sysmon -ErrorAction SilentlyContinue
    }

    # Config-update path: do NOT create a new snapshot, so undo still walks
    # back to the original install state.
    if ($existing) {
        Write-CcdcLog "Sysmon already installed; updating config (no undo snapshot)" -Level Info
        try {
            & $sysmonExe -c $configPath 2>&1 | Out-Null
        } catch {
            Write-CcdcLog "Sysmon config update failed: $_" -Level Error
            return
        }
        Write-CcdcLog "Sysmon config updated" -Level Success
        return
    }

    # Fresh install path
    $snapshotDir = New-CcdcUndoSnapshot -Category "siem" -Command "sysmon"
    "no" | Out-File (Join-Path $snapshotDir "was_installed")

    Write-CcdcLog "Installing Sysmon with ccdc config..." -Level Info
    try {
        & $sysmonExe -accepteula -i $configPath 2>&1 | Out-Null
    } catch {
        Write-CcdcLog "Sysmon install failed: $_" -Level Error
        return
    }

    Start-Sleep -Seconds 2
    $svc = Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue
    if (-not $svc) { $svc = Get-Service -Name Sysmon -ErrorAction SilentlyContinue }
    if ($svc -and $svc.Status -eq 'Running') {
        Write-CcdcLog "Sysmon service running" -Level Success
    } else {
        Write-CcdcLog "Sysmon installed but service status not Running" -Level Warn
    }

    Add-CcdcUndoLog "siem sysmon -- snapshot at $snapshotDir"
    Write-CcdcLog "Done. Undo: ccdc siem sysmon --undo" -Level Success
}

# ── Linux-only stubs ──

function Invoke-CcdcSiemSnoopy {
    Write-CcdcLog "snoopy is a Linux-only command. Run from a Linux host." -Level Info
}

function Invoke-CcdcSiemAuditd {
    Write-CcdcLog "auditd is a Linux-only command. Run from a Linux host." -Level Info
}

function Invoke-CcdcSiemWazuhServer {
    Write-CcdcLog 'wazuh-server is a Linux-only command. Run from a Linux host.' -Level Info
}

# ── Wazuh agent ──

function Get-CcdcWazuhAgentMsi {
    $bundledDir = Join-Path $global:CCDC_DIR 'bin\windows'
    if (Test-Path $bundledDir) {
        $bundled = Get-ChildItem -Path $bundledDir -Filter 'wazuh-agent*.msi' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bundled) { return $bundled.FullName }
    }

    $tempPath = Join-Path $env:TEMP 'wazuh-agent.msi'
    if (Test-Path $tempPath) { return $tempPath }

    Write-CcdcLog 'Bundled wazuh-agent.msi not found; downloading from packages.wazuh.com...' -Level Info
    if (Invoke-CcdcDownload -Url 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi' -Output $tempPath) {
        return $tempPath
    }
    return $null
}

function Invoke-CcdcSiemWazuhAgent {
    param([string[]]$ExtraArgs)

    $ossecConf = 'C:\Program Files (x86)\ossec-agent\ossec.conf'

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category 'siem' -Command 'wazuh-agent'
        if (-not $snapshotDir) {
            Write-CcdcLog 'No undo snapshot for siem wazuh-agent' -Level Error
            return
        }
        $wasInstalled = Get-Content (Join-Path $snapshotDir 'was_installed') -ErrorAction SilentlyContinue
        Stop-Service -Name WazuhSvc -ErrorAction SilentlyContinue
        if ($wasInstalled -eq 'no') {
            $msi = Get-CcdcWazuhAgentMsi
            if ($msi) {
                Start-Process msiexec.exe -ArgumentList "/x `"$msi`" /qn" -Wait -ErrorAction SilentlyContinue
                Write-CcdcLog 'Wazuh agent uninstalled (undo)' -Level Success
            } else {
                $product = Get-WmiObject -Class Win32_Product -Filter "Name LIKE 'Wazuh%'" -ErrorAction SilentlyContinue
                if ($product) { $product.Uninstall() | Out-Null }
            }
        } else {
            $backupConf = Join-Path $snapshotDir 'ossec.conf'
            if (Test-Path $backupConf) {
                Restore-CcdcFile -BackupPath $backupConf -OriginalPath $ossecConf | Out-Null
                Start-Service -Name WazuhSvc -ErrorAction SilentlyContinue
                Write-CcdcLog 'Wazuh agent ossec.conf restored (undo)' -Level Success
            }
        }
        Add-CcdcUndoLog 'siem wazuh-agent -- restored'
        return
    }

    if (-not $global:CCDC_WAZUH_IP) {
        Write-CcdcLog 'wazuh_server_ip not set. Run: ccdc config set wazuh_server_ip IP' -Level Error
        return
    }

    $existing = Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue

    # Config-update path: already installed, just rewrite ossec.conf address
    if ($existing) {
        Write-CcdcLog 'Wazuh agent already installed; updating server address (no undo snapshot)' -Level Info
        if (Test-Path $ossecConf) {
            $content = Get-Content $ossecConf -Raw
            $replacement = '<address>' + $global:CCDC_WAZUH_IP + '</address>'
            $newContent = [regex]::Replace($content, '<address>[^<]*</address>', $replacement, 1)
            Set-Content -Path $ossecConf -Value $newContent -Encoding ASCII
        }
        Restart-Service -Name WazuhSvc -ErrorAction SilentlyContinue
        Write-CcdcLog "Wazuh agent reconfigured to $($global:CCDC_WAZUH_IP)" -Level Success
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category 'siem' -Command 'wazuh-agent'
    'no' | Out-File (Join-Path $snapshotDir 'was_installed')
    if (Test-Path $ossecConf) {
        Backup-CcdcFile -Source $ossecConf -DestDir $snapshotDir
    }

    $msi = Get-CcdcWazuhAgentMsi
    if (-not $msi) {
        Write-CcdcLog 'Could not locate or download wazuh-agent MSI' -Level Error
        return
    }

    Write-CcdcLog "Installing wazuh-agent pointed at $($global:CCDC_WAZUH_IP)..." -Level Info
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn WAZUH_MANAGER=`"$($global:CCDC_WAZUH_IP)`"" -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-CcdcLog "msiexec exited with code $($proc.ExitCode)" -Level Error
        return
    }

    Start-Sleep -Seconds 2
    Start-Service -Name WazuhSvc -ErrorAction SilentlyContinue
    $svc = Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-CcdcLog 'WazuhSvc service running' -Level Success
    } else {
        Write-CcdcLog 'wazuh-agent installed but WazuhSvc status not Running' -Level Warn
    }

    Add-CcdcUndoLog "siem wazuh-agent -- snapshot at $snapshotDir"
    Write-CcdcLog 'Done. Undo: ccdc siem wazuh-agent --undo' -Level Success
}

# ── Handler ──

function Invoke-CcdcSiem {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcSiemUsage
        return
    }

    switch ($Command) {
        'sysmon' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc siem sysmon"; Write-Host "Install Sysmon with ccdc config"; return }
            Invoke-CcdcSiemSysmon -ExtraArgs $CmdArgs
        }
        'snoopy' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc siem snoopy (Linux only)"; return }
            Invoke-CcdcSiemSnoopy
        }
        'auditd' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc siem auditd (Linux only)"; return }
            Invoke-CcdcSiemAuditd
        }
        'wazuh-server' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc siem wazuh-server (Linux only)'; return }
            Invoke-CcdcSiemWazuhServer
        }
        'wazuh-agent' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc siem wazuh-agent'; Write-Host 'Install Wazuh agent (uses wazuh_server_ip from config)'; return }
            Invoke-CcdcSiemWazuhAgent -ExtraArgs $CmdArgs
        }
        '' { Show-CcdcSiemUsage }
        default {
            Write-CcdcLog "Unknown siem command: $Command" -Level Error
            Show-CcdcSiemUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcSiem
