# ccdc-cli — CCDC competition hardening toolkit
# Windows entry point

param(
    [Parameter(Position=0)][string]$Category,
    [Parameter(Position=1)][string]$Command,
    [Parameter(ValueFromRemainingArguments)][string[]]$RemainingArgs,
    [switch]$Help,
    [switch]$Undo,
    [switch]$NoPrompt,
    [switch]$DryRun
)

# ── Enable Script Execution (if restricted) ──
$currentPolicy = Get-ExecutionPolicy -Scope Process
if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'Undefined') {
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
        Write-Host "[INFO] Execution policy set to RemoteSigned for this session." -ForegroundColor Cyan
    } catch {
        Write-Host "[WARN] Could not set execution policy. If scripts fail, run:" -ForegroundColor Yellow
        Write-Host "  Set-ExecutionPolicy RemoteSigned -Scope Process -Force" -ForegroundColor Yellow
    }
}

# ── Require Administrator ──
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] ccdc-cli requires Administrator. Right-click PowerShell > Run as Administrator." -ForegroundColor Red
    exit 1
}

# ── Constants ──
$script:CCDC_VERSION = "0.1.0"
$script:CCDC_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:CCDC_DIR) {
    $script:CCDC_DIR = Split-Path -Parent $PSCommandPath
}
if (-not $script:CCDC_DIR) {
    $script:CCDC_DIR = $PWD.Path
}
$script:CCDC_CONF = Join-Path $script:CCDC_DIR ".ccdc.conf"

# ── Global State ──
$script:CCDC_OS = ""
$script:CCDC_OS_FAMILY = ""
$script:CCDC_OS_VERSION = ""
$script:CCDC_PKG = ""
$script:CCDC_FW_BACKEND = ""
$script:CCDC_BACKUP_DIR = ""
$script:CCDC_UNDO_DIR = ""
$script:CCDC_LOG = ""
$script:CCDC_WAZUH_IP = ""
$script:CCDC_SPLUNK_IP = ""
$script:CCDC_SCORED_TCP = ""
$script:CCDC_SCORED_UDP = ""
$script:CCDC_IS_DC = $false

# ── Global Flags ──
$script:CCDC_HELP = $Help.IsPresent
$script:CCDC_UNDO = $Undo.IsPresent
$script:CCDC_NO_PROMPT = $NoPrompt.IsPresent
$script:CCDC_DRY_RUN = $DryRun.IsPresent
$script:CCDC_VERBOSE = $VerbosePreference -ne 'SilentlyContinue'

# ── Import Phase 0 Modules ──
Import-Module (Join-Path $script:CCDC_DIR "lib/windows/common.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $script:CCDC_DIR "lib/windows/detect.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $script:CCDC_DIR "lib/windows/config.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $script:CCDC_DIR "lib/windows/undo.psm1") -Force -DisableNameChecking

# ── Load Config ──
Read-CcdcConfig

# If no config loaded, run detection
if (-not $script:CCDC_OS) {
    Invoke-CcdcDetect
}

# ── Start Transcript Logging ──
if ($script:CCDC_LOG) {
    $logDir = Split-Path $script:CCDC_LOG
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Start-Transcript -Path $script:CCDC_LOG -Append -ErrorAction SilentlyContinue | Out-Null
}

# ── Load Tab Completions ──
$completionsFile = Join-Path $script:CCDC_DIR "lib/windows/completions.ps1"
if (Test-Path $completionsFile) {
    . $completionsFile
}

# ── No category: show help ──
if (-not $Category) {
    if ($script:CCDC_HELP) {
        Show-CcdcUsage
        exit 0
    }
    Show-CcdcUsage
    exit 1
}

# ── Version ──
if ($Category -eq '--version') {
    Write-Host "ccdc-cli $($script:CCDC_VERSION)"
    exit 0
}

# ── Alias Resolution ──
$resolvedCategory = switch ($Category) {
    { $_ -in 'passwd','pw' }       { 'passwd' }
    { $_ -in 'backup','bak' }     { 'backup' }
    { $_ -in 'discover','disc' }  { 'discover' }
    { $_ -in 'service','svc' }    { 'service' }
    { $_ -in 'firewall','fw' }    { 'firewall' }
    { $_ -in 'harden','hrd' }     { 'harden' }
    'siem'                         { 'siem' }
    { $_ -in 'install','inst' }   { 'install' }
    'net'                          { 'net' }
    { $_ -in 'copy-paster','cp' } { 'copy-paster' }
    { $_ -in 'config','cfg' }     { 'config' }
    'undo'                         { 'undo' }
    'comp-start'                   { 'comp-start' }
    default                        { $null }
}

if (-not $resolvedCategory) {
    Write-CcdcLog "Unknown category: $Category" -Level Error
    Show-CcdcUsage
    exit 1
}

# ── Route to Module ──
switch ($resolvedCategory) {
    'config' {
        Invoke-CcdcConfig -Command $Command -Args $RemainingArgs
    }
    'undo' {
        Invoke-CcdcUndo -Command $Command -Args $RemainingArgs
    }
    { $_ -in 'passwd','backup','discover','service','firewall','harden','siem','install','net' } {
        $modulePath = Join-Path $script:CCDC_DIR "lib/windows/$resolvedCategory.psm1"
        if (-not (Test-Path $modulePath)) {
            Write-CcdcLog "Module '$resolvedCategory' not yet built. Coming soon." -Level Warn
            exit 1
        }
        Import-Module $modulePath -Force -DisableNameChecking
        $handlerName = "Invoke-Ccdc$(($resolvedCategory.Substring(0,1).ToUpper() + $resolvedCategory.Substring(1)))"
        & $handlerName -Command $Command -Args $RemainingArgs
    }
    'comp-start' {
        $modulePath = Join-Path $script:CCDC_DIR "lib/windows/comp-start.psm1"
        if (-not (Test-Path $modulePath)) {
            Write-CcdcLog "comp-start module not yet built. Run individual commands instead." -Level Warn
            exit 1
        }
        Import-Module $modulePath -Force -DisableNameChecking
        Invoke-CcdcCompStart -Args $RemainingArgs
    }
    'copy-paster' {
        $script = Join-Path $script:CCDC_DIR "lib/copy-paster/copy-paster.ps1"
        if (-not (Test-Path $script)) {
            Write-CcdcLog "copy-paster not yet built. Coming soon." -Level Warn
            exit 1
        }
        & $script @RemainingArgs
    }
    default {
        Write-CcdcLog "Unknown category: $resolvedCategory" -Level Error
        Show-CcdcUsage
        exit 1
    }
}

# ── Stop Transcript ──
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
