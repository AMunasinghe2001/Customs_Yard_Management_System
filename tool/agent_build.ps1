<#
.SYNOPSIS
  Build and launch the app WITHOUT touching the copy you are running.

.DESCRIPTION
  ⚠️ This exists because of a specific, repeated annoyance: the assistant
  rebuilding the app kept closing the app YOU had running.

  Both were building into the same place:

      build\windows\x64\runner\Debug\cus_yard_management.exe

  Windows locks a running .exe, so a second build cannot link over it. The only
  way to free the lock is to terminate the app holding it -- so every rebuild
  had to kill whatever was already running, which was usually your window, in
  the middle of whatever you were looking at.

  run_instance.ps1 already solved this for `flutter run` by giving each
  terminal a private build directory. This is the same trick for a BUILD plus a
  detached launch, which is what an automated check needs: it never attaches a
  debugger and never has to be stopped with Ctrl-C.

  The slot is named 'agent' and is reused, so the second build in it is
  incremental. Your own runs -- bare `flutter run`, or run_instance.ps1 -- keep
  using their own directories and are never evicted.

.NOTES
  The private %APPDATA% is per-PROCESS, so it applies to this script's shell
  and nothing outside it. See run_instance.ps1 for the full explanation.

.EXAMPLE
  .\tool\agent_build.ps1              # build, then launch it detached
  .\tool\agent_build.ps1 -NoLaunch    # build only
  .\tool\agent_build.ps1 -Stop        # close the agent's app, leaving yours
#>
param(
    [switch] $Release,
    [switch] $NoLaunch,
    [switch] $Stop
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$slotName = 'agent'
$slot     = Join-Path $root ".flutter-instances\$slotName"
$mode     = if ($Release) { 'Release' } else { 'Debug' }
$exe      = Join-Path $slot "out\windows\x64\runner\Debug\cus_yard_management.exe"
if ($Release) {
    $exe = Join-Path $slot 'out\windows\x64\runner\Release\cus_yard_management.exe'
}

# ── Stop only OUR copy ──────────────────────────────────────────────────────
# ⚠️ Matched by the PATH it was started from, never by process name. Killing
# every cus_yard_management is what caused the problem in the first place.
function Stop-AgentApp {
    Get-CimInstance Win32_Process -Filter "Name = 'cus_yard_management.exe'" |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -eq $exe } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

if ($Stop) {
    Stop-AgentApp
    Write-Host 'Agent app stopped. Anything you started is untouched.' -ForegroundColor DarkGray
    return
}

New-Item -ItemType Directory -Force -Path $slot | Out-Null

# Private %APPDATA% for this process only, so the build-dir below applies here
# and nowhere else. The real one is kept, to build the shared copy afterwards.
$realAppData = $env:APPDATA
$env:APPDATA = $slot
$buildDir = ".flutter-instances/$slotName/out"   # relative: Flutter requires it
@{ 'build-dir' = $buildDir } | ConvertTo-Json |
    Out-File (Join-Path $slot '.flutter_settings') -Encoding utf8

# Our own previous copy still holds a lock on our own exe, so it has to go --
# but only ours.
Stop-AgentApp

$modeFlag = if ($Release) { '--release' } else { '--debug' }
& flutter build windows $modeFlag
if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

if (-not (Test-Path $exe)) { throw "built, but no exe at $exe" }
Write-Host "  built: $exe" -ForegroundColor DarkGray

if (-not $NoLaunch) {
    $p = Start-Process -FilePath $exe -PassThru
    Write-Host "  launched pid $($p.Id) -- your own windows were not touched." -ForegroundColor Cyan
}

# ── Also refresh the SHARED build, if nothing is holding it ─────────────────
# ⚠️ Isolating the build fixed one problem and created a worse one: fixes
# stopped reaching build\windows\..., which is the exe you launch. So a build
# in this slot is followed by a build of the shared one -- but ONLY when no app
# is holding its lock. If one is, this says so and changes nothing, because
# closing your window to relink is the thing the slot exists to avoid.
$sharedExe = Join-Path $root (Join-Path 'build' (Join-Path 'windows' (Join-Path 'x64' (Join-Path 'runner' (Join-Path $mode 'cus_yard_management.exe')))))
$locked = $false
if (Test-Path $sharedExe) {
    try { [IO.File]::Open($sharedExe, 'Open', 'Write', 'None').Close() }
    catch { $locked = $true }
}

if ($locked) {
    Write-Host ''
    Write-Host '  NOTE: build\windows\... is locked by a running app, so it was' -ForegroundColor Yellow
    Write-Host '        NOT refreshed. Close that window and re-run this, or run' -ForegroundColor Yellow
    Write-Host '        `flutter run -d windows` yourself, to see these changes.' -ForegroundColor Yellow
} else {
    $env:APPDATA = $realAppData          # back to the default build directory
    & flutter build windows $modeFlag | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  shared build refreshed: your usual launch is up to date.' -ForegroundColor DarkGray
    } else {
        Write-Host '  shared build FAILED -- your usual launch is stale.' -ForegroundColor Red
    }
}
