<#
.SYNOPSIS
  Run the app WITHOUT closing the copies already running in other terminals.

.DESCRIPTION
  Every `flutter run -d windows` links the same file:

      build\windows\x64\runner\Debug\cus_yard_management.exe

  Windows locks a running .exe, so a second build cannot link over it -- and
  Flutter frees that lock by terminating the app it launched earlier. That is
  why starting a new run closes the windows already open. (It only started
  happening once the app stopped crashing at startup: before that there was
  rarely a live exe holding the lock.)

  Flutter's build directory is settable, but only as a per-USER setting
  (`flutter config --build-dir`) read from %APPDATA%\.flutter_settings -- so
  setting it globally would just move the collision, not remove it.

  The trick is that Flutter resolves that settings file through %APPDATA%,
  which is a per-PROCESS variable. This script points APPDATA at a private
  folder for this terminal only, writes a build-dir into the settings file
  there, and runs. Each terminal then builds and links its own exe, so no run
  ever has to evict another. Nothing outside this shell is affected.

.NOTES
  A slot's first run is a full native build (~60-90s) and its build output is
  about 450 MB, so keep a handful of named slots rather than one per session.
  Later runs in the same slot are as fast as a normal incremental build.
  `-Clean` deletes every slot's output.

.EXAMPLE
  .\tool\run_instance.ps1            # auto-named slot (a, b, c ...)
  .\tool\run_instance.ps1 login      # a named slot, reusable across sessions
  .\tool\run_instance.ps1 login -Release
  .\tool\run_instance.ps1 -Clean     # drop every slot's build output
#>
param(
    [string] $Name,
    [switch] $Release,
    [switch] $Clean,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Extra
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$slotRoot = Join-Path $root '.flutter-instances'

if ($Clean) {
    if (Test-Path $slotRoot) {
        Remove-Item -Recurse -Force $slotRoot
        Write-Host "Removed $slotRoot" -ForegroundColor Yellow
    } else {
        Write-Host 'Nothing to clean.' -ForegroundColor DarkGray
    }
    return
}

# Pick a slot. An unnamed run takes the first letter whose build output is not
# currently locked by a running exe, so two bare invocations never collide.
if (-not $Name) {
    foreach ($c in [char[]]'abcdefghijklmnopqrstuvwxyz') {
        $exe = Join-Path $slotRoot "$c\out\windows\x64\runner\Debug\cus_yard_management.exe"
        if (-not (Test-Path $exe)) { $Name = "$c"; break }
        # Exists -- but is it locked? A lock means that slot is still running.
        try {
            $fs = [IO.File]::Open($exe, 'Open', 'Write', 'None')
            $fs.Close()
            $Name = "$c"   # opened for writing, so nothing is running from it
            break
        } catch { }        # locked: this slot is in use, try the next letter
    }
    if (-not $Name) { throw 'All 26 instance slots are in use.' }
}

$slot = Join-Path $slotRoot $Name
New-Item -ItemType Directory -Force -Path $slot | Out-Null

# Private %APPDATA% for this shell only. Flutter reads .flutter_settings from
# here, so the build-dir below applies to THIS terminal and nowhere else.
$env:APPDATA = $slot
$settings = Join-Path $slot '.flutter_settings'
$buildDir = ".flutter-instances/$Name/out"   # relative: Flutter requires that
@{ 'build-dir' = $buildDir } | ConvertTo-Json | Out-File $settings -Encoding utf8

$mode = if ($Release) { '--release' } else { '--debug' }

Write-Host ''
Write-Host "  instance : $Name" -ForegroundColor Cyan
Write-Host "  build-dir: $buildDir" -ForegroundColor DarkGray
Write-Host "  mode     : $mode" -ForegroundColor DarkGray
Write-Host '  Apps running in other terminals are NOT closed.' -ForegroundColor DarkGray
Write-Host ''

$argv = @('run', '-d', 'windows', $mode)
if ($Extra) { $argv += $Extra }
& flutter @argv
