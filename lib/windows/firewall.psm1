# ccdc-cli: firewall module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1, undo.psm1
# All rules use CCDC- prefix in DisplayName for identification and cleanup

# ── Usage ──

function Show-CcdcFirewallUsage {
    Write-Host ""
    Write-Host "ccdc firewall - Firewall management" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  on                   Enable firewall, set default deny"
    Write-Host "  allow-in <port> [p]  Allow inbound port (default: tcp)"
    Write-Host "  block-in <port> [p]  Block inbound port"
    Write-Host "  allow-out <port> [p] Allow outbound port"
    Write-Host "  block-out <port> [p] Block outbound port"
    Write-Host "  drop-all-in          Default deny all inbound"
    Write-Host "  drop-all-out         Default deny all outbound"
    Write-Host "  allow-only-in <p,p>  Drop all except listed ports (in+out)"
    Write-Host "  block-ip <ip>        Block all traffic from IP"
    Write-Host "  status               Show current firewall rules"
    Write-Host "  save                 (auto-persists on Windows)"
    Write-Host "  allow-internet       Open outbound 80,443,53"
    Write-Host "  block-internet       Close outbound 80,443,53"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --activate <sec>     Auto-revert rules after N seconds unless confirmed"
    Write-Host "  --undo               Undo the last run of a command"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc fw on                          Enable firewall"
    Write-Host "  ccdc fw allow-only-in 80,443,3389   Lock down to scored ports"
    Write-Host "  ccdc fw allow-in 8080               Open port 8080/tcp inbound"
    Write-Host "  ccdc fw block-ip 10.0.0.99          Block attacker IP"
    Write-Host "  ccdc fw status                      Show rules"
}

# ── Internal Helpers ──

function Save-CcdcFirewallSnapshot {
    param([string]$SnapshotDir)
    try {
        Get-NetFirewallProfile | Export-Csv -Path (Join-Path $SnapshotDir "profiles.csv") -NoTypeInformation -Force
        Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Export-Csv -Path (Join-Path $SnapshotDir "rules.csv") -NoTypeInformation -Force
    } catch {
        Write-CcdcLog "Could not save firewall snapshot: $_" -Level Warn
    }
}

function Restore-CcdcFirewallSnapshot {
    param([string]$SnapshotDir)

    Write-CcdcLog "Restoring firewall rules from $SnapshotDir..." -Level Info

    # Remove all CCDC rules first
    Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'CCDC-*' } |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    # Restore profile defaults from snapshot
    $profilesCsv = Join-Path $SnapshotDir "profiles.csv"
    if (Test-Path $profilesCsv) {
        $profiles = Import-Csv $profilesCsv
        foreach ($p in $profiles) {
            try {
                Set-NetFirewallProfile -Name $p.Name `
                    -Enabled ([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]$p.Enabled) `
                    -DefaultInboundAction ([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Action]$p.DefaultInboundAction) `
                    -DefaultOutboundAction ([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Action]$p.DefaultOutboundAction) `
                    -ErrorAction SilentlyContinue
            } catch {
                Write-CcdcLog "Could not restore profile $($p.Name): $_" -Level Warn
            }
        }
    }

    # Re-create CCDC rules from snapshot
    $rulesCsv = Join-Path $SnapshotDir "rules.csv"
    if (Test-Path $rulesCsv) {
        $rules = Import-Csv $rulesCsv | Where-Object { $_.DisplayName -like 'CCDC-*' }
        foreach ($r in $rules) {
            try {
                New-NetFirewallRule -DisplayName $r.DisplayName `
                    -Direction $r.Direction `
                    -Action $r.Action `
                    -Enabled $r.Enabled `
                    -ErrorAction SilentlyContinue | Out-Null
            } catch {
                # Best-effort restore
            }
        }
    }

    Write-CcdcLog "Firewall rules restored" -Level Success
}

function Invoke-CcdcFirewallUndo {
    param([string]$Cmd)
    $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "firewall" -Command $Cmd
    if (-not $snapshotDir) {
        Write-CcdcLog "No undo snapshot found for firewall $Cmd" -Level Error
        return
    }
    Restore-CcdcFirewallSnapshot -SnapshotDir $snapshotDir
}

function Get-CcdcActivateTimeout {
    param([string[]]$Args)
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq '--activate' -and ($i + 1) -lt $Args.Count) {
            return [int]$Args[$i + 1]
        }
    }
    return $null
}

