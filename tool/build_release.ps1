<#
.SYNOPSIS
  Build the shipping Windows release: obfuscated, with debug symbols kept.

.DESCRIPTION
  The one command that produces a build for officers. It differs from
  `flutter build windows` in three ways that matter:

    --obfuscate            renames Dart classes, methods and fields in the
                           compiled output, so the .exe no longer hands a
                           reader the app's structure. It is NOT encryption
                           and does not protect a credential -- see the
                           warning below -- but it does make the binary a poor
                           place to start reading.

    --split-debug-info     writes the symbol map OUT of the binary and into a
                           directory. This is what makes --obfuscate usable:
                           without it the mapping is simply gone, and a crash
                           from a shipped build can never be turned back into
                           a stack trace anyone can read.

    a secrets audit first  because obfuscation hides names, not strings. A
                           hardcoded password is just as readable in an
                           obfuscated binary as in a plain one.

  ⚠️ KEEP THE SYMBOLS. Each release writes to build\symbols\<version>. That
  directory is the ONLY way to decode a crash report from the matching build,
  and it is gitignored on purpose -- committing it would undo the obfuscation
  for anyone with the repo. Archive it somewhere durable with the installer.

  Decode a stack trace from a shipped build with:

      flutter symbolize -i <crash.txt> -d build\symbols\<version>\app.windows-x64.symbols

.EXAMPLE
  .\tool\build_release.ps1                 # audit, then build
  .\tool\build_release.ps1 -SkipAudit      # build only (not for a real release)
  .\tool\build_release.ps1 -DefineEnv      # bake config in via --dart-define
#>
param(
    # Skip the pre-build security audit. For iterating on the build itself --
    # never for a build you intend to hand out.
    [switch] $SkipAudit,

    # Bake PG_* / GMAIL_* from the current .env into the binary as
    # --dart-define values instead of shipping a .env beside the .exe.
    #
    # ⚠️ This does NOT make them secret: --dart-define values sit in the
    # binary as plain strings and `strings app.exe` finds them. It only
    # removes the separate file. Prefer shipping a .env, which can be edited
    # or rotated without a rebuild.
    [switch] $DefineEnv
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# The version the pubspec declares, so symbols are filed under the build they
# actually belong to. Symbols from the wrong version decode to nonsense.
$version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$symbolDir = Join-Path $repo "build\symbols\$version"

Write-Host ''
Write-Host '================================================================'
Write-Host " Release build - version $version"
Write-Host '================================================================'

# ---- 1. Audit -------------------------------------------------------------
# Obfuscation cannot hide a string. If a credential is compiled in, it ships
# in the clear whatever flags are used -- so the audit runs FIRST and stops
# the build, rather than reporting after an installer already exists.
if (-not $SkipAudit) {
    Write-Host ''
    Write-Host '-- pre-build security audit --'
    python tool\audit_client_security.py
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host 'BUILD STOPPED: the client-security audit failed.' -ForegroundColor Red
        Write-Host 'Obfuscation does not hide hardcoded strings - fix the findings first.'
        Write-Host 'Use -SkipAudit only when iterating on the build itself.'
        exit 1
    }
}

# ---- 2. Config ------------------------------------------------------------
$defines = @()
if ($DefineEnv) {
    $envFile = Join-Path $repo '.env'
    if (-not (Test-Path $envFile)) {
        Write-Host 'No .env found; -DefineEnv has nothing to bake in.' -ForegroundColor Yellow
    } else {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
                $k, $v = $line.Split('=', 2)
                $k = $k.Trim(); $v = $v.Trim()
                if ($v) { $defines += "--dart-define=$k=$v" }
            }
        }
        Write-Host "Baking in $($defines.Count) --dart-define value(s) from .env."
        Write-Host 'Reminder: these are readable with `strings` on the .exe.' -ForegroundColor Yellow
    }
}

# ---- 3. Build -------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $symbolDir | Out-Null

Write-Host ''
Write-Host '-- flutter build windows --release --obfuscate --'
Write-Host "   symbols -> $symbolDir"
Write-Host ''

$buildArgs = @(
    'build', 'windows', '--release',
    '--obfuscate',
    "--split-debug-info=$symbolDir"
) + $defines

& flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host 'BUILD FAILED.' -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---- 4. Report ------------------------------------------------------------
$exe = Join-Path $repo 'build\windows\x64\runner\Release\cus_yard_management.exe'
Write-Host ''
Write-Host '================================================================'
if (Test-Path $exe) {
    $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
    Write-Host " Built: $exe ($mb MB)"
} else {
    Write-Host ' Build reported success but the .exe was not found.' -ForegroundColor Yellow
}

$symbols = Get-ChildItem $symbolDir -File -ErrorAction SilentlyContinue
if ($symbols) {
    Write-Host " Symbols: $symbolDir ($($symbols.Count) file(s))"
    Write-Host ''
    Write-Host ' ARCHIVE THE SYMBOLS with this installer. They are the only'
    Write-Host ' way to read a crash report from this build, and they are not'
    Write-Host ' committed to git.'
} else {
    Write-Host ' WARNING: no symbol files were written.' -ForegroundColor Yellow
    Write-Host ' Crashes from this build will not be decodable.'
}

Write-Host ''
Write-Host ' Ship a .env beside the .exe (copy .env.example) unless the build'
Write-Host ' was made with -DefineEnv.'
Write-Host '================================================================'
