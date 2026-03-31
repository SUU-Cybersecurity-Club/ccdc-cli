# ccdc-cli: backup module for Windows
# Depends on: common.psm1, detect.psm1, config.psm1, undo.psm1

# ── Usage ──

function Show-CcdcBackupUsage {
    Write-Host ""
    Write-Host "ccdc backup - Backup and restore" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  etc                  Export registry hives"
    Write-Host "  binaries (bin)       Backup Defender and firewall DLLs"
    Write-Host "  web                  Backup IIS wwwroot"
    Write-Host "  services (svc)       Save service list to CSV"
    Write-Host "  ip                   Save IP addresses and routes"
    Write-Host "  ports                Save listening ports"
    Write-Host "  db                   Backup SQL Server databases"
    Write-Host "  full (all)           Run all backup commands"
    Write-Host "  restore              Restore a specific backup by path"
    Write-Host "  list (ls)            List all backups with sizes"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --help"
    Write-Host "  -h                   Show help"
    Write-Host "  --undo               Restore from backup"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ccdc bak etc                    Export registry hives"
    Write-Host "  ccdc bak bin                    Backup Defender DLLs"
    Write-Host "  ccdc bak web                    Backup IIS wwwroot"
    Write-Host "  ccdc bak full                   Run all backups"
    Write-Host "  ccdc bak ls                     List existing backups"
    Write-Host "  ccdc bak restore C:\ccdc-backups\reghivves.zip"
    Write-Host "  ccdc bak etc --undo             Restore registry from backup"
}

# ── Internal Helpers ──

function New-CcdcBackupManifest {
    param([string]$FilePath)
    $dir = Split-Path $FilePath
    $name = Split-Path $FilePath -Leaf
    $manifest = Join-Path $dir ".$name.sha256"
    try {
        $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        Set-Content -Path $manifest -Value "$hash  $FilePath"
        Set-ItemProperty -Path $manifest -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue
        attrib +h $manifest 2>$null
    } catch {
        Write-CcdcLog "Could not create manifest: $_" -Level Warn
    }
}

function Test-CcdcBackupManifest {
    param([string]$FilePath)
    $dir = Split-Path $FilePath
    $name = Split-Path $FilePath -Leaf
    $manifest = Join-Path $dir ".$name.sha256"
    if (-not (Test-Path $manifest)) {
        Write-CcdcLog "No SHA256 manifest found for $name" -Level Warn
        return $true
    }
    try {
        Set-ItemProperty -Path $manifest -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        $stored = (Get-Content $manifest).Split(' ')[0].Trim()
        $current = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        Set-ItemProperty -Path $manifest -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue
        if ($stored -eq $current) {
            Write-CcdcLog "Integrity check passed for $name" -Level Info
            return $true
        } else {
            Write-CcdcLog "Integrity check FAILED for $name" -Level Error
            return $false
        }
    } catch {
        Write-CcdcLog "Manifest check error: $_" -Level Warn
        return $true
    }
}

function Set-CcdcAntiTamper {
    param([string]$FilePath)
    Set-ItemProperty -Path $FilePath -Name IsReadOnly -Value $true -ErrorAction SilentlyContinue
    attrib +h +r $FilePath 2>$null
}

function Remove-CcdcAntiTamper {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        attrib -h -r $FilePath 2>$null
        Set-ItemProperty -Path $FilePath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    }
    # Also unprotect manifest
    $dir = Split-Path $FilePath
    $name = Split-Path $FilePath -Leaf
    $manifest = Join-Path $dir ".$name.sha256"
    if (Test-Path $manifest) {
        attrib -h -r $manifest 2>$null
        Set-ItemProperty -Path $manifest -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    }
}

# ── Backup Etc (Registry Hives) ──

