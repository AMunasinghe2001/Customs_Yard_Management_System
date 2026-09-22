<#
.SYNOPSIS
  Build a release and the two update feeds, ready to upload to Supabase.

.DESCRIPTION
  One command from source to publishable files:

    1. flutter build windows --release, with the update URLs compiled in
    2. Inno Setup  -> installer\output\SLCustoms-SR-Setup-<version>.exe
    3. the feeds   -> installer\output\appcast.xml   (WinSparkle)
                      installer\output\latest.json   (the in-app banner)

  It does NOT bump the version. `tool\release.ps1 -Version x.y.z` does that,
  across pubspec.yaml, installer\setup.iss and lib\core\update_check.dart at
  once; run it first when the version is changing.

  ⚠️ TWO UPDATE PATHS, TWO FEEDS. The app carries both and they are
  independent:

    lib\core\update_check.dart   reads JSON, shows the in-app strip
                                 (widgets\update_banner.dart)
    lib\core\app_updater.dart    reads appcast.xml, drives WinSparkle's
                                 own download-and-install prompt

  Publishing both files keeps them agreeing. Publishing only one leaves half
  the officers on a version the other half is not offered.

  ⚠️ WHY SUPABASE AND NOT GITHUB. update_check.dart defaults to the GitHub
  Releases API for this repo, but the repo is PRIVATE -- the API answers 404
  to an officer's PC, so that path can never have shown anybody an update.
  Supabase Storage serves the same JSON publicly over https.

.PARAMETER Notes
  One line shown in the update prompt. Officers read it.

.PARAMETER NoUpdateFeed
  Build with update checking OFF. Correct for a one-off or hand-installed
  build; the app then never contacts anything.

.PARAMETER SkipFlutter
  Reuse the existing build\...\Release output. For rebuilding just the
  installer or the feeds.

.EXAMPLE
  .\tool\publish_release.ps1 -Notes "Fixes the ICT OTP resend"

.EXAMPLE
  .\tool\release.ps1 -Version 1.3.0
  .\tool\publish_release.ps1 -Notes "Adds rates and taxes to the ICT portal"
#>
param(
  [string]$Notes = '',

  # The Supabase `yard_app` password, baked into this build so an officer
  # can install and sign in with no file to edit.
  #
  # ⚠️ NEVER COMMITTED, and never written into a source file. It is
  # compiled into the binary and into the .env the installer writes, both of
  # which ship -- so it is only as secret as the installer is. Left out, the
  # build carries no credential and the officer supplies a .env, as before.
  [string]$DbPassword = '',
  [switch]$NoUpdateFeed,
  [switch]$SkipFlutter
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$BucketBase = 'https://knqpwufqpcoevjaxuihp.supabase.co/storage/v1/object/public/updates'
$FeedUrl     = "$BucketBase/appcast.xml"
$ManifestUrl = "$BucketBase/latest.json"

function Step($n, $text) {
  Write-Host ''
  Write-Host ('=' * 74) -ForegroundColor DarkGray
  Write-Host ("  [$n/3] $text") -ForegroundColor Cyan
  Write-Host ('=' * 74) -ForegroundColor DarkGray
}

# ── The three version strings must agree, checked BEFORE the long build ───
#
# ⚠️ A drift here is invisible until it misbehaves in the worst way: an app
# whose kAppVersion trails the published one offers the same update forever;
# one that leads it never offers anything. tool\release.ps1 writes all three
# from a single argument -- this only verifies.
$pubspec = Get-Content 'pubspec.yaml' -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  throw 'pubspec.yaml has no "version: X.Y.Z+N" line.'
}
$version = $Matches[1]
$build   = $Matches[2]

$iss = Get-Content 'installer\setup.iss' -Raw
if ($iss -notmatch '(?m)^#define\s+AppVersion\s+"([^"]+)"') {
  throw 'installer\setup.iss has no "#define AppVersion".'
}
$issVersion = $Matches[1]

$uc = Get-Content 'lib\core\update_check.dart' -Raw
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

Write-Host ''
Write-Host "Version : $version (build $build)" -ForegroundColor Green
if ($NoUpdateFeed) {
  Write-Host 'Updates : OFF for this build' -ForegroundColor Yellow
} else {
  Write-Host "Feeds   : $BucketBase/{appcast.xml, latest.json}" -ForegroundColor Green
}

