<#
.SYNOPSIS
  Cut a release: bump the version everywhere, build, and package the installer.

.DESCRIPTION
  The version number lives in THREE places, and the update notice only works
  when all three agree:

    pubspec.yaml            version: 1.2.0+3      (what Flutter stamps)
    installer/setup.iss     AppVersion "1.2.0"    (what Windows records)
    lib/core/update_check.dart  kAppVersion       (what the running app
                                                   compares against GitHub)

  Bumping them by hand is how they drift, and a drift here is invisible
  until it misbehaves in the worst way: if kAppVersion is left BEHIND the
  published tag, every branch is told to install an update they already have,
  forever. If it is left AHEAD, no branch is ever told about anything.

  This script writes all three from one argument, so they cannot disagree.

.PARAMETER Version
  The new version, e.g. 1.2.0

.EXAMPLE
  .\tool\release.ps1 -Version 1.2.0
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "Releasing $Version" -ForegroundColor Cyan

# ── Writing files without wrecking them ─────────────────────────────────────
#
# ⚠️ NOT Set-Content -Encoding utf8. In Windows PowerShell 5.1 that writes a
# BOM and re-encodes the file, which mangles every non-ASCII character already
# in it — the ⚠️ markers and box-drawing rules throughout setup.iss and the
# Dart sources came back as "â€”" mojibake the first time this ran, turning a
# version bump into a diff across the whole file.
#
# UTF8Encoding($false) writes the bytes as they are, with no BOM.
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Write-FileUtf8([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText((Resolve-Path $Path), $Text, $Utf8NoBom)
}


# ── 1. pubspec.yaml ─────────────────────────────────────────────────────────
# The build number after '+' must also rise: Windows compares the file version
# and two builds sharing one number are indistinguishable to the installer.
$pubspec = Get-Content 'pubspec.yaml' -Raw -Encoding UTF8
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  throw 'Could not find a "version: x.y.z+n" line in pubspec.yaml'
}
$build = [int]$Matches[2] + 1
# ⚠️ `[ \t]*` and not `\s*`. Under (?m), `\s` matches the newline too, so
# `\s*$` swallowed the blank line after the version and the bump showed up as
# a two-line diff instead of one.
$pubspec = $pubspec -replace '(?m)^version:[ \t]*\d+\.\d+\.\d+\+\d+[ \t]*$', "version: $Version+$build"
Write-FileUtf8 'pubspec.yaml' $pubspec
Write-Host "  pubspec.yaml      -> $Version+$build"

# ── 2. installer/setup.iss ──────────────────────────────────────────────────
$iss = Get-Content 'installer/setup.iss' -Raw -Encoding UTF8
if ($iss -notmatch '#define AppVersion\s+"[^"]+"') {
  throw 'Could not find #define AppVersion in installer/setup.iss'
}
$iss = $iss -replace '#define AppVersion\s+"[^"]+"', "#define AppVersion     `"$Version`""
Write-FileUtf8 'installer/setup.iss' $iss
Write-Host "  setup.iss         -> $Version"

# ── 3. lib/core/update_check.dart ───────────────────────────────────────────
$dart = Get-Content 'lib/core/update_check.dart' -Raw -Encoding UTF8
if ($dart -notmatch "defaultValue: '\d+\.\d+\.\d+'") {
  throw 'Could not find the kAppVersion default in lib/core/update_check.dart'
}
$dart = $dart -replace "defaultValue: '\d+\.\d+\.\d+'", "defaultValue: '$Version'"
Write-FileUtf8 'lib/core/update_check.dart' $dart
Write-Host "  update_check.dart -> $Version"

# ── 4. Build ────────────────────────────────────────────────────────────────
Write-Host "`nBuilding..." -ForegroundColor Cyan
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

# ── 5. Package ──────────────────────────────────────────────────────────────
$iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) {
  Write-Warning "Inno Setup not found at $iscc — skipping the installer."
  Write-Host ('Install it, then run:  & "{0}" installer\setup.iss' -f $iscc)
  exit 0
}
& $iscc 'installer\setup.iss'
if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }

$exe = Join-Path $root "installer\output\SLCustoms-SR-Setup-$Version.exe"
Write-Host "`nDone." -ForegroundColor Green
if (Test-Path $exe) {
  $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
  Write-Host ("  {0}  ({1} MB)" -f $exe, $mb)
}

Write-Host @"

NEXT — publish it, or no branch will ever be told:

  1. git commit -am "release $Version"  &&  git push
  2. git tag v$Version  &&  git push origin v$Version
  3. On GitHub: Releases -> Draft a new release
       Tag:    v$Version
       Title:  $Version
       Notes:  what changed, in plain words -- officers read this
       Attach: the .exe above
     Publish (NOT as a pre-release, and NOT as a draft: the app skips both).

  Every running copy checks GitHub at startup and shows the strip within a
  restart. Nothing needs to be pushed to the branches.
"@ -ForegroundColor Yellow
