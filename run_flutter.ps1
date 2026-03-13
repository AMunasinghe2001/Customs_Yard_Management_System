#!/usr/bin/env pwsh

# Setup Flutter
$flutterPath = "$env:USERPROFILE\flutter\bin"
$env:PATH = "$flutterPath;$env:PATH"
$env:FLUTTER_ROOT = "$env:USERPROFILE\flutter"

# Run the command passed as argument
if ($args.Count -eq 0) {
    & "$env:USERPROFILE\flutter\bin\flutter.bat" pub get
    & "$env:USERPROFILE\flutter\bin\flutter.bat" run -d windows
} else {
    & "$env:USERPROFILE\flutter\bin\flutter.bat" @args
}