# ── 1. The app ────────────────────────────────────────────────────────────
if ($SkipFlutter) {
  Write-Host ''
  Write-Host '  [1/3] flutter build ... SKIPPED (-SkipFlutter)' -ForegroundColor Yellow
} else {
  Step 1 'flutter build windows --release'

  # ⚠️ Compiled IN, not read from .env at runtime. These URLs decide which
  # .exe the app downloads and RUNS as administrator, so they must not be
  # changeable by a file sitting next to the app.
  $a = @('build', 'windows', '--release')
  if (-not $NoUpdateFeed) {
    $a += "--dart-define=UPDATE_FEED_URL=$FeedUrl"
    $a += "--dart-define=UPDATE_MANIFEST_URL=$ManifestUrl"
  }
  if ($DbPassword) {
    $a += "--dart-define=PG_CLOUD_PASSWORD=$DbPassword"
  }
  & flutter @a
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

if (-not (Test-Path 'build\windows\x64\runner\Release\cus_yard_management.exe')) {
  throw 'the built app is not in build\windows\x64\runner\Release'
}

# ── 2. The installer ──────────────────────────────────────────────────────
Step 2 'Inno Setup - the installer'

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

$isccArgs = @()
if ($DbPassword) {
  # ⚠️ Quoted as ONE argument. An office password containing `#` or a
  # space would otherwise be split, and ISCC reports it as "You may not
  # specify more than one script filename" -- which says nothing about the
  # password. Measured with a `#` in it.
  $isccArgs += "/DDbPassword=$DbPassword"
}
$isccArgs += 'installer\setup.iss'

& $iscc @isccArgs
if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }

$setupExe = "installer\output\SLCustoms-SR-Setup-$version.exe"
if (-not (Test-Path $setupExe)) { throw "installer not found at $setupExe" }

# ── 3. The feeds ──────────────────────────────────────────────────────────
if ($NoUpdateFeed) {
  Write-Host ''
  Write-Host '  [3/3] feeds SKIPPED - this build never checks for updates.' -ForegroundColor Yellow
  Write-Host ''
  Write-Host "  $setupExe" -ForegroundColor Green
  Write-Host ''
  exit 0
}

Step 3 'appcast.xml + latest.json'

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) {
  Write-Host 'python not found - the installer built, but the feeds did not.' -ForegroundColor Red
  Write-Host 'Generate them with:  python tools\generate_appcast.py'
  exit 1
}

$g = @('tools\generate_appcast.py')
if ($Notes) { $g += @('--notes', $Notes) }
& $python @g
if ($LASTEXITCODE -ne 0) { throw 'appcast generation failed' }

# ── How to publish ────────────────────────────────────────────────────────
$mb = [math]::Round((Get-Item $setupExe).Length / 1MB, 1)

Write-Host ''
Write-Host ('=' * 74) -ForegroundColor DarkGray
Write-Host '  DONE' -ForegroundColor Green
Write-Host ('=' * 74) -ForegroundColor DarkGray
Write-Host ''
Write-Host "  SLCustoms-SR-Setup-$version.exe   ($mb MB)"
Write-Host '  appcast.xml'
Write-Host '  latest.json'
Write-Host ''
Write-Host '  all three in installer\output\' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  UPLOAD to Supabase -> Storage -> updates' -ForegroundColor Cyan
Write-Host ''
Write-Host '    1. the .exe        FIRST' -ForegroundColor Yellow
Write-Host '    2. appcast.xml     (overwrite)'
Write-Host '    3. latest.json     (overwrite)'
Write-Host ''
Write-Host '  ORDER MATTERS. The moment a feed names a new version, every' -ForegroundColor Yellow
Write-Host '  running copy starts offering it. If the .exe is not uploaded' -ForegroundColor Yellow
Write-Host '  yet, each officer gets a failed download instead.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  First time only - create the bucket:'
Write-Host '    Supabase SQL Editor -> postgres\supabase_updates_bucket.sql'
Write-Host ''
Write-Host '  Then prove both are public (a private bucket answers 400):'
Write-Host "    curl.exe -I $ManifestUrl"
Write-Host "    curl.exe -I $FeedUrl"
Write-Host ''
