<#
.SYNOPSIS
  Take a verified, compressed backup of Customs_SR_DB and retire old ones.

.DESCRIPTION
  A daily full backup in PostgreSQL's custom format (-Fc), which is what
  pg_restore needs to restore selectively and in parallel.

  ⚠️ A backup nobody has restored is a guess, not a backup. This script runs
  `pg_restore --list` over every file it writes: that reads the whole archive
  and fails on a truncated or corrupt one, which is the failure mode that
  otherwise stays invisible until the day it matters.

  Schedule it with Task Scheduler (see postgres/SECURITY.md for the exact
  command line). Exit code is non-zero on any failure, so the scheduler shows
  a failed run rather than a green tick over a missing file.

.PARAMETER Destination
  Where backups are written. Default: D:\Backups\Customs_SR_DB
  ⚠️ Point this at a DIFFERENT physical disk from the database, and copy it
  off-machine as well. A backup on the drive that fails is not a backup.

.PARAMETER RetentionDays
  Delete backups older than this. Default 30. Keep monthly archives longer -
  the audit trail retains 365 days, so a 30-day backup window cannot recover
  an audit question older than a month.

.EXAMPLE
  .\tool\backup_database.ps1
  .\tool\backup_database.ps1 -Destination E:\Backups -RetentionDays 90
#>
param(
    [string] $Destination   = 'D:\Backups\Customs_SR_DB',
    [int]    $RetentionDays = 30,
    [string] $PgHost        = 'localhost',
    [int]    $Port          = 5432,
    [string] $Database      = 'Customs_SR_DB',
    [string] $User          = 'postgres',
    # Skip the restore-readability check. Faster, and worth strictly less.
    [switch] $SkipVerify
)

$ErrorActionPreference = 'Stop'

# ⚠️ pg_dump is NOT on PATH on this machine — the server was unpacked to
# C:\pgsql-extract rather than installed — so calling it bare fails with
# "not recognized as the name of a cmdlet". A scheduled task hits the same
# thing, and its only symptom is a failed run nobody reads. Find the binaries
# instead of assuming.
function Resolve-PgTool([string] $name) {
    $onPath = Get-Command $name -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $candidates = @()
    $candidates += "C:\pgsql-extract\pgsql\bin\$name.exe"
    $candidates += Get-ChildItem 'C:\Program Files\PostgreSQL' -Directory -ErrorAction SilentlyContinue |
                   ForEach-Object { Join-Path $_.FullName "bin\$name.exe" }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    throw "$name not found. Add PostgreSQL's bin directory to PATH, or edit Resolve-PgTool in this script."
}

$pgDump    = Resolve-PgTool 'pg_dump'
$pgRestore = Resolve-PgTool 'pg_restore'

# PGPASSWORD is read from the environment by pg_dump. Set it in the scheduled
# task, or use a %APPDATA%\postgresql\pgpass.conf entry (better: it is not
# visible in the process environment).
if (-not $env:PGPASSWORD -and -not (Test-Path "$env:APPDATA\postgresql\pgpass.conf")) {
    Write-Host 'No PGPASSWORD and no pgpass.conf - pg_dump will prompt and the' -ForegroundColor Yellow
    Write-Host 'scheduled run will hang. See postgres/SECURITY.md.' -ForegroundColor Yellow
}

$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$outFile = Join-Path $Destination "Customs_SR_DB_$stamp.dump"

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

Write-Host "Backing up $Database -> $outFile"
$started = Get-Date

# -Fc  custom format: compressed, and restorable table-by-table
# -Z6  moderate compression; -Z9 costs far more CPU for a few percent
#
# ⚠️ No --verbose and no `2>&1`. pg_dump writes progress to STDERR, and in
# Windows PowerShell 5.1 redirecting a native command's stderr wraps each line
# in an ErrorRecord (NativeCommandError) — so a completely successful dump
# came back looking like a failure. Let stderr go to the console untouched and
# judge the run by $LASTEXITCODE, which is the only reliable signal here.
& $pgDump --host=$PgHost --port=$Port --username=$User --dbname=$Database `
          --format=custom --compress=6 --file=$outFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "BACKUP FAILED (pg_dump exit $LASTEXITCODE)" -ForegroundColor Red
    if (Test-Path $outFile) { Remove-Item $outFile -Force }   # no half files
    exit 1
}

$sizeMb = [math]::Round((Get-Item $outFile).Length / 1MB, 1)
$secs   = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
Write-Host "  wrote $sizeMb MB in ${secs}s"

# ── Verify ─────────────────────────────────────────────────────────────────
if (-not $SkipVerify) {
    Write-Host '  verifying the archive is readable...'
    $entries = (& $pgRestore --list $outFile)
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'VERIFY FAILED: the archive is not readable by pg_restore.' -ForegroundColor Red
        Write-Host 'Keeping the file for inspection, but treat this run as failed.' -ForegroundColor Red
        exit 1
    }
    $count = ($entries | Measure-Object -Line).Lines
    Write-Host "  archive lists $count objects - readable"

    # A dump that restores but is missing the audit trail is worse than none:
    # it would restore a system with no history and look successful.
    if (-not ($entries -match 'audit_logs')) {
        Write-Host 'VERIFY FAILED: audit_logs is not in the archive.' -ForegroundColor Red
        exit 1
    }
    Write-Host '  audit_logs present'
}

# ── Retention ──────────────────────────────────────────────────────────────
$cutoff = (Get-Date).AddDays(-$RetentionDays)
$old = Get-ChildItem $Destination -Filter 'Customs_SR_DB_*.dump' |
       Where-Object { $_.LastWriteTime -lt $cutoff }
if ($old) {
    # ⚠️ Never delete the old one before the new one is written AND verified.
    # This runs last for that reason.
    foreach ($f in $old) {
        Write-Host "  retiring $($f.Name)"
        Remove-Item $f.FullName -Force
    }
}

$kept = (Get-ChildItem $Destination -Filter 'Customs_SR_DB_*.dump').Count
Write-Host "Done. $kept backup(s) in $Destination (retention $RetentionDays days)."
