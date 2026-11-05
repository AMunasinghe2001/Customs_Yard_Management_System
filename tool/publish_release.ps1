<#
.SYNOPSIS
  Build a release and the two update feeds for any yard deployment profile.

.DESCRIPTION
  One command from source to publishable files:
    1. Reads deployment profile from tool\deployment_profiles.json (e.g. gl1-office, gl2-office, cloud, etc.)
    2. flutter build windows --release, with the compiled-in database and update URLs
    3. Inno Setup  -> installer\output\SLCustoms-SR-Setup-<version>-<suffix>.exe
    4. Feeds       -> installer\output\<channel>\appcast.xml   (WinSparkle)
                      installer\output\<channel>\latest.json    (In-app banner)

  Supports automated GitHub Releases & gh-pages feed URLs out of the box when -UseGitHubUpdates is specified.

.PARAMETER Deployment
  The deployment profile key defined in tool\deployment_profiles.json (e.g. 'cloud', 'gl1-office', 'gl2-office', 'gl3-office', 'rct-office').
  Or provide a custom name and specify -OfficeHost.

.PARAMETER DbPassword
  The yard_app / postgres database password. Required.

.PARAMETER GmailPassword
  The Gmail App Password that sends officer sign-in verification OTPs.

.PARAMETER UseGitHubUpdates
  Automatically construct public GitHub Pages feeds and GitHub Release artifact download URLs
  based on repository settings in deployment_profiles.json.

.PARAMETER Notes
  Release notes displayed in the update banner and WinSparkle dialog.

.PARAMETER SkipFlutter
  Skip Flutter compilation and reuse existing Release build output (for packaging installer/feeds only).

.PARAMETER NoUpdateFeed
  Disable update checks completely for this build.

.EXAMPLE
  # Build GL1 office release using GitHub Releases & gh-pages feeds:
  .\tool\publish_release.ps1 -Deployment gl1-office -DbPassword 'secret' -GmailPassword 'app-pw' -UseGitHubUpdates -Notes "GL1 update"

.EXAMPLE
  # Build GL2 office release with custom host override:
  .\tool\publish_release.ps1 -Deployment gl2-office -OfficeHost 10.10.72.39 -DbPassword 'secret' -GmailPassword 'app-pw' -UseGitHubUpdates
