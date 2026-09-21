# ============================================================================
#  Build the whole SR database, in order, in one run.
#
#      .\postgres\install_all.ps1 -Target supabase
#      .\postgres\install_all.ps1 -Target local
#      .\postgres\install_all.ps1 -PgHost 10.10.71.15 -Database Customs_SR_DB
#
#  Running the ~90 files by hand in the right order is the thing that keeps
#  going wrong, so this does it: the four core files first, then every
#  numbered `postgres/` file, then every `migrations/` file, each in natural
#  numeric order.
#
#  ⚠️ VERIFY FAILURES ARE EXPECTED ON AN EMPTY DATABASE, and this script does
#  not stop for them. Many files end with a check written against the office
#  server's DATA -- "expected 228, got 11", "the page shows 369,383,700".
#  On a fresh database those cannot hold, and they say nothing about whether
#  the tables and views were created. Measured on a scratch database: 12
#  files report a failed verify, and the schema still comes out complete at
#  37 tables / 25 views, matching the live database exactly.
#
#  So: a file that reports an error still ran. What matters is the summary at
#  the end -- the object counts -- not the individual verify lines.
#
#  ⚠️ It does NOT create the login role. Run postgres/91 (Supabase) or
#  postgres/66 (office) afterwards, once the tables exist, so their
#  "grant on ALL tables" actually covers them.
# ============================================================================
param(
  # A named target, or leave it out and pass -PgHost/-Database yourself.
  [ValidateSet('supabase', 'local', 'backup', 'custom')]
  [string]$Target = 'custom',

  [string]$PgHost,
  [int]   $Port = 5432,
  [string]$Database,
  [string]$User,

  # Stop at the first error, including a data-driven verify. Off by default
  # for the reason in the header.
  [switch]$StopOnError,

  # Print what would run, and run nothing.
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ── Targets ────────────────────────────────────────────────────────────────
switch ($Target) {
  'supabase' {
    if (-not $PgHost)   { $PgHost   = 'aws-0-ap-south-1.pooler.supabase.com' }
    if (-not $Database) { $Database = 'postgres' }
    # ⚠️ The project ref is part of the username on the pooler, and the
    # SCHEMA LOAD must run as postgres -- yard_app cannot create tables.
    if (-not $User)     { $User     = 'postgres.knqpwufqpcoevjaxuihp' }
  }
  'local'  {
    if (-not $PgHost)   { $PgHost   = 'localhost' }
    if (-not $Database) { $Database = 'Customs_SR_DB' }
    if (-not $User)     { $User     = 'postgres' }
  }
  'backup' {
    if (-not $PgHost)   { $PgHost   = 'localhost' }
    if (-not $Database) { $Database = 'Customs_SR_DB_backup_20260914_1543' }
    if (-not $User)     { $User     = 'postgres' }
  }
}
if (-not $PgHost -or -not $Database -or -not $User) {
  Write-Host 'Give -Target, or all of -PgHost -Database -User.' -ForegroundColor Red
  exit 1
}

# ── psql ───────────────────────────────────────────────────────────────────
$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $guess = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe',
                         'C:\pgsql-extract\pgsql\bin\psql.exe' `
           -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($guess) { $psql = $guess.FullName }
}
if (-not $psql) {
  Write-Host 'Could not find psql.exe. Add PostgreSQL''s bin folder to PATH.' `
             -ForegroundColor Red
  exit 1
}

if (-not (Test-Path 'postgres\01_auth_and_session.sql')) {
  Write-Host 'Run this from the project root.' -ForegroundColor Red
  exit 1
}

# ── The order, as verified by rebuilding an empty database ─────────────────
#
# ⚠️ `Sort-Object` on the NUMBER, not the name. A plain string sort puts
# 10 before 2, which would run the views before the tables they read.
function Get-Ordered([string]$dir) {
  Get-ChildItem "$dir\*.sql" |
    Where-Object { $_.Name -notmatch '^(66|69|9[01])_' } |
    Sort-Object @{ Expression = {
      if ($_.Name -match '^(\d+)') { [int]$Matches[1] } else { 9999 } } },
      Name
}

$core = @(
  'postgres\01_auth_and_session.sql',  # auth.uid(), the grant-target roles
  'postgres\02_schema.sql',            # every table, policy and trigger
  'postgres\03_realtime.sql',          # NOTIFY triggers
  'postgres\04_auth.sql'               # sign_in / sign_up / change_password
)
# The numbered files after the core, then the migrations.
$rest = @(Get-Ordered 'postgres' | Where-Object {
            $core -notcontains "postgres\$($_.Name)" } |
          ForEach-Object { "postgres\$($_.Name)" })
$migs = @(Get-Ordered 'migrations' | ForEach-Object { "migrations\$($_.Name)" })
$files = $core + $rest + $migs

Write-Host ''
Write-Host "Server   : $PgHost`:$Port"  -ForegroundColor Cyan
Write-Host "Database : $Database"       -ForegroundColor Cyan
Write-Host "User     : $User"           -ForegroundColor Cyan
Write-Host "Files    : $($files.Count)" -ForegroundColor Cyan
Write-Host ''

if ($DryRun) {
  $i = 0
  foreach ($f in $files) { $i++; '{0,3}. {1}' -f $i, $f | Write-Host }
  exit 0
}

# ── Password ───────────────────────────────────────────────────────────────
# Asked for rather than taken on the command line, so it stays out of the
# PowerShell history file.
$sec = Read-Host "Password for $User" -AsSecureString
$env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

