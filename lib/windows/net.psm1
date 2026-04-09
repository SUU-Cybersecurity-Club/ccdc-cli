# ccdc-cli: net module for Windows - firewall-aware downloads
# Depends on: common.psm1, config.psm1, firewall.psm1

# Import firewall module if not already loaded
$fwModule = Join-Path $PSScriptRoot "firewall.psm1"
if (Test-Path $fwModule) {
    if (-not (Get-Command Invoke-CcdcFirewall -ErrorAction SilentlyContinue)) {
        Import-Module $fwModule -Force
    }
}

# ── Usage ──

function Show-CcdcNetUsage {
    Write-Host ""
    Write-Host "ccdc net - Firewall-aware downloads" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  wget <url> [output]  Download file (opens outbound, downloads, closes)"
    Write-Host "  curl <url>           Quick fetch to stdout"
    Write-Host ""
    Write-Host "These commands automatically open outbound 80,443,53 before downloading"
    Write-Host "and close them after, even if the download fails."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc net wget https://example.com/tool.msi"
    Write-Host "  ccdc net wget https://example.com/tool.msi C:\temp\tool.msi"
    Write-Host "  ccdc net curl https://api.example.com/status"
}

# ── wget ──

function Invoke-CcdcNetWget {
    param(
        [string]$Url,
        [string]$Output
    )

    if (-not $Url) {
        Write-CcdcLog 'Usage: ccdc net wget <url> [output]' -Level Error
        return
    }
    if (-not $Output) {
        $Output = Split-Path $Url -Leaf
    }

    Write-CcdcLog "Opening outbound for download..." -Level Info
    try { Invoke-CcdcFirewallAllowInternet } catch { Write-CcdcLog "Could not open outbound (firewall may not be configured)" -Level Warn }

    Write-CcdcLog "Downloading: $Url" -Level Info
    $success = $false
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $Output -UseBasicParsing
        $success = $true
    } catch {
        Write-CcdcLog "Download failed: $_" -Level Error
    }

    Write-CcdcLog "Closing outbound..." -Level Info
    try { Invoke-CcdcFirewallBlockInternet } catch {}

    if ($success) {
        Write-CcdcLog "Downloaded to $Output" -Level Success
    }
}

# ── curl ──

function Invoke-CcdcNetCurl {
    param([string]$Url)

    if (-not $Url) {
        Write-CcdcLog 'Usage: ccdc net curl <url>' -Level Error
        return
    }

    Write-CcdcLog "Opening outbound for fetch..." -Level Info
    try { Invoke-CcdcFirewallAllowInternet } catch { Write-CcdcLog "Could not open outbound" -Level Warn }

    Write-CcdcLog "Fetching: $Url" -Level Info
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        Write-Host $response.Content
    } catch {
        Write-CcdcLog "Fetch failed: $_" -Level Error
    }

    Write-CcdcLog "Closing outbound..." -Level Info
    try { Invoke-CcdcFirewallBlockInternet } catch {}
}

# ── Handler ──

function Invoke-CcdcNet {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcNetUsage
        return
    }

    $url = if ($CmdArgs.Count -ge 1) { $CmdArgs[0] } else { $null }
    $output = if ($CmdArgs.Count -ge 2) { $CmdArgs[1] } else { $null }

    switch ($Command) {
        'wget' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc net wget <url> [output]'; Write-Host 'Download file with auto firewall open/close'; return }
            Invoke-CcdcNetWget -Url $url -Output $output
        }
        'curl' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc net curl <url>'; Write-Host 'Quick fetch with auto firewall open/close'; return }
            Invoke-CcdcNetCurl -Url $url
        }
        '' { Show-CcdcNetUsage }
        default {
            Write-CcdcLog "Unknown net command: $Command" -Level Error
            Show-CcdcNetUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcNet
