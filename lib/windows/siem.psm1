# ccdc-cli: SIEM and monitoring module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1, undo.psm1

# ── Usage ──

function Show-CcdcSiemUsage {
    Write-Host ""
    Write-Host "ccdc siem - SIEM and monitoring setup" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  sysmon               Install Sysmon with ccdc config"
    Write-Host "  snoopy               (Linux only - N/A on Windows)"
    Write-Host "  auditd               (Linux only - N/A on Windows)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --undo               Undo the last run of a command"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc siem sysmon"
    Write-Host "  ccdc siem sysmon --undo"
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

    $snapshotDir = New-CcdcUndoSnapshot -Category "siem" -Command "sysmon"
    $existing = Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue
    if (-not $existing) {
        $existing = Get-Service -Name Sysmon -ErrorAction SilentlyContinue
    }
    if ($existing) {
        "yes" | Out-File (Join-Path $snapshotDir "was_installed")
    } else {
        "no" | Out-File (Join-Path $snapshotDir "was_installed")
    }

    $sysmonExe = Get-CcdcSysmonExe
    if (-not $sysmonExe) {
        Write-CcdcLog "Could not locate or download Sysmon64.exe" -Level Error
        return
    }

    try {
        if ($existing) {
            Write-CcdcLog "Sysmon already installed; updating config..." -Level Info
            & $sysmonExe -c $configPath 2>&1 | Out-Null
        } else {
            Write-CcdcLog "Installing Sysmon with ccdc config..." -Level Info
            & $sysmonExe -accepteula -i $configPath 2>&1 | Out-Null
        }
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
        '' { Show-CcdcSiemUsage }
        default {
            Write-CcdcLog "Unknown siem command: $Command" -Level Error
            Show-CcdcSiemUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcSiem
