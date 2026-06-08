# MEMORY.md — Repository Context

> High-signal map of this repo for fast onboarding. Keep concise; update on significant changes. Paths are clickable.

## Project Overview
- **Purpose**: Sri Lanka Customs "SR" (Seizure Report) yard management — package inspection/intake, SR warehouse holds & charges, returns/dispositions, forfeiture→tender→sale, officer/admin management, dashboards & reports.
- **Type**: Flutter **desktop** app, **Windows-first** (only [windows/](windows/) platform dir present; uses `window_manager`).
- **Backend**: Supabase (PostgreSQL + Auth + Row-Level Security + Realtime). No custom backend server.
- **Architecture**: Single Flutter client → Supabase directly. Service classes wrap all DB access; Riverpod providers expose data/state to widgets; realtime channels trigger re-fetch.
- **Core tech**: Flutter/Dart (SDK `>=3.0.0 <4.0.0`), Riverpod (`flutter_riverpod` + `riverpod_annotation`/`riverpod_generator`), `go_router`, `supabase_flutter`, `data_table_2`, `fl_chart`, `pdf`/`printing`/`barcode`, `google_sign_in`, `window_manager`. See [pubspec.yaml](pubspec.yaml).

## Repository Structure
- [lib/main.dart](lib/main.dart) — entry: window_manager init, `Supabase.initialize` (non-persisted sessions), `ProviderScope`, `MaterialApp.router`, offline-on-close handler.
- [lib/core/](lib/core/) — app-wide singletons/config:
  - [supabase_client.dart](lib/core/supabase_client.dart) — **hardcoded** Supabase URL + anon key; `supabase` getter.
  - [providers.dart](lib/core/providers.dart) — all Riverpod providers (services, state, futures, realtime triggers).
  - [router.dart](lib/core/router.dart) — `routerProvider` (GoRouter), redirect/auth guard, all routes.
  - [theme.dart](lib/core/theme.dart) — `AppTheme.lightTheme`/`darkTheme`, `context.colors` extension (themed color tokens).
  - [yards.dart](lib/core/yards.dart) — 7 yards + helpers (`kYards`, `kDefaultYardCode`, `yardByCode`, `yardSrPrefix`).
  - [app_session.dart](lib/core/app_session.dart) — `AppSession.currentYard` (set on login, tags writes).
- [lib/models/models.dart](lib/models/models.dart) — all domain models (single file).
- [lib/services/services.dart](lib/services/services.dart) — all service classes (single file, ~1800 lines).
- [lib/screens/](lib/screens/) — UI by feature (admin, auth, dashboard, forfeited_packages, home, inspection, login, packages, profile, reports, warehouses).
- [lib/widgets/](lib/widgets/) — shared widgets (shell, dropdowns, dialogs, chips, date picker).
- [lib/scripts/](lib/scripts/) — one-off dev scripts (e.g. dummy data seeding).
- [test/widget_test.dart](test/widget_test.dart) — **placeholder only** (trivial assertion).
- [supabase/](supabase/) — DB SQL: `schema.sql`, fixes/seeds, and timestamped `supabase/migrations/*.sql`.
- [migrations/](migrations/) — multi-yard SQL: `001_multi_yard.sql`, `002_strict_yard_isolation.sql` (run AFTER supabase/ migrations).
- Root: [README.md](README.md), [BARCODE_PRINTING_GUIDE.md](BARCODE_PRINTING_GUIDE.md), [analysis_options.yaml](analysis_options.yaml) (`flutter_lints`), SVG logo assets.

## Key Components
### Services ([lib/services/services.dart](lib/services/services.dart)) — each exposed via a Provider in providers.dart
- `AuthService` — Google + email/password sign-in, OTP, `verifyUserSession` (email-confirmed + active), heartbeat/online presence, sign-out. Sets `AppSession.currentYard` from `profile.yard`.
- `PackageService` — `getNextSrNumber({yard})` (`<PREFIX>/SR/NN/YYYY`), CRUD, `createPackage`/`upsertPackage({yard})`, `updatePackageStatus`, `getDashboardStats`.
- `WarehouseService` — warehouse CRUD, entries by warehouse, `addEntry`, `markAsReturned`, `disposeWarehouseItem`, `recordFinalDisposition`, storage-charge calc, stats.
- `AdminService` — profiles list, `requestSignupOtp`/`verifySignupOtp`/`createOfficer` (all accept `yard`), `toggleUserStatus`, `updateProfile({yard})`.
- `AuditLogService` — `recordLog` (writes tagged with `AppSession.currentYard`), `getAllLogs`, `getPackageCreator`.
- `HoldReasonService`, `PackageCategoryService` — shared lookup CRUD (NOT yard-scoped).
- `ForfeitedPackageService` — forfeited list, expired-appeal list, create/delete.
- `TendersService` — `createTender`, `recordDisposal`, list tenders/disposals.