function Invoke-CcdcBackupEtc {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        $archive = Join-Path $global:CCDC_BACKUP_DIR "reghivves.zip"
        if (-not (Test-Path $archive)) {
            Write-CcdcLog "No registry backup found at $archive" -Level Error
            return
        }
        if (-not (Test-CcdcBackupManifest $archive)) { return }
        Remove-CcdcAntiTamper $archive
        $tempDir = Join-Path $env:TEMP "ccdc_reg_restore"
        Expand-Archive -Path $archive -DestinationPath $tempDir -Force
        Get-ChildItem $tempDir -Filter "*.reg" | ForEach-Object {
            reg import $_.FullName 2>$null
        }
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Set-CcdcAntiTamper $archive
        Write-CcdcLog "Registry restored from $archive" -Level Success
        Add-CcdcUndoLog "backup etc -- restored from $archive"
        return
    }

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $archive = Join-Path $backupDir "reghivves.zip"
    Remove-CcdcAntiTamper $archive

    Write-CcdcLog "Exporting registry hives..." -Level Info
    $tempDir = Join-Path $env:TEMP "ccdc_reg_export"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $hives = @("HKLM\SYSTEM", "HKLM\SOFTWARE", "HKLM\SAM", "HKLM\SECURITY")
    foreach ($hive in $hives) {
        $name = ($hive -split '\\')[-1]
        $outFile = Join-Path $tempDir "$name.reg"
        try {
            reg save $hive $outFile /y 2>$null
            if (-not (Test-Path $outFile)) {
                reg export $hive $outFile /y 2>$null
            }
        } catch {
            Write-CcdcLog "Could not export $hive (may need SYSTEM privileges)" -Level Warn
        }
    }

    if (Test-Path $archive) { Remove-Item $archive -Force }
    $items = Get-ChildItem $tempDir
    if ($items) {
        Compress-Archive -Path $items.FullName -DestinationPath $archive -Force
    }
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $archive)) {
        Write-CcdcLog "Failed to create registry backup" -Level Error
        exit 1
    }
    New-CcdcBackupManifest $archive
    Set-CcdcAntiTamper $archive
    $size = "{0:N1} MB" -f ((Get-Item $archive -Force).Length / 1MB)
    Add-CcdcUndoLog "backup etc -- $archive ($size)"
    Write-CcdcLog "Registry hives backed up to $archive ($size)" -Level Success
}

# ── Backup Binaries ──

function Invoke-CcdcBackupBinaries {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        $archive = Join-Path $global:CCDC_BACKUP_DIR "dfndr_dlls.zip"
        if (-not (Test-Path $archive)) {
            Write-CcdcLog "No binaries backup found at $archive" -Level Error
            return
        }
        Write-CcdcLog "Binary restore requires manual extraction from $archive" -Level Warn
        return
    }

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $archive = Join-Path $backupDir "dfndr_dlls.zip"
    Remove-CcdcAntiTamper $archive

    Write-CcdcLog "Backing up Defender and firewall binaries..." -Level Info
    $tempDir = Join-Path $env:TEMP "ccdc_bin_backup"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # Windows Defender
    $defenderPath = Join-Path $env:ProgramFiles "Windows Defender"
    if (Test-Path $defenderPath) {
        $destDir = Join-Path $tempDir "WindowsDefender"
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Copy-Item "$defenderPath\*.dll" $destDir -ErrorAction SilentlyContinue
        Copy-Item "$defenderPath\*.exe" $destDir -ErrorAction SilentlyContinue
    }

    # Firewall service DLLs
    $fwPaths = @(
        "$env:SystemRoot\System32\mpssvc.dll",
        "$env:SystemRoot\System32\bfe.dll",
        "$env:SystemRoot\System32\FWPUCLNT.DLL"
    )
    $fwDir = Join-Path $tempDir "Firewall"
    New-Item -ItemType Directory -Path $fwDir -Force | Out-Null
    foreach ($p in $fwPaths) {
        if (Test-Path $p) { Copy-Item $p $fwDir -ErrorAction SilentlyContinue }
    }

    if (Test-Path $archive) { Remove-Item $archive -Force }
    $items = Get-ChildItem $tempDir -Recurse -File
    if ($items) {
        Compress-Archive -Path $items.FullName -DestinationPath $archive -Force
    }
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $archive)) {
        Write-CcdcLog "Failed to create binaries backup" -Level Error
        exit 1
    }
    New-CcdcBackupManifest $archive
    Set-CcdcAntiTamper $archive
    $size = "{0:N1} MB" -f ((Get-Item $archive -Force).Length / 1MB)
    Add-CcdcUndoLog "backup binaries -- $archive ($size)"
    Write-CcdcLog "Binaries backed up to $archive ($size)" -Level Success
}

# ── Backup Web ──