function Start-CcdcActivateTimer {
    param(
        [string]$SnapshotDir,
        [int]$Timeout
    )
    Write-CcdcLog "Rules will auto-revert in ${Timeout}s unless confirmed" -Level Warn

    $job = Start-Job -ScriptBlock {
        param($dir, $sec)
        Start-Sleep -Seconds $sec
        # Restore by removing CCDC rules
        Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'CCDC-*' } |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
    } -ArgumentList $SnapshotDir, $Timeout

    if (Confirm-CcdcAction 'Keep the new firewall rules?') {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -ErrorAction SilentlyContinue
        Write-CcdcLog "Rules confirmed and kept" -Level Success
    } else {
        Wait-Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $job -ErrorAction SilentlyContinue
        Write-CcdcLog "Rules reverted" -Level Info
    }
}

# ── Subcommands ──

function Invoke-CcdcFirewallOn {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "on"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "on"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    Write-CcdcLog "Enabling Windows Firewall..." -Level Info
    Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Block

    # Allow loopback
    $loopbackExists = Get-NetFirewallRule -DisplayName 'CCDC-Allow-Loopback' -ErrorAction SilentlyContinue
    if (-not $loopbackExists) {
        New-NetFirewallRule -DisplayName 'CCDC-Allow-Loopback' -Direction Inbound -InterfaceAlias 'Loopback*' -Action Allow -ErrorAction SilentlyContinue | Out-Null
    }

    Write-CcdcLog "Windows Firewall enabled with default deny in+out" -Level Success
    Add-CcdcUndoLog "firewall on -- enabled with default deny, snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallAllowIn {
    param(
        [string]$Port,
        [string]$Proto = "tcp",
        [string[]]$ExtraArgs
    )

    if (-not $Port) {
        Write-CcdcLog 'Usage: ccdc firewall allow-in <port> [proto]' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "allow-in"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "allow-in"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    $ruleName = "CCDC-Allow-In-${Port}-${Proto}"
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $Port -Protocol $Proto -Action Allow | Out-Null
    Write-CcdcLog "Allowed inbound ${Port}/${Proto}" -Level Success
    Add-CcdcUndoLog "firewall allow-in ${Port}/${Proto} -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallBlockIn {
    param(
        [string]$Port,
        [string]$Proto = "tcp",
        [string[]]$ExtraArgs
    )

    if (-not $Port) {
        Write-CcdcLog 'Usage: ccdc firewall block-in <port> [proto]' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "block-in"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "block-in"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    $ruleName = "CCDC-Block-In-${Port}-${Proto}"
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $Port -Protocol $Proto -Action Block | Out-Null
    Write-CcdcLog "Blocked inbound ${Port}/${Proto}" -Level Success
    Add-CcdcUndoLog "firewall block-in ${Port}/${Proto} -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallAllowOut {
    param(
        [string]$Port,
        [string]$Proto = "tcp",
        [string[]]$ExtraArgs
    )

    if (-not $Port) {
        Write-CcdcLog 'Usage: ccdc firewall allow-out <port> [proto]' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "allow-out"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "allow-out"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    $ruleName = "CCDC-Allow-Out-${Port}-${Proto}"
    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -LocalPort $Port -Protocol $Proto -Action Allow | Out-Null
    Write-CcdcLog "Allowed outbound ${Port}/${Proto}" -Level Success
    Add-CcdcUndoLog "firewall allow-out ${Port}/${Proto} -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallBlockOut {
    param(
        [string]$Port,
        [string]$Proto = "tcp",
        [string[]]$ExtraArgs
    )

    if (-not $Port) {
        Write-CcdcLog 'Usage: ccdc firewall block-out <port> [proto]' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "block-out"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "block-out"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    $ruleName = "CCDC-Block-Out-${Port}-${Proto}"
    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -LocalPort $Port -Protocol $Proto -Action Block | Out-Null
    Write-CcdcLog "Blocked outbound ${Port}/${Proto}" -Level Success
    Add-CcdcUndoLog "firewall block-out ${Port}/${Proto} -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallDropAllIn {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "drop-all-in"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "drop-all-in"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    Set-NetFirewallProfile -All -DefaultInboundAction Block
    Write-CcdcLog "Default inbound action set to Block" -Level Success
    Add-CcdcUndoLog "firewall drop-all-in -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallDropAllOut {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "drop-all-out"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "drop-all-out"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    Set-NetFirewallProfile -All -DefaultOutboundAction Block
    Write-CcdcLog "Default outbound action set to Block" -Level Success
    Add-CcdcUndoLog "firewall drop-all-out -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallAllowOnlyIn {
    param([string[]]$ExtraArgs)

    # Parse ports: first non-flag arg, or fall back to config
    $ports = ""
    foreach ($arg in $ExtraArgs) {
        if ($arg -notmatch '^--') {
            $ports = $arg
            break
        }
    }
    if (-not $ports) { $ports = $global:CCDC_SCORED_TCP }
    if (-not $ports) {
        Write-CcdcLog 'No ports specified and scored_ports_tcp not set in config' -Level Error
        Write-CcdcLog 'Usage: ccdc firewall allow-only-in <port1,port2,...>' -Level Info
        Write-CcdcLog 'Or set: ccdc config set scored_ports_tcp 22,80,443' -Level Info
        return
    }

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "allow-only-in"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "allow-only-in"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    Write-CcdcLog "Applying allow-only-in for ports: $ports" -Level Info

    # Remove existing CCDC rules
    Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'CCDC-*' } |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    # Set default deny both directions
    Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Block

    # Allow loopback
    New-NetFirewallRule -DisplayName 'CCDC-Allow-Loopback-In' -Direction Inbound -InterfaceAlias 'Loopback*' -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName 'CCDC-Allow-Loopback-Out' -Direction Outbound -InterfaceAlias 'Loopback*' -Action Allow -ErrorAction SilentlyContinue | Out-Null

    # Allow scored TCP ports inbound
    $portList = $ports -split ','
    foreach ($port in $portList) {
        $port = $port.Trim()
        if (-not $port) { continue }
        $ruleName = "CCDC-Allow-In-${port}-tcp"
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow | Out-Null
        Write-CcdcLog "Allowed inbound ${port}/tcp" -Level Info
    }

    # Allow scored UDP ports from config
    if ($global:CCDC_SCORED_UDP) {
        $udpList = $global:CCDC_SCORED_UDP -split ','
        foreach ($port in $udpList) {
            $port = $port.Trim()
            if (-not $port) { continue }
            $ruleName = "CCDC-Allow-In-${port}-udp"
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $port -Protocol UDP -Action Allow | Out-Null
            Write-CcdcLog "Allowed inbound ${port}/udp" -Level Info
        }
    }

    Write-CcdcLog "allow-only-in applied ($ports), all other traffic dropped" -Level Success
    Add-CcdcUndoLog "firewall allow-only-in $ports -- snapshot at $snapshotDir"

    # Handle --activate timer
    $timeout = Get-CcdcActivateTimeout -Args $ExtraArgs
    if ($timeout) {
        Start-CcdcActivateTimer -SnapshotDir $snapshotDir -Timeout $timeout
    }
}

function Invoke-CcdcFirewallBlockIp {
    param(
        [string]$Ip,
        [string[]]$ExtraArgs
    )

    if (-not $Ip) {
        Write-CcdcLog 'Usage: ccdc firewall block-ip <ip>' -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "block-ip"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "block-ip"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    $ruleName = "CCDC-Block-${Ip}"
    New-NetFirewallRule -DisplayName "$ruleName-In" -Direction Inbound -RemoteAddress $Ip -Action Block | Out-Null
    New-NetFirewallRule -DisplayName "$ruleName-Out" -Direction Outbound -RemoteAddress $Ip -Action Block | Out-Null
    Write-CcdcLog "Blocked all traffic from/to $Ip" -Level Success
    Add-CcdcUndoLog "firewall block-ip $Ip -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallStatus {
    Write-Host ""
    Write-Host "=== Firewall Profiles ===" -ForegroundColor Cyan
    Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Format-Table -AutoSize

    Write-Host "=== CCDC Rules ===" -ForegroundColor Cyan
    $ccdcRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'CCDC-*' }
    if ($ccdcRules) {
        $ccdcRules | Select-Object DisplayName, Direction, Action, Enabled | Format-Table -AutoSize
    } else {
        Write-Host "  (no CCDC rules found)"
    }
}

function Invoke-CcdcFirewallSave {
    Write-CcdcLog "Windows Firewall auto-persists rules. No action needed." -Level Info
    Add-CcdcUndoLog "firewall save -- Windows auto-persists"
}

function Invoke-CcdcFirewallAllowInternet {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "allow-internet"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "allow-internet"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    New-NetFirewallRule -DisplayName 'CCDC-Internet-HTTP' -Direction Outbound -RemotePort 80 -Protocol TCP -Action Allow | Out-Null
    New-NetFirewallRule -DisplayName 'CCDC-Internet-HTTPS' -Direction Outbound -RemotePort 443 -Protocol TCP -Action Allow | Out-Null
    New-NetFirewallRule -DisplayName 'CCDC-Internet-DNS-TCP' -Direction Outbound -RemotePort 53 -Protocol TCP -Action Allow | Out-Null
    New-NetFirewallRule -DisplayName 'CCDC-Internet-DNS-UDP' -Direction Outbound -RemotePort 53 -Protocol UDP -Action Allow | Out-Null

    Write-CcdcLog "Outbound 80,443,53 opened for downloads" -Level Success
    Add-CcdcUndoLog "firewall allow-internet -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallBlockInternet {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Invoke-CcdcFirewallUndo -Cmd "block-internet"
        return
    }

    $snapshotDir = New-CcdcUndoSnapshot -Category "firewall" -Command "block-internet"
    Save-CcdcFirewallSnapshot -SnapshotDir $snapshotDir

    'CCDC-Internet-HTTP','CCDC-Internet-HTTPS','CCDC-Internet-DNS-TCP','CCDC-Internet-DNS-UDP' | ForEach-Object {
        Remove-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
    }

    Write-CcdcLog "Outbound 80,443,53 closed" -Level Success
    Add-CcdcUndoLog "firewall block-internet -- snapshot at $snapshotDir"
}

# ── Handler ──

function Invoke-CcdcFirewall {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcFirewallUsage
        return
    }

    # Parse port and proto from CmdArgs
    $port = if ($CmdArgs.Count -ge 1 -and $CmdArgs[0] -notmatch '^--') { $CmdArgs[0] } else { $null }
    $proto = if ($CmdArgs.Count -ge 2 -and $CmdArgs[1] -notmatch '^--') { $CmdArgs[1] } else { "tcp" }

    switch ($Command) {
        'on' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc firewall on"; Write-Host "Enable firewall, set default deny"; return }
            Invoke-CcdcFirewallOn -ExtraArgs $CmdArgs
        }
        'allow-in' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc firewall allow-in <port> [proto]'; return }
            Invoke-CcdcFirewallAllowIn -Port $port -Proto $proto -ExtraArgs $CmdArgs
        }
        'block-in' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc firewall block-in <port> [proto]'; return }
            Invoke-CcdcFirewallBlockIn -Port $port -Proto $proto -ExtraArgs $CmdArgs
        }
        'allow-out' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc firewall allow-out <port> [proto]'; return }
            Invoke-CcdcFirewallAllowOut -Port $port -Proto $proto -ExtraArgs $CmdArgs
        }
        'block-out' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc firewall block-out <port> [proto]'; return }
            Invoke-CcdcFirewallBlockOut -Port $port -Proto $proto -ExtraArgs $CmdArgs
        }
        'drop-all-in' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc firewall drop-all-in"; Write-Host "Default deny all inbound"; return }
            Invoke-CcdcFirewallDropAllIn -ExtraArgs $CmdArgs
        }
        'drop-all-out' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc firewall drop-all-out"; Write-Host "Default deny all outbound"; return }
            Invoke-CcdcFirewallDropAllOut -ExtraArgs $CmdArgs
        }
        'allow-only-in' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc firewall allow-only-in <port1,port2,...> [--activate <sec>]'; Write-Host 'Drop all except listed ports (inbound+outbound)'; return }
            Invoke-CcdcFirewallAllowOnlyIn -ExtraArgs $CmdArgs
        }
        'block-ip' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc firewall block-ip <ip>'; return }
            Invoke-CcdcFirewallBlockIp -Ip $port -ExtraArgs $CmdArgs
        }
        { $_ -in 'status','show' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc firewall status"; Write-Host "Show current firewall rules"; return }
            Invoke-CcdcFirewallStatus
        }
        'save' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc firewall save"; return }
            Invoke-CcdcFirewallSave
        }
        'allow-internet' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc firewall allow-internet"; Write-Host "Open outbound 80,443,53"; return }
            Invoke-CcdcFirewallAllowInternet -ExtraArgs $CmdArgs
        }
        'block-internet' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc firewall block-internet"; Write-Host "Close outbound 80,443,53"; return }
            Invoke-CcdcFirewallBlockInternet -ExtraArgs $CmdArgs
        }
        '' { Show-CcdcFirewallUsage }
        default {
            Write-CcdcLog "Unknown firewall command: $Command" -Level Error
            Show-CcdcFirewallUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcFirewall
