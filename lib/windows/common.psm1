# ccdc-cli: common PowerShell helpers
# Sourced first — no dependencies on other modules

# ── Logging ──

function Write-CcdcLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warn','Error','Success')]
        [string]$Level = 'Info'
    )
    $ts = Get-Date -Format "HH:mm:ss"
    $oldColor = [Console]::ForegroundColor
    switch ($Level) {
        'Info'    { [Console]::ForegroundColor = 'Cyan';    $prefix = "[INFO]"  }
        'Warn'    { [Console]::ForegroundColor = 'Yellow';  $prefix = "[WARN]"  }
        'Error'   { [Console]::ForegroundColor = 'Red';     $prefix = "[ERROR]" }
        'Success' { [Console]::ForegroundColor = 'Green';   $prefix = "[OK]"    }
    }
    Write-Host "$ts $prefix $Message"
    [Console]::ForegroundColor = $oldColor
}

# ── Root/Admin Check ──

function Test-CcdcAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-CcdcLog "This command requires Administrator. Run PowerShell as Admin." -Level Error
        exit 1
    }
}

# ── User Interaction ──

function Confirm-CcdcAction {
    param([string]$Prompt = "Continue?")
    if ($script:CCDC_NO_PROMPT) { return $true }
    $reply = Read-Host "$Prompt [y/N]"
    return ($reply -match '^[Yy]$')
}

# ── Command Execution ──

function Invoke-CcdcRun {
    param(
        [Parameter(Mandatory)][scriptblock]$Command,
        [string]$Description = ""
    )
    if ($script:CCDC_DRY_RUN) {
        Write-CcdcLog "[DRY RUN] Would run: $Description" -Level Info
        return
    }
    if ($script:CCDC_VERBOSE -and $Description) {
        Write-CcdcLog "Running: $Description" -Level Info
    }
    try {
        & $Command
    } catch {
        Write-CcdcLog "Command failed: $_" -Level Error
        throw
    }
}

# ── File Operations ──

function Backup-CcdcFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$DestDir
    )
    if (-not (Test-Path $Source)) { return }
    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }
    Copy-Item -Path $Source -Destination $DestDir -Force
    # Best-effort read-only + deny delete
    $destFile = Join-Path $DestDir (Split-Path $Source -Leaf)
    try {
        Set-ItemProperty -Path $destFile -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue
    } catch {}
}

function Restore-CcdcFile {
    param(
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][string]$OriginalPath
    )
    if (-not (Test-Path $BackupPath)) {
        Write-CcdcLog "Backup not found: $BackupPath" -Level Error
        return $false
    }
    try {
        Set-ItemProperty -Path $BackupPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    } catch {}
    Copy-Item -Path $BackupPath -Destination $OriginalPath -Force
    return $true
}

# ── Network ──

function Invoke-CcdcDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Output
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Output -ErrorAction Stop
        return $true
    } catch {
        Write-CcdcLog "Download failed: $_" -Level Error
        return $false
    }
}

# ── Help ──

function Show-CcdcUsage {
    Write-Host ""
    Write-Host "ccdc-cli - CCDC competition hardening toolkit" -ForegroundColor White
    Write-Host ""
    Write-Host "Usage: .\ccdc.ps1 <category> <command> [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "Categories:" -ForegroundColor White
    Write-Host "  passwd    (pw)     Password management"
    Write-Host "  backup    (bak)    Backup and restore"
    Write-Host "  discover  (disc)   System discovery and recon"
    Write-Host "  service   (svc)    Service management"
    Write-Host "  firewall  (fw)     Firewall configuration"
    Write-Host "  harden    (hrd)    System hardening"
    Write-Host "  siem               SIEM and monitoring setup"
    Write-Host "  install   (inst)   Package and tool installation"
    Write-Host "  net                Firewall-aware downloads"
    Write-Host "  config    (cfg)    Persistent configuration"
    Write-Host "  comp-start         Run full competition checklist"
    Write-Host ""
    Write-Host "Global Flags:" -ForegroundColor White
    Write-Host "  -Help              Show help"
    Write-Host "  -Undo              Undo last run of a command"
    Write-Host "  -NoPrompt          Skip confirmation prompts"
    Write-Host "  -DryRun            Show what would be done"
    Write-Host "  -Verbose           Verbose output"
    Write-Host ""
    Write-Host "Run '.\ccdc.ps1 <category> -Help' for command-specific help."
}

Export-ModuleMember -Function Write-CcdcLog, Test-CcdcAdmin, Confirm-CcdcAction,
    Invoke-CcdcRun, Backup-CcdcFile, Restore-CcdcFile, Invoke-CcdcDownload, Show-CcdcUsage
