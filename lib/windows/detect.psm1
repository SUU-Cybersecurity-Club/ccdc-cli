# ccdc-cli: Windows OS and AD detection
# Depends on: common.psm1

function Invoke-CcdcDetect {
    # OS Detection
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $compInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    } catch {
        Write-CcdcLog "CIM query failed, falling back to WMI..." -Level Warn
        $osInfo = Get-WmiObject -Class Win32_OperatingSystem
        $compInfo = Get-WmiObject -Class Win32_ComputerSystem
    }

    $script:CCDC_OS = "windows"
    $script:CCDC_OS_FAMILY = "windows"
    $script:CCDC_PKG = "none"
    $script:CCDC_FW_BACKEND = "windows"

    # Parse Windows version from caption
    $caption = $osInfo.Caption
    switch -Regex ($caption) {
        ".*Server 2016.*"  { $script:CCDC_OS_VERSION = "2016" }
        ".*Server 2019.*"  { $script:CCDC_OS_VERSION = "2019" }
        ".*Server 2022.*"  { $script:CCDC_OS_VERSION = "2022" }
        ".*Server 2025.*"  { $script:CCDC_OS_VERSION = "2025" }
        ".*Windows 10.*"   { $script:CCDC_OS_VERSION = "10" }
        ".*Windows 11.*"   { $script:CCDC_OS_VERSION = "11" }
        default            { $script:CCDC_OS_VERSION = $osInfo.Version }
    }

    # AD Detection
    $script:CCDC_IS_DC = $false
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Get-ADDomain -ErrorAction Stop | Out-Null
        $script:CCDC_IS_DC = $true
    } catch {
        $script:CCDC_IS_DC = $false
    }

    # Also check DomainRole: 4=BackupDC, 5=PrimaryDC
    $role = $compInfo.DomainRole
    if ($role -ge 4) {
        $script:CCDC_IS_DC = $true
    }

    Write-CcdcLog "OS:        $($script:CCDC_OS) $($script:CCDC_OS_VERSION) ($caption)" -Level Info
    Write-CcdcLog "Firewall:  $($script:CCDC_FW_BACKEND)" -Level Info
    Write-CcdcLog "Domain DC: $($script:CCDC_IS_DC)" -Level Info
}

Export-ModuleMember -Function Invoke-CcdcDetect
