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
    Write-Host "  commit [-m msg]      Save numbered snapshot of current rules"
    Write-Host "  commit --log         Show commit history"
    Write-Host "  commit --diff [N]    Diff current rules vs commit N"
    Write-Host "  commit --undo        Rollback to previous commit"
    Write-Host "  commit --to N        Rollback to specific commit number"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --activate <sec>     Auto-revert rules after N seconds unless confirmed"
    Write-Host "  --undo               Undo the last run of a command"
    Write-Host ""
    $v = Get-CcdcFirewallVersion
    Write-Host "Version: v$v"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc fw on                          Enable firewall"
    Write-Host "  ccdc fw allow-only-in 80,443,3389   Lock down to scored ports"
    Write-Host "  ccdc fw commit -m 'initial lockdown' Save current rules"
    Write-Host "  ccdc fw commit --log                Show commit history"
    Write-Host "  ccdc fw commit --undo               Rollback one commit"
}

# ── Version Counter ──

function Get-CcdcFirewallVersion {
    $vfile = Join-Path $global:CCDC_UNDO_DIR "firewall\commits\version"
    if (Test-Path $vfile) { return (Get-Content $vfile).Trim() }
    return "0"
}

function Step-CcdcFirewallVersion {
    $commitsDir = Join-Path $global:CCDC_UNDO_DIR "firewall\commits"
    if (-not (Test-Path $commitsDir)) { New-Item -ItemType Directory -Path $commitsDir -Force | Out-Null }
    $vfile = Join-Path $commitsDir "version"
    $v = [int](Get-CcdcFirewallVersion)
    $v++
    Set-Content -Path $vfile -Value $v
    return $v
}

function Set-CcdcFirewallVersion {
    param([int]$N)
    $vfile = Join-Path $global:CCDC_UNDO_DIR "firewall\commits\version"
    $dir = Split-Path $vfile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $vfile -Value $N
}

# ── Commit System ──

function Get-CcdcFirewallRulesText {
    $output = @()
    $output += "=== Firewall Profiles ==="
    try { $output += (Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Format-Table -AutoSize | Out-String) } catch {}
    $output += "=== CCDC Rules ==="
    try {
        $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'CCDC-*' }
        if ($rules) { $output += ($rules | Select-Object DisplayName, Direction, Action, Enabled | Format-Table -AutoSize | Out-String) }
        else { $output += "  (no CCDC rules)" }
    } catch {}
    return ($output -join "`r`n")
}

function Invoke-CcdcFirewallCommit {
    param([string[]]$ExtraArgs)

    $action = ""
    $msg = ""
    $target = ""

    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        switch ($ExtraArgs[$i]) {
            '--log'     { $action = "log" }
            '--diff'    { $action = "diff"; if ($i + 1 -lt $ExtraArgs.Count -and $ExtraArgs[$i+1] -notmatch '^--') { $i++; $target = $ExtraArgs[$i] } }
            '--undo'    { $action = "undo" }
            '--to'      { $action = "to"; $i++; $target = $ExtraArgs[$i] }
            { $_ -in '-m','--message' } { $i++; $msg = $ExtraArgs[$i] }
        }
    }

    $commitsDir = Join-Path $global:CCDC_UNDO_DIR "firewall\commits"
    if (-not (Test-Path $commitsDir)) { New-Item -ItemType Directory -Path $commitsDir -Force | Out-Null }

    switch ($action) {
        'log'   { Invoke-CcdcFirewallCommitLog }
        'diff'  { Invoke-CcdcFirewallCommitDiff -Target $target }
        'undo'  { Invoke-CcdcFirewallCommitUndo }
        'to'    { Invoke-CcdcFirewallCommitTo -Target $target }
        default { Invoke-CcdcFirewallCommitSave -Message $msg }
    }
}

function Invoke-CcdcFirewallCommitSave {
    param([string]$Message)

    $commitsDir = Join-Path $global:CCDC_UNDO_DIR "firewall\commits"
    $latestFile = Join-Path $commitsDir "latest"
    $lastCommit = 0
    if (Test-Path $latestFile) { $lastCommit = [int](Get-Content $latestFile) }
    $newCommit = $lastCommit + 1

    $commitDir = Join-Path $commitsDir $newCommit
    New-Item -ItemType Directory -Path $commitDir -Force | Out-Null

    # Save rules
    Get-CcdcFirewallRulesText | Out-File (Join-Path $commitDir "rules.txt") -Encoding UTF8
    Save-CcdcFirewallSnapshot -SnapshotDir $commitDir
    Get-Date -Format 'yyyy-MM-dd HH:mm:ss' | Out-File (Join-Path $commitDir "timestamp")
    $Message | Out-File (Join-Path $commitDir "message")

    Set-Content -Path $latestFile -Value $newCommit

    Write-CcdcLog "Firewall commit #$newCommit" -Level Success
    if ($Message) { Write-CcdcLog "Message: $Message" -Level Info }

    # Diff against previous
    $prevRules = Join-Path $commitsDir "$lastCommit\rules.txt"
    $currRules = Join-Path $commitDir "rules.txt"
    if (Test-Path $prevRules) {
        $diff = Compare-Object (Get-Content $prevRules) (Get-Content $currRules) -ErrorAction SilentlyContinue
        if ($diff) {
            $added = ($diff | Where-Object { $_.SideIndicator -eq '=>' }).Count
            $removed = ($diff | Where-Object { $_.SideIndicator -eq '<=' }).Count
            Write-CcdcLog "$added additions, $removed removals since commit #$lastCommit" -Level Info
            foreach ($d in $diff) {
                if ($d.SideIndicator -eq '=>') { Write-Host "  + $($d.InputObject)" -ForegroundColor Green }
                else { Write-Host "  - $($d.InputObject)" -ForegroundColor Red }
            }
        } else {
            Write-CcdcLog "No changes from commit #$lastCommit" -Level Info
        }
    } else {
        Write-CcdcLog "(first commit - no diff available)" -Level Info
    }

    Add-CcdcUndoLog "firewall commit #$newCommit -- $Message"
}

function Invoke-CcdcFirewallCommitLog {
    $commitsDir = Join-Path $global:CCDC_UNDO_DIR "firewall\commits"
    $latestFile = Join-Path $commitsDir "latest"
    $latest = 0
    if (Test-Path $latestFile) { $latest = [int](Get-Content $latestFile) }

    if ($latest -eq 0) {
        Write-CcdcLog "No commits yet. Run: ccdc firewall commit" -Level Info
        return
    }

    $v = Get-CcdcFirewallVersion
    Write-Host ""
    Write-Host "Firewall commit history (version: v$v):" -ForegroundColor White
    Write-Host ""
    for ($i = 1; $i -le $latest; $i++) {
        $dir = Join-Path $commitsDir $i
        if (-not (Test-Path $dir)) { continue }
        $ts = Get-Content (Join-Path $dir "timestamp") -ErrorAction SilentlyContinue
        $msg = Get-Content (Join-Path $dir "message") -ErrorAction SilentlyContinue
        $marker = if ($i -eq $latest) { " *" } else { "" }
        if ($msg) { Write-Host "  #$i$marker  $ts  $msg" }
        else { Write-Host "  #$i$marker  $ts" }
    }
    Write-Host ""
    Write-Host "* = latest commit"
}

function Invoke-CcdcFirewallCommitDiff {
    param([string]$Target)

    $commitsDir = Join-Path $global:CCDC_UNDO_DIR "firewall\commits"
    $latestFile = Join-Path $commitsDir "latest"
    $latest = 0
    if (Test-Path $latestFile) { $latest = [int](Get-Content $latestFile) }

    if ($latest -eq 0) {
        Write-CcdcLog "No commits to diff against" -Level Info
        return
    }

    $compareNum = if ($Target) { [int]$Target } else { $latest }
    $committedRules = Join-Path $commitsDir "$compareNum\rules.txt"
    if (-not (Test-Path $committedRules)) {
        Write-CcdcLog "Commit #$compareNum not found" -Level Error
        return
    }

    Write-CcdcLog "Diff: commit #$compareNum vs current rules" -Level Info
    Write-Host ""

    $currentRules = Get-CcdcFirewallRulesText
    $diff = Compare-Object (Get-Content $committedRules) ($currentRules -split "`r?`n") -ErrorAction SilentlyContinue
    if ($diff) {
        foreach ($d in $diff) {
            if ($d.SideIndicator -eq '=>') { Write-Host "  + $($d.InputObject)" -ForegroundColor Green }
            else { Write-Host "  - $($d.InputObject)" -ForegroundColor Red }
        }
    } else {
        Write-CcdcLog "No changes since commit #$compareNum" -Level Success
    }
}

