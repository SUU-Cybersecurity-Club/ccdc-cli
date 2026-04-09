# ccdc-cli: discovery module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1

# ── Usage ──

function Show-CcdcDiscoverUsage {
    Write-Host ""
    Write-Host "ccdc discover - System discovery and enumeration" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  network (net)        Show network interfaces, routes, DNS"
    Write-Host "  ports                Show listening ports and connections"
    Write-Host "  users                List users, groups, admin membership"
    Write-Host "  processes (ps)       Show running processes"
    Write-Host "  cron                 List scheduled tasks"
    Write-Host "  services (svc)       List running and enabled services"
    Write-Host "  firewall (fw)        Dump current firewall rules"
    Write-Host "  integrity            Run system file checker"
    Write-Host "  all                  Run all discovery commands"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --help"
    Write-Host "  -h                   Show help"
    Write-Host ""
    Write-Host "All output is saved to $global:CCDC_BACKUP_DIR\discovery\"
}

# ── Internal Helpers ──

function Get-CcdcDiscoverOutDir {
    $outdir = Join-Path $global:CCDC_BACKUP_DIR "discovery"
    if (-not (Test-Path $outdir)) {
        New-Item -ItemType Directory -Path $outdir -Force | Out-Null
    }
    return $outdir
}

function Save-CcdcDiscoverOutput {
    param(
        [string]$OutFile,
        [string]$Content
    )
    $Content | Out-File -FilePath $OutFile -Encoding UTF8 -Force
    Write-Host $Content
    Write-CcdcLog "Saved to $OutFile" -Level Success
}

# ── Network ──

function Invoke-CcdcDiscoverNetwork {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover network"; Write-Host "Show network interfaces, routes, and DNS"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "network.txt"

    Write-CcdcLog "Discovering network configuration..." -Level Info

    $output = @()
    $output += "=== IP Configuration ==="
    try { $output += (ipconfig /all 2>$null) } catch { $output += "(ipconfig failed)" }
    $output += ""

    $output += "=== IP Addresses ==="
    try { $output += (Get-NetIPAddress | Format-Table -AutoSize | Out-String) } catch { $output += "(Get-NetIPAddress failed)" }
    $output += ""

    $output += "=== Routes ==="
    try { $output += (Get-NetRoute | Format-Table -AutoSize | Out-String) } catch { $output += "(Get-NetRoute failed)" }
    $output += ""

    $output += "=== DNS Servers ==="
    try { $output += (Get-DnsClientServerAddress | Format-Table -AutoSize | Out-String) } catch { $output += "(DNS query failed)" }
    $output += ""

    $output += "=== Hostname ==="
    $output += $env:COMPUTERNAME

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── Ports ──

function Invoke-CcdcDiscoverPorts {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover ports"; Write-Host "Show listening ports and active connections"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "ports.txt"

    Write-CcdcLog "Discovering listening ports..." -Level Info

    $output = @()
    $output += "=== Listening TCP Connections ==="
    try {
        $output += (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Select-Object LocalAddress, LocalPort, OwningProcess,
                @{Name='ProcessName';Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} |
            Sort-Object LocalPort |
            Format-Table -AutoSize |
            Out-String)
    } catch { $output += "(Get-NetTCPConnection failed)" }
    $output += ""

    $output += "=== All TCP Connections ==="
    try {
        $output += (Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Select-Object State, LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess |
            Format-Table -AutoSize |
            Out-String)
    } catch { $output += "(failed)" }
    $output += ""

    $output += "=== UDP Endpoints ==="
    try {
        $output += (Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
            Select-Object LocalAddress, LocalPort, OwningProcess |
            Format-Table -AutoSize |
            Out-String)
    } catch { $output += "(Get-NetUDPEndpoint failed)" }

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── Users ──

function Invoke-CcdcDiscoverUsers {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover users"; Write-Host "List users, groups, admin membership"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "users.txt"

    Write-CcdcLog "Discovering users and groups..." -Level Info

    $output = @()
    $output += "=== Local Users ==="
    try {
        $output += (Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet, Description |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(Get-LocalUser failed)" }
    $output += ""

    $output += "=== Administrators Group ==="
    try {
        $output += (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(failed)" }
    $output += ""

    $output += "=== Remote Desktop Users ==="
    try {
        $output += (Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(no Remote Desktop Users group)" }
    $output += ""

    $output += "=== All Local Groups ==="
    try {
        $output += (Get-LocalGroup | Format-Table -AutoSize | Out-String)
    } catch { $output += "(failed)" }
    $output += ""

    # AD users if DC
    if ($global:CCDC_IS_DC) {
        $output += "=== AD Domain Admins ==="
        try {
            $output += (Get-ADGroupMember -Identity "Domain Admins" -ErrorAction SilentlyContinue |
                Format-Table -AutoSize | Out-String)
        } catch { $output += "(AD query failed)" }
        $output += ""

        $output += "=== AD Enterprise Admins ==="
        try {
            $output += (Get-ADGroupMember -Identity "Enterprise Admins" -ErrorAction SilentlyContinue |
                Format-Table -AutoSize | Out-String)
        } catch { $output += "(AD query failed)" }
        $output += ""

        $output += "=== AD Users ==="
        try {
            $output += (Get-ADUser -Filter * -Properties Enabled, LastLogonDate, PasswordLastSet |
                Select-Object Name, SamAccountName, Enabled, LastLogonDate, PasswordLastSet |
                Format-Table -AutoSize | Out-String)
        } catch { $output += "(AD query failed)" }
    }

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── Processes ──

function Invoke-CcdcDiscoverProcesses {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover processes"; Write-Host "Show running processes"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "processes.txt"

    Write-CcdcLog "Discovering running processes..." -Level Info

    $output = @()
    $output += "=== Running Processes ==="
    try {
        $output += (Get-Process | Select-Object Id, ProcessName, CPU, WorkingSet64, Path |
            Sort-Object ProcessName |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(Get-Process failed)" }
    $output += ""

    $output += "=== Process Command Lines ==="
    try {
        $output += (Get-CimInstance Win32_Process |
            Select-Object ProcessId, Name, CommandLine |
            Format-Table -AutoSize -Wrap | Out-String)
    } catch { $output += "(WMI query failed)" }

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── Cron (Scheduled Tasks) ──

function Invoke-CcdcDiscoverCron {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover cron"; Write-Host "List scheduled tasks"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "cron.txt"

    Write-CcdcLog "Discovering scheduled tasks..." -Level Info

    $output = @()
    $output += "=== Scheduled Tasks ==="
    try {
        $output += (Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne 'Disabled' } |
            Select-Object TaskName, TaskPath, State, Author |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(Get-ScheduledTask failed)" }
    $output += ""

    $output += "=== Scheduled Tasks (Detailed) ==="
    try {
        $output += (schtasks /query /fo LIST /v 2>$null)
    } catch { $output += "(schtasks failed)" }
    $output += ""

    $output += "=== Startup Items (Registry) ==="
    $startupKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($key in $startupKeys) {
        $output += "--- $key ---"
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                    $output += "  $($_.Name) = $($_.Value)"
                }
            } else {
                $output += "  (empty)"
            }
        } catch {
            $output += "  (not accessible)"
        }
    }

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── Services ──

function Invoke-CcdcDiscoverServices {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover services"; Write-Host "List running and enabled services"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "services.txt"

    Write-CcdcLog "Discovering services..." -Level Info

    $output = @()
    $output += "=== Running Services ==="
    try {
        $output += (Get-Service | Where-Object { $_.Status -eq 'Running' } |
            Select-Object Name, DisplayName, Status, StartType |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(Get-Service failed)" }
    $output += ""

    $output += "=== All Services (Detailed) ==="
    try {
        $output += (Get-CimInstance Win32_Service |
            Select-Object Name, DisplayName, State, StartMode, PathName |
            Sort-Object Name |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(WMI query failed)" }

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── Firewall ──

function Invoke-CcdcDiscoverFirewall {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover firewall"; Write-Host "Dump current firewall rules"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "firewall.txt"

    Write-CcdcLog "Discovering firewall rules..." -Level Info

    $output = @()
    $output += "=== Firewall Profiles ==="
    try {
        $output += (Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(Get-NetFirewallProfile failed)" }
    $output += ""

    $output += "=== Enabled Inbound Rules ==="
    try {
        $output += (Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue |
            Select-Object DisplayName, Action, Profile, Direction |
            Sort-Object DisplayName |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(failed)" }
    $output += ""

    $output += "=== Enabled Outbound Rules ==="
    try {
        $output += (Get-NetFirewallRule -Direction Outbound -Enabled True -ErrorAction SilentlyContinue |
            Select-Object DisplayName, Action, Profile, Direction |
            Sort-Object DisplayName |
            Format-Table -AutoSize | Out-String)
    } catch { $output += "(failed)" }

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── Integrity ──

function Invoke-CcdcDiscoverIntegrity {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover integrity"; Write-Host "Run system file checker (slow)"; return }

    $outdir = Get-CcdcDiscoverOutDir
    $outfile = Join-Path $outdir "integrity.txt"

    Write-CcdcLog "Starting system file checker in background (takes 5-15 min)..." -Level Info

    $output = @()
    $output += "=== System File Checker ==="
    $output += "sfc /verifyonly started as background job"
    $output += "Check results later: Get-Content $outfile"

    # Run sfc in background so it doesn't block
    Start-Job -ScriptBlock {
        param($outPath)
        $result = sfc /verifyonly 2>&1
        Add-Content -Path $outPath -Value "`r`n=== sfc Results ==="
        Add-Content -Path $outPath -Value ($result -join "`r`n")
    } -ArgumentList $outfile | Out-Null

    $text = $output -join "`r`n"
    Save-CcdcDiscoverOutput -OutFile $outfile -Content $text
}

# ── All ──

function Invoke-CcdcDiscoverAll {
    if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover all"; Write-Host "Run all discovery commands"; return }

    Write-CcdcLog "Running full system discovery..." -Level Info
    Write-Host ""

    $failed = 0

    try { Invoke-CcdcDiscoverNetwork } catch { $failed++ }
    Write-Host ""
    try { Invoke-CcdcDiscoverPorts } catch { $failed++ }
    Write-Host ""
    try { Invoke-CcdcDiscoverUsers } catch { $failed++ }
    Write-Host ""
    try { Invoke-CcdcDiscoverProcesses } catch { $failed++ }
    Write-Host ""
    try { Invoke-CcdcDiscoverCron } catch { $failed++ }
    Write-Host ""
    try { Invoke-CcdcDiscoverServices } catch { $failed++ }
    Write-Host ""
    try { Invoke-CcdcDiscoverFirewall } catch { $failed++ }
    Write-Host ""
    try { Invoke-CcdcDiscoverIntegrity } catch { $failed++ }
    Write-Host ""

    $outdir = Join-Path $global:CCDC_BACKUP_DIR "discovery"
    Write-CcdcLog "=== Discovery Summary ===" -Level Info
    Write-CcdcLog "Output directory: $outdir" -Level Info
    $count = (Get-ChildItem -Path $outdir -Filter "*.txt" -ErrorAction SilentlyContinue).Count
    Write-CcdcLog "Files created: $count" -Level Info
    if ($failed -gt 0) {
        Write-CcdcLog "$failed discovery commands had errors" -Level Warn
    } else {
        Write-CcdcLog "All discovery commands completed successfully" -Level Success
    }
}

# ── Handler ──

function Invoke-CcdcDiscover {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcDiscoverUsage
        return
    }

    switch ($Command) {
        { $_ -in 'network','net' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover network"; Write-Host "Show network interfaces, routes, and DNS"; return }
            Invoke-CcdcDiscoverNetwork
        }
        'ports' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover ports"; Write-Host "Show listening ports and active connections"; return }
            Invoke-CcdcDiscoverPorts
        }
        'users' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover users"; Write-Host "List users, groups, admin membership"; return }
            Invoke-CcdcDiscoverUsers
        }
        { $_ -in 'processes','ps' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover processes"; Write-Host "Show running processes"; return }
            Invoke-CcdcDiscoverProcesses
        }
        'cron' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover cron"; Write-Host "List scheduled tasks"; return }
            Invoke-CcdcDiscoverCron
        }
        { $_ -in 'services','svc' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover services"; Write-Host "List running and enabled services"; return }
            Invoke-CcdcDiscoverServices
        }
        { $_ -in 'firewall','fw' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover firewall"; Write-Host "Dump current firewall rules"; return }
            Invoke-CcdcDiscoverFirewall
        }
        'integrity' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover integrity"; Write-Host "Run system file checker"; return }
            Invoke-CcdcDiscoverIntegrity
        }
        'all' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc discover all"; Write-Host "Run all discovery commands"; return }
            Invoke-CcdcDiscoverAll
        }
        '' { Show-CcdcDiscoverUsage }
        default {
            Write-CcdcLog "Unknown discover command: $Command" -Level Error
            Show-CcdcDiscoverUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcDiscover
