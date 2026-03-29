# ccdc-cli: password management module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1, undo.psm1

# ── Usage ──

function Show-CcdcPasswdUsage {
    Write-Host ""
    Write-Host "ccdc passwd - Password management" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  list (ls)            List all local users with groups and status"
    Write-Host "  <username>           Change password for a specific user"
    Write-Host "  root                 Change Administrator password"
    Write-Host "  backup-user (bak)    Create backup admin user (default: printer)"
    Write-Host "  lock-all (lock)      Disable all users except Administrator and backup"
    Write-Host "  ad-change (ad)       Change AD account password (DC only)"
    Write-Host "  dsrm                 Reset DSRM password (DC only)"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --name <name>        Custom backup username (for backup-user)"
    Write-Host "  --keep <u1,u2>       Users to skip when locking (for lock-all)"
    Write-Host "  --undo               Undo the last run of a command"
}

# ── List Users ──

function Invoke-CcdcPasswdList {
    Write-CcdcLog "Listing all local users..." -Level Info

    # Get admin group members
    $adminMembers = @()
    try {
        $adminMembers = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue).Name |
            ForEach-Object { ($_ -split '\\')[-1] }
    } catch {}

    # Get RDP group members
    $rdpMembers = @()
    try {
        $rdpMembers = (Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue).Name |
            ForEach-Object { ($_ -split '\\')[-1] }
    } catch {}

    $users = Get-LocalUser
    Write-Host ""
    Write-Host ("{0,-20} {1,-12} {2,-30} {3,-10} {4}" -f "USERNAME", "ENABLED", "GROUPS", "LOCKED", "LAST LOGON")
    Write-Host ("{0,-20} {1,-12} {2,-30} {3,-10} {4}" -f "--------", "-------", "------", "------", "----------")

    foreach ($user in $users) {
        $groups = @()
        if ($user.Name -in $adminMembers) { $groups += "Administrators" }
        if ($user.Name -in $rdpMembers) { $groups += "RDP" }
        $groupStr = if ($groups.Count -gt 0) { ($groups -join ",") } else { "-" }

        $locked = if (-not $user.Enabled) { "YES" } else { "no" }
        $lastLogon = if ($user.LastLogon) { $user.LastLogon.ToString("yyyy-MM-dd HH:mm") } else { "Never" }

        $prefix = if ($user.Name -in $adminMembers) { "*" } else { " " }
        Write-Host ("{0}{1,-19} {2,-12} {3,-30} {4,-10} {5}" -f $prefix, $user.Name, $user.Enabled, $groupStr, $locked, $lastLogon)
    }
    Write-Host ""
    Write-Host "* = user is in Administrators group"
}

# ── Change User Password ──

function Invoke-CcdcPasswdChange {
    param(
        [string]$Username,
        [string[]]$ExtraArgs
    )

    if (-not $Username) {
        Write-CcdcLog "Usage: ccdc passwd <username> [--password <pass>]" -Level Error
        return
    }

    # Validate user exists
    try {
        Get-LocalUser -Name $Username -ErrorAction Stop | Out-Null
    } catch {
        Write-CcdcLog "User '$Username' does not exist" -Level Error
        return
    }

    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Password undo is not supported on Windows (no shadow file equivalent)" -Level Warn
        return
    }

    # Parse --password flag for non-interactive use (testing/automation)
    $plainPass = ""
    if ($ExtraArgs) {
        for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
            if ($ExtraArgs[$i] -eq '--password' -and ($i + 1) -lt $ExtraArgs.Count) {
                $plainPass = $ExtraArgs[$i + 1]
            }
        }
    }

    if ($plainPass) {
        $secPass = ConvertTo-SecureString $plainPass -AsPlainText -Force
    } else {
        $secPass1 = Read-Host "New password for $Username" -AsSecureString
        $secPass2 = Read-Host "Confirm password" -AsSecureString

        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass1)
        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
        $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass2)
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)

        if ($plain1 -ne $plain2) {
            Write-CcdcLog "Passwords do not match" -Level Error
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
            return
        }
        $secPass = $secPass1
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
    }

    try {
        Set-LocalUser -Name $Username -Password $secPass
        Write-CcdcLog "Password changed for $Username" -Level Success
        Add-CcdcUndoLog "passwd $Username -- password changed"
    } catch {
        Write-CcdcLog "Failed to change password: $_" -Level Error
    }
}

# ── Change Root (Administrator) ──

function Invoke-CcdcPasswdRoot {
    if ($global:CCDC_HELP) {
        Write-Host "Usage: ccdc passwd root"
        Write-Host "Changes the Administrator password"
        return
    }
    Invoke-CcdcPasswdChange -Username "Administrator"
}

# ── Backup User ──

function Invoke-CcdcPasswdBackupUser {
    param([string[]]$ExtraArgs)

    $backupName = $global:CCDC_BACKUP_USERNAME
    if (-not $backupName) { $backupName = "printer" }

    # Parse --name and --password flags
    $plainPass = ""
    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        if ($ExtraArgs[$i] -eq '--name' -and ($i + 1) -lt $ExtraArgs.Count) {
            $backupName = $ExtraArgs[$i + 1]
        }
        if ($ExtraArgs[$i] -eq '--password' -and ($i + 1) -lt $ExtraArgs.Count) {
            $plainPass = $ExtraArgs[$i + 1]
        }
    }

    # Undo: remove the user
    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "passwd" -Command "backup-user"
        if ($snapshotDir) {
            $savedName = Get-Content (Join-Path $snapshotDir "backup_username") -ErrorAction SilentlyContinue
            if ($savedName) { $backupName = $savedName }
        }
        try {
            Remove-LocalUser -Name $backupName -ErrorAction Stop
            Write-CcdcLog "Removed backup user: $backupName" -Level Success
            Add-CcdcUndoLog "passwd backup-user -- removed $backupName"
        } catch {
            Write-CcdcLog "Failed to remove user: $_" -Level Error
        }
        return
    }

    # Check if exists
    $existing = Get-LocalUser -Name $backupName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-CcdcLog "User '$backupName' already exists" -Level Warn
        return
    }

    # Get password (interactive or --password flag)
    if ($plainPass) {
        $secPass = ConvertTo-SecureString $plainPass -AsPlainText -Force
    } else {
        $secPass = Read-Host "Password for $backupName" -AsSecureString
    }

    # Create user
    try {
        New-LocalUser -Name $backupName -Password $secPass -FullName $backupName -Description "Backup admin account" | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member $backupName -ErrorAction SilentlyContinue
        Write-CcdcLog "Created backup user '$backupName' in Administrators group" -Level Success
    } catch {
        Write-CcdcLog "Failed to create local user: $_" -Level Error
        # Try AD if local fails (might be a DC)
        if ($global:CCDC_IS_DC) {
            try {
                Write-CcdcLog "Trying AD user creation..." -Level Info
                New-ADUser -Name $backupName -AccountPassword $secPass -Enabled $true -ErrorAction Stop
                Add-ADGroupMember -Identity "Domain Admins" -Members $backupName
                Write-CcdcLog "Created AD backup user '$backupName' in Domain Admins" -Level Success
            } catch {
                Write-CcdcLog "Failed to create AD user: $_" -Level Error
                return
            }
        } else {
            return
        }
    }

    # Save to snapshot for undo
    $snapshotDir = New-CcdcUndoSnapshot -Category "passwd" -Command "backup-user"
    Set-Content -Path (Join-Path $snapshotDir "backup_username") -Value $backupName
    Add-CcdcUndoLog "passwd backup-user -- created $backupName"
}

# ── Lock All Users ──

function Invoke-CcdcPasswdLockAll {
    param([string[]]$ExtraArgs)

    # Undo: re-enable users we disabled
    if ($global:CCDC_UNDO) {
        $snapshotDir = Get-CcdcUndoSnapshotLatest -Category "passwd" -Command "lock-all"
        if (-not $snapshotDir) {
            Write-CcdcLog "No undo snapshot found for lock-all" -Level Error
            return
        }
        $lockedFile = Join-Path $snapshotDir "locked_by_us.txt"
        if (-not (Test-Path $lockedFile)) {
            Write-CcdcLog "No locked user list in snapshot" -Level Error
            return
        }
        $count = 0
        Get-Content $lockedFile | ForEach-Object {
            try {
                Enable-LocalUser -Name $_ -ErrorAction Stop
                Write-CcdcLog "Unlocked: $_" -Level Info
                $count++
            } catch {}
        }
        Write-CcdcLog "Unlocked $count users" -Level Success
        Add-CcdcUndoLog "passwd lock-all -- unlocked $count users"
        return
    }

    # Build exclusion list
    $exclusions = @("Administrator", $env:USERNAME)
    if ($global:CCDC_BACKUP_USERNAME) {
        $exclusions += $global:CCDC_BACKUP_USERNAME
    }
    if ($global:CCDC_PASSWD_KEEP_UNLOCKED) {
        $exclusions += $global:CCDC_PASSWD_KEEP_UNLOCKED -split ','
    }

    # Parse --keep flag
    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        if ($ExtraArgs[$i] -eq '--keep' -and ($i + 1) -lt $ExtraArgs.Count) {
            $exclusions += $ExtraArgs[$i + 1] -split ','
        }
    }

    $exclusions = $exclusions | Select-Object -Unique
    Write-CcdcLog "Exclusions: $($exclusions -join ', ')" -Level Info

    # Create snapshot
    $snapshotDir = New-CcdcUndoSnapshot -Category "passwd" -Command "lock-all"

    # Lock users
    $count = 0
    Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -notin $exclusions } | ForEach-Object {
        try {
            Disable-LocalUser -Name $_.Name -ErrorAction Stop
            Add-Content -Path (Join-Path $snapshotDir "locked_by_us.txt") -Value $_.Name
            Write-CcdcLog "Locked: $($_.Name)" -Level Info
            $count++
        } catch {
            Write-CcdcLog "Failed to lock $($_.Name): $_" -Level Warn
        }
    }

    Add-CcdcUndoLog "passwd lock-all -- locked $count users"
    Write-CcdcLog "Locked $count users (excluded: $($exclusions -join ', '))" -Level Success
}

# ── AD Change (Windows DC only) ──

function Invoke-CcdcPasswdAdChange {
    param([string]$Username)

    if (-not $Username) {
        Write-CcdcLog "Usage: ccdc passwd ad-change <username>" -Level Error
        return
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Write-CcdcLog "Active Directory module not available. Is this a Domain Controller?" -Level Error
        return
    }

    try {
        Get-ADUser -Identity $Username -ErrorAction Stop | Out-Null
    } catch {
        Write-CcdcLog "AD user '$Username' not found" -Level Error
        return
    }

    $secPass = Read-Host "New AD password for $Username" -AsSecureString
    try {
        Set-ADAccountPassword -Identity $Username -NewPassword $secPass -Reset
        Set-ADUser -Identity $Username -ChangePasswordAtLogon $false
        Write-CcdcLog "AD password changed for $Username" -Level Success
        Add-CcdcUndoLog "passwd ad-change $Username -- password changed"
    } catch {
        Write-CcdcLog "Failed to change AD password: $_" -Level Error
    }
}

# ── DSRM (Windows DC only) ──

function Invoke-CcdcPasswdDsrm {
    if (-not $global:CCDC_IS_DC) {
        Write-CcdcLog "DSRM is only available on Domain Controllers" -Level Error
        return
    }

    Write-CcdcLog "Resetting DSRM password..." -Level Info
    Write-Host "You will be prompted by ntdsutil for the new DSRM password."
    Write-Host ""

    try {
        $process = Start-Process -FilePath "ntdsutil.exe" `
            -ArgumentList '"set dsrm password" "reset password on server null" q q' `
            -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0) {
            Write-CcdcLog "DSRM password reset successful" -Level Success
            Add-CcdcUndoLog "passwd dsrm -- password reset"
        } else {
            Write-CcdcLog "ntdsutil exited with code $($process.ExitCode)" -Level Error
        }
    } catch {
        Write-CcdcLog "Failed to run ntdsutil: $_" -Level Error
    }
}

# ── Handler ──

function Invoke-CcdcPasswd {
    param(
        [string]$Command,
        [string[]]$Args
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcPasswdUsage
        return
    }

    switch ($Command) {
        { $_ -in 'list','ls' }          { Invoke-CcdcPasswdList }
        'root'                           { Invoke-CcdcPasswdRoot }
        { $_ -in 'backup-user','bak' }  { Invoke-CcdcPasswdBackupUser -ExtraArgs $Args }
        { $_ -in 'lock-all','lock' }    { Invoke-CcdcPasswdLockAll -ExtraArgs $Args }
        { $_ -in 'ad-change','ad' }     { Invoke-CcdcPasswdAdChange -Username ($Args | Select-Object -First 1) }
        'dsrm'                           { Invoke-CcdcPasswdDsrm }
        ''                               { Show-CcdcPasswdUsage }
        default {
            # Treat unrecognized subcommand as a username
            Invoke-CcdcPasswdChange -Username $Command -ExtraArgs $Args
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcPasswd
