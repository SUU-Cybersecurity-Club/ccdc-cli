# ccdc-cli: service management module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1, undo.psm1

# ── Usage ──

function Show-CcdcServiceUsage {
    Write-Host ""
    Write-Host "ccdc service - Service management" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list (ls)            List running services"
    Write-Host "  stop <name>          Stop a service"
    Write-Host "  disable <name>       Stop and disable a service"
    Write-Host "  enable <name>        Enable and start a service"
    Write-Host "  cockpit              (Linux only - N/A on Windows)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --undo               Undo the last run of a command"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc svc ls                     List running services"
    Write-Host "  ccdc svc stop Spooler            Stop Print Spooler"
    Write-Host "  ccdc svc disable Spooler         Stop and disable Print Spooler"
    Write-Host "  ccdc svc enable W3SVC            Enable and start IIS"
}

# ── List ──

function Invoke-CcdcServiceList {
    Write-CcdcLog "Running services:" -Level Info
    Write-Host ""
    Get-Service | Where-Object { $_.Status -eq 'Running' } |
        Select-Object Name, DisplayName, Status, StartType |
        Format-Table -AutoSize
}

# ── Stop ──

function Invoke-CcdcServiceStop {
    param([string]$Name)

    if (-not $Name) {
        Write-CcdcLog 'Usage: ccdc service stop <name>' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "service" -Command "stop-$Name"
        if (-not $snapshotDir) {
            Write-CcdcLog "No undo snapshot for service stop $Name" -Level Error
            return
        }
        $wasRunning = Get-Content (Join-Path $snapshotDir "was_running") -ErrorAction SilentlyContinue
        if ($wasRunning -eq 'Running') {
            Start-Service -Name $Name -ErrorAction SilentlyContinue
            Write-CcdcLog "Service $Name started (undo)" -Level Success
        } else {
            Write-CcdcLog "Service $Name was not running before, skipping" -Level Info
        }
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "service" -Command "stop-$Name"
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        $svc.Status | Out-File (Join-Path $snapshotDir "was_running")
        $svc.StartType | Out-File (Join-Path $snapshotDir "was_starttype")
    }

    Stop-Service -Name $Name -Force -ErrorAction Stop
    Write-CcdcLog "Service $Name stopped" -Level Success
    Add-CcdcUndoLog "service stop $Name -- snapshot at $snapshotDir"
}

# ── Disable ──

function Invoke-CcdcServiceDisable {
    param([string]$Name)

    if (-not $Name) {
        Write-CcdcLog 'Usage: ccdc service disable <name>' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "service" -Command "disable-$Name"
        if (-not $snapshotDir) {
            Write-CcdcLog "No undo snapshot for service disable $Name" -Level Error
            return
        }
        $wasStartType = Get-Content (Join-Path $snapshotDir "was_starttype") -ErrorAction SilentlyContinue
        $wasRunning = Get-Content (Join-Path $snapshotDir "was_running") -ErrorAction SilentlyContinue
        if ($wasStartType) {
            Set-Service -Name $Name -StartupType $wasStartType.Trim() -ErrorAction SilentlyContinue
        }
        if ($wasRunning -eq 'Running') {
            Start-Service -Name $Name -ErrorAction SilentlyContinue
        }
        Write-CcdcLog "Service $Name re-enabled and started (undo)" -Level Success
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "service" -Command "disable-$Name"
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        $svc.Status | Out-File (Join-Path $snapshotDir "was_running")
        $svc.StartType | Out-File (Join-Path $snapshotDir "was_starttype")
    }

    Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    Set-Service -Name $Name -StartupType Disabled
    Write-CcdcLog "Service $Name stopped and disabled" -Level Success
    Add-CcdcUndoLog "service disable $Name -- snapshot at $snapshotDir"
}

# ── Enable ──

function Invoke-CcdcServiceEnable {
    param([string]$Name)

    if (-not $Name) {
        Write-CcdcLog 'Usage: ccdc service enable <name>' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "service" -Command "enable-$Name"
        if (-not $snapshotDir) {
            Write-CcdcLog "No undo snapshot for service enable $Name" -Level Error
            return
        }
        $wasStartType = Get-Content (Join-Path $snapshotDir "was_starttype") -ErrorAction SilentlyContinue
        $wasRunning = Get-Content (Join-Path $snapshotDir "was_running") -ErrorAction SilentlyContinue
        if ($wasStartType) {
            Set-Service -Name $Name -StartupType $wasStartType.Trim() -ErrorAction SilentlyContinue
        }
        if ($wasRunning -ne 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Write-CcdcLog "Service $Name restored to previous state (undo)" -Level Success
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "service" -Command "enable-$Name"
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        $svc.Status | Out-File (Join-Path $snapshotDir "was_running")
        $svc.StartType | Out-File (Join-Path $snapshotDir "was_starttype")
    }

    Set-Service -Name $Name -StartupType Automatic
    Start-Service -Name $Name
    Write-CcdcLog "Service $Name enabled and started" -Level Success
    Add-CcdcUndoLog "service enable $Name -- snapshot at $snapshotDir"
}

# ── Handler ──

function Invoke-CcdcService {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcServiceUsage
        return
    }

    $name = if ($CmdArgs.Count -ge 1 -and $CmdArgs[0] -notmatch '^--') { $CmdArgs[0] } else { $null }

    switch ($Command) {
        { $_ -in 'list','ls' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc service list"; Write-Host "List running services"; return }
            Invoke-CcdcServiceList
        }
        'stop' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc service stop <name>'; return }
            Invoke-CcdcServiceStop -Name $name
        }
        'disable' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc service disable <name>'; Write-Host 'Stop and disable a service'; return }
            Invoke-CcdcServiceDisable -Name $name
        }
        'enable' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc service enable <name>'; Write-Host 'Enable and start a service'; return }
            Invoke-CcdcServiceEnable -Name $name
        }
        'cockpit' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc service cockpit (Linux only)"; return }
            Write-CcdcLog "Cockpit is not available on Windows" -Level Info
        }
        '' { Show-CcdcServiceUsage }
        default {
            Write-CcdcLog "Unknown service command: $Command" -Level Error
            Show-CcdcServiceUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcService
