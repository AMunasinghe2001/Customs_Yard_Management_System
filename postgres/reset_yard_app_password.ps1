# ============================================================================
#  Reset the `yard_app` password, and nothing else.
#
#      .\postgres\reset_yard_app_password.ps1 -Target supabase `
#          -NewPassword 'SrYard#2026Customs'
#
#  ⚠️ WHY THIS EXISTS: a re-run of the role file left `yard_app` with an
#  UNKNOWN password. `postgres/91` did
#
#      alter role yard_app password '<pw>';
#      alter role yard_app nosuperuser nocreatedb nocreaterole ...;
#
#  and on Supabase the admin is CREATEROLE but NOT superuser, so the second
#  statement failed with `permission denied to alter role`. Both statements
#  were in one DO block, so the whole block rolled back -- including the
#  password change -- and the app was locked out of a database that had been
#  working. Both role files now set the password in its own statement and
#  tolerate the attribute re-assertion failing; this script is the repair
#  for a project already in that state.
#
#  It runs ONE statement as the project admin, so it cannot disturb anything
#  else on the way past.
# ============================================================================
param(
  [ValidateSet('supabase', 'local', 'backup', 'custom')]
  [string]$Target = 'custom',

  [string]$PgHost,
  [int]   $Port = 5432,
  [string]$Database,

  # The ADMIN to connect as. Not yard_app — that is the account being fixed.
  [string]$User,

  [Parameter(Mandatory = $true)]
  [string]$NewPassword
)

$ErrorActionPreference = 'Stop'

switch ($Target) {
  'supabase' {
    if (-not $PgHost)   { $PgHost   = 'aws-0-ap-south-1.pooler.supabase.com' }
    if (-not $Database) { $Database = 'postgres' }
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

$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $guess = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe',
                         'C:\pgsql-extract\pgsql\bin\psql.exe' `
           -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($guess) { $psql = $guess.FullName }
}
if (-not $psql) { Write-Host 'psql.exe not found.' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host "Server : $PgHost`:$Port"  -ForegroundColor Cyan
Write-Host "As     : $User"           -ForegroundColor Cyan
Write-Host ''

$sec = Read-Host "Password for $User" -AsSecureString
$env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

if ($PgHost -like '*supabase*') {
  $env:PGSSLMODE = 'verify-full'
  $ca = Join-Path (Get-Location) 'supabase-root-2021.crt'
  if (-not (Test-Path $ca)) {
    $ca = Join-Path (Get-Location) 'installer\certs\supabase-root-2021.crt'
  }
  if (-not (Test-Path $ca)) {
    Write-Host 'supabase-root-2021.crt not found.' -ForegroundColor Red; exit 1
  }
  $env:PGSSLROOTCERT = $ca
}
$env:PGCONNECT_TIMEOUT = '30'

# ⚠️ Written to a temp file rather than passed with -c, so the password never
# appears in the process command line or the shell history.
$tmp = [IO.Path]::GetTempFileName() + '.sql'
$sql = @"
do `$fix`$
begin
  if not exists (select 1 from pg_roles where rolname = 'yard_app') then
    raise exception 'there is no yard_app role here - run postgres/91 (or 66)';
  end if;
  execute format('alter role yard_app password %L', '$NewPassword');
  raise notice 'yard_app password reset';
end `$fix`$;

-- Prove the account is still the restricted one. A password reset that also
-- handed it BYPASSRLS would be worse than the lockout it is fixing.
do `$check`$
declare r record;
begin
  select rolsuper, rolbypassrls, rolcanlogin, rolinherit into r
    from pg_roles where rolname = 'yard_app';
  if r.rolsuper or r.rolbypassrls then
    raise exception 'yard_app can bypass RLS - the app will refuse to start';
  end if;
  if not r.rolcanlogin then raise exception 'yard_app cannot log in'; end if;
  if not r.rolinherit then raise exception 'yard_app must INHERIT'; end if;
  raise notice 'PASS: login, inherit, and subject to RLS';
end `$check`$;
"@
# No BOM: PowerShell 5.1's `Set-Content -Encoding utf8` writes one, and psql
# reads those bytes as part of the first token.
[IO.File]::WriteAllText($tmp, $sql, [Text.UTF8Encoding]::new($false))

$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$errFile = [IO.Path]::GetTempFileName()
& $psql -h $PgHost -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -f $tmp 2>$errFile | Out-Null
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
$stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { '' }
Remove-Item $tmp, $errFile -ErrorAction SilentlyContinue
Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue

($stderr -split "`r?`n" | Where-Object { $_ -match 'NOTICE|ERROR' }) |
  ForEach-Object { Write-Host "  $_" }

Write-Host ''
if ($code -eq 0) {
  Write-Host 'Done. Put the SAME password in .env:' -ForegroundColor Green
  Write-Host '    PG_PASSWORD__supabase="<the password>"'
  Write-Host '  (quote it if it contains #, or dotenv drops the whole line)' `
             -ForegroundColor DarkGray
} else {
  Write-Host 'Failed - see the message above.' -ForegroundColor Red
}
Write-Host ''
