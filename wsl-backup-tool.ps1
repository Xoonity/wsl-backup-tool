#Requires -Version 5.1
<#
.SYNOPSIS
    Advanced WSL2 Backup Tool by Xoonity.
.DESCRIPTION
    Exports all WSL distributions to .tar archives with logging,
    error handling, backup rotation, and prerequisite checks.
    Developed by the Engineering Team at Cosmo-Edge.com.

    Full Documentation (EN): https://cosmo-edge.com/expert-windows-11-wsl2-vhdx-backup
    Tutoriel Complet (FR): https://cosmo-games.com/sauvegarde-expert-windows-11-wsl2-vhdx
.NOTES
    Version: 1.1 (2026 Update)
    License: MIT License - Copyright (c) 2026 Xoonity
.PARAMETER BackupPath
    Target folder for backups (NAS, external drive, etc.)
.PARAMETER RetentionDays
    Number of days to keep archives (default: 7)
.PARAMETER Compress
    Compress archives to .tar.gz using gzip (slower but saves space)
.EXAMPLE
    .\wsl-backup.ps1 -BackupPath "F:\Backups\WSL" -RetentionDays 14
#>

param(
    [string]$BackupPath   = "F:\Backup\WSL",
    [int]$RetentionDays   = 7,
    [switch]$Compress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
$date    = Get-Date -Format "yyyy-MM-dd"
$logFile = Join-Path $BackupPath "backup_$date.log"

# ─────────────────────────────────────────────
# FUNCTIONS
# ─────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{ INFO = "White"; SUCCESS = "Green"; WARNING = "Yellow"; ERROR = "Red"; HEADER = "Cyan" }
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Write-Host $line -ForegroundColor $colors[$Level]
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N2} KB" -f ($Bytes / 1KB)
}

function Test-Prerequisites {
    # Check drive availability
    $drive = Split-Path -Qualifier $BackupPath
    if (!(Test-Path $drive)) {
        Write-Log "Drive $drive is not accessible. Check your backup destination." "ERROR"
        exit 1
    }

    # Check available disk space (warn if < 10 GB)
    $freeSpace = (Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue).Free
    if ($null -ne $freeSpace -and $freeSpace -lt 10GB) {
        Write-Log ("Low disk space on {0} : {1} remaining." -f $drive, (Format-Size $freeSpace)) "WARNING"
    }

    # Check WSL availability
    try {
        $null = Get-Command wsl -ErrorAction Stop
    } catch {
        Write-Log "WSL command not found. Is WSL installed and accessible?" "ERROR"
        exit 1
    }

    # Check admin rights (recommended for wsl --shutdown)
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$isAdmin) {
        Write-Log "Script is not running as Administrator. wsl --shutdown may fail." "WARNING"
    }
}

function Get-WslDistributions {
    # Force UTF-8 encoding to avoid UTF-16 LE artifacts from wsl --list
    $prevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        $raw = wsl --list --quiet 2>&1
    } finally {
        [Console]::OutputEncoding = $prevEncoding
    }

    $distros = $raw | ForEach-Object {
        # Strip null characters and BOM-like artifacts
        $_ -replace '\x00', '' -replace '^\xEF\xBB\xBF', ''
    } | Where-Object { $_.Trim() -ne "" }

    if (!$distros -or $distros.Count -eq 0) {
        Write-Log "No WSL distribution found." "ERROR"
        exit 1
    }

    return $distros
}

function Remove-OldBackups {
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    
    # Le @(...) force PowerShell à traiter le résultat comme un tableau (Array)
    $oldFiles = @(Get-ChildItem $BackupPath -Include "*.tar","*.tar.gz" -Recurse |
        Where-Object { $_.LastWriteTime -lt $cutoff })

    # Désormais .Count fonctionnera même avec un seul fichier trouvé
    if ($oldFiles.Count -eq 0) {
        Write-Log "No archives older than $RetentionDays days to delete." "INFO"
        return
    }

    foreach ($file in $oldFiles) {
        try {
            Remove-Item $file.FullName -Force
            Write-Log "Deleted old archive: $($file.Name)" "INFO"
        } catch {
            Write-Log "Could not delete: $($file.Name) — $_" "WARNING"
        }
    }
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

# Create backup folder if needed
if (!(Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Force -Path $BackupPath | Out-Null
}

# Initialize log file
$null = New-Item -ItemType File -Path $logFile -Force

Write-Log "══════════════════════════════════════" "HEADER"
Write-Log "  WSL BACKUP — $date" "HEADER"
Write-Log "  Destination : $BackupPath" "HEADER"
Write-Log "  Retention   : $RetentionDays days" "HEADER"
Write-Log "══════════════════════════════════════" "HEADER"

# Prerequisite checks
Test-Prerequisites

# Rotate old backups before starting
Write-Log "Checking archives to rotate..." "INFO"
Remove-OldBackups

# Shutdown WSL to ensure filesystem consistency
Write-Log "Shutting down WSL instances (ensures ext4 consistency)..." "INFO"
wsl --shutdown
Start-Sleep -Seconds 3   # Allow time for complete shutdown

# Retrieve distributions
$distros = Get-WslDistributions
Write-Log "$($distros.Count) distribution(s) found : $($distros -join ', ')" "INFO"

# Backup counters
$successCount = 0
$failCount    = 0
$totalStart   = Get-Date

foreach ($distro in $distros) {
    $cleanDistro = $distro.Trim()
    $extension   = if ($Compress) { "tar.gz" } else { "tar" }
    $fileName    = "${cleanDistro}_${date}.${extension}"
    $fullPath    = Join-Path $BackupPath $fileName

    Write-Log "──────────────────────────────────────" "HEADER"
    Write-Log "Exporting : $cleanDistro → $fileName" "INFO"

    $startTime = Get-Date

    try {
        if ($Compress) {
            # Export via pipe to gzip (requires gzip in PATH or WSL)
            wsl --export $cleanDistro - | & gzip -c | Set-Content $fullPath -AsByteStream
        } else {
            wsl --export $cleanDistro $fullPath
        }

        # Validate output
        if (!(Test-Path $fullPath)) {
            throw "Archive not found after export."
        }

        $fileSize = (Get-Item $fullPath).Length
        if ($fileSize -eq 0) {
            throw "Archive created but is empty (0 bytes)."
        }

        $elapsed = (Get-Date) - $startTime
        Write-Log ("✔ Success : {0} | Size : {1} | Duration : {2:mm\:ss}" -f `
            $fileName, (Format-Size $fileSize), $elapsed) "SUCCESS"

        $successCount++

    } catch {
        Write-Log "✖ Error exporting $cleanDistro : $_" "ERROR"
        # Clean up partial file if it exists
        if (Test-Path $fullPath) { Remove-Item $fullPath -Force }
        $failCount++
    }
}

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
$totalElapsed = (Get-Date) - $totalStart

Write-Log "══════════════════════════════════════" "HEADER"
Write-Log "  BACKUP COMPLETE" "HEADER"
Write-Log ("  ✔ Success : {0} | ✖ Errors : {1}" -f $successCount, $failCount) "HEADER"
Write-Log ("  Total duration : {0:mm\:ss}" -f $totalElapsed) "HEADER"
Write-Log "  Log file : $logFile" "HEADER"
Write-Log "══════════════════════════════════════" "HEADER"

# Exit code reflects overall status
exit $failCount