function Invoke-CcdcBackupWeb {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        $archive = Join-Path $global:CCDC_BACKUP_DIR "iiswww.zip"
        if (-not (Test-Path $archive)) {
            Write-CcdcLog "No web backup found at $archive" -Level Error
            return
        }
        if (-not (Test-CcdcBackupManifest $archive)) { return }
        Remove-CcdcAntiTamper $archive
        $wwwroot = "C:\inetpub\wwwroot"
        if (Test-Path $wwwroot) { Remove-Item "$wwwroot\*" -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $archive -DestinationPath $wwwroot -Force
        Set-CcdcAntiTamper $archive
        Write-CcdcLog "Web content restored from $archive" -Level Success
        Add-CcdcUndoLog "backup web -- restored from $archive"
        return
    }

    $wwwroot = "C:\inetpub\wwwroot"
    if (-not (Test-Path $wwwroot)) {
        Write-CcdcLog "IIS wwwroot not found - skipping web backup" -Level Info
        return
    }

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $archive = Join-Path $backupDir "iiswww.zip"
    Remove-CcdcAntiTamper $archive

    Write-CcdcLog "Backing up IIS wwwroot..." -Level Info
    if (Test-Path $archive) { Remove-Item $archive -Force }
    $items = Get-ChildItem $wwwroot
    if ($items) {
        Compress-Archive -Path $items.FullName -DestinationPath $archive -Force
    }

    if (-not (Test-Path $archive)) {
        Write-CcdcLog "Failed to create web backup" -Level Error
        exit 1
    }
    New-CcdcBackupManifest $archive
    Set-CcdcAntiTamper $archive
    $size = "{0:N1} MB" -f ((Get-Item $archive -Force).Length / 1MB)
    Add-CcdcUndoLog "backup web -- $archive ($size)"
    Write-CcdcLog "Web content backed up to $archive ($size)" -Level Success
}

# ── Backup Services ──

function Invoke-CcdcBackupServices {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Services snapshot is informational - nothing to undo" -Level Info
        return
    }

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $outFile = Join-Path $backupDir "svcc_lisst.csv"
    Remove-CcdcAntiTamper $outFile

    Write-CcdcLog "Saving service list..." -Level Info
    Get-CimInstance Win32_Service |
        Select-Object Name, DisplayName, State, StartMode, StartName, PathName |
        Export-Csv $outFile -NoTypeInformation

    New-CcdcBackupManifest $outFile
    Set-CcdcAntiTamper $outFile
    Add-CcdcUndoLog "backup services -- $outFile"
    Write-CcdcLog "Service list saved to $outFile" -Level Success
}

# ── Backup IP ──

function Invoke-CcdcBackupIp {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Write-CcdcLog "IP snapshot is informational - nothing to undo" -Level Info
        return
    }

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $outFile = Join-Path $backupDir "ipp_addrs.txt"
    Remove-CcdcAntiTamper $outFile

    Write-CcdcLog "Saving IP configuration..." -Level Info
    $content = @()
    $content += "=== IP Configuration ==="
    $content += (ipconfig /all 2>$null) -join "`n"
    $content += ""
    $content += "=== Routes ==="
    $content += (route print 2>$null) -join "`n"
    $content += ""
    $content += "=== Network Adapters ==="
    $content += (Get-NetIPAddress | Format-Table -AutoSize | Out-String)
    $content += ""
    $content += "=== DNS ==="
    $content += (Get-DnsClientServerAddress | Format-Table -AutoSize | Out-String)

    Set-Content -Path $outFile -Value ($content -join "`n")

    New-CcdcBackupManifest $outFile
    Set-CcdcAntiTamper $outFile
    Add-CcdcUndoLog "backup ip -- $outFile"
    Write-CcdcLog "IP configuration saved to $outFile" -Level Success
}

# ── Backup Ports ──

function Invoke-CcdcBackupPorts {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Ports snapshot is informational - nothing to undo" -Level Info
        return
    }

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $outFile = Join-Path $backupDir "prts_snap.txt"
    Remove-CcdcAntiTamper $outFile

    Write-CcdcLog "Saving port information..." -Level Info
    $content = @()
    $content += "=== TCP Connections ==="
    $content += (Get-NetTCPConnection | Sort-Object State, LocalPort | Format-Table -AutoSize | Out-String)
    $content += ""
    $content += "=== UDP Endpoints ==="
    $content += (Get-NetUDPEndpoint | Sort-Object LocalPort | Format-Table -AutoSize | Out-String)
    $content += ""
    $content += "=== Listening Ports ==="
    $content += (Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Format-Table -AutoSize | Out-String)

    Set-Content -Path $outFile -Value ($content -join "`n")

    New-CcdcBackupManifest $outFile
    Set-CcdcAntiTamper $outFile
    Add-CcdcUndoLog "backup ports -- $outFile"
    Write-CcdcLog "Port information saved to $outFile" -Level Success
}