### Models ([lib/models/models.dart](lib/models/models.dart))
- `PackageModel` (+ `toInsertJson`/`copyWith`), `PackageItem`, `WarehouseEntryModel`, `WarehouseModel`, `ProfileModel` (has `yard`), `AuditLogModel`, `ForfeitedPackageModel`, `TenderModel`, `TenderDisposalModel`, `PackageCategory`, `HoldReasonModel`. All have `fromJson`; `yard` is a nullable column on data models.

### Reusable widgets ([lib/widgets/](lib/widgets/))
- [app_shell.dart](lib/widgets/app_shell.dart) — sidebar nav shell wrapping authed screens (`NavItem` list = nav menu; "SR Registration" → `/inspection`).
- [styled_dropdown.dart](lib/widgets/styled_dropdown.dart) — `StyledDropdownButton` (filter) + `StyledDropdownFormField` (form field) → gold popup that expands downward; used for filters AND yard selectors. Params incl. `prefixIcon`, `contentPadding`, `helperText`, `menuWidth`.
- [custom_dropdown.dart](lib/widgets/custom_dropdown.dart) — `CustomDropdownField`/`CustomDropdown` (dark-themed Material dropdowns).
- [one_tap_date_picker.dart](lib/widgets/one_tap_date_picker.dart) — shared gold calendar (`OneTapDatePicker`); tap-to-select, manual-entry mode; used in SR registration + tender placement.
- [status_chip.dart](lib/widgets/status_chip.dart) — `StatusChip(status:)` central status→color/label mapping.
- [package_details_dialog.dart](lib/widgets/package_details_dialog.dart) — large SR details modal (per-item status badges incl. custom "Other").
- Also: `date_range_picker_dialog.dart`, `print_barcode_dialog.dart`, `warehouse_selection_dialog.dart`, `error_view.dart`, `empty_table_state.dart`.

### Routes ([lib/core/router.dart](lib/core/router.dart))
- Public: `/`, `/login`, `/signup`, `/admin/login`, `/admin/signup`.
- Authed (NoTransitionPage): `/dashboard`, `/inspection`, `/warehouses`, `/packages`, `/returned-packages`, `/abandoned-packages`, `/forfeited-packages`, `/sold-packages`, `/destroyed-packages`, `/reexported-packages`, `/other-dispositions`, `/tender-disposals`, `/admin`, `/admin/panel?tab=N`, `/profile`, `/reports`.
- `/sold|destroyed|reexported|other` reuse `DispositionCategoryScreen` with a `finalTag`.
- Redirect guard: unauthenticated → `/`; authenticated on `/`|`/login` → `/dashboard`; runs `verifyUserSession()` each navigation.

## Data Flow
- **Read**: widget `ref.watch(xProvider)` → FutureProvider → `ref.read(serviceProvider).method()` → Supabase query → model. `packageDataProvider.family(id)` caches per-package.
- **Write**: widget → `ref.read(serviceProvider).method()` → Supabase insert/update (tagged `yard = AppSession.currentYard` unless a `yard` arg overrides) → invalidate/trigger refresh.
- **Realtime**: Supabase channel `onPostgresChanges` → `RefreshTrigger.trigger()` → `*ChangeTriggerProvider` (StreamProvider) yields → FutureProviders watching it re-fetch. Tables wired: `packages`, `package_items`, `warehouse_entries`, `profiles`, `package_categories`, `audit_logs`, `forfeited_packages`.
- **Auth/session**: sessions **not persisted** (`_NoPersistLocalStorage`) → login required every launch. Online presence via `profiles.is_online`/`last_seen_at` heartbeat; on app close → set offline + audit log.
- **SR numbers**: `<yardPrefix>/SR/<NN>/<year>` from `getNextSrNumber` (max existing for yard+year + 1). Legacy/misc formats like `GL1/MISC/...` accepted in lookups.

## Multi-Yard (tenancy)
- 7 yards in [yards.dart](lib/core/yards.dart): `GL1` (default), `GL2`, `RCT`, `BQ`, `JCT`, `NNR`, `CVT`.
- Every data table has a `yard` text column; **RLS strictly scopes all rows to the caller's own yard** (`auth_user_yard()`), **admins included** — no cross-yard access ([migrations/002_strict_yard_isolation.sql](migrations/002_strict_yard_isolation.sql)).
- `hold_reasons`, `package_categories` stay global (not yard-scoped).
- Yard is **selected at account signup** (→ `profiles.yard`) and **editable in Edit Profile** (gold `StyledDropdownFormField`). SR Registration yard field is **locked/display-only** (you can only write to your own yard).
- `AppSession.currentYard` mirrors the signed-in user's yard and tags new writes + SR prefixes.

