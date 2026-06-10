# MEMORY.md — Repository Context

> High-signal map of this repo for fast onboarding. Keep concise; update on significant changes. Paths are clickable.

## Project Overview
- **Purpose**: Sri Lanka Customs "SR" (Seizure Report) yard management — package inspection/intake, SR warehouse holds & charges, returns/dispositions, forfeiture→tender→sale, officer/admin management, dashboards & reports.
- **Type**: Flutter **desktop** app, **Windows-first** (only [windows/](windows/) platform dir present; uses `window_manager`).
- **Backend**: Supabase (PostgreSQL + Auth + Row-Level Security + Realtime). One **Edge Function** ([supabase/functions/admin-officers/](supabase/functions/admin-officers/index.ts)) for admin-creates-officer (service_role + Resend email); otherwise no custom backend server.
- **Architecture**: Single Flutter client → Supabase directly. Service classes wrap all DB access; Riverpod providers expose data/state to widgets; realtime channels trigger re-fetch.
- **Core tech**: Flutter/Dart (SDK `>=3.0.0 <4.0.0`), Riverpod (`flutter_riverpod` + `riverpod_annotation`/`riverpod_generator`), `go_router`, `supabase_flutter`, `data_table_2`, `fl_chart`, `pdf`/`printing`/`barcode`, `google_sign_in`, `window_manager`, `auto_updater` (background updates). See [pubspec.yaml](pubspec.yaml).

## Repository Structure
- [lib/main.dart](lib/main.dart) — entry: window_manager init, `Supabase.initialize` (non-persisted sessions), `ProviderScope`, `MaterialApp.router`, offline-on-close handler.
- [lib/core/](lib/core/) — app-wide singletons/config:
  - [supabase_client.dart](lib/core/supabase_client.dart) — **hardcoded** Supabase URL + anon key; `supabase` getter.
  - [providers.dart](lib/core/providers.dart) — all Riverpod providers (services, state, futures, realtime triggers).
  - [router.dart](lib/core/router.dart) — `routerProvider` (GoRouter), redirect/auth guard, all routes.
  - [theme.dart](lib/core/theme.dart) — `AppTheme.lightTheme`/`darkTheme`, `context.colors` extension (themed color tokens).
  - [yards.dart](lib/core/yards.dart) — 7 yards + helpers (`kYards`, `kDefaultYardCode`, `yardByCode`, `yardSrPrefix`).
  - [app_session.dart](lib/core/app_session.dart) — `AppSession.currentYard` (set on login, tags writes).
  - [app_updater.dart](lib/core/app_updater.dart) — `initAutoUpdater()` / `checkForUpdatesNow()`; feed URL derived from `supabaseUrl` + `updates` bucket.
- [lib/models/models.dart](lib/models/models.dart) — all domain models (single file).
- [lib/services/services.dart](lib/services/services.dart) — all service classes (single file, ~1800 lines).
- [lib/screens/](lib/screens/) — UI by feature (admin, auth, dashboard, forfeited_packages, home, inspection, login, packages, profile, reports, warehouses).
- [lib/widgets/](lib/widgets/) — shared widgets (shell, dropdowns, dialogs, chips, date picker).
- [lib/scripts/](lib/scripts/) — one-off dev scripts (e.g. dummy data seeding).
- [test/widget_test.dart](test/widget_test.dart) — **placeholder only** (trivial assertion).
- [supabase/](supabase/) — DB SQL: `schema.sql`, fixes/seeds, timestamped `supabase/migrations/*.sql`, and Edge Functions under `supabase/functions/` (`admin-officers` = OTP + officer creation + credential email via Resend).
- [migrations/](migrations/) — multi-yard SQL: `001_multi_yard.sql`, `002_strict_yard_isolation.sql` (run AFTER supabase/ migrations).
- [updates/](updates/) — auto-update release assets: `appcast.xml` template + [release README](updates/README.md). Upload to the public Supabase `updates` bucket.
- Root: [README.md](README.md), [BARCODE_PRINTING_GUIDE.md](BARCODE_PRINTING_GUIDE.md), [analysis_options.yaml](analysis_options.yaml) (`flutter_lints`), SVG logo assets.