# ── Backup Database ──

function Invoke-CcdcBackupDb {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Database restore requires manual import from backup file" -Level Warn
        return
    }

    # Check for sqlcmd
    $sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if (-not $sqlcmd) {
        Write-CcdcLog "SQL Server (sqlcmd) not found - skipping database backup" -Level Info
        return
    }

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $outFile = Join-Path $backupDir "dbb_dmpp.bak"
    Remove-CcdcAntiTamper $outFile

    Write-CcdcLog "Backing up SQL Server databases..." -Level Info
    try {
        $databases = sqlcmd -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4" -h -1 2>$null
        if ($databases) {
            foreach ($db in $databases) {
                $db = $db.Trim()
                if ($db) {
                    $dbBackup = Join-Path $backupDir "dbb_${db}.bak"
                    sqlcmd -Q "BACKUP DATABASE [$db] TO DISK='$dbBackup' WITH FORMAT" 2>$null
                    Write-CcdcLog "Backed up database: $db" -Level Info
                }
            }
        }
        New-CcdcBackupManifest $outFile
        Set-CcdcAntiTamper $outFile
        Add-CcdcUndoLog "backup db -- $backupDir"
        Write-CcdcLog "Database backup complete" -Level Success
    } catch {
        Write-CcdcLog "Database backup failed: $_" -Level Error
    }
}

# ── Backup Full ──

function Invoke-CcdcBackupFull {
    param([string[]]$ExtraArgs)

    if ($global:CCDC_UNDO) {
        Write-CcdcLog "Use --undo on individual backup commands (e.g. ccdc bak etc --undo)" -Level Info
        return
    }

    Write-CcdcLog "Running full backup..." -Level Info
    $total = 0; $succeeded = 0

    $commands = @('etc', 'binaries', 'web', 'services', 'ip', 'ports', 'db')
    foreach ($cmd in $commands) {
        $total++
        Write-CcdcLog "--- backup $cmd ---" -Level Info
        try {
            & "Invoke-CcdcBackup$( (Get-Culture).TextInfo.ToTitleCase($cmd) )" -ExtraArgs $ExtraArgs
            $succeeded++
        } catch {
            Write-CcdcLog "backup $cmd had issues: $_ (continuing)" -Level Warn
        }
        Write-Host ""
    }

    Add-CcdcUndoLog "backup full -- $succeeded/$total succeeded"
    if ($succeeded -eq $total) {
        Write-CcdcLog "Full backup complete: $succeeded/$total succeeded" -Level Success
    } else {
        Write-CcdcLog "Full backup complete: $succeeded/$total succeeded, $($total - $succeeded) had issues" -Level Warn
    }
}

# ── Backup Restore ──

function Invoke-CcdcBackupRestore {
    param([string[]]$ExtraArgs)

    $archive = if ($ExtraArgs) { $ExtraArgs[0] } else { "" }
    if (-not $archive) {
        Write-CcdcLog 'Usage: ccdc backup restore <archive-path>' -Level Error
        return
    }

    if (-not (Test-Path $archive)) {
        Write-CcdcLog "File not found: $archive" -Level Error
        return
    }

    Test-CcdcBackupManifest $archive | Out-Null
    Remove-CcdcAntiTamper $archive

    $ext = [System.IO.Path]::GetExtension($archive)
    switch ($ext) {
        '.zip' {
            Write-CcdcLog "Restoring zip archive: $archive" -Level Info
            $dest = Split-Path $archive
            Expand-Archive -Path $archive -DestinationPath $dest -Force
        }
        '.reg' {
            Write-CcdcLog "Importing registry file: $archive" -Level Info
            reg import $archive 2>$null
        }
        default {
            Write-CcdcLog "Unknown archive type: $ext" -Level Error
            Set-CcdcAntiTamper $archive
            return
        }
    }

    Set-CcdcAntiTamper $archive
    Write-CcdcLog "Restored from $archive" -Level Success
    Add-CcdcUndoLog "backup restore -- restored $archive"
}

