# ============================================================================
#  Bring the LOCAL and BACKUP databases up to `sr_auth`, so every profile in
#  .env works again.
#
#      .\postgres\migrate_local_to_sr_auth.ps1 -YardAppPassword '<the one in .env>'
#
#  ⚠️ WHY THE APP SUDDENLY FAILED ON local/backup:
#
#      Severity.error 3F000: schema "sr_auth" does not exist
#
#  Migration 048 renamed our `auth` schema to `sr_auth`, and the Dart code
#  now asks for `sr_auth` everywhere. That rename was only ever applied to
#  the Supabase project, so Supabase works and the two local databases --
#  which still have the old `auth` -- do not. Nothing is broken in them;
#  they are simply one migration behind.
#
#  ⚠️ THE RENAME ALONE IS NOT ENOUGH. `alter schema ... rename` does not
#  reach inside function bodies, and 48 of them still name the old schema,
#  so the first login would fail with `schema "auth" does not exist`. The
#  definitions have to be re-applied from the (already renamed) .sql files,
#  which is exactly what install_all.ps1 does. Hence: 048, then install.
#  048's own verification refuses to pass while any body still names `auth`.
#
#  Safe to re-run. 048 skips a database that is already on sr_auth, and
#  refuses outright to touch a Supabase-owned `auth`.
# ============================================================================
param(
  # The password the app signs in with, from PG_PASSWORD__local in .env.
  # local and backup share it.
  [Parameter(Mandatory = $true)]
  [string]$YardAppPassword,

  # Which databases to do. Both, by default.
  [ValidateSet('local', 'backup', 'both')]
  [string]$Target = 'both',

  # The admin to connect as while migrating. NOT yard_app: renaming a
  # schema and replacing functions needs an owner.
  [string]$User = 'postgres'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$targets = @()
if ($Target -eq 'both') { $targets = @('local', 'backup') }
else                    { $targets = @($Target) }

$dbFor = @{
  'local'  = 'Customs_SR_DB'
  'backup' = 'Customs_SR_DB_backup_20260914_1543'
}

$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $guess = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe',
                         'C:\pgsql-extract\pgsql\bin\psql.exe' `
           -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($guess) { $psql = $guess.FullName }
}
if (-not $psql) { Write-Host 'psql.exe not found.' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host "Migrating: $($targets -join ', ')" -ForegroundColor Cyan
Write-Host ''

# ⚠️ CLEAR ANY INHERITED TLS SETTING. This script only ever talks to
# localhost, but PGSSLMODE is an ENVIRONMENT variable: if this window ran
# install_all.ps1 against Supabase earlier, `verify-full` is still set, and
# a local PostgreSQL built without SSL refuses every connection with
#
#     server does not support SSL, but SSL was required
#
# which looks like a broken server rather than a leftover variable.
Remove-Item Env:PGSSLMODE     -ErrorAction SilentlyContinue
Remove-Item Env:PGSSLROOTCERT -ErrorAction SilentlyContinue

$sec = Read-Host "PostgreSQL password for '$User'" -AsSecureString
$adminPw = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$env:PGPASSWORD = $adminPw

foreach ($t in $targets) {
  $db = $dbFor[$t]
  Write-Host ''
  Write-Host ('=' * 74) -ForegroundColor DarkGray
  Write-Host "  $t  ->  $db" -ForegroundColor Cyan
  Write-Host ('=' * 74) -ForegroundColor DarkGray

  # ⚠️ Re-set every time round: install_all.ps1 clears PGPASSWORD
  # when it finishes, so the second database would otherwise be prompted
  # for -- or fail outright.
  $env:PGPASSWORD = $adminPw

  # ---- Step 1: the rename -------------------------------------------------
  Write-Host ''
  Write-Host '  [1/2] migrations/048 - auth becomes sr_auth' -ForegroundColor Yellow

  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $errFile = [IO.Path]::GetTempFileName()
  & $psql -h localhost -p 5432 -U $User -d $db -v ON_ERROR_STOP=1 `
      -f (Join-Path $root 'migrations/048_the_auth_schema_becomes_sr_auth.sql') `
      2>$errFile | Out-Null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev

  $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { '' }
  Remove-Item $errFile -ErrorAction SilentlyContinue
  ($stderr -split "`r?`n" | Where-Object { $_ -match 'NOTICE|ERROR' }) |
    ForEach-Object { Write-Host "        $_" }

  if ($code -ne 0) {
    Write-Host ''
    Write-Host "  FAILED on $db - stopping before the install step." -ForegroundColor Red
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    exit 1
  }

  # ---- Step 2: re-apply every definition ----------------------------------
  #
  # ⚠️ This is the half that is easy to skip and must not be. The
  # rename moved the schema; this rewrites the 48 function bodies that
  # still say `auth.` inside their source.
  Write-Host ''
  Write-Host '  [2/2] install_all.ps1 - re-applying definitions' -ForegroundColor Yellow

  & (Join-Path $PSScriptRoot 'install_all.ps1') `
      -Target $t -YardAppPassword $YardAppPassword
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  install_all.ps1 reported a problem on $db." -ForegroundColor Red
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    exit 1
  }
}

Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('=' * 74) -ForegroundColor DarkGray
Write-Host '  Done. Switch PG_PROFILE in .env and the app should start on' -ForegroundColor Green
Write-Host '  any of local / backup / supabase.' -ForegroundColor Green
Write-Host ('=' * 74) -ForegroundColor DarkGray
Write-Host ''