## Key Components
### Services ([lib/services/services.dart](lib/services/services.dart)) — each exposed via a Provider in providers.dart
- `AuthService` — Google + email/password sign-in, `signInWithIdentifier` (**username OR email** → resolves via `email_for_login` RPC, then password), `changePassword`, OTP, `verifyUserSession` (email-confirmed + active), heartbeat/online presence, sign-out. Sets `AppSession.currentYard` from `profile.yard`.
- `PackageService` — `getNextSrNumber({yard})` (`<PREFIX>/SR/NN/YYYY`), CRUD, `createPackage`/`upsertPackage({yard})`, `updatePackageStatus`, `getDashboardStats`.
- `WarehouseService` — warehouse CRUD, entries by warehouse, `addEntry`, `markAsReturned`, `disposeWarehouseItem`, `recordFinalDisposition`, storage-charge calc, stats.
- `AdminService` — profiles list, `requestSignupOtp`/`verifySignupOtp` (admin self-signup, accept `username`+`yard`), `requestOfficerOtp`/`verifyAndCreateOfficer` (officer creation via `admin-officers` Edge Function — emails system-generated username+password), legacy `createOfficer` (client-side signUp; **orphaned/unused**), `toggleUserStatus`, `updateProfile({username,yard})`.
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
- [year_filter.dart](lib/widgets/year_filter.dart) — `YearFilterButton` ("All Years" dropdown) + `srYears()`/`srYearMatches()` helpers (parse trailing `/YYYY` of SR numbers). Used on all history/disposition list pages.
- [styled_form_dialog.dart](lib/widgets/styled_form_dialog.dart) — `StyledFormDialog` (gradient header + gold icon + label/title + footer) + `StyledFormSection` (gold-headed card) + `StyledDialogPrimaryButton`. Matches the SR Register edit modal; used by all Admin Panel dialogs (officer/warehouse/category/storage/hold-reason).
- [status_chip.dart](lib/widgets/status_chip.dart) — `StatusChip(status:)` central status→color/label mapping.
- [package_details_dialog.dart](lib/widgets/package_details_dialog.dart) — large SR details modal (per-item status badges incl. custom "Other").
- Also: `date_range_picker_dialog.dart`, `print_barcode_dialog.dart`, `warehouse_selection_dialog.dart`, `error_view.dart`, `empty_table_state.dart`.

### Routes ([lib/core/router.dart](lib/core/router.dart))
- Public: `/`, `/login`, `/admin/login`, `/admin/signup`. (Officer self-signup `/signup` **removed** — officers are created by admins only; `officer_signup_screen.dart` is now a dead file.)
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

## Auto-Update (desktop)
- `auto_updater` (WinSparkle on Windows) wired in [main.dart](lib/main.dart) via `initAutoUpdater()` → background check on startup + every 6h. See [app_updater.dart](lib/core/app_updater.dart).
- Feed = public Supabase Storage bucket **`updates`** → `<supabaseUrl>/storage/v1/object/public/updates/appcast.xml` (auto-derived; no extra config).
- Release flow + appcast template in [updates/](updates/) (see [updates/README.md](updates/README.md)): bump `pubspec` version → `flutter build windows` → Inno Setup `.exe` → edit `appcast.xml` (version/url/length/pubDate) → upload `.exe` + `appcast.xml` to the bucket.
- Init is guarded (`Platform.isWindows||isMacOS`) and swallows all errors — never blocks startup.

## Build & Run Commands
- Install: `flutter pub get`
- Dev run: `flutter run -d windows`
- Analyze (lint/type): `flutter analyze`
- Test: `flutter test` (only placeholder test exists)
- Codegen (riverpod_generator): `dart run build_runner build --delete-conflicting-outputs` (most providers are hand-written, so rarely needed)
- Production: `flutter build windows` → output `build/windows/x64/runner/Release/`
- Windows installer: Inno Setup script (added in git history; see repo root if present).
- Release/auto-update: bump `pubspec` version → build → Inno Setup `.exe` → update + upload [updates/appcast.xml](updates/appcast.xml) and the `.exe` to the public `updates` bucket. Full steps: [updates/README.md](updates/README.md).

