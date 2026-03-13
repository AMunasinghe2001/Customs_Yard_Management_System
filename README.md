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

To build a Windows executable:

```bash
flutter build windows
```

Output is generated under `build/windows/x64/runner/Release/`.

## Notes

- This repository is intended to track source code, configuration, and database schema only.
- Local editor metadata, temporary helper scripts, and generated build artifacts are excluded from version control.

## License

This project currently has no license file configured.