# ── Backup List ──

function Invoke-CcdcBackupList {
    param([string[]]$ExtraArgs)

    $backupDir = $global:CCDC_BACKUP_DIR
    if (-not (Test-Path $backupDir)) {
        Write-CcdcLog "No backup directory found at $backupDir" -Level Info
        return
    }

    Write-CcdcLog "Backups in ${backupDir}:" -Level Info
    Write-Host ""
    Write-Host ("{0,-25} {1,-12} {2,-20} {3}" -f "NAME", "SIZE", "DATE", "SHA256")
    Write-Host ("{0,-25} {1,-12} {2,-20} {3}" -f "----", "----", "----", "------")

    $files = Get-ChildItem $backupDir -File -Force | Where-Object { -not $_.Name.StartsWith('.') }
    foreach ($file in $files) {
        $size = if ($file.Length -gt 1MB) { "{0:N1} MB" -f ($file.Length / 1MB) }
               elseif ($file.Length -gt 1KB) { "{0:N1} KB" -f ($file.Length / 1KB) }
               else { "$($file.Length) B" }
        $date = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")

        $manifest = Join-Path $backupDir ".$($file.Name).sha256"
        $shaStatus = if (Test-Path $manifest) {
            try {
                $stored = (Get-Content $manifest).Split(' ')[0].Trim()
                $current = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
                if ($stored -eq $current) { "PASS" } else { "FAIL" }
            } catch { "ERR" }
        } else { "-" }

        Write-Host ("{0,-25} {1,-12} {2,-20} {3}" -f $file.Name, $size, $date, $shaStatus)
    }
}

# ── Handler ──

function Invoke-CcdcBackup {
    param(
        [string]$Command,
        [string[]]$CmdArgs
    )

    if ($global:CCDC_HELP -and -not $Command) {
        Show-CcdcBackupUsage
        return
    }

    # Ensure backup dir exists
    if (-not (Test-Path $global:CCDC_BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $global:CCDC_BACKUP_DIR -Force | Out-Null
    }

    switch ($Command) {
        'etc' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup etc"; Write-Host "Export registry hives"; return }
            Invoke-CcdcBackupEtc -ExtraArgs $CmdArgs
        }
        { $_ -in 'binaries','bin' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup binaries"; Write-Host "Backup Defender and firewall DLLs"; return }
            Invoke-CcdcBackupBinaries -ExtraArgs $CmdArgs
        }
        'web' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup web"; Write-Host "Backup IIS wwwroot"; return }
            Invoke-CcdcBackupWeb -ExtraArgs $CmdArgs
        }
        { $_ -in 'services','svc' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup services"; Write-Host "Save service list to CSV"; return }
            Invoke-CcdcBackupServices -ExtraArgs $CmdArgs
        }
        'ip' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup ip"; Write-Host "Save IP addresses and routes"; return }
            Invoke-CcdcBackupIp -ExtraArgs $CmdArgs
        }
        'ports' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup ports"; Write-Host "Save listening ports"; return }
            Invoke-CcdcBackupPorts -ExtraArgs $CmdArgs
        }
        'db' {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup db"; Write-Host "Backup SQL Server databases"; return }
            Invoke-CcdcBackupDb -ExtraArgs $CmdArgs
        }
        { $_ -in 'full','all' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup full"; Write-Host "Run all backup commands in sequence"; return }
            Invoke-CcdcBackupFull -ExtraArgs $CmdArgs
        }
        'restore' {
            if ($global:CCDC_HELP) { Write-Host 'Usage: ccdc backup restore <archive-path>'; Write-Host 'Restore a specific backup by path'; return }
            Invoke-CcdcBackupRestore -ExtraArgs $CmdArgs
        }
        { $_ -in 'ls','list' } {
            if ($global:CCDC_HELP) { Write-Host "Usage: ccdc backup ls"; Write-Host "List all backups with sizes and integrity status"; return }
            Invoke-CcdcBackupList -ExtraArgs $CmdArgs
        }
        '' { Show-CcdcBackupUsage }
        default {
            Write-CcdcLog "Unknown backup command: $Command" -Level Error
            Show-CcdcBackupUsage
        }
    }
}

Export-ModuleMember -Function Invoke-CcdcBackup