#>
param(
  [string]$Notes = '',

  [string]$Deployment = 'cloud',

  # Optional overrides for database connection
  [string]$OfficeHost = '',
  [int]$OfficePort = 0,
  [string]$OfficeDatabase = '',
  [string]$OfficeUser = '',

  # Secrets (never committed)
  [string]$DbPassword = '',
  [string]$GmailPassword = '',

  # GitHub Updates automation
  [switch]$UseGitHubUpdates,
  [string]$GitHubOwner = '',
  [string]$GitHubRepo = '',

  # Manual override for update URLs
  [string]$UpdateFeedUrl = '',
  [string]$UpdateManifestUrl = '',
  [string]$UpdateArtifactBaseUrl = '',
  [switch]$NoUpdateFeed,
  [switch]$SkipFlutter
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# ── Load Deployment Profiles ──────────────────────────────────────────────────
$profilesFile = Join-Path $PSScriptRoot 'deployment_profiles.json'
if (-not (Test-Path $profilesFile)) {
  throw "Profiles configuration file not found at $profilesFile"
}
$config = Get-Content $profilesFile -Raw -Encoding UTF8 | ConvertFrom-Json

$depKey = $Deployment.ToLower().Trim()
$profile = $config.profiles.$depKey

if (-not $profile) {
  # Fallback for dynamic/custom yard profile names like 'gl4-office'
  Write-Host "Notice: Deployment '$Deployment' not predefined in deployment_profiles.json. Using dynamic template." -ForegroundColor Yellow
  $yardTag = ($depKey -replace '-office$', '').ToUpper()
  $profile = [PSCustomObject]@{
    name          = "$yardTag Yard Office Server"
    profileType   = 'office'
    dbHost        = if ($OfficeHost) { $OfficeHost } else { '127.0.0.1' }
    dbPort        = if ($OfficePort -gt 0) { $OfficePort } else { 5432 }
    dbName        = if ($OfficeDatabase) { $OfficeDatabase } else { 'Customs_SR_DB' }
    dbUser        = if ($OfficeUser) { $OfficeUser } else { 'yard_app' }
    dbSsl         = 'true'
    dbSslVerify   = 'false'
    dbRootCert    = ''
    setupSuffix   = "$yardTag-Office"
    feedChannel   = $depKey
    tagPrefix     = "$depKey-v"
  }
}

# Apply explicit overrides if supplied via CLI
$dbProfile   = $profile.profileType
$dbHost      = if ($OfficeHost) { $OfficeHost } else { $profile.dbHost }
$dbPort      = if ($OfficePort -gt 0) { $OfficePort } else { $profile.dbPort }
$dbName      = if ($OfficeDatabase) { $OfficeDatabase } else { $profile.dbName }
$dbUser      = if ($OfficeUser) { $OfficeUser } else { $profile.dbUser }
$dbSsl       = $profile.dbSsl
$dbSslVerify = $profile.dbSslVerify
$dbRootCert  = $profile.dbRootCert
$setupSuffix = $profile.setupSuffix
$feedChannel = $profile.feedChannel
$tagPrefix   = if ($profile.tagPrefix) { $profile.tagPrefix } else { 'v' }

# Read default passwords from .env if not explicitly passed
if (-not $DbPassword -and (Test-Path '.env')) {
  $envContent = Get-Content '.env' -Raw
  if ($depKey -eq 'gl1-office') {
    if ($envContent -match '(?m)^PG_PASSWORD__gl1=(.*)$') {
      $DbPassword = $Matches[1].Trim().Trim('"').Trim("'")
    } elseif ($envContent -match '(?m)^PG_PASSWORD__office=(.*)$') {
      $DbPassword = $Matches[1].Trim().Trim('"').Trim("'")
    }
  } elseif ($depKey -eq 'gl2-office') {
    if ($envContent -match '(?m)^PG_PASSWORD__gl2=(.*)$') {
      $candidate = $Matches[1].Trim().Trim('"').Trim("'")
      if ($candidate -and $candidate -ne 'CHANGE_ME_GL2_PASSWORD') {
        $DbPassword = $candidate
      }
    }
    if (-not $DbPassword -and $envContent -match '(?m)^PG_PASSWORD__office=(.*)$') {
      $DbPassword = $Matches[1].Trim().Trim('"').Trim("'")
    }
  } elseif ($depKey -eq 'cloud') {
    if ($envContent -match '(?m)^PG_PASSWORD__supabase=(.*)$') {
      $DbPassword = $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
}

if (-not $GmailPassword -and (Test-Path '.env')) {
  $envContent = Get-Content '.env' -Raw
  if ($envContent -match '(?m)^GMAIL_APP_PASSWORD=(.*)$') {
    $GmailPassword = $Matches[1].Trim().Trim('"').Trim("'")
  }
}

if (-not $DbPassword) {
  throw "-DbPassword is required for Deployment '$Deployment'."
}

# ── Read Versions ─────────────────────────────────────────────────────────────
$pubspec = Get-Content 'pubspec.yaml' -Raw -Encoding UTF8
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  throw 'pubspec.yaml has no "version: X.Y.Z+N" line.'
}
$version = $Matches[1]
$build   = $Matches[2]

$iss = Get-Content 'installer\setup.iss' -Raw -Encoding UTF8
if ($iss -notmatch '(?m)^#define\s+AppVersion\s+"([^"]+)"') {
  throw 'installer\setup.iss has no "#define AppVersion".'
}
$issVersion = $Matches[1]

$uc = Get-Content 'lib\core\update_check.dart' -Raw -Encoding UTF8
if ($uc -notmatch "defaultValue:\s*'(\d+\.\d+\.\d+)'") {
  throw 'lib\core\update_check.dart has no kAppVersion default.'
}
$dartVersion = $Matches[1]

if ($issVersion -ne $version -or $dartVersion -ne $version) {
  Write-Host ''
  Write-Host 'VERSION MISMATCH - nothing was built.' -ForegroundColor Red
  Write-Host ("    pubspec.yaml               {0}" -f $version)
  Write-Host ("    installer\setup.iss        {0}" -f $issVersion)
  Write-Host ("    lib\core\update_check.dart {0}" -f $dartVersion)
  Write-Host ''
  Write-Host ("Fix all three at once:  .\tool\release.ps1 -Version {0}" -f $version) -ForegroundColor Yellow
  exit 1
}

# ── Configure Update URLs (GitHub Pages vs Supabase Storage) ──────────────────
$ghOwner = if ($GitHubOwner) { $GitHubOwner } else { $config.github.owner }
$ghRepo  = if ($GitHubRepo) { $GitHubRepo } else { $config.github.repo }
$ghBranch = if ($config.github.ghPagesBranch) { $config.github.ghPagesBranch } else { 'gh-pages' }
$BucketBase = 'https://knqpwufqpcoevjaxuihp.supabase.co/storage/v1/object/public/updates'

if ($UseGitHubUpdates) {
  $channelFolder = if ($feedChannel) { "$feedChannel/" } else { '' }
  $ghReleaseTag = "$tagPrefix$version"
  
  if (-not $UpdateFeedUrl) {
    $UpdateFeedUrl = "https://raw.githubusercontent.com/$ghOwner/$ghRepo/$ghBranch/${channelFolder}appcast.xml"
  }
  if (-not $UpdateManifestUrl) {
    $UpdateManifestUrl = "https://raw.githubusercontent.com/$ghOwner/$ghRepo/$ghBranch/${channelFolder}latest.json"
  }
  if (-not $UpdateArtifactBaseUrl) {
    $UpdateArtifactBaseUrl = "https://github.com/$ghOwner/$ghRepo/releases/download/$ghReleaseTag"
  }
}

$FeedUrl = if ($UpdateFeedUrl) { $UpdateFeedUrl } else {
  "$BucketBase" + $(if ($feedChannel) { "/$feedChannel" } else { '' }) + '/appcast.xml'
}
$ManifestUrl = if ($UpdateManifestUrl) { $UpdateManifestUrl } else {
  "$BucketBase" + $(if ($feedChannel) { "/$feedChannel" } else { '' }) + '/latest.json'
}

function Step($n, $text) {
  Write-Host ''
  Write-Host ('=' * 74) -ForegroundColor DarkGray
  Write-Host ("  [$n/3] $text") -ForegroundColor Cyan
  Write-Host ('=' * 74) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host "Version    : $version (build $build)" -ForegroundColor Green
Write-Host "Deployment : $Deployment ($($profile.name))" -ForegroundColor Green
Write-Host "DB Target  : ${dbHost}:${dbPort}/${dbName} ($dbUser)" -ForegroundColor Gray
Write-Host "Suffix     : $setupSuffix" -ForegroundColor Gray
if ($NoUpdateFeed) {
  Write-Host 'Updates    : OFF for this build' -ForegroundColor Yellow
} else {
  Write-Host "Feed URL   : $FeedUrl" -ForegroundColor Green
  Write-Host "Manifest   : $ManifestUrl" -ForegroundColor Green
  if ($UpdateArtifactBaseUrl) {
    Write-Host "Artifact   : $UpdateArtifactBaseUrl" -ForegroundColor Green
  }
}

# ── 1. The app ────────────────────────────────────────────────────────────────
if ($SkipFlutter) {
  Write-Host ''
  Write-Host '  [1/3] flutter build ... SKIPPED (-SkipFlutter)' -ForegroundColor Yellow
} else {
  Step 1 "flutter build windows --release [$Deployment]"

  $symbolDir = Join-Path $root "build\symbols\$version+$build-$setupSuffix"
  New-Item -ItemType Directory -Force -Path $symbolDir | Out-Null

  $flutterCmd = (Get-Command flutter -ErrorAction SilentlyContinue).Source
  if (-not $flutterCmd) {
    if (Test-Path "C:\Users\user\flutter\bin\flutter.bat") {
      $flutterCmd = "C:\Users\user\flutter\bin\flutter.bat"
    } else {
      $flutterCmd = 'flutter'
    }
  }

  $a = @('build', 'windows', '--release',
         '--obfuscate', "--split-debug-info=$symbolDir")
  if (-not $NoUpdateFeed) {
    $a += "--dart-define=UPDATE_FEED_URL=$FeedUrl"
    $a += "--dart-define=UPDATE_MANIFEST_URL=$ManifestUrl"
  } else {
    $a += '--dart-define=UPDATE_FEED_URL='
    $a += '--dart-define=UPDATE_MANIFEST_URL='
  }
  if ($DbPassword) {
    $a += "--dart-define=PG_PASSWORD=$DbPassword"
  }
  $a += "--dart-define=PG_PROFILE=$dbProfile"
  $a += "--dart-define=PG_HOST=$dbHost"
  $a += "--dart-define=PG_PORT=$dbPort"
  $a += "--dart-define=PG_DATABASE=$dbName"
  $a += "--dart-define=PG_USER=$dbUser"
  $a += "--dart-define=PG_SSL=$dbSsl"
  $a += "--dart-define=PG_SSL_VERIFY=$dbSslVerify"
  $a += "--dart-define=PG_SSL_ROOT_CERT=$dbRootCert"
  if ($GmailPassword) {
    $a += "--dart-define=GMAIL_APP_PASSWORD=$GmailPassword"
  }

  & $flutterCmd @a
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

  $syms = Get-ChildItem $symbolDir -File -ErrorAction SilentlyContinue
  if (-not $syms) {
    throw "the build wrote no debug symbols to $symbolDir"
  }
  Write-Host ("  symbols -> {0}  ({1} file(s))" -f $symbolDir, $syms.Count) -ForegroundColor DarkGray
}

if (-not (Test-Path 'build\windows\x64\runner\Release\cus_yard_management.exe')) {
  throw 'the built app is not in build\windows\x64\runner\Release'
}

# ── 2. The installer ──────────────────────────────────────────────────────────
Step 2 "Inno Setup - SLCustoms-SR-Setup-$version-$setupSuffix.exe"

$iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
  foreach ($c in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
                   "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
    if (Test-Path $c) { $iscc = $c; break }
  }
}
if (-not $iscc) {
  throw 'ISCC.exe (Inno Setup 6) not found - https://jrsoftware.org/isdl.php'
}

# Compile to a clean staging directory to prevent antivirus/file locks on installer\output
$tempOutDir = Join-Path ([System.IO.Path]::GetTempPath()) "iscc_stage_$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tempOutDir | Out-Null

$isccArgs = @("/O$tempOutDir")
if ($DbPassword) {
  $isccArgs += "/DDbPassword=$DbPassword"
}
$isccArgs += "/DDbProfile=$dbProfile"
$isccArgs += "/DDbHost=$dbHost"
$isccArgs += "/DDbPort=$dbPort"
$isccArgs += "/DDbName=$dbName"
$isccArgs += "/DDbUser=$dbUser"
$isccArgs += "/DDbSsl=$dbSsl"
$isccArgs += "/DDbSslVerify=$dbSslVerify"
$isccArgs += "/DDbRootCert=$dbRootCert"
$isccArgs += "/DSetupSuffix=$setupSuffix"
if ($GmailPassword) {
  $isccArgs += "/DGmailPassword=$GmailPassword"
}
$isccArgs += 'installer\setup.iss'

& $iscc @isccArgs
if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }

$targetExeName = "SLCustoms-SR-Setup-$version-$setupSuffix.exe"
$stagedExe = Join-Path $tempOutDir $targetExeName
$setupExe = "installer\output\$targetExeName"

if (-not (Test-Path $stagedExe)) { throw "installer not found at $stagedExe" }
New-Item -ItemType Directory -Force -Path 'installer\output' | Out-Null
Copy-Item -Path $stagedExe -Destination $setupExe -Force
Remove-Item -Path $tempOutDir -Recurse -Force -ErrorAction SilentlyContinue

# ── 3. The feeds ──────────────────────────────────────────────────────────────
if ($NoUpdateFeed) {
  Write-Host ''
  Write-Host '  [3/3] feeds SKIPPED - this build never checks for updates.' -ForegroundColor Yellow
  Write-Host ''
  Write-Host "  Installer generated: $setupExe" -ForegroundColor Green
  exit 0
}

Step 3 "appcast.xml + latest.json (Channel: $(if ($feedChannel) { $feedChannel } else { 'cloud' }))"

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) {
  if (Test-Path "C:\Python314\python.exe") {
    $python = "C:\Python314\python.exe"
  }
}
if (-not $python) {
  Write-Host 'python not found - installer built, but feeds could not be generated.' -ForegroundColor Red
  exit 1
}

$g = @('tools\generate_appcast.py', '--exe', $setupExe)
if ($feedChannel) { $g += @('--channel', $feedChannel) }
if ($UpdateArtifactBaseUrl) { $g += @('--artifact-base-url', $UpdateArtifactBaseUrl) }
if ($Notes) { $g += @('--notes', $Notes) }
& $python @g
if ($LASTEXITCODE -ne 0) { throw 'appcast generation failed' }

# ── Publishing Summary ────────────────────────────────────────────────────────
$mb = [math]::Round((Get-Item $setupExe).Length / 1MB, 1)
$channelSubDir = if ($feedChannel) { "installer\output\$feedChannel" } else { 'installer\output' }

Write-Host ''
Write-Host ('=' * 74) -ForegroundColor DarkGray
Write-Host '  RELEASE PACKAGE COMPLETE' -ForegroundColor Green
Write-Host ('=' * 74) -ForegroundColor DarkGray
Write-Host ''
Write-Host "  Installer : $setupExe ($mb MB)" -ForegroundColor Green
Write-Host "  Feed Dir  : $channelSubDir" -ForegroundColor Green
Write-Host "  Channel   : $(if ($feedChannel) { $feedChannel } else { 'cloud' })" -ForegroundColor Green
Write-Host ''
Write-Host "Publishing Checklist:" -ForegroundColor Cyan
if ($UseGitHubUpdates) {
  Write-Host "  1. GitHub Release Tag  : $tagPrefix$version" -ForegroundColor Yellow
  Write-Host "     -> Upload Asset     : $setupExe"
  Write-Host "  2. GitHub Pages Branch : $ghBranch" -ForegroundColor Yellow
  Write-Host "     -> Commit & Push    : $channelSubDir\appcast.xml"
  Write-Host "     -> Commit & Push    : $channelSubDir\latest.json"
} else {
  Write-Host "  1. Upload installer to target release host." -ForegroundColor Yellow
  Write-Host "  2. Overwrite appcast.xml & latest.json in storage channel ($channelSubDir)." -ForegroundColor Yellow
}
Write-Host ''