# ⚠️ Supabase's pooler is signed by its OWN root CA, which Windows does not
# trust. Without this psql fails the handshake and the message names TLS
# rather than the missing file.
if ($PgHost -like '*supabase*') {
  $env:PGSSLMODE = 'verify-full'
  $ca = Join-Path (Get-Location) 'supabase-root-2021.crt'
  if (-not (Test-Path $ca)) { $ca = Join-Path (Get-Location) 'installer\certs\supabase-root-2021.crt' }
  if (Test-Path $ca) {
    $env:PGSSLROOTCERT = $ca
    Write-Host "TLS      : verify-full against $([IO.Path]::GetFileName($ca))" -ForegroundColor Cyan
  } else {
    Write-Host 'supabase-root-2021.crt not found - TLS verification will fail.' -ForegroundColor Red
    exit 1
  }
}
$env:PGCONNECT_TIMEOUT = '30'

# ── Run ────────────────────────────────────────────────────────────────────
$ok = 0; $bad = @(); $i = 0
foreach ($f in $files) {
  $i++
  $label = '{0,3}/{1}  {2}' -f $i, $files.Count, (Split-Path $f -Leaf)
  Write-Host -NoNewline ($label.PadRight(72))

  $args = @('-h', $PgHost, '-p', $Port, '-U', $User, '-d', $Database,
            '-v', 'ON_ERROR_STOP=1', '-q', '-f', $f)

  # ⚠️ Redirect psql's stderr to a FILE, not through the pipeline.
  #
  # Windows PowerShell 5.1 wraps every stderr line from a native exe in an
  # ErrorRecord, so `2>&1 |` turns psql's ordinary NOTICEs ("column ...
  # already exists, skipping") into terminating NativeCommandErrors and the
  # run dies on the very first file. Measured: it stopped at 1/114 on a
  # NOTICE that is not even a warning.
  # ⚠️ And `$ErrorActionPreference` must be relaxed AROUND the call. With
  # it set to 'Stop' at script scope, PowerShell promotes the wrapped
  # NativeCommandError to terminating even when stderr goes to a file -- so
  # the redirect alone was not enough and the run still died at 1/114.
  $errFile = [IO.Path]::GetTempFileName()
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $stdout = (& $psql @args 2>$errFile | Out-String)
  $ErrorActionPreference = $prevEAP
  $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { '' }
  Remove-Item $errFile -ErrorAction SilentlyContinue
  $out = "$stdout`n$stderr"

  # ⚠️ Match psql's OWN error lines, not the word "ERROR" anywhere.
  #
  # PowerShell's wrapper text contains "NativeCommandError", so a bare
  # `-match 'ERROR'` flagged 93 of 114 files when only 12 had actually
  # failed -- burying the real ones. A psql error always looks like
  # `psql:<file>:<line>: ERROR:  ...`.
  $psqlErrors = @($out -split "`r?`n" | Where-Object { $_ -match ':\s*ERROR:' })

  if ($psqlErrors.Count -gt 0) {
    $bad += $f
    Write-Host 'verify/error' -ForegroundColor Yellow
    ($psqlErrors[0] -replace '^.*?:\s*ERROR:\s*', '      ').TrimEnd() |
      Write-Host -ForegroundColor DarkYellow
    if ($StopOnError) {
      Write-Host ''
      Write-Host "Stopped at $f" -ForegroundColor Red
      Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
      exit 1
    }
  } else {
    $ok++
    Write-Host 'ok' -ForegroundColor Green
  }
}

# ── What actually landed ───────────────────────────────────────────────────
#
# ⚠️ THIS is the result, not the per-file lines above. A data-driven verify
# failing on an empty database says nothing about the schema.
$q = @"
select (select count(*) from information_schema.tables
         where table_schema='public' and table_type='BASE TABLE')::text
       || ' tables, ' ||
       (select count(*) from information_schema.views
         where table_schema='public')::text || ' views, ' ||
       (select count(*) from pg_policies where schemaname='public')::text
       || ' policies'
"@
$ErrorActionPreference = 'Continue'
$counts = (& $psql -h $PgHost -p $Port -U $User -d $Database -At -c $q 2>$null | Out-String).Trim()

Write-Host ''
Write-Host '────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
Write-Host "Ran $($files.Count) files: $ok clean, $($bad.Count) reported an error."
Write-Host "Schema now: $counts" -ForegroundColor Cyan
Write-Host 'Expected  : 37 tables, 25 views, ~160 policies' -ForegroundColor DarkGray
Write-Host ''
if ($bad.Count -gt 0) {
  Write-Host 'Files that reported an error (mostly data-driven verifies):' -ForegroundColor Yellow
  $bad | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
  Write-Host ''
  Write-Host 'On a FRESH database this is normal - those checks compare row' -ForegroundColor DarkGray
  Write-Host 'counts against the office server. Judge by the counts above.'   -ForegroundColor DarkGray
  Write-Host ''
}
Write-Host 'NEXT:' -ForegroundColor Cyan
Write-Host '  1. Create the login role:'
Write-Host '       Supabase -> postgres\91_supabase_yard_app_role.sql'
Write-Host '       Office   -> postgres\66_yard_app_role.sql'
Write-Host '  2. Re-run postgres\90_supabase_readiness_check.sql (Supabase).'
Write-Host '  3. Create the first admin - see postgres\README.md.'
Write-Host ''

Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
