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

    $global:CCDC_OS = "windows"
    $global:CCDC_OS_FAMILY = "windows"
    $global:CCDC_PKG = "none"
    $global:CCDC_FW_BACKEND = "windows"

    # Parse Windows version from caption
    $caption = $osInfo.Caption
    switch -Regex ($caption) {
        ".*Server 2016.*"  { $global:CCDC_OS_VERSION = "2016" }
        ".*Server 2019.*"  { $global:CCDC_OS_VERSION = "2019" }
        ".*Server 2022.*"  { $global:CCDC_OS_VERSION = "2022" }
        ".*Server 2025.*"  { $global:CCDC_OS_VERSION = "2025" }
        ".*Windows 10.*"   { $global:CCDC_OS_VERSION = "10" }
        ".*Windows 11.*"   { $global:CCDC_OS_VERSION = "11" }
        default            { $global:CCDC_OS_VERSION = $osInfo.Version }
    }

    # AD Detection
    $global:CCDC_IS_DC = $false
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Get-ADDomain -ErrorAction Stop | Out-Null
        $global:CCDC_IS_DC = $true
    } catch {
        $global:CCDC_IS_DC = $false
    }

    # Also check DomainRole: 4=BackupDC, 5=PrimaryDC
    $role = $compInfo.DomainRole
    if ($role -ge 4) {
        $global:CCDC_IS_DC = $true
    }

    Write-CcdcLog "OS:        $($global:CCDC_OS) $($global:CCDC_OS_VERSION) ($caption)" -Level Info
    Write-CcdcLog "Firewall:  $($global:CCDC_FW_BACKEND)" -Level Info
    Write-CcdcLog "Domain DC: $($global:CCDC_IS_DC)" -Level Info
}

Export-ModuleMember -Function Invoke-CcdcDetect
