# Sri Lanka Customs Yard Management System

A Flutter desktop application for managing Sri Lanka Customs yard operations, package inspections, warehouse holds, and officer workflows.

## Overview

This project provides a Windows-first operations interface for customs officers to:

- inspect inbound packages
- track SR warehouse admissions and returns
- search package history and SR numbers
- manage officer profiles and customs rules
- view dashboard statistics for daily activity

The application uses Supabase for authentication, PostgreSQL data storage, and row-level security.

## Tech Stack

- Flutter
- Dart
- Riverpod
- GoRouter
- Supabase
- PostgreSQL

## Features

- Officer and admin authentication
- Dashboard with package and warehouse summary cards
- Inspection workflow for package intake
- SR warehouse tracking across multiple warehouses
- Package history with search and filters
- Admin panel for profile and customs rule management
- Profile editing for logged-in users

## Project Structure

```text
lib/
	core/        App configuration, providers, routing, theme, Supabase client
	models/      Domain models for packages, warehouses, rules, and profiles
	screens/     UI screens for dashboard, inspection, packages, warehouses, admin, auth
	services/    Business logic and Supabase data access
	widgets/     Shared reusable UI widgets
supabase/
	schema.sql   Database schema, policies, seed data, and helper views
```

## Prerequisites

- Flutter SDK 3.x or later
- Dart SDK 3.x or later
- Windows development environment for desktop builds
- A Supabase project

## Getting Started

1. Clone the repository.
2. Install Flutter dependencies:

```bash
flutter pub get
```

3. Create a Supabase project.
4. Run the SQL in [supabase/schema.sql](supabase/schema.sql) inside the Supabase SQL Editor.
5. Update Supabase credentials in [lib/core/supabase_client.dart](lib/core/supabase_client.dart).
6. Run the application:

```bash
flutter run -d windows
```

## Supabase Setup

The app expects:

- Supabase Auth enabled
- the database schema in [supabase/schema.sql](supabase/schema.sql)
- publishable project URL and anon key configured in [lib/core/supabase_client.dart](lib/core/supabase_client.dart)

## Build

### Development

```bash
flutter build windows
```

Output is generated under `build/windows/x64/runner/Release/`.

### Release (obfuscated)

Use the release script — it audits for hardcoded secrets first, then builds
with obfuscation and keeps the debug symbols:

```powershell
.	ooluild_release.ps1
```

It runs exactly this, filing symbols under the pubspec version:

```bash
flutter build windows --release   --obfuscate   --split-debug-info=build/symbols/<version>
```

**`--split-debug-info` is not optional when obfuscating.** `--obfuscate`
renames the app's classes and methods in the compiled output; without the
split, the mapping is discarded and a crash report from a shipped build can
never be turned back into a readable stack trace.

Decode a crash from a shipped build with the symbols from *that same* version:

```bash
flutter symbolize -i crash.txt   -d build/symbols/<version>/app.windows-x64.symbols
```

⚠️ **Archive `build/symbols/<version>/` alongside each installer.** It is
gitignored on purpose — committing it would undo the obfuscation for anyone
with the repo — so if it is not stored with the release, crash reports from
that build are permanently unreadable.

⚠️ **Obfuscation hides names, not strings.** A hardcoded password or API key
is just as readable in an obfuscated binary (`strings app.exe` finds it), which
is why the build script refuses to proceed when the secrets audit fails.

### Configuration

Credentials are never compiled in. Copy `.env.example` to `.env` and ship it
beside the `.exe`; the app reads it at start-up, so a password can be rotated
without a rebuild. Precedence is `--dart-define` > `.env` > compiled default.

### Security audits

```bash
python tool/audit_client_security.py     # secrets, release logging, build flags
python tool/audit_network_security.py    # TLS, SQL injection, RLS, exposure
python tool/audit_user_security.py       # OTP/2FA, password policy, RBAC
python tool/audit_backup_readiness.py    # append-only audit trail, backups, PITR
```

Daily backups: `.	oolackup_database.ps1` (see
[postgres/SECURITY.md](postgres/SECURITY.md) §8 for the scheduled task,
retention schedule, and the PITR restore procedure).

Both exit non-zero on a critical finding, so they can gate a release. See
[postgres/SECURITY.md](postgres/SECURITY.md) for the network and database side.

## Notes

- This repository is intended to track source code, configuration, and database schema only.
- Local editor metadata, temporary helper scripts, and generated build artifacts are excluded from version control.

## License

This project currently has no license file configured.