## Important Configuration
- **Supabase creds**: hardcoded in [lib/core/supabase_client.dart](lib/core/supabase_client.dart) (`supabaseUrl`, `supabaseAnonKey`). **No env vars / .env**. Change here to point to another project.
- **DB setup order**: run [supabase/schema.sql](supabase/schema.sql) → `supabase/migrations/*.sql` (timestamped, incl. `20260609_officer_username_auth.sql` = `profiles.username` + `officer_signup_otps` + `email_for_login` RPC) → `migrations/001_multi_yard.sql` → `migrations/002_strict_yard_isolation.sql`.
- **Edge Function setup**: `supabase functions deploy admin-officers`; set secrets `RESEND_API_KEY` and `RESEND_FROM` (verified sender). Without these, officer-credential emails fail (the create dialog then shows the username/password on screen as a fallback).
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
- **Officer creation now via Edge Function**: `admin-officers` uses the **service_role** key (bypasses RLS) so the admin keeps their session and the profile/username are written reliably. New officer's `yard` = the calling admin's yard (read server-side). Legacy client-side `createOfficer` (signUp) is left in `services.dart`/`admin_screen.dart` (`_showAddDialog`) but **unwired** — it logs the admin out and shouldn't be used.
- **8-month account expiry is client-computed**: derived from `created_at` (not a DB flag/cron), enforced at login + shown in the Officers table. ⚠️ Any account already older than 8 months — **including the signed-in admin** — is immediately treated as expired and cannot log in. The legacy `_StatusToggle`/`AdminService.toggleUserStatus` remain in code but are no longer wired.
- **Username login**: `email_for_login(identifier)` RPC (SECURITY DEFINER, granted to `anon`) maps a username→auth email; login screens pass the single field through `signInWithIdentifier`. `profiles.username` is unique (case-insensitive partial index). Admin picks username at signup; officer's is system-generated and self-editable in Edit Profile.
- **Windows-only**: no macos/linux/web/android/ios platform dirs.
- **`TenderPlacementScreen`** ([tender_placement_screen.dart](lib/screens/forfeited_packages/tender_placement_screen.dart)) appears unused; the wired flow is `TenderPlacementDialog` (opened from forfeited/tender-disposal screens).
- **Minimal tests**: only a placeholder; no real coverage.
- **`print()` debug logging** left throughout (esp. auth/session/window-close).
- **Warehouse "in-yard" logic**: `_leftYardStatuses` / `WarehouseEntryModel.isNoChargeStatus` decide visibility & charges in [warehouses_screen.dart](lib/screens/warehouses/warehouses_screen.dart); summary cards = All/Detain/Forfeit/Abandoned counts.
- **Two disposition note-tag conventions** (`warehouse_entries.return_notes`): `disposeWarehouseItem` writes `[RE-EXPORT]`/`[DESTROY]`/`[FORFEIT]`/`[ABANDONED]` (present tense); `recordFinalDisposition` writes `[FINAL:RE-EXPORTED]`/`[FINAL:DESTROYED]`/… [disposition_category_screen.dart](lib/screens/packages/disposition_category_screen.dart) `_matchesTag` must accept BOTH per category.
- **Auto-update unverified natively**: `auto_updater` native (WinSparkle) linking only confirmable via a full `flutter build windows`; production updates should be EdDSA-signed (see [updates/README.md](updates/README.md)).

## Change Log Summary (inferred from git)
- Built admin dashboard, package management, reporting + centralized providers & package details dialog.
- Added Google sign-in + `verifyUserSession`; admin login UI.
- Added forfeited packages + tenders (models, services, `TenderPlacementDialog`, disposal flow); dummy-data scripts.
- Barcode printing/saving; Windows Inno Setup installer.
- Year filter for package management; warehouse item status/charge handling.
- Multi-yard support — `yard` column + RLS isolation (migrations 001/002), yard dropdowns at signup/profile, yard-locked SR registration, shared `OneTapDatePicker`, warehouse summary cards reworked ("yard manage and dropdown fixed").
- **Admin UX pass** (2026-06-09): all Admin Panel dialogs (Add Officer, Add/Edit Warehouse, Add/Edit Category, Storage Charges, Add/Edit Hold Reason) restyled with the shared [styled_form_dialog.dart](lib/widgets/styled_form_dialog.dart) (gradient header + gold-headed section cards + gold primary button) to match the SR Register edit modal. **Account auto-deactivation**: accounts (admins + officers) auto-deactivate 8 months after `created_at` — `ProfileModel.isExpired`/`isEffectivelyActive`; `signIn`/`verifyUserSession` throw `account_expired`; the manual active/inactive toggle in the Officers table is **removed** and replaced with a read-only ACTIVE/EXPIRED/INACTIVE chip (with an "auto-deactivates on …" tooltip). Officers tab uses `skipLoadingOnReload: true` so the 2-min heartbeat realtime refresh no longer flickers the table.
- **Auth overhaul** (2026-06-09): removed "Grey Line 1" branding everywhere (multi-yard app); **officers can no longer self-register** — admins create them from Admin → Officers ("Add Officer": email/mobile/salary/name → email OTP verify → system-generated username+password emailed via Resend, using the `admin-officers` Edge Function so the admin stays logged in); **username support** (`profiles.username`) — admins choose a username at signup, officers get a generated one and can change username+password in Edit Profile; **login accepts username OR email** in one field (resolved by `email_for_login` RPC). New migration `20260609_officer_username_auth.sql`. SMS OTP intentionally not used (email OTP only).
- **Latest** (2026-06): styled yard dropdowns (gold popup) on signup/profile/admin; warehouse cards → All/Detain/Forfeit/Abandoned (+ removed Confiscated chip); custom "Other" status badge in package details; tender dialog polish (themed number field, shared calendar, Select All/Clear All); disposition tables now match both `[FINAL:…]` and `[RE-EXPORT]`/`[DESTROY]` tags; **Year filter** (`YearFilterButton`) + Date Range added to all history/disposition pages (packages, abandoned, released, forfeited, sold/destroyed/re-exported/other, tender disposals); sign-in surfaces real errors (no more vague "check credentials"); **auto-update** via `auto_updater` + Supabase `updates` bucket.
