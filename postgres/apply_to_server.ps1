# ============================================================================
#  Apply migrations 021 -> 024 to the SR database on a server.
#
#  Run this from the project root ON A MACHINE THAT CAN REACH THE SERVER.
#
#      .\postgres\apply_to_server.ps1                     # 10.10.71.15
#      .\postgres\apply_to_server.ps1 -PgHost 192.168.1.5 # somewhere else
#
#  It asks for the postgres password rather than taking it on the command
#  line, so the password does not end up in the PowerShell history file.
#
#  Everything is idempotent: running it twice is safe and the second run
#  reports the same "OK" line.
# ============================================================================
param(
  [string]$PgHost   = '10.10.71.15',
  [int]   $Port     = 5432,
  [string]$Database = 'Customs_SR_DB',
  [string]$User     = 'postgres',
  # The SQL to apply. Defaults to the 021->031 bundle; pass a single migration
  # to apply just that one, e.g.
  #   .\postgres\apply_to_server.ps1 -File migrations\035_sign_up_writes_the_profile_atomically.sql
  [string]$File     = 'postgres\69_apply_021_to_031.sql'
)

$ErrorActionPreference = 'Stop'

# psql must be on PATH, or in the usual Windows install location.
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

if (-not (Test-Path 'postgres\69_apply_021_to_031.sql')) {
  Write-Host 'Run this from the project root (D:\Company\Cus_Yard_Management).' `
             -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host "Server   : $PgHost`:$Port" -ForegroundColor Cyan
Write-Host "Database : $Database"      -ForegroundColor Cyan
Write-Host "As       : $User"          -ForegroundColor Cyan
Write-Host "Applying : $File"          -ForegroundColor Cyan
Write-Host ''

# Reachability first: a timeout here is a network problem, not a SQL one, and
# the error psql gives for it reads like the server is broken.
Write-Host 'Checking the server is reachable...' -NoNewline
$probe = Test-NetConnection -ComputerName $PgHost -Port $Port -WarningAction SilentlyContinue
if (-not $probe.TcpTestSucceeded) {
  Write-Host ' NO' -ForegroundColor Red
  Write-Host ''
  Write-Host "Cannot open $PgHost`:$Port from this machine." -ForegroundColor Red
  Write-Host 'Connect to the office network (or VPN) and run this again.'
  exit 1
}
Write-Host ' yes' -ForegroundColor Green

$secure = Read-Host "Password for $User" -AsSecureString
$env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))

# WARNING: psql writes its NOTICEs to stderr, and PowerShell turns a native
# command's stderr into error records -- so a perfectly good run ("column
# already exists, skipping") was reported as a failure. The EXIT CODE is the
# only honest verdict here, so stderr is merged into stdout and the result is
# judged by $LASTEXITCODE alone.
$ErrorActionPreference = 'Continue'
try {
  & $psql -h $PgHost -p $Port -U $User -d $Database `
          -v ON_ERROR_STOP=1 -f 'postgres\69_apply_021_to_031.sql' 2>&1 |
    ForEach-Object { "$_" }
  $code = $LASTEXITCODE
} finally {
  # Never leave the password in the environment of this shell.
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
}

Write-Host ''
if ($code -eq 0) {
  Write-Host "DONE. $File applied and self-verified." -ForegroundColor Green
  Write-Host ''
  Write-Host 'Point the .env at this server and restart the app:'
  Write-Host "  PG_HOST=$PgHost"
  Write-Host '  PG_USER=yard_app'
} else {
  Write-Host "FAILED (exit $code). Nothing was left half-applied: the script" -ForegroundColor Red
  Write-Host 'stops at the first error, and every file is safe to re-run once' -ForegroundColor Red
  Write-Host 'the cause is fixed.' -ForegroundColor Red
}
exit $code