## Build & Run Commands
- Install: `flutter pub get`
- Dev run: `flutter run -d windows`
- Analyze (lint/type): `flutter analyze`
- Test: `flutter test` (only placeholder test exists)
- Codegen (riverpod_generator): `dart run build_runner build --delete-conflicting-outputs` (most providers are hand-written, so rarely needed)
- Production: `flutter build windows` → output `build/windows/x64/runner/Release/`
- Windows installer: Inno Setup script (added in git history; see repo root if present).

## Important Configuration
- **Supabase creds**: hardcoded in [lib/core/supabase_client.dart](lib/core/supabase_client.dart) (`supabaseUrl`, `supabaseAnonKey`). **No env vars / .env**. Change here to point to another project.
- **DB setup order**: run [supabase/schema.sql](supabase/schema.sql) → `supabase/migrations/*.sql` (timestamped) → `migrations/001_multi_yard.sql` → `migrations/002_strict_yard_isolation.sql`.
- **Assets**: `Sri_Lanka_Customs_logo.svg`, `Sri_Lanka_Customs_logo_tinted.svg` (declared in pubspec).
- **Window**: min size 1000×700, title "Sri Lanka Customs SR Management System", `preventClose` for graceful offline.
- **Lint**: [analysis_options.yaml](analysis_options.yaml) = `package:flutter_lints/flutter.yaml` defaults (`avoid_print` NOT disabled but `print()` is used widely).

## Development Conventions
- **Theming**: always use `context.colors.<token>` (e.g. `primaryGold`, `surfaceDark`, `textMuted`, `dangerRed`, `heldOrange`, `accentLightBlue`, `successGreen`) — not hardcoded colors. Supports light/dark.
- **Money**: `NumberFormat('#,##0.00')`, prefixed `LKR`.
- **Status display**: route through `StatusChip`; status strings are **case-sensitive and inconsistent** — capitalized for `Detain`/`Forfeit`/`Abandoned`/`Re-export`/`Destroy`, lowercase for `held`/`pending`/`returned`/`released`/`sold`. The typo `Forfiet` is normalized to `Forfeit` in several places.
- **Dropdowns**: filter/yard selectors use `StyledDropdownFormField`/`StyledDropdownButton`; dark Material forms use `CustomDropdownField`.
- **Dates**: use shared `OneTapDatePicker` for new pickers (not raw `showDatePicker`).
- **State**: one provider per concern in [providers.dart](lib/core/providers.dart); realtime via `RefreshTrigger` + `*ChangeTriggerProvider`. Filters often `StateProvider.family` keyed by warehouse/package id.
- **New authed screen**: add route in [router.dart](lib/core/router.dart) (NoTransitionPage), wrap body in `AppShell(currentRoute: ...)`, add `NavItem` in [app_shell.dart](lib/widgets/app_shell.dart) if it needs a sidebar entry.
- Models/services are each **one big file** — extend in place.

## Known Caveats
- **Secrets in source**: Supabase URL/anon key committed in `supabase_client.dart`.
- **No session persistence**: intentional (`_NoPersistLocalStorage`) — every launch needs fresh login.
- **Status string drift**: mixed casing + `Forfiet` typo; normalization is scattered (warehouses screen, status_chip, package_details_dialog). Be careful comparing statuses.
- **Two SQL locations**: legacy/base in [supabase/](supabase/); multi-yard RLS in root [migrations/](migrations/). README only mentions `supabase/schema.sql`.
- **`createOfficer` + RLS**: admin-creates-user upserts a profile with the new user's id, but `profiles` insert policy is `id = auth.uid()` → upsert may be blocked; yard is also passed in `signUp` metadata so a DB trigger can set it. Verify trigger behavior when debugging missing officer profiles/yards.
- **Windows-only**: no macos/linux/web/android/ios platform dirs.
- **`TenderPlacementScreen`** ([tender_placement_screen.dart](lib/screens/forfeited_packages/tender_placement_screen.dart)) appears unused; the wired flow is `TenderPlacementDialog` (opened from forfeited/tender-disposal screens).
- **Minimal tests**: only a placeholder; no real coverage.
- **`print()` debug logging** left throughout (esp. auth/session/window-close).
- **Warehouse "in-yard" logic**: `_leftYardStatuses` / `WarehouseEntryModel.isNoChargeStatus` decide visibility & charges in [warehouses_screen.dart](lib/screens/warehouses/warehouses_screen.dart); summary cards = All/Detain/Forfeit/Abandoned counts.

## Change Log Summary (inferred from git)
- Built admin dashboard, package management, reporting + centralized providers & package details dialog.
- Added Google sign-in + `verifyUserSession`; admin login UI.
- Added forfeited packages + tenders (models, services, `TenderPlacementDialog`, disposal flow); dummy-data scripts.
- Barcode printing/saving; Windows Inno Setup installer.
- Year filter for package management; warehouse item status/charge handling.
- **Recent**: multi-yard support — `yard` column + RLS isolation (migrations 001/002), yard dropdowns at signup/profile, yard-locked SR registration, shared `OneTapDatePicker`, warehouse summary cards reworked ("yard manage and dropdown fixed").