function Invoke-CcdcFirewallCommitUndo {
    $commitsDir = Join-Path $global:CCDC_UNDO_DIR "firewall\commits"
    $latestFile = Join-Path $commitsDir "latest"
    $latest = 0
    if (Test-Path $latestFile) { $latest = [int](Get-Content $latestFile) }

    if ($latest -le 0) {
        Write-CcdcLog "No commits to undo" -Level Error
        return
    }

    $target = $latest - 1
    if ($target -lt 1) {
        Write-CcdcLog "Already at first commit" -Level Warn
        return
    }

    Write-CcdcLog "Rolling back from commit #$latest to commit #$target..." -Level Info
    Restore-CcdcFirewallSnapshot -SnapshotDir (Join-Path $commitsDir $target)
    Set-Content -Path $latestFile -Value $target
    Write-CcdcLog "Restored to commit #$target" -Level Success
    Add-CcdcUndoLog "firewall commit --undo -- rolled back to commit #$target"
}

function Invoke-CcdcFirewallCommitTo {
    param([string]$Target)

    if (-not $Target) {
        Write-CcdcLog 'Usage: ccdc firewall commit --to <N>' -Level Error
        return
    }

    $commitsDir = Join-Path $global:CCDC_UNDO_DIR "firewall\commits"
    $commitDir = Join-Path $commitsDir $Target

    if (-not (Test-Path $commitDir)) {
        Write-CcdcLog "Commit #$Target not found" -Level Error
        return
    }

    Write-CcdcLog "Rolling back to commit #$Target..." -Level Info
    Restore-CcdcFirewallSnapshot -SnapshotDir $commitDir
    Set-Content -Path (Join-Path $commitsDir "latest") -Value $Target
    Write-CcdcLog "Restored to commit #$Target" -Level Success
    $msg = Get-Content (Join-Path $commitDir "message") -ErrorAction SilentlyContinue
    if ($msg) { Write-CcdcLog "Message: $msg" -Level Info }
    Add-CcdcUndoLog "firewall commit --to $Target -- restored to commit #$Target"
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
    $v = Step-CcdcFirewallVersion
    Write-CcdcLog "[v$v]" -Level Info
    Add-CcdcUndoLog "firewall on [v$v] -- enabled with default deny, snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall allow-in [v$v] ${Port}/${Proto} -- snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall block-in [v$v] ${Port}/${Proto} -- snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall allow-out [v$v] ${Port}/${Proto} -- snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall block-out [v$v] ${Port}/${Proto} -- snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall drop-all-in [v$v] -- snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall drop-all-out [v$v] -- snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall allow-only-in [v$v] $ports -- snapshot at $snapshotDir"

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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall block-ip [v$v] $Ip -- snapshot at $snapshotDir"
}

function Invoke-CcdcFirewallStatus {
    $v = Get-CcdcFirewallVersion
    Write-Host ""
    Write-Host "Firewall version: v$v  (backend: windows)" -ForegroundColor White
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall allow-internet [v$v] -- snapshot at $snapshotDir"
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
    $v = Step-CcdcFirewallVersion
    Add-CcdcUndoLog "firewall block-internet [v$v] -- snapshot at $snapshotDir"
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
        'commit' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc firewall commit [-m msg] [--log] [--diff [N]] [--undo] [--to N]'; Write-Host 'Save numbered snapshot, view history, or rollback'; return }
            Invoke-CcdcFirewallCommit -ExtraArgs $CmdArgs
        }
        '' { Show-CcdcFirewallUsage }
        default {
            Write-CcdcLog "Unknown firewall command: $Command" -Level Error
            Show-CcdcFirewallUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcFirewall
