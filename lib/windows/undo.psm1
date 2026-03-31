# ccdc-cli: 3-layer undo framework for Windows
# Depends on: common.psm1, config.psm1

# ══════════════════════════════════════════
# Layer 1: Original Baseline
# ══════════════════════════════════════════

function Invoke-CcdcCreateBaseline {
    $base = Join-Path $global:CCDC_UNDO_DIR "original"
    if (-not (Test-Path $base)) {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
    }
    Write-CcdcLog "Creating initial baseline snapshot..." -Level Info

    # Firewall rules
    try {
        Get-NetFirewallRule | Select-Object DisplayName, Enabled, Direction, Action, Profile |
            Export-Csv (Join-Path $base "firewall-rules.csv") -NoTypeInformation
        Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
            Export-Csv (Join-Path $base "firewall-profiles.csv") -NoTypeInformation
    } catch {
        Write-CcdcLog "Could not export firewall rules: $_" -Level Warn
    }

    # Service list
    try {
        Get-CimInstance Win32_Service |
            Select-Object Name, DisplayName, State, StartMode, StartName, PathName |
            Export-Csv (Join-Path $base "services.csv") -NoTypeInformation
    } catch {}

    # Local users
    try {
        Get-LocalUser | Select-Object Name, Enabled, LastLogon |
            Export-Csv (Join-Path $base "local-users.csv") -NoTypeInformation
    } catch {}

    # Local group membership
    try {
        $admins = net localgroup administrators 2>$null
        Set-Content -Path (Join-Path $base "admins.txt") -Value $admins
    } catch {}

    # Registry backups for common hardening keys
    try {
        reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" (Join-Path $base "reg-policies.reg") /y 2>$null
        reg export "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" (Join-Path $base "reg-lsa.reg") /y 2>$null
        reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" (Join-Path $base "reg-smb.reg") /y 2>$null
    } catch {}

    # Scheduled tasks
    try {
        Get-ScheduledTask | Where-Object { $_.State -eq "Ready" } |
            Select-Object TaskName, TaskPath, State |
            Export-Csv (Join-Path $base "scheduled-tasks.csv") -NoTypeInformation
    } catch {}

    # Make read-only
    Get-ChildItem $base -Recurse -File | ForEach-Object {
        Set-ItemProperty -Path $_.FullName -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue
    }

    # Sentinel
    "" | Set-Content (Join-Path $base ".created")

    Add-CcdcUndoLog "baseline created at $base"
    Write-CcdcLog "Baseline snapshot saved to $base" -Level Success
}

# ══════════════════════════════════════════
# Layer 2: Per-Command Snapshots
# ══════════════════════════════════════════

function New-CcdcUndoSnapshot {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Command
    )
    $ts = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $dir = Join-Path $global:CCDC_UNDO_DIR "$Category\$Command\$ts"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Get-CcdcUndoSnapshotLatest {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Command
    )
    $dir = Join-Path $global:CCDC_UNDO_DIR "$Category\$Command"
    if (-not (Test-Path $dir)) { return $null }
    $latest = Get-ChildItem $dir -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

# ══════════════════════════════════════════
# Layer 3: Undo Log
# ══════════════════════════════════════════

function Add-CcdcUndoLog {
    param([Parameter(Mandatory)][string]$Message)
    $logFile = Join-Path $global:CCDC_UNDO_DIR "undo.log"
    if (-not (Test-Path (Split-Path $logFile))) {
        New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
    }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$ts] $Message"
}

function Show-CcdcUndoLog {
    $logFile = Join-Path $global:CCDC_UNDO_DIR "undo.log"
    if (Test-Path $logFile) {
        Write-Host "Undo Log:" -ForegroundColor White
        Get-Content $logFile
    } else {
        Write-CcdcLog "No undo log yet. Run some commands first." -Level Info
    }
}

# ══════════════════════════════════════════
# Undo Handler
# ══════════════════════════════════════════

function Invoke-CcdcUndo {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )
    switch ($Command) {
        { $_ -in 'log','show','' } { Show-CcdcUndoLog }
        default {
            Write-CcdcLog "Unknown undo command: $Command" -Level Error
            Write-Host "Usage: .\ccdc.ps1 undo log"
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcCreateBaseline, New-CcdcUndoSnapshot,
    Get-CcdcUndoSnapshotLatest, Add-CcdcUndoLog, Show-CcdcUndoLog, Invoke-CcdcUndo
