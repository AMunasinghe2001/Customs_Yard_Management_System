# MEMORY.md — Repository Context

> High-signal map of this repo for fast onboarding. Keep concise; paths are clickable.
>
> ⚠️ **MAINTENANCE RULE — keep this file current.** After ANY significant change to the system (new feature/tab/screen/route, new service method or model field, a schema migration, a fixed bug worth remembering, a new config/convention, or a change to the yard list), **update the relevant section of this file in the same change**. Prefer editing the existing bullet over appending a duplicate; keep it high-signal (what & why, not line-by-line). This is the first doc a new session reads — an out-of-date map is worse than none.

## Project Overview
- **Purpose**: Sri Lanka Customs "SR" (Seizure Report) yard management — package inspection/intake, SR warehouse holds & charges, returns/dispositions, forfeiture→tender→sale, officer/admin management, dashboards & reports.
- **Type**: Flutter **desktop** app, **Windows-first** (only [windows/](windows/) platform dir present; uses `window_manager`).
- **Backend**: a **plain PostgreSQL server**, reached directly with the `postgres` Dart package. ⚠️ **NOT Supabase** — the project ran on it until **2026-08-30** and was migrated off; `supabase_flutter`, the `supabase/` directory and the Edge Function are all gone. Auth, row-level security and realtime are now the app's own layer in [lib/core/db/](lib/core/db/) (`pg_auth.dart`, 155 RLS policies in SQL, `pg_realtime.dart` over LISTEN/NOTIFY).
- ⚠️ **The identifier `supabase` survives as a VARIABLE NAME** at ~198 call sites ([db_client.dart](lib/core/db_client.dart) re-exports it). It is a handle, not a dependency — renaming it would touch every data-layer call for no behavioural change. Seeing `supabase.from(...)` in this codebase does **not** mean Supabase.
- **Architecture**: Single Flutter client → PostgreSQL directly. Service classes wrap all DB access; Riverpod providers expose data/state to widgets; realtime channels trigger re-fetch.
- **Where the database lives**: configured per install, never compiled in — `--dart-define` > `.env` beside the .exe > built-in default ([app_env.dart](lib/core/app_env.dart), [pg_connection.dart](lib/core/db/pg_connection.dart)). Templates in [installer/env-templates/](installer/env-templates/): `local-server`, `cloud-server`, **`supabase`**.
- **Core tech**: Flutter/Dart (SDK `>=3.0.0 <4.0.0`), Riverpod (`flutter_riverpod` + `riverpod_annotation`/`riverpod_generator`), `go_router`, **`postgres: ^3.5.12`**, `data_table_2`, `fl_chart`, `pdf`/`printing`/`barcode`, `google_sign_in`, `window_manager`. See [pubspec.yaml](pubspec.yaml).

## Repository Structure
- [lib/main.dart](lib/main.dart) — entry: window_manager init, `ProviderScope`, `MaterialApp.router`, offline-on-close handler. ⚠️ The first database call is deliberately NOT awaited at start-up: a dead server used to hang the app on a blank, uncloseable window.
- [lib/core/](lib/core/) — app-wide singletons/config:
  - [db_client.dart](lib/core/db_client.dart) — re-exports the PostgreSQL layer under the legacy `supabase` name. No URL, no key: the connection is resolved at run time from `.env`.
  - [providers.dart](lib/core/providers.dart) — all Riverpod providers (services, state, futures, realtime triggers).
  - [router.dart](lib/core/router.dart) — `routerProvider` (GoRouter), redirect/auth guard, all routes.
  - [theme.dart](lib/core/theme.dart) — `AppTheme.lightTheme`/`darkTheme`, `context.colors` extension (themed color tokens).
  - [yards.dart](lib/core/yards.dart) — 34 yards + helpers (`kYards`, `kDefaultYardCode`, `yardByCode`, `yardSrPrefix`, `yardOfSrNumber`).
  - [directorates.dart](lib/core/directorates.dart) — the 8 head-office directorates (`kDirectorates`, `kYardDirectorates`) + SR-number composition (`composeSrNumber`, `stripDirectoratePrefix`, `hasDirectoratePrefix`, `directorateSrPrefix`).
  - [app_session.dart](lib/core/app_session.dart) — `AppSession.currentYard` (set on login, tags writes).
  - [app_updater.dart](lib/core/app_updater.dart) — `initAutoUpdater()` / `checkForUpdatesNow()`; feed URL derived from `supabaseUrl` + `updates` bucket.
- [lib/models/models.dart](lib/models/models.dart) — all domain models (single file).
- [lib/services/services.dart](lib/services/services.dart) — all service classes (single file, ~1800 lines).
- [lib/screens/](lib/screens/) — UI by feature (admin, auth, dashboard, forfeited_packages, home, inspection, login, packages, profile, reports, warehouses).
- [lib/widgets/](lib/widgets/) — shared widgets (shell, dropdowns, dialogs, chips, date picker).
- [lib/scripts/](lib/scripts/) — one-off dev scripts (e.g. dummy data seeding).
- [test/widget_test.dart](test/widget_test.dart) — **placeholder only** (trivial assertion).
- [supabase/](supabase/) — DB SQL: `schema.sql`, fixes/seeds, timestamped `db/migrations/*.sql`, and Edge Functions under `supabase/functions/` (`admin-officers` = OTP + officer creation + credential email via Resend).
- [migrations/](migrations/) — multi-yard SQL: `001_multi_yard.sql` … `012_rls_helpers_evaluated_once.sql` (run AFTER supabase/ migrations). Folded into the generated `postgres/02_schema.sql` by `postgres/build_schema.py` — add an `emit(...)` there for every new one.
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
- `ForfeitedPackageService` — forfeited list, expired-appeal list, create/delete; **`getRequestableExpiredPackages`** (appeal-passed & not-yet-requested, this yard) + **`createDisposalRequest({requestDate, dispositions})`** (yard submits a Disposal Request).
- `TendersService` — `createTender`, `recordDisposal`, list tenders/disposals.
- `DisposalService` (Central Disposal Directorate) — `getSoldPackages({yard})` (cross-yard via RLS), `getForfeitedPackages({yard})`, `getDisposalRequests()` (all yards' requests + items + forfeited detail), **`getSaleRequestItems()`** (Sale-tagged request items not yet in a sale), `getTenderSales` (now embeds `tender_sale_items` + package detail), `createTenderSale({…, packageYards})` (creates `tender_sale_items`), **`markTenderSaleItemSold({tenderSaleItemId, receipt})`** (calls `disposal_mark_sale_item_sold` RPC → writes `[FINAL:SOLD]` in the package's yard). `PackageService.getAllPackages` now takes an optional `yard` filter for these cross-yard reads.

### Models ([lib/models/models.dart](lib/models/models.dart))
- `PackageModel` (+ `toInsertJson`/`copyWith`), `PackageItem`, `WarehouseEntryModel`, `WarehouseModel`, `ProfileModel` (has `yard`), `AuditLogModel`, `ForfeitedPackageModel` (now has `yard`), `TenderModel`, `TenderDisposalModel`, `TenderSaleModel` (has `items: List<TenderSaleItemModel>`, `soldCount`), `TenderSaleItemModel` (sold tracking), `DisposalRequestModel`/`DisposalRequestItemModel` (+ `kDispositions`/`dispositionLabel` — `destruction`|`sale`), `PackageCategory`, `HoldReasonModel`. All have `fromJson`; `yard` is a nullable column on data models.

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
- Public: `/`, `/login`, `/admin/login`, `/admin/signup`, `/disposal/login`, `/disposal/signup`, `/appeal/login`, `/appeal/signup`, `/valuation/login`, `/valuation/signup`. (Officer self-signup `/signup` **removed** — officers are created by admins only; `officer_signup_screen.dart` is now a dead file.)
- `/disposal` (Central Disposal Directorate dashboard, [disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart)) — standalone scaffold (NOT `AppShell`); **8 tabs**: **Sold Packages**, **Destroyed Packages**, **Disposal Requests**, **Tender Sales**, **Unsold Tenders**, **Destructions**, **Undestroyed**, **Taxes** (all cross-yard, shared yard dropdown `disposalSelectedYardProvider`). Login-time redirect is role-aware: disposal→`/disposal`, appeal→`/appeal`, valuation→`/valuation`, admin→`/admin`, else `/dashboard`. Key mechanics:
  - **Two parallel disposal pipelines — SALE (tender) and DESTRUCTION** — with identical shapes. A forwarded Disposal Request's items are tagged `sale` or `destruction`; SALE items flow Tender Sales→Sold; DESTRUCTION items flow Destructions→Destroyed. Each has a *pool of unsold/undestroyed* re-tender/re-destruction tab.
  - **Tender/Destruction cards** show per-item rows (SR·Case No·Item·Source·Qty·Forfeit Reason·Location·Goods Desc·**Valuation**·Status·Details) and a per-item **Mark Sold**/**Mark Destroyed** action. Mark Sold captures **receipt + price + taxes**; **Mark Destroyed captures receipt + price only (NO taxes)**. A live **`_DeadlineCountdown`** chip ("Sell/Destroy within Xd Yh") ticks to `sale.unsoldDeadline` (= sale date + the following day's 23:59) — **Central Disposal only** (yard read-only views hide it). Mark buttons unlock once `saleTimePassed` (date+time moment passed); disabled with a tooltip until then.
  - **Auto unsold/undestroyed transition**: once `unsoldDeadline` passes, un-marked items drop from Tender/Destruction (card `_rows()` skips them; card hides when empty; list `visible` filter also drops window-closed sales so the empty-state shows) and appear in the **Unsold Tenders / Undestroyed** pools (`getUnsoldTenderSales`/`getUndestroyedDestructions` — eligible when the LATEST-created sale's deadline has passed AND not sold/destroyed; sorted by `createdAt` so a fresh re-tender with a future/blank date counts as pending, not unsold). "Times Tendered/Attempted" = count of sales the package sat in. **Re-tender / Re-destruction** creates a NEW sale moving the item (`createTenderSale`/`createDestruction`) — submit resolves the picker keys against the RIGHT pool (`unsoldTenderSalesProvider`/`undestroyedDestructionsProvider`, NOT the sale-request pool) so `packageYards`/`packageItems` fill.
  - **Item-scoped SOLD/DESTROYED (fixes the "sold Palm Oil when only Jasmine was sold" + wrong-price bugs)**: `tender_sale_items`/`destruction_items` carry a **`package_item_id`**; `createTenderSale`/`createDestruction` stamp it (from the disposal-request row's item). RPCs `disposal_mark_sale_item_sold` / `disposal_mark_destruction_item_destroyed` resolve `target_item = coalesce(tsi.package_item_id, fp.item_id)` and record EXACTLY ONE `[FINAL:SOLD]`/`[FINAL:DESTROYED]` warehouse entry for it (no loop, no status-gate → partial sales of the same item each record; guard raises `ambiguous_*_item` rather than bulk-processing a package-level row with >1 item). A **BEFORE-INSERT trigger** (`tsi_autofill_package_item`/`di_autofill_package_item`, migration [20260625_autofill_package_item.sql](db/migrations/20260625_autofill_package_item.sql)) self-heals a NULL `package_item_id` from the FP's `item_id` at the DB layer, so it works regardless of app build + prevents re-tender duplicates. Cells/popups pin the exact row by **receipt** (key `packageId|packageItemId|receipt`) — an item sold across several partial tenders shows each sale's own qty/price/valuation/delivery. Migrations: [20260625_mark_sold_per_tsi_item.sql](db/migrations/20260625_mark_sold_per_tsi_item.sql), [20260625_destruction_per_di_item.sql](db/migrations/20260625_destruction_per_di_item.sql), [20260630_destruction_price.sql](db/migrations/20260630_destruction_price.sql) (`destruction_items.destroyed_price`).
  - **Sold/Destroyed tables + popups**: show **Valuation** (Valuation Directorate's `valuationCost × qty`) AND **Sold/Destruction Price** as separate columns; Sold has Receipt No + taxes, Destruction price only. Officer/"Sold By"/"Destroyed By" is **hidden from the tables** — shown in the details popup ("Sold By" field) instead. Provider `saleItemForPackageItemProvider`/`destructionItemForPackageItemProvider` (both join `forfeited_packages(*, disposal_request_items(valuation_cost))` so `.forfeited.valuationCost` loads).
  - **Yard-side view-only Tender/Destruction Sale pages** ([tender_disposal_screen.dart](lib/screens/forfeited_packages/tender_disposal_screen.dart), [destruction_disposal_screen.dart](lib/screens/forfeited_packages/destruction_disposal_screen.dart), routes `/tender-disposals` + `/destruction-disposals`) reuse `TenderSaleCard`/`DestructionCard` with **`readOnly: true`**: keep every row forever (never drop on window-close), hide the timer, show a read-only status chip (Pending until window closes → Unsold/Undestroyed; Sold/Destroyed once marked — same `unsoldDeadline` logic as Central), disable Mark actions, and the details popup uses the **default blue header** (matching Forfeited etc.) not the green Central-Disposal accent (`headerAccentColor: readOnly ? null : green`).
- ⚠️ **Valuation Directorate** (role `valuation`, positions DC/SDDC via usernames `vdc`/`vsddc` — see [models.dart](lib/models/models.dart) `kValuationPositions`): a fifth institutional portal modelled on the Appeal Directorate (OTP login/signup at `/valuation/login`+`/signup`, cross-yard READ RLS, one SECURITY-DEFINER write RPC). `/valuation` = standalone dashboard ([valuation_dashboard_screen.dart](lib/screens/valuation/valuation_dashboard_screen.dart)) listing every yard's disposal requests **awaiting valuation**, with a per-item cost dialog. **Mandatory gate**: a yard's disposal request now lands in Valuation FIRST (`disposal_requests.valuation_status = 'pending_valuation'`); Valuation sets `disposal_request_items.valuation_cost` per item and forwards (`valuation_set_costs(p_request_id, p_costs jsonb, p_forward)` RPC → status `'forwarded'`, requires every item costed). ⚠️ `valuation_cost` stores the **per-UNIT** cost (the value typed in the dialog); the **total** is always derived = `unitCost × totalQuantity` (NOT stored), via `DisposalRequestItemModel` getters `coveredItems`/`totalQuantity`/`hsCodeLabel`/`unitCost`/`totalCost`. Both the Valuation dashboard table and Set-Valuation dialog (live `_LiveTotal` widget, dialog rebuilds per keystroke) and Central Disposal show HS Code · Qty · total. `coveredItems` = the package item matching `forfeited.itemId` if set, else all package items; `hsCodeLabel`='Multiple' when items differ; qty defaults to 1 if no item detail. Central Disposal's `getDisposalRequests()` only returns `valuation_status='forwarded'` rows. Migration [20260617_valuation_directorate.sql](db/migrations/20260617_valuation_directorate.sql) backfills pre-existing requests to `forwarded` (no regression). ⚠️ **BUG FIXED**: that backfill was originally an UNCONDITIONAL `update disposal_requests set valuation_status='forwarded'` (no WHERE) — since the migration is documented "safe to re-run", any re-run silently re-forwarded brand-new `pending_valuation` requests too, so they vanished from the Valuation dashboard (Pending Valuation = 0). Now the backfill is a one-shot guarded by a sentinel in new table `public.app_migration_flags(flag pk)` (`flag='valuation_directorate_backfilled'`). Recovery for an already-broken DB: [fix_valuation_status_backfill.sql](supabase/fix_valuation_status_backfill.sql) reverts wrongly-forwarded rows (those with `valued_by IS NULL` AND no item `valuation_cost`) back to `pending_valuation`. Providers: `valuationServiceProvider`, `valuationRequestsProvider` (shares the `disposalRequestsChangeTriggerProvider` realtime stream).
- **Disposal-request details popup** ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)): Central Disposal / Valuation request rows open it with `useLegacySummary: true`, `highlightItemId: f.itemId ?? package.items.first.id` (so it shows exactly ONE item — the row's item — not every package item), and `yardLabel: yardName(f.yard ?? request.yard)`. New `yardLabel` param renders a **Yard** row at the top of the Warehouse Summary (also shown in the empty-state when no warehouse entry exists). `legacyEntries` now filters to the highlighted item's entries (incl. null-packageItemId/package-level, falling back to all) even without a `highlightEntry`, so the right warehouse surfaces. Final-Disposition footer now requires `onSaleOrDestroyRequest != null` (only Forfeited/Other/Abandoned screens pass it) so it stays hidden in the read-only Central Disposal / Valuation popups. It also shows the Valuation cost via new `valuationUnitCost`/`valuationTotalCost`/`valuationQty` params (a "Valuation" section: cost/item + total). `getDisposalRequests()` / `getValuationRequests()` selects now also pull `warehouse_entries(*, warehouses(*))` so the Warehouse Summary has data (was empty — not fetched). ⚠️ Requires app **restart** (query change), not just hot-reload.
- ⚠️ **Per-item forfeited_packages rows** (fixes "two abandoned/Other rows of one package both show the combined qty, e.g. 67"): `forfeited_packages` gained an **`item_id`** column (migration [20260617_forfeited_item_id.sql](db/migrations/20260617_forfeited_item_id.sql), FK→package_items, on delete set null). `ForfeitedPackageModel.fromJson` now reads `item_id`. `createDisposalRequest()` synthetic-row creation groups by **(package, item, source)** — cacheKey `pkg:item:source` — and stores `item_id`, so each selected abandoned/"Other" item gets its OWN forfeited_packages row instead of collapsing all items of a package+source into one. With `item_id` set, `DisposalRequestItemModel.coveredItems`/`totalQuantity`/`hsCodeLabel` resolve to the single item, and the details popup's `highlightItemId: f.itemId` filters to that item (qty/HS/value correct, not the whole package). NOTE: only fixes requests created AFTER the migration — pre-existing aggregated rows lost the per-item info; delete + re-submit them.
- ⚠️ **OTP dev bypass**: [dev_config.dart](lib/core/dev_config.dart) `kDevSkipOtp` (currently **true** for the testing period). When true, the 3 OTP portals (Disposal/Valuation/Appeal) sign in with password only — their `_continue()` calls `AuthService.passwordOnlyLogin()` (verifies password via `signInWithPassword`, keeps session, runs the same active/expired/password-expiry gates as `finishOtpLogin`, audit logs "OTP skipped — dev") instead of `startOtpLogin`. ➜ **Set `kDevSkipOtp = false` to restore OTP** (one line, no other changes). ⚠️ **OTP e-mail delivery is now Gmail SMTP, NOT Supabase** (Supabase free tier caps OTP e-mails at ~2/hour): login + signup send a self-issued 6-digit code via the [GmailOtpService](lib/services/otp_service.dart) (`mailer` package, in-memory verify) — configure the sender in [otp_config.dart](lib/core/otp_config.dart) (`kGmailUser`/`kGmailAppPassword`, 2FA App Password). `startOtpLogin` verifies password then `GmailOtpService.sendCode`; `finishOtpLogin(email, otp, password)` verifies the code then re-`signInWithPassword` (the 3 login screens pass `_passwordCtrl.text`). Signup: `requestSignupOtp` sends the code; `verifySignupOtp` verifies then `signUp` creates the account — **needs Supabase → Auth → Email → "Confirm email" OFF**. Officer creation still uses the `admin-officers` Edge Function (Resend) — a separate path, not the Supabase OTP limit. ⚠️ **Every e-mail now says what it is FOR** (2026-09-06): `sendCode` takes an `OtpPurpose` (`signIn`/`createAccount`/`passwordReset`/`officerAccount`) and each gets its own subject, heading, lead line and — the part that matters — its own *"if this was not you"* instruction, because an unexpected sign-in code (someone has your password) and an unexpected account code (someone typed your address) call for different action. All 5 call sites name their flow; `signIn` is the default, so a caller that forgets would send the wrong letter — a test counts `sendCode(` against `purpose:` to catch that. `sendCredentials` splits on `isReissue`: a **welcome** (says to delete the mail once the password is changed, since it carries a working credential) vs a **reissue** (says the old password has stopped working, and to raise it at once) — only `resetDirectorateCredentials` sets it; the two officer-creation paths are genuine welcomes. One `_shell()` frame keeps them one system. Tests: [otp_email_purpose_test.dart](test/otp_email_purpose_test.dart).
- ⚠️ **One shared dashboard for officers + admins.** Both `/dashboard` (officer landing) and `/admin` (admin landing) now render `AdminDashboardScreen` (the rich dashboard: stat cards, Forfeit & Disposal Lifecycle, Online-in-yard, Warehouse Capacity). `AdminDashboardScreen` takes an optional `currentRoute` (default `/admin`); the `/dashboard` route passes `currentRoute: '/dashboard'` so the officer's nav highlights correctly, and the title names the **directorate and the yard** -- `$myPrefix · ${yardName(myYard)} Dashboard` ("CED · Grey Line 1 Dashboard"), with the badge opposite carrying the **full code, "CED/GL1"**. "Admin Dashboard" said who was looking while every page under it is filtered to one yard; the yard code alone was no better, because GL1 means nothing until you know it belongs to CED, and ICT groups yards under directorates precisely because that is the division that matters. The title spells the yard out in words, the badge writes it the way it appears on an SR number -- either half alone is the one an officer cannot use. The prefix comes from **`myDirectoratePrefixProvider`** ([providers.dart](lib/core/providers.dart)): `profiles.directorate` wins where set (a yard under two directorates -- NNR is CED and PSD -- has no single answer, and the account registered under one), falling back to `yard_directorates` and returning **null where the yard sits under several**, because a guess would put the wrong directorate on every page the officer opens. ⚠️ Never hardcode it: ICT re-pairs yards and directorates from the portal at run time. The date line is a live `StreamBuilder<DateTime>` clock (`EEEE, d MMMM yyyy · HH:mm:ss`) -- the dashboard auto-refreshes every 25s, so a time frozen at open is worse than none. The role moved under the officer’s name in the rail (`profile.postShortTitle`, the **post** ICT recorded, not the two-valued permission `role`). The old simple officer view (`DashboardScreen._buildOfficerDashboard` in [dashboard_screen.dart](lib/screens/dashboard/dashboard_screen.dart)) is now **unrouted/dead** (file kept, import removed from router). All data is yard-scoped so officers render it fine.
- ⚠️ **The lifecycle panel counts GOODS, once each** ([admin_dashboard_screen.dart](lib/screens/admin/admin_dashboard_screen.dart) `_ForfeitLifecycleSection` + `AuthService.getForfeitLifecycleSummary`). Every figure was wrong in a different way, and each was found by measuring against the live DB rather than reading the code:
  - **Appeals counted only forfeits** (`source='forfeit'`) -- 3 held / 12 decided, while the directorate had frozen 26 and ruled on 77. Detained, abandoned and "Other" goods raise appeals exactly as forfeits do, and theirs were the majority. Now reads `item_appeal_outcomes` (postgres/47), which carries **its own `yard` and `sr_number`** because it is a VIEW -- PostgREST has no FK to embed through, so `package_items!inner(...)` fails to resolve.
  - **Appeals now count only goods STILL IN A WAREHOUSE** (26/77 → **15/31**): a ruling on goods that have since left is history, not outstanding work. Filtered through `warehouse_rows` (postgres/48, the same view the Warehouses page reads) so the panel and that page cannot disagree about what is present. ⚠️ `warehouse_rows` has **no `yard` column** -- a warehouse belongs to a facility, not a directorate; narrow it on `sr_number ilike '%/<yard>/%'`.
  - **Tender rows are ATTEMPTS, not goods.** A package that failed four times has four `tender_sale_items` rows, so counting rows reported 109 unsold when **27** lots were. Now per-package on its **latest round** (`everSold` / `latestOutcome`), and a package that failed twice then sold is SOLD.
  - **Seven groups, each answering ONE question**: what the Appeal Directorate holds, what Central Disposal has, what the **tender did** (sold / unsold / held-but-not-recorded), then **Sold**, **Destroyed**, the **Top Management rulings** (four tiles) and **Re-exported** — one group per question an officer arrives with. Delivery used to be tiles of its own beside the tender result, which made a reader scan five tiles to learn how a tender went.
  - **Sold stands alone.** It is the outcome the yard is measured by, the only one with money behind it, and far the largest (76 against 39 and 19); in a row of three it read as one option among equals.
  - ⚠️ **Do not name a dashboard group "Final Outcomes".** That is the RAIL's section for the Top Management Directorate's rulings on goods nothing could sell — five pages (`/government-use-packages`, `/auction-packages`, `/re-export-packages`, `/converted-packages`, `/removed-packages`), all reading `unsold_proposals.proposal`, all rendered by `UnsoldPackagesScreen` with a `proposalFilter`. The panel's group is **"Top Management rulings"**, one tile per page in the rail's order; a test asserts it does not borrow the rail's name, because the same words pointing at different tables is the confusion this whole section exists to remove.
  - ⚠️ **Re-export is ONE tile, though the rail lists it under Final Outcomes.** `/re-export-packages` counts the **2** goods the DG ruled on; `/reexported-packages` (Disposed) counts **19**, everything that left the country by any route. The 2 are a **SUBSET of the 19**, not a separate population — measured, not assumed: both `re_export` proposals resolve to a `disposition_rows` row tagged RE-EXPORTED, while `auction`, `government_use`, `convert` and `remove_from_premises` resolve to **none at all**. So the panel emits four rulings, not five, and the re-export figure comes from the 19. Where the split matters it already exists: the Re-exported Goods page carries a **Decided By** column, because the difference is between ROWS on one page, not between two counts.
  - ⚠️ **A re-export has TWO events, and only one used to be stored.** The yard RULES it (the `[FINAL:RE-EXPORTED]` tag, which also closes the warehouse entry) and later the goods LEAVE. Migration **54** made the view say `when final_tag = 'RE-EXPORTED' then true` — to drive the dashboard's "n/a" count to zero — so all 17 yard rows reported themselves delivered on the day their tag was written, the page showed a green pill with nothing to press, and goods still standing in the yard were indistinguishable from goods gone weeks ago. **A figure that cannot be false is not a figure.** [postgres/55_reexport_delivery_is_recorded.sql](postgres/55_reexport_delivery_is_recorded.sql) adds `warehouse_entries.re_export_delivered` (+`_at`/`_by`, with the same date-consistency check `unsold_proposals` carries), points the view at it, and adds `yard_toggle_reexport_delivery(entry_id, delivered)` — which **refuses any entry that is not a re-export** and, unlike `disposal_toggle_outcome_delivery`, does **not** re-close the entry (it is already closed; re-closing would overwrite `returned_at` with today). **No backfill**: everything starts *awaiting collection*, because nobody recorded a departure. GL1 now reads **1 delivered / 18 awaiting / 0 unknown**. ⚠️ The migration body is 54's four-source union **copied verbatim** — retyping it from memory got two of the four sources wrong, which is how a hand-transcribed view silently drops rows.
  - ⚠️ **A tender history belongs to ONE item — never fall back to the package.** `getTenderSaleItemForPackageItem` used to end with `return getTenderSaleItemForPackage(packageId)`, and that package-level lookup returns the newest sale row for **any** of its items. `CED/GL1/OA/07/2026` is the case that exposed it: *Truck Tyres* was re-exported with no tender at all, and its popup showed the two rounds, three re-valuations and bids belonging to *Ceramic Floor Tiles* — the abandoned item still sitting in the yard. **58 rows in GL1 were being shown another item's valuation, silently.** It returns `null` now, and `TenderHistorySection` simply does not render; a caller that genuinely wants the package's newest sale calls `getTenderSaleItemForPackage` directly. The null-`packageItemId` path is unchanged — that caller asked about the package.
  - ⚠️ **Re-export and Release are TWO EVENTS wearing one date**, and only the first was stored. The yard RULES it — writing the `[FINAL:RE-EXPORTED]` tag or the release receipt, which also closes the warehouse entry — and the goods LEAVE later, when a ship sails or an owner arrives. Both pages reported every row finished on the day it was decided. Fixed by two matching migrations — [55](postgres/55_reexport_delivery_is_recorded.sql) and [57](postgres/57_released_delivery.sql) — each adding `<kind>_delivered` (+`_at`/`_by`) to `warehouse_entries` with a date-consistency check, pointing the view at it, and adding a `yard_toggle_<kind>_delivery` RPC that **refuses the other kind of entry** and does **not** re-close the entry. One `_HandoverCell` (enum `_HandoverKind`) serves both columns; one `_HandoverSection` (enum `HandoverKind`) serves both popups. ⚠️ **Sold and Destroyed pass null** — they already state their ending twice, in the tender history's Final Outcome panel plus a Sold Price column, or a Destruction Status & Financials section, and a third panel there repeated what was directly above it. A Top Management row passes null too: its ruling, date, note and hand-over are all in that same panel.
  - ⚠️ **Released Goods is `ReturnedPackagesScreen`, a SEPARATE screen** — not the shared `DispositionCategoryScreen`. A column added to the shared one does not reach it. That is why `HandoverCell` / `HandoverEntryKind` live in their own file ([handover_cell.dart](lib/widgets/handover_cell.dart)) rather than privately inside the disposition screen: the only other way to give Released the same pill would have been to copy it.
  - ⚠️ **A zone is occupied until the goods LEAVE; the storage charge ends when the yard RULES.** They are different days and they answer different questions. [postgres/58_zone_holds_until_delivery.sql](postgres/58_zone_holds_until_delivery.sql) adds `zone_occupancy_entries`, which keeps a released or re-exported entry in its zone until the hand-over is recorded — **187 → 233** in GL1 (15 awaiting shipment, 31 awaiting collection). `getYardWarehouseCapacity` reads that view instead of `is_returned = false`. The accrued charge deliberately still stops at the ruling: the bill is issued and closed there, and the goods then wait on their owner, not on the yard — billing them for their own delay would be wrong. The migration asserts the figure can only ever GROW (a shrink would mean the filter dropped something genuinely held) and that a completed hand-over frees its space.
  - ⚠️ **A hand-over collects MONEY, so it opens a form.** Marking goods delivered set a boolean; storage had been accruing since the goods arrived and nobody had a record of collecting it. **All THREE** Delivery buttons — release, re-export and **sale** — now open [handover_form_dialog.dart](lib/widgets/handover_form_dialog.dart): the charge (from the SR's **entry date**, the rule Released Goods has always used), a **required** receipt number, and an editable hand-over date **pre-filled with today** but capped at today. Cancelling writes nothing. [postgres/60_handover_receipt.sql](postgres/60_handover_receipt.sql) stores `handover_receipt_no` + `handover_charge` on `warehouse_entries`, written in the SAME statement as the delivery flag. ⚠️ The **amount is stored, never recomputed** — `storage_rates` is a history ICT edits, so a recalculation next year would not match the receipt in the owner's hand. [postgres/61_sold_handover_receipt.sql](postgres/61_sold_handover_receipt.sql) does the same for `tender_sale_items`: a buyer used to walk out with goods the yard had stored for years, the charge collected on no receipt.
  - ⚠️ **`calculatePackageCharge` returns ZERO for confiscated / forfeit / abandoned / destroyed goods** — the state has taken them, so there is no owner left to bill. Right for an INVOICE, wrong for a VALUATION: **48 of the 168** goods that reach a valuation form carry exactly those statuses, so `StorageChargeNote` would never have appeared on the forms it was built for. It walks the rate history itself (`_spaceCost`) and **labels which figure it is showing** — *"payable on collection"* for billable goods, *"cost of space · not billable, the state holds these goods"* otherwise. An officer told "accrued" about goods nobody can be billed for would read it as money the yard is owed.
  - ⚠️ **`create or replace function` matches on the ARGUMENT LIST.** Adding parameters creates an **overload**, leaving the old signature resolvable — so a caller that forgot the new receipt argument would silently take the 2-argument version and hand goods over with no record of the money. Migration 60 `drop function`s both old signatures first, and its verify block counts `pg_proc` rows to prove no overload survived. It caught this on the first run.
  - ⚠️ **Every form that sets a PRICE shows what the goods have already cost to keep** — [storage_charge_note.dart](lib/widgets/storage_charge_note.dart) in Pending Valuation, the re-valuation after a failed tender, the ADG's committee figure (**the ADG enters it**, not the DG), and Mark Sold. A valuation set without it is a number chosen in ignorance: goods worth Rs 40,000 that ran up Rs 90,000 in storage are worth tendering at a different figure than the same goods admitted last week. It charges only entries **still held** and only **this item** (a package holds several with separate entries), it is a NOTE never an input, and it watches `warehouseRefreshTriggerProvider` so a stale figure cannot reach a receipt.
  - ⚠️ **Central Disposal's Sold popup now carries the tender history.** The yard's has shown every round, re-valuation, bid and committee since it was written; the directorate that RUNS the tenders opened the same package and saw none of it. Read on the tap from `saleItemForPackageItemProvider(r.saleItemKey)` — the row already resolved that key for its Valuation cell, so it is cached.
  - ⚠️ **The `5×` tender count and the sold+unsold rows are CORRECT data**, checked against the database: 5 rounds is Valuation Tender + Tenders 1-3 + Committee Tender 1, exactly the process; and all 23 forfeited packages carrying both a sold and an unsold row failed *before* they sold (zero unsold rounds postdate a sale). A package that fails twice and then sells has three rows and one outcome. ⚠️ Group by **forfeited_package**, never by SR — one SR holds several items, each with its own tender history, and grouping by SR invents contradictions that are not there. [postgres/59_committee_pool_seed.sql](postgres/59_committee_pool_seed.sql) appoints the two missing committees so the tab has rows.
  - ⚠️ **A PERISHABLE takes no bids and no re-valuation.** It runs ONE special tender sale; if that fails the goods go straight to the Top Management Directorate through Unsold Perishables, because they are rotting. `unsold_retender_pool` has excluded them since migration 44, so no UI offers the Bids cell — but **nothing stopped the WRITE**, and 20 bids sat against 28 perishable packages, recorded through the special sale. [postgres/62_perishable_never_bids.sql](postgres/62_perishable_never_bids.sql) deletes them and adds a `before insert or update` trigger on `tender_bids`; its verify block **attempts a real insert and requires the rejection**, because a trigger that exists and does not fire reads as enforced and is not. `saveTenderRoundBids` checks first so the officer gets a sentence about perishables rather than a Postgres `check_violation`.
  - ⚠️ **`TenderHistorySection` speaks a different language for a perishable.** `_isPerishable` (from `forfeited.source`) stops it fetching bids, re-valuations or a committee at all — a stale row must not be able to put a bid chip under a round nobody can re-price. The round is labelled **"Special Tender Sale"**, not "Valuation Tender" (that name only means something as the first of a series, and implied a Tender 1 that is never coming); an empty bid list reads **"Perishable goods take no bids"** rather than "No bids recorded", which sounds like an omission; and the waiting line says the special sale failed rather than that *every tender has been exhausted*.
  - **Every page whose rows have TENDER ROUNDS now passes `tenderHistoryFor`** — Central Disposal's Unsold Tenders and Committees tabs, the Valuation portal's two tabs, and Perishable Goods (its single special sale, from `forfeitedByItemProvider`). ⚠️ A committee prices goods that failed four or more rounds and those rounds ARE the case for its figure; Unsold Tenders showed a current price with no history behind it, which is the one thing that says whether it is falling fast enough to sell.
  - ⚠️ **A pending delivery is AMBER, never red.** The sale popup had a row reading "Pending" in `dangerRed`, wedged between a receipt number and a tax figure — the one thing a reader opens that popup to check was the least visible thing on it, in the colour this app uses for something wrong. Goods awaiting collection are the yard's outstanding **work**. `DeliveryStatusBanner` leads the Sale & Financial section, green when gone and amber while waiting (the same two the delivery pills in the tables use), and it says **what** they are waiting for — "Pending" is one word for three different jobs. The hand-over receipt and charge ride on it (`TenderSaleItemModel.handoverReceiptNo` / `handoverCharge`), because the record of the money belongs beside the fact that the goods went. ⚠️ **The Final Outcome tile uses the same banner**, on Government Use, Auction, Re-export, Converted and Removed — pages whose whole job is to say whether the goods have gone, where it had been an 11.5pt line under the decision note.
  - ⚠️ **`showFinalOutcome: false` on the three MIDDLE-of-the-story tabs** — Tender Sales, Unsold Tenders and Committees. A package in a live sale is waiting for bidding to close, one on Unsold Tenders for a new price, one at a committee for its figure; "Awaiting Top Management" on any of them announces an ending several steps away. (The Valuation portal passes it too, via `valuerView`.)
  - ⚠️ **`getForfeitedByItemForPackage` needs the `disposal_request_items` embed**, like `_reTenderInfoForIds` did. `valuation_cost` lives there, not on `forfeited_packages`, and the model reads it from the embed — without it the Perishable popup's one tender round had no price, no bids (a perishable takes none) and no seal, and **a round with none of those is dropped from the history**, so the section rendered an outcome with nothing above it.
  - ⚠️ **The Final Outcome tile has FOUR states, not three.** It knew sold, decided and "awaiting Top Management" — so a package on its **first round, in a sale opened three days ago**, was told every tender had been exhausted. 71 forfeited packages in GL1 have exactly one round. The fourth is **`stillRunning`**: `mine.every((s) => s.hasRun)` — the same clock the round tiles seal reserve prices on, so the outcome and the rounds above it cannot disagree. It reads *At tender*, in blue rather than amber, because amber is the colour of work waiting on somebody and this waits on a clock. Sold and decided still win over it: a package can sell in a sale whose window is still open.
  - ⚠️ **`readOnly` cannot choose a popup's colour.** It means "cannot mark an item sold" — true of the yard AND of the Top Management Directorate, two portals with two colours — so Top Management opened a package from Tender Sales and got the **yard's blue header on a page that is teal everywhere else**. `TenderSaleCard` now takes a `popupAccent`; null keeps the old behaviour (green for Central Disposal, the popup's default for the yard).
  - **[YardChip](lib/widgets/yard_chip.dart) and [SourceChip](lib/widgets/source_chip.dart) are shared** across the directorate portals; only the ACCENT differs. ⚠️ Each portal had its own private copy and they had drifted. The yard chip names the **directorate too** — "CED/GL1 · Grey Line 1" — and takes the prefix from the group's **SR NUMBER** first (unambiguous: `CED/GL1/SR/24/2026` is a CED entry whatever else GL1 belongs to), falling back to `yard_directorates` only when that yard sits under exactly one. `SourceChip` also fixes **detained** goods reading as "Forfeit" — they fell through to the default.
  - **NINE tables now share one column order**: SR · Goods · Consignee · HS · **Location** · Qty · Value · **Source** · Disposition · … · Details — identity, place, numbers, state, action. The Valuation portal's three, Central Disposal's six (Disposal Requests, Tender Sales, Unsold Tenders, Unsold Goods, Sold Goods, Destroyed Goods) and Perishable Goods. **Location** is yard · warehouse · zone via `unsoldLocation`; **Case No** and **Reason** gave way to **Consignee** and **HS Code** on the tender tables (a case number is looked up, not scanned, and the hold reason is on the popup). Every non-text column is centred, header and cell alike. ⚠️ **Count cells against columns after ANY change here** — `data_table_2` throws at RUNTIME when they differ, the compiler cannot see it, and a green build proves nothing.
  - ⚠️ **A table with fixed-width columns needs a `minWidth`.** `data_table_2` asserts `totalFixedWidth < totalColAvailableWidth` — adding one column pushed Perishable Goods past a narrow window and the failure is a red screen, not a squeeze. Every other table in the app sets one.
  - ⚠️ **A widget test must override EVERY provider the page touches.** A new one (`perishableValuationsProvider`) opened a real realtime channel, and the test then ended with a pending timer outliving the widget tree — `pumpAndSettle` never settles against a live Postgres connection. The provider itself watches **one** trigger, not two, for the same reason.
  - **Destroyed Goods' date column is "Decided On"** — the `[FINAL:DESTROYED]` tag's own date, the moment an officer ruled the goods condemned. ⚠️ "Date" alone let a reader take it for the burn date, which for the rows still pending has not happened. **Sold Goods** carries a compact `StorageChargeNote` beside its Delivery button — the charge is collected on the form that button opens, so the figure and the collection sit together.
  - ⚠️ **The seal does not apply to the VALUATION DIRECTORATE.** A reserve price is sealed until bidding closes so nobody can bid against it — and the directorate that SET it is not "nobody". Its Unsold Tenders popup hid the very figures it was about to revise. `TenderHistorySection` and `PackageDetailsDialog` take **`valuerView`**, passed by that portal alone; it lifts both the per-round seal and the locked Valuation panel. Both of that portal's popups also now pass **`tenderHistoryFor`** — every row on Unsold Tenders failed at least one round, and the rounds, re-valuations and bids are the whole evidence for the price being set. ⚠️ **Three places had to change, and the third was hardcoded**: the per-round seal (`!valuerView && !ranById[id]`), the locked Valuation panel, and the **NEXT round's tile**, which carried a literal `sealed: true`. That last tile IS the directorate's own pending re-valuation — its popup told it the number was "shown once the tender closes" on the page where it had just typed it. For the valuer it shows the figure and reads *"Set for the next round. Central Disposal re-tenders at this price"* (`upcoming: true`) — same fact, different reason: not withheld, just still to happen.
  - ⚠️ **`StorageChargeNote` counts CLOSED entries too**, to the day they closed. It skipped returned entries, so all **146 rows on the disposition pages** — every sold, released, re-exported and "other" package in GL1 — showed nothing, and those are exactly the goods whose storage cost somebody wants to know. The day count runs to the **last day counted**, not to today ("703 days in storage" about goods that left in 2024 is a figure and a lie in one line), and the wording splits three ways: *payable on collection* (still accruing), *the goods have left the yard* (settled), *not billable, the state holds these goods* (forfeited/abandoned).
  - ⚠️ **A section wrapping an empty widget still draws its frame.** `StorageChargeNote` returns `SizedBox.shrink()` for a package with no warehouse entries, but `_DetailSection` around it kept the heading, the border and the padding — so the popup carried an empty panel titled STORAGE. `storageChargeVisibleProvider` answers the question BEFORE the frame is built (null while loading, so the section is held back rather than flashed away). The section itself appears only where the old Warehouse Charges one is skipped — `useLegacySummary`, a no-charge status, or a sale — so the two never both show.
  - ⚠️ **Storage reads BEFORE the signatures.** It is a fact about the GOODS; *System Entry By* and *Released By* name the officers who signed for them, and every paper form in this office puts the signature at the bottom.
  - ⚠️ **No Final Outcome on the valuer's popup.** Its work is one step of a process with several still to run — the price it sets goes to Central Disposal, which re-tenders, and only after that does anything reach Top Management. `showFinalOutcome && !valuerView`.
  - **`_SystemEntrySection` wears the same frame as every other section** — tinted header strip, gold icon, spaced capitals — with an **avatar of the officer's initials** rather than a second copy of the icon already in its heading. ⚠️ It had a gradient card of its own, so the last thing on every popup looked like it came from a different screen. An unrecorded entry stays muted and italic: gold-and-bold announces a person, and using it for "Not recorded" made a blank field look like a finding.
  - ⚠️ **There is no `/re-export-packages`.** Top Management's re-export ruling had its own page listing 2 goods — every one of which already appears on **Re-exported Goods** (`/reexported-packages`), which lists all 19 that left the country by any route and marks each row **Yard** or **Top Management** in its Decided By column. Two pages for one population, one a strict subset of the other, meant a reader had to know which answered their question. The other four rulings keep their pages: their goods appear nowhere else.
  - ⚠️ **The popup section is a `_DetailSection` of `_DetailItem`s, not a tinted banner.** It sits directly above Warehouse Summary and the two are read as a pair — where the goods are, and whether they have gone — so a banner in a different visual language between the dialog's other sections made the popup look assembled from two designs.
  - ⚠️ **A delivery DATE must be gated on its own flag.** [postgres/56_delivery_carries_its_date.sql](postgres/56_delivery_carries_its_date.sql) adds `delivered_at` to `disposition_rows` from the same four sources in the same order as `delivered` — each wrapped in `case when <flag> then <date> end`. **`tender_sale_items` and `destruction_items` carry NO delivery-consistency check** (only `unsold_proposals` has one), and the data drifted through the gap: **20 rows hold a `delivered_at` while reading not-delivered**, and 20 more are delivered with no date at all. The flag is the answer; a date beside a false flag is a leftover. The second case is legal and left alone — the popup says "Delivered" and names no day, which is exactly what is known.
  - ⚠️ **Assert the RULE in a migration, not the tally.** 55 pinned re-export deliveries at exactly 1 — true on the day it ran. Officers marked two more within the hour through the button 55 had just created, so re-running it failed on a system working exactly as intended. 56 asserts what must always hold instead: *no re-export reports delivered without a recorded departure behind it*. Fixed counts are only safe for tables the migration cannot cause writes to.
  - ⚠️ **`dispositionPageProvider` must watch every delivery source.** It watched packages, warehouse entries and bids but **not `tender_sale_items`**, which is where a sold lot's delivery lives — so marking one delivered updated the pill and left the row's own data stale until the page was reopened. The re-export path was correct only by accident (it writes to `warehouse_entries`, already watched).
  - ⚠️ **Destroyed splits by `is_destroyed`, NEVER by delivery.** Nothing is handed over to be burnt: 23 of the 39 destroyed rows carry no delivery state at all, so a delivered/pending split read "9 delivered · 7 awaiting" of 39 and left the reader to wonder about the other 23. Done or not done — **17 destroyed / 22 awaiting** — is the question that page answers.
  - ⚠️ **The destroyed figure comes from the PAGE's view, not the destruction list.** `destruction_items` says 16 destroyed; `/destroyed-packages` says 17, because one package (`Copper Wire Coils`, CED/GL1/SR/24/2026) reached destroyed through a warehouse entry tagged `[FINAL:DESTROYED]` with **no `destruction_items` row at all**. A tile that opens a page showing a different number is worse than no tile, so `destruction_items` is now read for its **ids alone** — which packages are already placed, so "forwarded, not yet placed" can exclude them.
  - **Outcomes come from `disposition_rows`** — the same view the Sold / Destroyed / Re-exported pages page through, so a dashboard figure and a row count cannot disagree. Each is ONE `_SplitTile` carrying the total with its split beneath ("39 delivered · 37 awaiting collection"): the two halves are one fact, and separate tiles made six saying what two do. ⚠️ `delivered` is **NULL, not false**, where there is no hand-over step (17 of the 19 re-exported); counting null as pending would claim goods are awaiting collection that nobody is coming for, so the tile shows it as `n/a` rather than letting the arithmetic quietly not close. On `unsold_proposals` it is instead **NOT NULL DEFAULT false** — every ruling is delivered or pending, no third state.
  - **"Sent for destruction" was structurally always 0** and was removed: a yard raises a disposal request for SALE; goods reach destruction another way entirely (a DG ruling, or a perishable that failed at tender). All 39 destruction items arrived with no request behind them.
  - **"Forwarded" showed the same goods twice** -- 135 forwarded, of which 113 were already counted under At Tender on the same panel. Now **`forwardedNotPlaced`** (22): forwarded, and not yet at tender or in destruction.
  - **Valuation was counted in requests** while everything beside it counted goods (`valuation_rows` is one row per request): 9 shown, 33 goods to cost.
  Pinned by [yard_dashboard_holdings_test.dart](test/yard_dashboard_holdings_test.dart) -- which asserts the **property** ("no tile can only ever read zero", "forwarded counts only what is not already shown at tender"), not the label text.
- Authed (NoTransitionPage): `/dashboard`, `/inspection`, `/warehouses`, `/packages`, `/returned-packages`, `/abandoned-packages`, `/forfeited-packages`, `/other-packages`, `/sold-packages`, `/destroyed-packages`, `/reexported-packages`, `/tender-disposals`, `/admin`, `/admin/panel?tab=N`, `/profile`, `/reports`. The `/other-dispositions` route + "Other Dispositions" nav items were **removed** — only "Other Packages" (`/other-packages`, held "Other"-status mgmt) remains.
- **Reports** ([reports_screen.dart](lib/screens/reports/reports_screen.dart)) cover the yard's pages (NOT directorate functions): sections = Standard, **Disposal Lifecycle** (Forfeited / Abandoned / Other / Sold / Destroyed — each PDF+Excel), Warehouse & Movement, Financial, System. Forfeited/Abandoned/Other come from `forfeitedPackageServiceProvider.getForfeitedPackages()` (Abandoned/Other filter by `source`) via new `ReportService.generateForfeitedPdf`/`exportForfeitedToExcel`. Sold/Destroyed = packages whose `warehouseEntries` carry a `[FINAL:SOLD]`/`[FINAL:DESTROYED]` tag, via `generatePackagePdf`/`exportPackagesToExcel`. `_filterByDate` handles `ForfeitedPackageModel` (by `forfeitedAt`). All respect the page-top Start/End date filters. ⚠️ **Stale-report fixes** (the report code predated the app redesign): removed the Status dropdown's `'seized'` option (packages never carry that status → always empty) and deleted the "Confiscated Items" card + `_generateConfiscatedPdf`/`_exportConfiscatedExcel` (filtered package status `'confiscated'`, which the app no longer sets — forfeiture is item-level `Forfeit` → `forfeited_packages`, now covered by the Forfeited card). Canonical package statuses to filter on: `pending`, `held` (incl. `detained`), `cleared`, `returned`.
- **Reports now include item identity + richer summary** (so a package is identifiable, not just by SR): EVERY package/warehouse/financial/forfeited report (PDF + Excel) has **Item** + **HS Code** columns. `ReportService.itemLabel(items)`/`hsLabel(items)` build them ('Multiple' when codes differ). `WarehouseEntryModel` gained `itemName`/`hsCode` (parsed from the joined `packages.package_items` matching `package_item_id`, or first item) — `getAllWarehouseEntries` now selects `packages(*, package_items(*))`. The **Abandoned/Other** reports use new `ForfeitedPackageService.getForfeitedBySource(source)` (the main `getForfeitedPackages()` is `source='forfeit'` only, so the old `.where(source==…)` filter returned empty). **Summary reports** (Day/Week/Month) now break down releases into **Forfeit · Abandoned · Re-export · Destroy · Sold · Other** columns (via `_dispoOf(entry)` reading the `[FINAL:…]`/`[ABANDONED]`/`[OTHER]` return-note tags), beyond Admitted/Released/Net. **Audit Logs report removed** (card + `_generateLogsPdf`/`_exportLogsExcel`).
- **Reports → QR Code Labels** section: `_QrLabelCard` opens `_QrLabelPickerDialog` (searchable multi-select of `getAllPackages()`), then hands the chosen packages to the existing `PrintBarcodeDialog` (print/save). Regenerates labels live from package data — so any previously registered package's QR labels can be produced again anytime (no stored history). QR payload + visible label now include **HS Code** ([barcode_service.dart](lib/services/barcode_service.dart) `_ItemLabel.hsCode`).
- **SR Registration form**: per-item **HS Code** and **Value** are now REQUIRED (validators + `*` labels in `_ItemRow`, [inspection_screen.dart](lib/screens/inspection/inspection_screen.dart)); Value must parse > 0. The form has NO Origin-country UI field (only a vestigial `_originCtrl` that saves '').
- **Packages report is now ITEM-PER-ROW** (`_buildPackageTable` + `exportPackagesToExcel`): an SR with several items shows several rows under the same SR number, each with Item · HS Code · **Qty** · Status · Value. Removed the **Origin** and **Weight** columns (Origin isn't captured; Weight replaced by per-item Qty). The reports Status + Warehouse filters now use the styled `CustomDropdownField` (matches the form dropdowns).
- **Officer nav** ([app_shell.dart](lib/widgets/app_shell.dart) `_officerNav`) now includes **Zone Capacity** (`/zone-capacity`) — was admin-only, so officers couldn't reach the page though the route isn't gated.
- **Package details "Actions" button** is disabled for officers (greyed + tooltip "Actions are restricted to administrators only"), matching the already-officer-disabled "Update" button ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart) — `onPressed: (isConfiscated || isOfficer) ? null : …`).
- ⚠️ **Forfeit actionability = window passed OR appeal decision received.** New `ForfeitedPackageModel.isActionable` (`isAppealExpired || hasAppealDecision`). A forfeited package is requestable / final-dispositionable as soon as the Appeal Directorate returns a decision — no need to wait out the 30-day window. Replaced `isAppealExpired` gates with `isActionable` at: the yard Forfeited screen's "Send Disposal Request" button (`actionableCount > 0`) and `allowFinalDisposition`, and `PackageService.getRequestableExpiredPackages()` (dropped the server `.lt('appeal_deadline', now)` filter → client `.where((f) => f.isActionable)`; still excludes RELEASE/RE-EXPORT/OTHER decisions, holds, sold/destroyed, already-requested). The "Expired" stat chip still counts only truly window-passed rows.
- ⚠️ **Package History is server-side paginated** (was loading ALL packages → slow with large tables). New `PackageService.getPackagesPaged({offset, limit, search, dateStart, dateEnd, year, yard})` returns `({rows, total})` using postgrest 2.x `.range()` + a separate `.count(CountOption.exact)` (count-only query). Providers: `packagePageProvider` (StateProvider<int> page index), `packagesPageProvider` (FutureProvider<({rows,total})>, `kPackagePageSize=50`). The Packages screen watches `packagesPageProvider` (NOT `livePackagesProvider`), shows a Prev/Next pager ("Showing X–Y of Total"), and resets the page to 0 when search/date/year filters change (`ref.listen` → `_resetPage`, deferred via postFrame). Year-filter options are now a fixed recent-years list (no full load); the SR autocomplete reads `livePackagesProvider` lazily via `ref.read` so it no longer force-loads everything on open.
- `/sold|destroyed|reexported` reuse `DispositionCategoryScreen` with a `finalTag` (`/other-dispositions` no longer routed).
- `/appeal` (Appeal Directorate) and `/valuation` (Valuation Directorate) are standalone directorate dashboards (NOT `AppShell`), each with its own OTP login/signup.
- Redirect guard: unauthenticated → `/`; authenticated on `/`|`/login` → role dashboard (disposal/appeal/valuation/admin/officer); runs `verifyUserSession()` each navigation.

## Data Flow
- **Read**: widget `ref.watch(xProvider)` → FutureProvider → `ref.read(serviceProvider).method()` → Supabase query → model. `packageDataProvider.family(id)` caches per-package.
- **Write**: widget → `ref.read(serviceProvider).method()` → Supabase insert/update (tagged `yard = AppSession.currentYard` unless a `yard` arg overrides) → invalidate/trigger refresh.
- **Realtime**: Supabase channel `onPostgresChanges` → `RefreshTrigger.trigger()` → `*ChangeTriggerProvider` (StreamProvider) yields → FutureProviders watching it re-fetch. Tables wired: `packages`, `package_items`, `warehouse_entries`, `profiles`, `package_categories`, `audit_logs`, `forfeited_packages`.
- **Auth/session**: sessions **not persisted** (`_NoPersistLocalStorage`) → login required every launch. Online presence via `profiles.is_online`/`last_seen_at` heartbeat; on app close → set offline + audit log.
- **SR numbers**: `<directoratePrefix>/<yardPrefix>/SR/<NN>/<year>` from `getNextSrNumber` (max existing serial for yard+year + 1, scanned across BOTH shapes). Accounts with no directorate still mint the older `<yardPrefix>/SR/<NN>/<year>`. Legacy/misc formats like `GL1/MISC/...` accepted in lookups. See the Multi-Yard section for the full rule.

## Multi-Yard (tenancy)
- ⚠️ **Executive Office** (role `executive`, positions **DG / ADG** via usernames `dg`/`adg` — [models.dart](lib/models/models.dart) `kExecutivePositions`): a 6th institutional portal for Customs' two highest posts, modelled on the Valuation Directorate (OTP login/signup at `/executive/login`+`/signup`, cross-yard READ RLS, one-each position limit via `executive_position_available` RPC, never auto-expires). `/executive` = standalone dashboard ([executive_dashboard_screen.dart](lib/screens/executive/executive_dashboard_screen.dart)) = a directorate-style header + the **Reports hub reused per-yard**: `ReportsScreen(executiveMode: true)` ([reports_screen.dart](lib/screens/reports/reports_screen.dart)) shows a **Yard selector** and scopes every report to the picked yard (`_yardArg` passed to `getAllPackages`/`getAllWarehouseEntries(yard:)`; `_filterByYard` on forfeited lists; report cards hidden until a yard is chosen). Officer/admin `/reports` unchanged (`executiveMode` false → own yard via RLS). Migration [20260714_executive_directorate.sql](db/migrations/20260714_executive_directorate.sql) (mirror of the valuation migration) adds the role + `auth_user_is_executive()` + `executive_read_all` cross-yard SELECT policies on the report tables. 5th landing card in [home_screen.dart](lib/screens/home/home_screen.dart) (accent `customsBlue`).
- ⚠️ **ICT Directorate** (role `ict`, positions `IDC`/`ISDDC`/`ICT_ADMIN`/`ICT_OFFICER` — [models.dart](lib/models/models.dart) `kIctPositions`): the head-office portal that **provisions every yard account** and maintains the yard/directorate reference data. OTP login/signup at `/ict/login`+`/signup`, dashboard `/ict` ([ict_dashboard_screen.dart](lib/screens/ict/ict_dashboard_screen.dart)) with **two tabs** — *Staff Accounts* (create/edit/deactivate DC-SDDC + officers across all yards, credentials e-mailed) and *Yards & Directorates* ([yard_directorate_tab.dart](lib/screens/ict/yard_directorate_tab.dart), add/edit directorates and yards, tick the many-to-many links, live "Example SR" preview per row). ⚠️ **BUG FIXED (2026-08-30)**: the ICT screens shipped earlier but **no migration ever added `'ict'` to the `profiles_role_check` constraint** (it stopped at `executive`), so every ICT sign-up failed the profile INSERT with SQLSTATE 23514 — and because `verifySignupOtp` swallowed that write in a bare `catch (_) {}` and the screen's `_friendlyError` had no branch for it, the user saw **"Network problem — couldn't reach the server"** and went looking at the Wi-Fi. Now: the role is in the constraint ([20260839](db/migrations/20260839_ict_directorates_and_yards.sql)), the profile write **is no longer swallowed** (it signs the half-made auth user back out and rethrows, so no account is left un-loginnable), and `AdminService._profileWriteMessage` maps 23514/23505/42703/42501 to messages that name the actual cause. Deactivate rather than delete a yard/directorate — its code is stamped on all historical rows.
- **Rename: "High Panel Officers" → "Top Management Directorate"** (2026-08-30), across ~76 display strings in 18 files. **Display-only** — the role is still `executive`, the routes are still `/executive/*`, and `executivePostIs()` still matches `(DG)`/`(ADG)`/`(DC)` in `full_name`, so pre-rename accounts keep working untouched.
- **Old Entry registration**: SR Registration ([inspection_screen.dart](lib/screens/inspection/inspection_screen.dart)) has a "Registration Type" dropdown — **New Entry** (default, unchanged) vs **Old Entry** (migrating a legacy package). Old Entry adds a required **Old SR Number** field, stored on `packages.old_sr_number` ([20260714_old_sr_number.sql](db/migrations/20260714_old_sr_number.sql); `PackageModel.oldSrNumber`). Such packages follow the normal package process AND appear on the dedicated **Old Entries** page ([old_entries_screen.dart](lib/screens/packages/old_entries_screen.dart), route `/old-entries`, nav after SR Registration) — a table of old SR → new SR + consignee/entry/items + details popup, filtered client-side from `livePackagesProvider` where `oldSrNumber != null`. The Registration Type dropdown uses `StyledDropdownFormField` (matches the item-row dropdowns).
- **Package Items row order** (registration): Item Name → **Unit Type** (was "Unit") → **Quantity** (was "Pkgs") → Status → Category. When Unit Type = **Cartons**, two extra fields appear — **Inner Unit** dropdown + **Inner Qty** — persisted on `package_items.inner_unit`/`inner_quantity` ([20260714_carton_inner_unit.sql](db/migrations/20260714_carton_inner_unit.sql); `PackageItem.innerUnit`/`innerQuantity`, NULL unless Cartons). Edit-load now also restores the unit type (was previously lost).
- ⚠️ **Yards & directorates are DATA, not code** (2026-08-30). The lists live in the DB tables `directorates`, `yards` and the many-to-many `yard_directorates`, maintained by the ICT portal at run time — adding a yard no longer needs a rebuild. `kYards` ([yards.dart](lib/core/yards.dart), now **34** yards) and `kDirectorates`/`kYardDirectorates` ([directorates.dart](lib/core/directorates.dart)) remain as the migration **seed** and the **offline fallback** the providers use when the query fails. Read `yardsProvider` / `directoratesProvider` / `yardDirectoratesProvider` / `yardsForDirectorateProvider(dirCode)` rather than the const lists in user-facing code. Migration: [20260839_ict_directorates_and_yards.sql](db/migrations/20260839_ict_directorates_and_yards.sql). `profiles.yard` is still plain text with no enum/check.
- ⚠️ **SR numbers now carry a DIRECTORATE prefix**: `<DIRECTORATE>/<YARD>/SR/<NN>/<YYYY>` (e.g. `CED/GL1/SR/25/2026`). The prefix comes from **the signed-in user's `profiles.directorate`** (`AppSession.currentDirectorate`), NOT from the yard — because a yard can sit under several directorates (**NNR** is CED *and* PSD; **Katunayaka/Rathmalana/Mattala** are B/A *and* ACD). Accounts with no directorate (pre-2026-08-30) keep minting the old unprefixed form, so **both shapes coexist**: always compose with `composeSrNumber()` and parse with `stripDirectoratePrefix()` — never `split('/').first` (the `B/A` prefix itself contains a slash, making a 5-segment number). `getNextSrNumber` counts the serial **per yard per year across both shapes**, so CED and PSD officers at NNR cannot mint the same serial. `getPackageBySrNumber` matches either shape. Covered by [directorate_sr_number_test.dart](test/directorate_sr_number_test.dart).
- ✅ **The SR-prefix migration HAS BEEN RUN on the local database** (2026-08-31): 71 `packages` + 63 `forfeited_packages` rewritten, 0 ambiguous (every row was GL1 → CED), 268 rows logged in `sr_number_migration_log`. A `pg_dump` was taken first (`before_sr_prefix.dump`). Every portal now shows `CED/GL1/SR/62/2026`.
- ⚠️ **The migration alone is not enough — back-fill `profiles.directorate` too.** The prefix on a NEW registration comes from the signed-in user, and only the admin had a directorate; the three officers had NULL, so they would have kept minting bare `GL1/SR/88/2026` against a table where every other row carried a prefix. Backfilled from the yard, but ONLY for yards belonging to exactly one directorate — an ambiguous yard (NNR is CED and PSD) has no right answer without asking the person. Verified: `getNextSrNumber` now returns `CED/GL1/SR/87/2026`.
- **Existing SR numbers were migrated** to the prefixed form by [20260840_sr_number_directorate_prefix.sql](db/migrations/20260840_sr_number_directorate_prefix.sql) (updates `packages` **and** the denormalised `forfeited_packages.sr_number`). ⚠️ SR numbers are printed on the **barcode/QR labels physically on the goods** — after running it those labels no longer match until reprinted. Every old→new pair is kept in `public.sr_number_migration_log` (ambiguous two-directorate yards flagged `was_ambiguous` for ICT review); undo with [rollback_sr_number_directorate_prefix.sql](supabase/rollback_sr_number_directorate_prefix.sql). Idempotent — a second run is a no-op, not `CED/CED/…`.
- Every data table has a `yard` text column; **RLS strictly scopes all rows to the caller's own yard** (`auth_user_yard()`), **admins included** — no cross-yard access ([migrations/002_strict_yard_isolation.sql](migrations/002_strict_yard_isolation.sql)). Exception: the directorate roles (disposal/appeal/valuation) have permissive cross-yard SELECT policies.
- ⚠️ **A policy on `profiles` must never read `profiles` inline.** The subquery is itself subject to the policies being evaluated, so PostgreSQL raises `42P17 infinite recursion detected in policy for relation "profiles"` — and because the router reads the profile on every redirect, **every sign-in fails and the window freezes with no way back**. Role checks go through the `SECURITY DEFINER` helpers (`auth_user_is_ict()`, `auth_user_yard()`, …), which run as the table owner and are not re-filtered. Two policies broke this rule: `yard_staff_boundary` (fixed in [006](migrations/006_profiles_policy_recursion_fix.sql)) and the base schema's `"Admins can manage all profiles"` (fixed in [007](migrations/007_drop_admin_profiles_policy.sql)).
- **007 DROPS the admin policy rather than rewriting it.** 002 had already removed cross-yard admin access and dropped `auth_user_is_admin()` as "the admin-bypass helper", replacing it with `yard_profiles_select/update/insert` — it just never dropped the base schema's policy, which still granted `FOR ALL` across every yard. Re-adding a `SECURITY DEFINER` admin helper would break the recursion but silently re-open that hole, so the helper must stay dropped.
- A failed `verifyUserSession()` in [lib/core/router.dart](lib/core/router.dart) now **signs the user out before bouncing**, and returns `null` on a route that is already public. Deliberate rejections (deactivated/expired/no profile) already signed out, so they settled; an *unexpected* failure (DB down, bad policy) left the session alive and redirecting to `/` re-ran the same failing check on arrival — an endless redirect where no page is ever built.
- `hold_reasons`, `package_categories` stay global (not yard-scoped).
- **Warehouses and their zones belong to a yard** ([008](migrations/008_warehouses_belong_to_a_yard.sql)). `warehouses` had NO yard column, so every yard saw every other yard's storage — GL2, which had never had one added, showed GL1's four warehouses, 18 zones and 72,000 units of capacity. `warehouse_zones` has no yard of its own; it inherits through `warehouse_id` via the `warehouse_yard(uuid)` `SECURITY DEFINER` helper (inline would recurse — see the 42P17 note above). Backfilled to GL1: all 333 entries across all four warehouses were GL1's, and the backfill *refuses to guess* for a warehouse two yards had used.
- ⚠️ **A yard column is not enough — the table also needs the RESTRICTIVE boundary** ([009](migrations/009_warehouse_yard_boundary.sql)). Permissive policies are OR-ed, so `warehouses_disposal_read` / `executive_read_all` widen the result past `warehouses_yard_select`. [005](migrations/005_restrict_yard_staff_at_database.sql) applies `yard_staff_boundary` automatically to every BASE TABLE **with a `yard` column** — but it ran before 008 added that column, so `warehouses` was never a candidate, and `warehouse_zones` has no `yard` column at all (it inherits via `warehouse_yard(warehouse_id)`). **When adding a `yard` to a table, add the restrictive boundary too; 005 will not retro-apply.**
- ⚠️ **A view without `security_invoker` bypasses every policy** — it runs as its OWNER. [010](migrations/010_remaining_views_run_as_caller.sql) closed the last two (`daily_stats`, which aggregated `packages` across all yards, and `password_rotation_status`); `warehouse_contents` was fixed in 008. Its verify block now fails if ANY view in `public` is left running as its owner, so a new view that forgets the flag is caught at migration time.
- **How the leak actually worked** (GL2 officer seeing `CED/GL1/...` rows): `packages` carries a PERMISSIVE `"Officers can view all packages"` = `auth.role() = 'authenticated'`. Permissive policies are OR-ed, so that alone grants every row; `yard_all` cannot narrow it. Only the RESTRICTIVE `yard_staff_boundary` (AND-ed) contains it. **Verified by removing the boundary on a scratch copy: a GL2 officer immediately saw all 176 GL1 packages.**
## Performance — measured, not guessed (2026-09-11)

- ⚠️ **Never benchmark through `flutter test`.** The harness inflated every query ~25x: the app's own path (`pool.execute(Sql.named(...))`) measured **365 ms** under `flutter test` but **14.4 ms** in a plain `dart run` and **11.3 ms** compiled AOT. Timings taken under the test harness sent me chasing a bottleneck that was not there. Benchmark with a standalone Dart script against a scratch copy of the database.
- **Release vs Debug is only ~25%** (11.3 ms AOT vs 14.4 ms JIT) — worth having, but not the lever it looks like.
- **`getAllPackages()` is ONE query and costs ~68 ms (Debug) / ~55 ms (Release)** — measured by dumping the generated SQL and benchmarking it standalone. The compat layer compiles the whole nested select (`package_items`, `warehouse_entries → warehouses → returned_profile`, `profiles`) into a single statement with `json_agg` correlated subqueries; it is neither N+1 nor multi-trip. **Do not "optimise" this — hand-writing the SQL produces the same query.**
- ⚠️ An earlier note here claimed "~18 round-trips". That was WRONG: it came from diffing `pg_stat_database.xact_commit`, which counts the whole database — the running app's own traffic was being counted. To count a call's queries, dump the SQL (a temporary print in `PgDatabase._run`), don't diff server-wide counters.
- **Server-side is not the problem**: `select * from packages` (176 rows) executes in **2–16 ms**. The cost is client round-trips and Dart-side text decoding.
- [012](migrations/012_rls_helpers_evaluated_once.sql) wraps every no-argument RLS helper in a scalar subquery — `(select auth_user_yard())` is hoisted to an InitPlan and evaluated **once per statement** instead of once per row. Before: `Seq Scan ... Buffers: shared hit=613` to count 176 rows. It is an evaluation-order change only; the migration **proves** semantics are unchanged by diffing the md5 of every visible row id, for all 11 users × 12 tables, before and after (identical). Gain is real but modest (~35 ms → ~21 ms on a single policy) — the round-trips dominate.
- **The data layer is NOT the source of the page-to-page lag.** Server 2–16 ms, one query ~55–68 ms. What is left is Flutter's **Debug build**: unlike the Dart database code (only ~25% slower in JIT), Flutter's *rendering* in Debug is far slower than Release, and first-visit-per-screen cost is its classic symptom. Test with a Release build before optimising anything else.
- ⚠️ **`postgres/63_server_tuning.conf` has NEVER been applied.** Live runs defaults: `max_connections = 100`, `shared_buffers = 128 MB`. The app opens a pool of **3 connections per instance**, so **~33 concurrent app instances** exhausts the server. The dev laptop is a TEMPORARY test host — do not tune it. The real server is a separate office PC (i5 14th gen, 16 GB RAM, 256 GB NVMe + 2 TB drive, Windows), and `63_server_tuning.conf` is now sized for exactly that: `max_connections = 200` (≈66 PCs at `PG_POOL_SIZE=3` + 1 LISTEN), `shared_buffers = 4 GB`, `effective_cache_size = 12 GB`, `work_mem = 8 MB`. ⚠️ `random_page_cost`/`effective_io_concurrency` are set for **PGDATA on the NVMe**; if the data directory goes on the spinning 2 TB drive both must change together (3.0 / 2) or the planner picks index scans that make queries slower.

- 🔴 **The yard leak users actually SAW was in memory, not in the database.** Riverpod caches a `FutureProvider`'s value for the life of its container and **none of the ~100 data providers are `autoDispose`**. Signing out cleared only `currentProfileProvider`, so the previous officer's packages/warehouses/disposition rows stayed cached and rendered under the next person's name. The DB was scoping correctly the whole time — which is why psql AND a database-level integration test both passed while the screen showed another yard. **A DB-level test cannot prove this class of bug; only the running app can.**
- The fix is [lib/core/session_reset.dart](lib/core/session_reset.dart): `AuthService.signOut()` calls `clearCachedSessionData()`, which bumps `sessionEpoch`; `main.dart` keys the `ProviderScope` on it, so the whole container is dropped and a new session starts empty **by construction**. Invalidating providers one by one was rejected deliberately — with ~100 of them, the first one added later without touching the list silently restores the leak. The bump is deferred one frame because callers still touch the live container (clearing the profile, navigating) right after `signOut()`.
- ⚠️ Reset on sign-OUT only, never on a failed sign-in: the login screens call `supabase.auth.signOut()` directly for rejections (wrong portal, disabled account) and then write the error message through `ref` — resetting there would discard the message the user needs to read.
- ⚠️ **`AppSession.clear()` used to reset `currentYard` to `kDefaultYardCode`, which is `'GL1'`** — so a signed-out session silently *claimed to be GL1*, and any yard filter or yard stamp running before the next profile loaded said GL1. Now cleared to `''`; the filter builders already skip an empty yard and fall through to the database's own policies, and a write with an empty yard is rejected by RLS rather than landing in GL1.
- **`test/yard_leak_integration_test.dart` signs in as real users through the real stack** and asserts what each sees. `psql` alone cannot catch a client-side leak (a stale pooled session, a Dart filter), which is why a psql-only check once reported a fix that the app did not actually have. Run it against a scratch copy: `flutter test test/yard_leak_integration_test.dart --dart-define=PG_DATABASE=<copy>` after setting a known bcrypt password on the test users. It also covers user-switching, which is where a pooled session would leak.
- ⚠️ **A yard's warehouses come from `warehouses.yard`, never from `warehouse_entries`.** The old `warehousesForYardProvider` derived it from entries, which cannot place a NEW warehouse: it only appeared once goods were stored in it, and goods cannot be stored in a warehouse the picker does not offer. `getWarehouseIdsForYard()` existed only for that and is gone.
- A yard with no warehouses now correctly shows the **empty state** on both Warehouses and Zone Capacity, telling the officer to add one in the Admin Panel. `addWarehouse()` stamps `AppSession.currentYard`; the RLS write policy rejects an insert into another yard.
- Zone Capacity showed **"Unknown"** for warehouse names because they came only from `zone_occupancy_entries`, which is filtered to stored goods — so an empty warehouse contributed no name. Names now come from `getWarehouses()`.
- `warehouse_contents` was the one view [003](migrations/003_database_yard_isolation.sql) missed: no `security_invoker`, so it ran as its owner and leaked every yard's stock to any authenticated caller. Nothing queries it, which is why it went unnoticed; 008 sets the flag.
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
- ⚠️ **Running SEVERAL copies at once**: `.\tool\run_instance.ps1 [name]` ([run_instance.ps1](tool/run_instance.ps1)). A plain `flutter run` **closes the app already running in your other terminals** — every run links the same `build\windows\x64\runner\Debug\cus_yard_management.exe`, Windows locks a running exe, and Flutter frees the lock by terminating the app it launched before. (It only began happening once the app stopped crashing at startup: before that, no live exe held the lock.) Flutter's build dir is settable ONLY as a per-user setting (`flutter config --build-dir`, read from `%APPDATA%\.flutter_settings`) — there is no `flutter run --build-dir` flag, so setting it would just move the collision. The script instead points **`%APPDATA%` (a per-PROCESS variable) at a private folder for that terminal only** and writes a `build-dir` into the settings file there, so each terminal links its own exe and no run evicts another. Slots live in `.flutter-instances/<name>/` (gitignored); `-Clean` drops them all. The global config is never touched.
un_instance.ps1 [name]` ([run_instance.ps1](tool/run_instance.ps1)). A plain `flutter run` **closes the app already running in your other terminals** — every run links the same `build\windowsd
unner\Debug\cus_yard_management.exe`, Windows locks a running exe, and Flutter frees the lock by terminating the app it launched before. (It only began happening once the app stopped crashing at startup: before that, no live exe held the lock.) Flutter's build dir is settable ONLY as a per-user setting (`flutter config --build-dir`, read from `%APPDATA%\.flutter_settings`) — there is no `flutter run --build-dir` flag, so setting it would just move the collision. The script instead points **`%APPDATA%` (a per-PROCESS variable) at a private folder for that terminal only** and writes a `build-dir` into the settings file there, so each terminal links its own exe and no run evicts another. Slots live in `.flutter-instances/<name>/` (gitignored); `-Clean` drops them all. The global config is never touched.
- Analyze (lint/type): `flutter analyze`
- Test: `flutter test`
- Codegen (riverpod_generator): `dart run build_runner build --delete-conflicting-outputs` (most providers are hand-written, so rarely needed)
- Production: `flutter build windows` → output `build/windows/x64/runner/Release/`
- Windows installer: Inno Setup script (added in git history; see repo root if present).
- Release/auto-update: bump `pubspec` version → build → Inno Setup `.exe` → update + upload [updates/appcast.xml](updates/appcast.xml) and the `.exe` to the public `updates` bucket. Full steps: [updates/README.md](updates/README.md).

## Important Configuration
- **Supabase creds**: hardcoded in [lib/core/db_client.dart](lib/core/db_client.dart) (`supabaseUrl`, `supabaseAnonKey`). **No env vars / .env**. Change here to point to another project.
- ⚠️ **Start-up never dies on a dead database** ([main.dart](lib/main.dart)). `supabase.initialize()` used to be a bare `await` after `windowManager.show()` + `setPreventClose(true)`, so an unreachable server threw before `runApp()` — the user got a **blank white window that could not even be closed**. It is now caught and rendered as `DatabaseUnavailableApp`: names the target server (`databaseDescription`), the likely cause, the raw error, plus **Try again** (re-runs `initialize()`, swaps in the real app on success) and **Exit** (`exit(0)` — the only way out given `setPreventClose`). Keep that shape for any future start-up work. Note the `port=NNNNN` in a `SocketException` is the LOCAL ephemeral port, not the target.
- ⚠️ **Global exception handling** ([error_handling.dart](lib/core/error_handling.dart), installed from [main.dart](lib/main.dart)). Before this the app had NO global handler: a build error painted Flutter grey box in release, an async error vanished silently, and nothing was ever written down — on a desktop app whose users have no console. `AppErrorHandler` installs four things, in this order: `guard()` wraps ALL of main (incl. `runApp`, which must be inside the same zone or widget async errors escape), `FlutterError.onError` (build/layout/paint/gesture), `PlatformDispatcher.instance.onError` (returns true so the isolate survives), and `ErrorWidget.builder` (custom screen in release, Flutter red screen kept in debug). Every error is appended to `%APPDATA%/com.example/cus_yard_management/logs/crash.log` (rolls at 2MB, keeps `.1`; identical signatures suppressed after 5 to stop a per-frame build failure filling the disk) and kept in `AppErrorHandler.recent`. **Verified end-to-end** with a temporary async-throw probe: the app stayed running and a full timestamped stack landed in the log. Tests: [error_handling_test.dart](test/error_handling_test.dart).
- ⚠️ **The schema could NOT be built from scratch until 2026-08-30.** It only ever ran against a Supabase project that already had things the repo never wrote down. Six real bugs, all fixed at source: (1) **four tables were never CREATEd anywhere** — `package_categories`, `hold_reasons`, `audit_logs`, `storage_rates` — made by hand in the dashboard, so `schema.sql` only ALTERed them; definitions reconstructed in [db/schema.sql](db/schema.sql) from the models that read them. (2) unguarded `ADD COLUMN` — the base schema and early migrations add the same columns, so it failed on a FIRST run. (3) unguarded `CREATE TRIGGER` (no IF NOT EXISTS in Postgres — needs an explicit DROP). (4) **same-day migrations sort by filename, not dependency**: `20260611_taxes_and_delivery` ALTERs the table `20260611_tender_sale_items` creates, and `20260625_autofill_package_item` reads a column `20260625_destruction_per_di_item` adds — pinned via `EARLY` in [build_schema.py](postgres/build_schema.py). (5) `migrations/001_multi_yard.sql` lives outside `db/migrations` and the README said run it AFTER, but `20260620_seed_data.sql` inserts rows carrying a `yard` value — now folded in ahead of it (002 folded in last, since it locks RLS down). (6) a stray `r` on its own line in [20260714_old_sr_number.sql](db/migrations/20260714_old_sr_number.sql). Also: `build_schema.py`'s ON-CONFLICT rewrite was appending to INSERTs **inside function bodies** (breaking them, and silently swallowing writes) — now applied only outside `$$…$$`; and `04_auth.sql`'s self-test signed up with a fake `role:probe` that `profiles_role_check` rejects. **Verified**: a from-scratch build of all four files now runs clean, 32 tables, and the app connects.
- **Runtime config lives in `.env`** ([app_env.dart](lib/core/app_env.dart), 2026-08-30). Precedence, first match wins: **`--dart-define`** (build-time, so every existing deployment behaves exactly as before) -> **`.env`** beside the `.exe`, else the project root -> the compiled-in default. Covers `PG_HOST/PORT/DATABASE/USER/PASSWORD/SSL/SSL_VERIFY/CONNECT_TIMEOUT/QUERY_TIMEOUT` and `GMAIL_USER/APP_PASSWORD/FROM_NAME`. [.env.example](.env.example) is the committed template (`.gitignore` has `!.env.example` so the `.env.*` rule does not swallow it); `.env` itself is ignored. Uses the `dotenv` package, NOT `flutter_dotenv` -- the latter bundles the file as an asset INSIDE the binary, which defeats the point. Because `String.fromEnvironment` is only const-folded, each define is read into a private `_xDefine` const and handed to `AppEnv`; the config fields became getters, so nothing is `const` any more. ⚠️ **A `.env` on a desktop app is not a secret store** -- it ships to the user's machine and opens in Notepad; its real value is keeping credentials out of the source tree. Tests: [app_env_test.dart](test/app_env_test.dart) (verified by mutating the file and watching the values change).
- ⚠️ **A real Gmail App Password is in git history** (commit `875e445`, `lib/core/otp_config.dart`). The hard-coded defaults are now gone -- the Gmail values resolve to empty unless `.env` supplies them, so `kGmailConfigured` is false and the app says e-mail is unconfigured rather than silently using the old account. **That password should be revoked in the Google account**; removing it from the file does not remove it from history.
- **Supabase data was migrated to the local PostgreSQL** (2026-08-30): 1,198 rows across 22 tables + 11 `auth.users` accounts (packages 71, package_items 101, warehouse_entries 112, audit_logs 112, tender_bids 176, forfeited_packages 63, profiles 10). Every existing password came across verbatim in `encrypted_password`, so all accounts still sign in. Notes for any future re-run: (1) Supabase's **direct host `db.<ref>.supabase.co` is IPv6-only** — unreachable from an IPv4-only network; use the **session pooler** (`aws-1-ap-southeast-2.pooler.supabase.com:5432`, user `postgres.<ref>`) which answers on IPv4. (2) **Data only** — the local schema is AHEAD of Supabase, so never restore its schema over this one. (3) **Disable `on_auth_user_created` during the load**, or it invents a profiles row per account and the real ones fail with `duplicate key ... profiles_pkey`. (4) Supabase's `auth.users` has 35 columns to our compat layer's 8; copy just the shared 8 rather than widening the table. (5) The live shapes corrected two guesses in [schema.sql](db/schema.sql): `hold_reasons` keys on **`reason_text`** (not `name`) and `package_categories` has a `description`.
- ⚠️ **Type-cast bugs at the Supabase→PostgreSQL seam** (all fixed 2026-08-30, and all of them threw at RUNTIME with nothing caught at compile time). Supabase returned JSON, so every value arrived as a String/num; the local driver returns native types. Three families: (a) **timestamps** come back as `DateTime`, so `json['x'] as String` threw — 29 sites in models.dart now use `parseDbDate` / `parseDbDateRequired`, plus 3 in services.dart; (b) **`numeric` comes back as a String** (the driver preserves precision), so `as num?` threw — 28 sites now use `parseDbNum` / `parseDbInt`; (c) `return data.map((e) => X.fromJson(e)).toList()` infers `List<dynamic>` because `data` is dynamic, throwing `List<dynamic> is not a subtype of FutureOr<List<X>>` — 9 sites rewritten as typed collection-for. **When adding any new model or query, use the helpers; a plain cast will compile and then fail on first use.**
- ⚠️ **"Logged in successfully" then bounced back to the portal picker** — FIXED 2026-08-30. `auth.sign_in()` returned only `(id, email, meta)`, so `AuthUser.emailConfirmedAt` was ALWAYS null. The router's first guard calls `AuthService.verifyUserSession()`, which signs the user out and throws `email_not_confirmed` on a null value, and the router turns that into `return '/'` — so every login succeeded, showed its success toast, and redirected straight back to the portal picker. The password, the profile and the RLS were all fine; the function simply never reported the column. Fixed by returning `email_confirmed_at` from `auth.sign_in`, `auth.sign_up` and `auth.user_by_id` ([04_auth.sql](postgres/04_auth.sql)) and selecting it in [pg_auth.dart](lib/core/db/pg_auth.dart). ⚠️ Those three are now `drop function`-ed before creation — **CREATE OR REPLACE cannot change a function's return type**, so without the drop a re-run against an older database fails with "cannot change return type of existing function". **When adding a field the app gates on, check every compat function that produces an AuthUser.**
- ⚠️ **Filters on an EMBEDDED table** (`\.eq('profiles.role', ...)`) — FIXED 2026-08-30. PostgREST allowed a filter to name a column on an embed, and `AuditLogService.getAllLogs` relies on it (it keeps only rows whose ACTOR is yard staff). The local builder quoted the whole thing as one identifier, emitting `t."profiles.role"` → `column t.profiles.role does not exist` — which the dashboard surfaced as **"Couldn't load some data — check your internet connection"**, sending the user to look at the network for a SQL bug. Now rendered as a correlated `exists (select 1 from "profiles" f0 where f0."id" = t."user_id" and ...)`. `_resolveJoin`/`_joinOn` were factored out of `_embed` so both paths agree on the foreign key. A dotted name that is NOT a selected embed stays a plain column. Regression tests in [pg_query_sql_test.dart](test/pg_query_sql_test.dart) (verified: they fail on the old code).
- **Mojibake in two source files** — FIXED 2026-08-30. `lib/screens/admin/admin_dashboard_screen.dart` and `lib/screens/packages/packages_screen.dart` had UTF-8 that had been decoded as Latin-1 and re-saved: `—` stored as `Ã¢â‚¬"`, `…` as `Ã¢â‚¬Â¦`, `·` as `Ã‚Â·`, `─` as `Ã¢â€â‚¬`. It showed on screen wherever those literals rendered (the dashboard's storage-rate placeholder, the "—" empty-cell dashes). 220 sequences repaired. Pre-existing, committed in `dc6674a`. If it recurs, check the editor is saving UTF-8.
- ⚠️ **`or()` with a NESTED `and(...)`/`or(...)` group** — FIXED 2026-08-30. `ForfeitedPackageService.getInAppealNonForfeitPackages` asks for `entry_date.gte.X,and(entry_date.is.null,created_at.gte.X)`. `_splitTopLevel` kept the group together, but the loop then split every term on `.` — so the group became the column `and(entry_date` and the SQL died with `syntax error at or near "$2"`, which the Appeal portal showed as "Something went wrong". `or()` now calls a recursive `_parseGroup` that handles nested groups, `is.null` (inlined as syntax, since `col is @p` does not parse), `in.(a,b)` and `not.`. Regression tests in [pg_query_sql_test.dart](test/pg_query_sql_test.dart).
- ⚠️ **Error messages now name the REAL cause** ([error_view.dart](lib/widgets/error_view.dart), and the dashboard's `_ConnectionBanner`) — FIXED 2026-08-30. The shared panel called anything whose text contained "connection" a network failure and printed **"check your internet connection"**, so every SQL bug sent people to look at their router; it also rendered the message as `error.toString().split(':').last`, throwing away everything before the last colon (the SQLSTATE included). It now classifies into **network / database / permission / unknown** — Postgres signals (`Severity.error`, a SQLSTATE, "does not exist", "is not a subtype", "syntax error") are checked BEFORE the network branch, precisely because their text often contains the word "connection" — and shows the full message in a selectable monospace box so it can be copied to ICT. Tests: [error_view_test.dart](test/error_view_test.dart) (verified: 7 of 9 fail on the old widget).
- **How to find these fast**: a temporary probe test that resolves everything against the real database and prints each failure with its true message. ⚠️ Probe **BOTH LAYERS** — a services-only probe passed while three screens still failed, because those screens read through PROVIDERS and the broken cast lived in the provider body (`storageRateProvider` parsing `effective_from`). The provider probe generates its list from `grep`ping `providers.dart` for non-family `FutureProvider`s, so nothing is missed (57 of them). Two harness notes: give each read its own `.timeout(...)` so one hang cannot hide the rest, and **resolve the `*ChangeTrigger` StreamProviders first** — every list provider `ref.watch`es one, which SUSPENDS until the stream yields; in the app realtime connects and it resolves, in a bare `ProviderContainer` it looks like a hang. With those warmed, all 57 resolve.
- **ICT portal UI aligned with the other directorates** (2026-08-30):
  - **Accent is now deep plum `0xFF8E3A5F`** (constant still named `AppTheme.ictCyan`, so nothing else needed touching). Three rejected attempts, all recorded in the theme comment: cyan `0xFF0097A7` was indistinguishable from Top Management's teal; bright indigo `0xFF4A3AFF` was far too vivid as a header wash; slate indigo `0xFF3F51B5` was still BLUE, and the app already has two (customsBlue, teal). Hues already taken are 37/42 (golds), 123 (green), 185 (teal), 242 (blue), 282 (purple) — **334 was the clear gap**. Reds were the alternative but every candidate collided with the error red `0xFFD32F2F`. [home_card_layout_test.dart](test/home_card_layout_test.dart) now guards all three constraints: distance from every portal accent, distance from the error red, and **not blue-dominant** (verified: the slate-indigo attempt fails that assertion).
  - Header uses the **Customs emblem** (flat `colorFilter` tint) instead of a terminal glyph, the "User Management & Provisioning" pill is gone, and the padding/wash match Central Disposal exactly (24/16, 0.08).
  - Tab strip rebuilt as the same rounded, bordered panel the others use (`surfaceDark`, radius 12, inset 20/10), with the same 44px indicator (0.15 fill / 0.5 border / radius 9).
  - **Shared components adopted** so the portal stops looking bespoke: the filter dropdowns are now `StyledDropdownFormField` (the paged popup, via a local `_IctFilter` mirroring Central Disposal's `YardAllFilter`); the search box matches `DisposalSearch` (14px radius, accent prefix icon, dense 13px); the Add button dropped its custom 20/16 padding + r10 for the theme default; both tables use `fixedTopRows: 1` with a `surfaceDark` heading (12/16 spacing), and the Yards & Directorates table header moved from `scaffoldBg` to `surfaceDark`.
  - **The profile pill was DEAD** — a static badge, so ICT officers had no way to open their profile or change their password. It is now the same clickable pill the others use, opening the shared `DisposalProfileDialog(accent:)`, including the amber/red password-expiry dot.
  - **Dialogs**: every ICT form now passes `headerAccentColor` (they fell back to GOLD — Central Disposal's colour — on an ICT form) and `barrierDismissible` is back to true, so clicking outside closes them as it does everywhere else.
  - ⚠️ **Table corners need a `ClipRRect`, not just a `borderRadius`.** Central Disposal's `_listCard` wraps its table in one; without it the rows paint straight over the container's rounded corners and they read as square. ICT had no ClipRRect at all — both its tables now do (radius 13 inside a 14 border).
  - **Yards & Directorates page** was visibly off-scale: section titles 16px where every other page uses 22, page padding 28 vs 24, table headers 10.5px vs the 12.5px every DataTable2 uses, and a 22px on/off toggle that read smaller than the pencil beside it (now 30px). Its action button also moved from `FilledButton` to the `ElevatedButton` + white label the others use.
  - **The Create/Edit Staff DIALOG's dropdowns** were the last plain ones: Account Role had no `isExpanded` (its longest item, "DC / SDDC (Yard Admin)", overflowed the row by 49px) and `_DirectorateField`/`_YardField` opened the grey Material menu. All three now go through a local `_IctDialogDropdown` wrapping `StyledDropdownFormField`. ⚠️ `accent` is a local in `build()`, so inside a dialog builder use `AppTheme.ictCyan` directly. Tests cover the dialog row down to 340px.
  - **Sign Out** was a bare `IconButton` calling `supabase.auth.signOut()` directly — it skipped `AuthService.signOut()`'s bookkeeping (audit log, presence). Now the same labelled `OutlinedButton` + `authServiceProvider` the others use.
  - **Table headers are Title Case**, matching every DataTable2 in the app ("SR Number", "Goods Name"). The staff table shouted them; the Yards & Directorates shell called `.toUpperCase()`. Its Actions column was also unnamed, and its rows were padding-driven — now `minHeight: 52`, matching `dataRowHeight`.
  - **The section-header icon** sat above its title: `CrossAxisAlignment.start` aligned it to the top of a two-line block (title + subtitle). A 3px top pad puts it on the title's line.
  - **Shared account cells** ([account_cells.dart](lib/widgets/account_cells.dart)): `ExpiresInCell`, `AccountStatusChip` and `RowActionButtons` were lifted out of `admin_screen.dart`, where they were private — which is exactly why ICT grew plainer copies (a grey ACTIVE pill, no expiry column at all). Both screens now render the same widgets, and the ICT staff table gained the **Disables In** column it was missing. `RowActionButtons` matches the Admin Panel's `_tableActionButton` exactly (6px padding, 15px icon, 0.1 fill + 0.25 border, radius 6).
  - **`numeric: true` right-aligns a DataColumn2's HEADER**, which is why "Actions" floated far from the buttons beneath it. Use a `fixedWidth` and let the cell align its own contents.
  - ⚠️ **The tab strip is a real `TabBar`, not a hand-rolled one.** The custom `_IctTabBar`/`_IctTab` painted a plain `Container` per tab, so the highlight SNAPPED — and showed nothing at all mid-swipe. A real TabBar drives its indicator from the controller's `animation`, so it slides with the drag. Both custom widgets were deleted (101 lines). [tab_swipe_test.dart](test/tab_swipe_test.dart) asserts the animation value is strictly between 0 and 1 half-way through a transition, which the snapping version could never produce.
  - **The ICT tabs are now SWIPEABLE.** They swapped bodies with `if (_tab == 1) ... else ...`, so the only way between the two pages was tapping the strip. Now a `TabController` + `TabBarView` (what Central Disposal uses), which brings horizontal drag for free; the custom strip drives the controller with `animateTo` and follows it through a listener. Tests: [tab_swipe_test.dart](test/tab_swipe_test.dart). ⚠️ A REVERSE drag does not settle reliably in the test harness (velocity), so the back direction is asserted through the controller — testing the forward drag and the strip is what actually covers the app.
  - The Yards & Directorates **status** was still a bare dot + "Active"/"Off" while the staff tables used a bordered chip; it now renders the same ACTIVE/INACTIVE chip.
  - ⚠️ **The filter-row overflow needed `isExpanded: true`, not `Flexible`.** A `DropdownButtonFormField` reports an intrinsic width from its label, prefix icon and longest menu item, and `Flexible` only lets a child shrink if the child agrees to — so wrapping alone left a 445px overflow. Regression test: [ict_filter_row_test.dart](test/ict_filter_row_test.dart), 1900→1000px (verified: all five fail without `isExpanded`).
- **Portal picker "Create Account" was cropped** ([home_screen.dart](lib/screens/home/home_screen.dart)): the label wrapped inside its fixed 42px box, so the second line was clipped and the button read "Create". Now a `FittedBox` + `maxLines: 1`, verified down to 100px wide.
- **Enter submits on every auth field, in every portal** (2026-08-31). Coverage was uneven — some OTP boxes verified on Enter, the admin and officer sign-ups did not, and most credential fields needed the mouse. 42 fields across 14 screens now carry `onFieldSubmitted`. ⚠️ The submit method is NOT uniformly named: Appeal/Disposal/Executive/Valuation logins use `_continue()`, ICT uses `_submitLogin()` + `_submitPasswordChange()`, the yard login uses `_signIn()` and has no `_isLoading` field at all (it reads a provider). [enter_submits_test.dart](test/enter_submits_test.dart) scans the real screens, so a new portal added without keyboard submit fails the suite by file and line (verified by deleting one handler). `lib/screens/auth/signup_screen.dart` is skipped — it is dead code, nothing imports or routes it.
- **Sold Goods' Tender History loaded late — in the YARD only** (2026-08-31). `TenderHistorySection` derived a package's rounds by filtering **`tenderSalesProvider`**, which fetches EVERY tender sale joined down through items → packages → package_items → warehouse_entries (measured on the live DB: 389 rows, **~122ms**). Central Disposal's Tender Sales tab had already cached that, so its popup was instant — which is exactly why the delay looked screen-specific. The yard's Sold Goods page never loads it, so every popup paid the cold fetch and the section popped in after the rest of the dialog.
  - New `getTenderRoundsForPackage(fpId)` + `tenderRoundsForPackageProvider` fetch ONE package's rounds — just `(id, createdAt)`, which is all the round numbering ("Valuation Tender" / "Tender 1" / …) needs. Measured **~11ms**.
  - `_SaleValuationCell` **warms** `tenderRoundsForPackageProvider` + `tenderBidsProvider` while the table is on screen. It already resolves the forfeited package per row, so the reads are free there and the history is ready on click rather than starting to load then.
  - ⚠️ General lesson: a whole-table provider feels instant on whichever screen happens to have cached it already. [tender_history_load_test.dart](test/tender_history_load_test.dart) pins the per-package query and the warming (verified by restoring the old path: the suite goes red).
- ⚠️ **The Tender Committees pool is EXACTLY 4 rounds, never `>= 4`** (2026-08-31). A package belongs there from the moment the Valuation Tender + Tenders 1-3 have all failed until **Central Disposal re-tenders it** at the committee's price. That re-tender creates a **5th** round, and the package leaves **for good** — to **Sold**, or to the DG's **Unsold Goods** when that round fails too. `>= 4` kept 5-round packages listed, so the same goods appeared on the Tender Committees tab AND the DG's Unsold Goods tab at once (Wash Basins, Toilet Seat Covers, Newsprint Reels, Kraft Paper Reels). Now `tenderCount == kMaxBidTenderRounds + 1`.
  - ⚠️ The old `!c.isSubmitted` row filter was **hiding this by accident** — every 5-round package happens to be ADG-submitted, so removing that filter (correctly) exposed the real bug underneath.
- **A submitted package now STAYS on the Tender Committees tab** (2026-08-31). The tab filtered `c == null || !c.isSubmitted`, so a package vanished the moment the ADG submitted — the finished committee work disappeared and the two tables disagreed on how many committee cases there were. The cell **already had** a submitted state (green, `verified_rounded`, the amount + a **"Final"** label); it simply never rendered. A package now leaves on its own once its committee-priced tender has been held and failed, at which point it is exhausted and moves to the DG's Unsold Goods tab.
- **The ADG's committee submission had the SAME bug** (2026-08-31). `submitCommitteeValuation` wrote the figure to `round.id` — the round just held — which (a) overwrote that round's own reserve and (b) left **no pending row**, so the package showed **"Committee valued" forever** in Unsold while **vanishing from the Tender Committees table** (the ADG's work there was done). That is the "2 in Unsold, 1 in Committees" mismatch. It now passes `round.saleTimePassed ? null : round.id`, the same rule as the Valuation Directorate's dialog, and invalidates `reTenderEligibleProvider` + `valuedCurrentRoundProvider`.
  - **Data repaired**: Machine-made carpet rolls' round R044 had its reserve overwritten (**425.60 → 465.50**). The seed steps down by 12% of the original each round (665 → 585.20 → 505.40 → 425.60, and Basin Mixer Taps confirms it exactly: 5200 → 4576 → 3952 → 3328), so R044 was set back to **425.60** and the committee's **465.50** moved to a **pending** row.
- ⚠️ **"This round has a valuation" ≠ "the next round is priced"** (2026-08-31) — the distinction five separate checks got wrong. Under [[the valuation chain]] **every held round has its own reserve**, so `revals[currentRound] != null` is always true for a package in the unsold pool and says nothing about whether the Valuation Directorate has done its next job. Only the **PENDING** row (`revals['']`) means "the next round is priced". Fixed in all five:
  - `_issued` in the valuation dialog — was falling back to the current round's reserve, so the dialog read **"Valuation set"** and hid Save before anything had been entered for Tender 3.
  - The Valuation Directorate's table cell — showed a green amount for packages it still owed a figure for.
  - `getValuedCurrentRoundIds` — marked every package valued, hiding **Set Value** everywhere.
  - The Re-valuation **chip** — read "Re-valued" for packages nobody had re-valued.
  - `_currentRoundLocked` in Record Bids — a round's own reserve exists **before** any bid is recorded against it, so locking on it stopped Central Disposal entering that round's bids at all. Bids close only once the VD has priced the next round **from** them.
- **Disposal Requests' valuation is sealed unconditionally** (2026-09-01). `getDisposalRequests()` already excludes any package placed in a `tender_sale_items` row, so a row on this screen has, BY DEFINITION, no scheduled sale to check `saleEnded` against yet — the figure is still the reserve price for whichever tender it eventually joins. The old "Disposal Requests is exempt" carve-out in the leak-sweep test is gone; the table cell and popup both seal unconditionally now.
- **The yard's own read-only "Value" column is also sealed, and renamed to "Latest Valuation"** — `TenderSaleCard`'s `useItemValue` branch (`disposal_dashboard_screen.dart`) shows the SR item's own declared value, a DIFFERENT figure from the Valuation Directorate's reserve, but it is equally commercially sensitive to a bidder (confirmed: Distress Flares showed unit_value 1,900 × 120 = 228,000, matching the screenshot exactly). It now shares the same `sealedUntilSale` gate and the same column name as Central Disposal's card, on both the Tender Sale and Destruction Sale cards.
  Its figure also now carries the same **`@ unit × qty`** breakdown Central Disposal's column already shows (`LKR 228,000` over `@ 1,900 × 120`), not a bare total — the yard's version had read as a plainer, less detailed KIND of number instead of the same shape.
- **Sale End Time layout fixed** (2026-08-31) — a leftover partial edit had **duplicated** the field in the Tender Sale form (two identical rows, one with an empty slot beside it) while leaving the **Destruction Sale form without one at all**, despite its state field, validation and submit code all existing. Both forms are now **Date+Start / End+Serial / Year** — balanced two-per-row, matching the New **and** Re-tender/Re-destruction dialogs (they share the same form).
- ⚠️ **The seal lifts at the sale's END, not its start** (2026-08-31). Sealing on `saleTimePassed` (the START) unsealed the reserve price at exactly the wrong moment — the instant bidding opened. New column **`sale_end_time`** on `tender_sales` and `destructions` ([20260841_sale_end_time.sql](db/migrations/20260841_sale_end_time.sql)), plus `saleEndMoment` / **`saleEnded`** on both models.
  - **`saleEndMoment` falls back to `saleMoment`** when no end time was recorded, so rows created before the column behave exactly as they did.
  - All **23** sealing / "has this round run" checks moved to `saleEnded`; **Mark Sold and Mark Destroyed deliberately stay on `saleTimePassed`** — you may sell once the sale has opened.
  - Both dialogs (which serve New **and** Re-tender / Re-destruction — 4 forms) now take a **Sale End Time**, required and validated to be after the start; an end at or before the start would unseal the figure immediately.
  - The Tender Sales and Destruction Sales cards' column is now **"Latest Valuation"** (145px) and seals like the Unsold table. The yard's read-only view still says **"Value"** — that is the SR item's own declared figure, a different number.
- ⚠️ **THE VALUATION CHAIN** (2026-08-31, stated by the user) — the rule the whole tender flow hangs on:
  > A round is **held at its own valuation**. Its bids come in against that figure. Those bids then decide the price of the **NEXT** round.
- **The Tender Sale card's details popup now carries the Tender History block** too (2026-09-01) — previously only the Unsold Tenders popup passed `tenderHistoryFor`, so the live sale's own popup had no way to show the per-round chain that led to the current price. Passed for **both** the yard and directorate views now, since the old `readOnly ? null : ...` gate hid the number from the popup while the yard's own table column already showed the same figure — hiding it one way and not the other protected nothing. Sealing (`valuationSealedUntilSale: !widget.sale.saleEnded` + each history round's own per-round seal) is what actually protects the reserve price, not omission.


  So round 1 runs at the **original** valuation (`disposal_request_items.valuation_cost`) and has **no** `tender_revaluations` row; round 2's figure is decided from round 1's bids; round 3's from round 2's; and so on. **Invariant: any round with bids must have a valuation, except round 1.**
  - The Valuation Directorate's "New Valuation" panel was titled with the round whose bids were listed, so a figure for **Tender 3** read as "Tender 2 · New Valuation". It now names the round it **prices**: `_valuedRoundIndex = _current.saleTimePassed ? _rounds.length + 1 : _rounds.length` — the next round once the current one has been held, or that round directly if Central Disposal has already scheduled it. Same condition as the pending-vs-round storage, so the label and the write can never disagree.
- ⚠️ **A `tender_revaluations` row is the RESERVE PRICE OF THE ROUND IT IS KEYED TO** (2026-08-31) — settled with live data after I briefly got this backwards. SR/37/2025, Pipe Tees, qty 180:

  | round | reserve | best bid | outcome |
  |---|---|---|---|
  | 1 | 820 × 180 = 147,600 | 110,700 | unsold |
  | 2 | 738 × 180 = 132,840 | 103,320 | unsold |
  | 3 | 656 × 180 = 118,080 | 95,940 | unsold |
  | 4 | 574 × 180 = 103,320 | **174,168** | **SOLD** |

  Every round's bids sit below its OWN figure and the round whose bid finally cleared it is the one that sold. I had read it as "the price for the NEXT round" and shifted every price by one, which printed each figure against the wrong tender, invented a phantom "next round" tile, and sealed **sold** goods. Round 1 has no re-valuation — it runs at the original valuation; the committee round runs at the ADG's submitted value.
- **The shared Unsold table showed the committee's RECOMMENDATION, not the submitted price** (2026-08-31). `unsoldCells` (yard + Central Disposal + Top Management) took `committees[..]?.committeeValue`. A recorded committee figure with **no ADG submission** is a reserve price that has not been tendered — printing it leaks it. All three now pass **`submittedValue`**, the price the package was actually offered at. (Harmless in today's data — where both exist they are equal, and every row comes from `exhaustedUnsoldProvider`, which already requires the submission — but the fallback was a live trap.) Its seal now orders rounds by the **sale moment** too; `ReTenderSaleInfo.latestSale` is newest-by-`created_at`, and the two can disagree.
- ⚠️ **Setting a new valuation OVERWROTE the round it was decided from** (2026-08-31) — a data-integrity bug, not just a display one. `saveTenderRevaluation` deleted+inserted on `(forfeited_package_id, tender_sale_id)` with the **newest** round, so a figure entered after that round had run replaced the price it actually went to tender at. Live damage: CED/GL1/SR/20/2026 round **R018** ran at **5,400** (Life Jackets) and **6,800** (Life Buoys) per unit; a new valuation of 5,000 was saved against it and the history then read 5,000 for both — the real prices were gone.
  - `tender_revaluations.tender_sale_id` is **nullable** (and was unused). A new figure is now stored **PENDING** (null round) = "the price for the NEXT tender, not yet placed"; `createTenderSale` **claims** it for the new round on re-tender. `getTenderRevaluationsByRound` already maps a null round to the key `''`.
  - Needed a new `isNull()` in [pg_query.dart](lib/core/db/pg_query.dart) — `eq(col, null)` compiles to `= NULL`, which is never true.
  - Eligibility and the Re-valuation chip both accept a pending row.
- **A pending valuation must take effect in EVERY portal at once** (2026-08-31). Three more readers still missed it:
  - Saving invalidated only `tenderRevaluationsProvider`, but the Valuation Directorate's Set-Value/amount chip reads **`valuedCurrentRoundProvider`** and Central Disposal's re-tender state reads **`reTenderEligibleProvider`** — so the row still read "Set Value" right after saving. All three are invalidated now.
  - `_currentRoundLocked` in Central Disposal's **Record Bids** dialog keyed on the round, so it went on offering "Add bid" / "Save Bids" for a round the Valuation Directorate had already priced. Bids now close on a pending figure too.
  - The sealed next-tender row is **detected inside `TenderHistorySection`** (`revals[''] != null`) instead of being passed by each caller, so **every** popup showing tender history gets it and no caller can forget.
- **Every yard-filter dropdown is now DB-driven, split by directorate for a multi-directorate yard** (2026-09-01). ICT adding/removing a yard, directorate or link in [[yards-directorates-are-db-data]] now shows up everywhere with no rebuild.
  - New `yardFilterOptionsProvider` ([lib/core/providers.dart](lib/core/providers.dart)) labels **EVERY** yard `<DIRECTORATE>/<YARD CODE>` — `CED/GL1`, `CED/RCT`, `PSD/BO` — the same shape as the SR numbers it mints and as ICT's own "Example SR" column, so the picker reads like the number on the goods. A multi-directorate yard (NNR = CED+PSD; Katunayaka/Rathmalana/Mattala = B/A+ACD) becomes ONE ENTRY PER DIRECTORATE; a yard with NO directorate keeps its bare code (`CVT`), matching the unprefixed `CVT/SR/01/2026` it still mints. Verified live: 38 options.
  - ⚠️ Only a MULTI-directorate yard gets a split VALUE (`"<yard>|<dir>"`). A single-directorate yard is labelled `CED/GL1` but keeps the bare value `GL1`: filtering by yard alone is already exact there, and a `"GL1|CED"` value would silently drop the **legacy unprefixed** `GL1/SR/62/2026` rows that pre-date directorates.
  - New `matchesYardFilter(filterValue, rowYard, rowSrNumber)` applies a selection to a row: a plain value matches on `yard` alone; a split value ALSO requires the row's SR-number directorate prefix (via new `directorateOfSrNumber()` in [directorates.dart](lib/core/directorates.dart)) to match — confirmed with the user this, not the physical yard, is the correct split for filtering PACKAGE lists.
  - Every filter call site across Central Disposal, Appeal, Valuation, Executive (Tender Committees / Unsold Goods / Financials) and ICT's own Staff Accounts now goes through one of these two — replacing a direct `.yard == filter` at ~15 sites. A sale/request row filters on **any of its items** matching, not the sale's own yard, since one tender sale can mix items from different directorates at the same multi-directorate yard.
  - ICT's Staff filter is the one exception that does NOT use `matchesYardFilter`: `profiles.directorate` is a direct column, so `getAllYardStaff(yard:, directorate:)` checks it straight rather than parsing an SR number.
  - **Two deliberate non-changes**, both are "which yard to act at/report on", not "which packages to show": `_StyledYardPicker` (create a tender/destruction sale AT yard X) and the Reports screen's yard scope (an executive report at a multi-directorate yard covers ALL of that yard's goods) both moved from `kYards` to the live `yardsProvider` but stay **un-split** — splitting them would have broken the ~48 `_yardArg` call sites that pass a bare yard code straight into a server query.
  - Adding a DB-backed widget to a shared cell/header **breaks any widget test that renders it without stubbing** `yardsProvider`/`directoratesProvider`/`yardDirectoratesProvider` — hit again in `unsold_proposals_tab_test.dart` and `unsold_tab_header_layout_test.dart` (same "Timer still pending" signature as every previous instance of this). [yard_filter_directorate_test.dart](test/yard_filter_directorate_test.dart) pins the split + match logic in isolation.
- ⚠️ **Every reader of a valuation must check the PENDING row too** (2026-08-31). Storing a new figure with a null round hid it from anything keyed on `tender_sale_id`: the **Valuation Directorate's own table** went back to "Set Value" after saving, and `_alreadyValued` stayed false so the Save button allowed a second edit. Fixed with ONE helper, `_issued => _revals[''] ?? _revals[_current.id]`, used by the editor, the lock and the cell; `getValuedCurrentRoundIds` now counts `saleId == null` as valued. **A pending figure is still a set figure** — it just has no round yet.
- **Central Disposal's Record Bids dialog gained a sealed "Valuation Directorate · Next Tender" block** — the mirror of `_committeeValueSection`. It says a valuation exists and withholds it, so Central Disposal knows the package is priced and ready to re-tender without seeing the reserve. Shown only for a **pending** row: a figure keyed to a round belongs to that round and already appears in the history above.
- **"Re-valued" and "Committee valued" mean a price is set for a tender NOT YET HELD**, so both are **sealed** in the table, and the popup's Tender History gains a sealed next-tender row mirroring the committee block. The flag is passed in (`nextTenderValued`) — the figure itself never reaches the widget. **"Awaiting ADG" is NOT sealed**: re-valued but past Tender 3, so it cannot be re-tendered until the committee and ADG act, and its last concluded price is safe to show.
- **One sealing rule: a round's valuation is shown once THAT round has run.** Nothing else. Sold goods seal nothing (tender over, sale done); a scheduled-but-unheld round is sealed; the Unsold table shows the newest round's own figure, sealed only while that round is still to run. [tender_history_seal_test.dart](test/tender_history_seal_test.dart) pins the round→price pairing by asserting each round's **unit** price — totals alone cannot tell a correct mapping from a shifted one (verified: shifting it makes the suite fail).
- ⚠️ **The details popup leaked the NEXT round's price in two more places** (2026-08-31). Both showed a figure for a tender that had not opened yet:
  - **Tender History** rendered EVERY round's valuation, including the committee round the ADG had only just priced. Each round is now gated on its **own** sale moment (`hasRun`, added to `getTenderRoundsForPackage` — from `sale_date`+`sale_time`, never `created_at`). A sealed round **still renders**, showing the sealed notice; dropping it would end the history early and hide that the round exists.
  - **Central Disposal's "Top Management Directorate Committee Valuation" block** showed the committee figure the moment it was recorded. Recording a value — or even the ADG submitting it — is NOT the same as having tendered at it, so it now waits for a round that ran after the submission, and says which of the two waits it is in.
  - The Unsold table's Valuation column shows the price of the **last round that actually RAN** (the latest concluded valuation), with the pending next-round price withheld — not the first valuation.
- ⚠️ **Two bugs found by walking the workflow** (2026-08-31).
  - **A package could get STUCK at 5 rounds and never reach the DG.** `getExhaustedUnsoldPackages` asked `s.createdAt.isAfter(submittedAt)` — but `created_at` is when the sale ROW was inserted, not when the tender ran, and **two packages can share one sale row**. Live proof: Toilet Seat Covers and Wash Basins both sat in round F01 (one row, created 08-17 04:25, scheduled 08-19). Wash Basins submitted at 03:25 → passed; Toilet Seat Covers submitted at 18:31 → failed, so it stayed on Unsold Tenders showing "5×" forever. Now keyed on the **sale MOMENT**: `moment.isAfter(submittedAt) && s.saleTimePassed`. Verified against the DB — exactly one package flips, nothing else moves.
  - **"Re-valued" / "Committee valued" leaked the NEXT round's price.** Those chips mean a new valuation is already set for the round about to be tendered; that round has no date yet, so the open-round seal did not fire and the figure showed beside the chip. Now a new valuation with no scheduled round counts as **pending** and is withheld — but the cell shows the price the package was **last actually tendered at** rather than going blank.
  - ⚠️ **A `tender_revaluations` row is keyed to the round that just FAILED** — it is the price for the NEXT tender, not for the round it hangs off. (Toilet Seat Covers' 1,645 hangs off R016 and was what F01 then ran at.) So the price a round RAN at is the re-valuation attached to the round BEFORE it. Reading the row's own key shows the pending price again — the exact trap this fix had to avoid.
- **The disposal workflow, confirmed against the code** (2026-08-31). Valuation Tender + Tender 1/2/3, each priced by the **Valuation Directorate**. Still unsold after four rounds (`tenderCount >= 4`) → the package appears in **Top Management → Tender Committees**, where the DG/ADG appoints a committee. The committee decides a value **outside this application** (in writing) and the **ADG enters it**; Central Disposal is told a value exists but does **not** see the figure. The package is then tendered ONCE MORE at that price — and only if THAT round also fails does it reach the DG's **Unsold Goods** table (dropping off Tender Committees and Unsold Tenders). No further tendering after that. Guarded in `getExhaustedUnsoldPackages`: `i.sales.any((s) => s.createdAt.isAfter(submittedAt))` — without it the DG was deciding the final outcome of a package that still had a live chance of selling. Pinned by [valuation_sealed_test.dart](test/valuation_sealed_test.dart).
- ⚠️ **The valuation is SEALED until the sale runs** (2026-08-31) — an anti-collusion rule from management, not a UI preference. The valuation is the **reserve price**: anyone who can see it before bidding closes knows the lowest bid that will be accepted, so it must not appear ANYWHERE — table, popup or tender history — while the tender or destruction sale is still open. [sealed_valuation.dart](lib/widgets/sealed_valuation.dart) holds the one rule (`valuationSealed(saleTimePassed:)`) and the `SealedValuation` placeholder.
  - The gate is **`saleTimePassed`** (sale date + time, on both `TenderSaleModel` and `DestructionModel`) — the SAME clock that already unlocks Mark Sold, so "the sale is over" means one thing everywhere.
  - Also sealed (added after a second sweep): **Top Management → Tender Committees** and **Central Disposal → Committees**, both of which showed the figure while the package could still be re-tendered. A test now sweeps every `valuationUnitCost:` popup and fails by file:line if one lacks the gate — the only allowed exception is **Disposal Requests**, which is the stage before any tender exists.
  - **The gate follows the GOODS, not the screen.** A package that fails a round is re-valued and entered into ANOTHER tender straight away, so sealing only the sale cards was too narrow — the Unsold/Undestroyed tables still showed the NEW reserve price while that new round was open. Sealed wherever the item's newest round is still pending: the live **Tender Sales** and **Destructions** cards, **Unsold Tenders** (all three portals, via `unsoldCells`), **Undestroyed**, and every one of their details popups (incl. `TenderHistorySection`, since each round carries its own valuation).
  - The gate is derived from `info.latestSale` / `info.latestDestruction` **inside** `unsoldCells`, not passed by each caller, so a portal cannot forget it.
  - **Deliberately NOT sealed**, because there is no open bidding left to protect: Sold / Destroyed Goods (already sold or destroyed), an unsold package with **no newer round yet** (committee / re-valuation work), and the **Valuation Directorate's own dashboard** — they author the figure, so hiding it there would break their job.
  - The yard's read-only view was already safe: `useItemValue` shows the SR item's own declared Value, a different number, and stays visible.
  - The placeholder says **why** the figure is missing. An empty cell reads as "not valued yet" and sends someone hunting for the number elsewhere — which is the leak.
  - [valuation_sealed_test.dart](test/valuation_sealed_test.dart) also **scans the real source** so a future live-sale cell added without the gate fails by name (verified by removing the seal: the suite goes red).
- **The Sold pages hid re-valuations, and Unsold hid the committee's figure** (2026-08-31). Three screens showed a package's ORIGINAL valuation long after it had been superseded, so the same goods carried different numbers depending on which portal you opened.
  - **Yard Sold Goods** ([disposition_category_screen.dart](lib/screens/packages/disposition_category_screen.dart)): `_SaleValuationCell` is the yard's own copy of Central Disposal's cell and only ever read `fp.valuationCost`. It now watches `tenderRevaluationsProvider(fp.id)`, takes the latest by `createdAt`, and marks it blue + `price_change_rounded` + "· re-valued" — the same signal Central Disposal uses.
  - **Sold details popup**: `TenderHistorySection` is already reusable and gated on `tenderHistoryFor`; the Sold pages simply never passed it, so the per-round price chain visible on Unsold vanished once goods sold. It now passes `tenderHistoryFor: saleItem?.forfeited` (from `saleItemForPackageItemProvider`) + `valuationQty`.
  - **Unsold tables** ([unsold_shared.dart](lib/screens/executive/unsold_shared.dart)): a package reaches Unsold only after the Valuation tender, up to three re-valued rounds, and finally the Top Management tender committee — and the committee's figure is what the final outcome is decided on. `unsoldCells` gained `committeeUnitValue` (preferred over `f.valuationCost`), a `committee · @ unit × qty` sub-label, and the column was renamed **"Valuation" → "Latest Valuation"**. All three consumers (yard [unsold_packages_screen.dart](lib/screens/packages/unsold_packages_screen.dart), Central Disposal, Top Management [unsold_decision_tab.dart](lib/screens/executive/unsold_decision_tab.dart)) watch `tenderCommitteesProvider` and pass it.
  - ⚠️ **Adding a provider watch to a shared cell breaks widget tests that never stubbed it** — the two Unsold tests failed with "A Timer is still pending" because `tenderCommitteesProvider` opened a real socket to PostgreSQL. Any test rendering these tables must override it alongside `exhaustedUnsoldProvider` / `unsoldProposalsProvider` / `storageRateProvider`.
- ⚠️ **"Value" meant two different things** — FIXED 2026-08-31. The details popup ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)) showed the bare `unitValue` (LKR 18,500) while every table shows `unitValue × quantity` (LKR 832,500 for 45 reels), both under the label "Value". Neither number was wrong; nothing said which was which. All four popup sites now read **"Value (total)"** with `@ unit × qty` beside the figure — the shape the Valuation column already used — and the one-line item summary says **"Value/unit"**. Note `package_items.unit_value` is PER UNIT despite the plain name; the total is always derived, never stored.
- **DB setup order**: run [db/schema.sql](db/schema.sql) → `db/migrations/*.sql` (timestamped, incl. `20260609_officer_username_auth.sql` = `profiles.username` + `officer_signup_otps` + `email_for_login` RPC) → `migrations/001_multi_yard.sql` → `migrations/002_strict_yard_isolation.sql`. ⚠️ `20260839_ict_directorates_and_yards.sql` is **required** for the ICT portal to work at all (it adds the `'ict'` role); `20260840_sr_number_directorate_prefix.sql` rewrites existing SR numbers and is **optional/reversible** — read its header before running it.
- **Disposal Directorate migration**: `db/migrations/20260610_disposal_directorate.sql` adds the `disposal` role (expands `profiles_role_check`), `tender_sales` table, and cross-yard SELECT RLS for disposal users (`auth_user_is_disposal()` permissive policies on packages/package_items/warehouse_entries/profiles). Then `20260610_disposal_forfeited.sql` (disposal read-all on `forfeited_packages`), **`20260611_disposal_requests.sql`** (`disposal_requests` + `disposal_request_items`; RLS = owning yard manages its own rows via `profiles.yard`, disposal reads all), and **`20260611_tender_sale_items.sql`** (`tender_sale_items` + the `disposal_mark_sale_item_sold(uuid,text)` SECURITY DEFINER RPC that writes `[FINAL:SOLD]` warehouse entries in the package's own yard).
- **Edge Function setup**: `supabase functions deploy admin-officers`; set secrets `RESEND_API_KEY` and `RESEND_FROM` (verified sender). Without these, officer-credential emails fail (the create dialog then shows the username/password on screen as a fallback).
- **Assets**: `Sri_Lanka_Customs_logo.svg`, `Sri_Lanka_Customs_logo_tinted.svg` (declared in pubspec).
- **Window**: min size 1000×700, title "Sri Lanka Customs SR Management System", `preventClose` for graceful offline.
- **Lint**: [analysis_options.yaml](analysis_options.yaml) = `package:flutter_lints/flutter.yaml` defaults (`avoid_print` NOT disabled but `print()` is used widely).

## Development Conventions
- **Theming**: always use `context.colors.<token>` (e.g. `primaryGold`, `surfaceDark`, `textMuted`, `dangerRed`, `heldOrange`, `accentLightBlue`, `successGreen`) — not hardcoded colors. Supports light/dark.
- **Snackbars**: use the `AppSnackBar` extension in [theme.dart](lib/core/theme.dart) — `context.showSuccess(msg)` (green + check icon), `context.showError(msg)` (red), `context.showInfo(msg)` (gold). Do NOT hand-roll `ScaffoldMessenger…showSnackBar` for these; the helper guarantees success=green app-wide across all yards/directorates (login screens previously showed success in blue/navy — fixed). It `clearSnackBars()` first so toasts don't stack.
- **Money**: `NumberFormat('#,##0.00')`, prefixed `LKR`.
- **Status display**: route through `StatusChip`; status strings are **case-sensitive and inconsistent** — capitalized for `Detain`/`Forfeit`/`Abandoned`/`Re-export`/`Destroy`, lowercase for `held`/`pending`/`returned`/`released`/`sold`. The typo `Forfiet` is normalized to `Forfeit` in several places.
- **Dropdowns**: filter/yard selectors use `StyledDropdownFormField`/`StyledDropdownButton`; dark Material forms use `CustomDropdownField`.
- **Dates**: use shared `OneTapDatePicker` for new pickers (not raw `showDatePicker`).
- **State**: one provider per concern in [providers.dart](lib/core/providers.dart); realtime via `RefreshTrigger` + `*ChangeTriggerProvider`. Filters often `StateProvider.family` keyed by warehouse/package id.
- **New authed screen**: add route in [router.dart](lib/core/router.dart) (NoTransitionPage), wrap body in `AppShell(currentRoute: ...)`, add `NavItem` in [app_shell.dart](lib/widgets/app_shell.dart) if it needs a sidebar entry.
- Models/services are each **one big file** — extend in place.

## Known Caveats
- **Secrets in source**: Supabase URL/anon key committed in `db_client.dart`.
- **No session persistence**: intentional (`_NoPersistLocalStorage`) — every launch needs fresh login.
- **Status string drift**: mixed casing + `Forfiet` typo; normalization is scattered (warehouses screen, status_chip, package_details_dialog). Be careful comparing statuses.
- **Two SQL locations**: legacy/base in [supabase/](supabase/); multi-yard RLS in root [migrations/](migrations/). README only mentions `db/schema.sql`.
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

## Central Disposal search + yard filters (2026-06-12)
- Every Central Disposal tab now has a styled **search box** (`_DisposalSearch`, per-tab `_disposalSearchProvider` family in [disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart)); filters by SR / item / consignee / sale-no as relevant. Taxes tab ([taxes_tab.dart](lib/screens/disposal/taxes_tab.dart)) filters by tax name via `_taxSearchProvider`.
- **Yard selector** on every list tab: Sold/Forfeited keep `_YardFilter` (single yard, `disposalSelectedYardProvider`); Disposal Requests + the cross-yard tabs (Tender Sales, Unsold Tenders, Destructions, Undestroyed) use `_YardAllFilter` ("All Yards" + yards) bound to `_disposalYardFilterProvider` family and filter their list by `sale.yard` / `info.forfeited.yard`. Taxes has no yard (global).

## Central Disposal consolidated onto Tender Sales (2026-06-12)
- The standalone **"Tenders" tab was removed** from Central Disposal; the lifecycle now runs through **Tender Sales** + **Unsold Tenders**. Tabs (6, uniform `Tab(height:44, Row[Icon,Gap,Flexible(Text)])`): Sold · Forfeited · Disposal Requests · **Tender Sales** · **Unsold Tenders** · Taxes.
- **Disposal Requests** (`getDisposalRequests`) now hides packages already in a `tenders` row OR a `tender_sale_items` row (they've moved on); requests with no remaining items are dropped.
- **Tender Sales** cards hide **sold** items (`_TenderSaleCard._rows` filters `!sold`); fully-sold sales are hidden from the tab.
- ⚠️ **Unsold tab header overflow FIXED** ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart) ~L548): the header was `Text(title) + Spacer() + DisposalSearch(300) + YardAllFilter(220)`. Both controls are FIXED widths, so a bare `Text` had nowhere to shrink and the Row threw "RenderFlex overflowed by 47 pixels" below ~800px. Now the title is `Expanded` + `TextOverflow.ellipsis`. Regression test at [unsold_tab_header_layout_test.dart](test/unsold_tab_header_layout_test.dart) pumps 1400→620px (verified: it fails on the old code).
- **Unsold Tenders** tab uses the externally-added `unsoldTenderSalesProvider` (`getUnsoldTenderSales`, `ReTenderSaleInfo`) — unsold `tender_sale_items` past their sale window. **Re-tender** opens `_TenderSaleFormDialog(reTender: true)` whose pool is ONLY those unsold packages (mapped to `DisposalRequestItemModel`). `createTenderSale` now **upserts** `tender_sale_items` (`onConflict: forfeited_package_id`, resets `sold`/`sold_at`) so a re-tendered package moves to the new sale instead of violating the unique constraint.
- The yard `DisposalDialog` "Sold" outcome (only reachable by disposal users, which no longer happens) writes `[FINAL:SOLD]` via `disposal_mark_forfeited_sold` RPC (migration `20260612_mark_forfeited_sold.sql`) — now effectively dormant since the Tenders tab is gone; harmless. The old-flow migrations `20260612_tender_sale_schedule.sql` / `20260612_disposal_manage_tenders.sql` are likewise no longer required for the consolidated flow.

## Tender re-tendering workflow (2026-06-12)
- **Place Tender form redesigned** ([tender_placement_dialog.dart](lib/screens/forfeited_packages/tender_placement_dialog.dart)) to match the disposal-request form (gradient header + gold-headed `_Section` cards + checkbox ListView rows). Added **Tender Sale Date** + **Sale Start Time** fields (`tenders.sale_date date`, `sale_time text` — migration `20260612_tender_sale_schedule.sql`); `TenderModel` gained `saleDate`/`saleTime` + `saleWindowPassed` (saleDate + 1 grace day, null = passed). `createTender` takes `saleDate`/`saleTime`.
- **Re-tender (unlimited)**: a tendered package that wasn't marked SOLD and whose sale window passed becomes re-tenderable. `TendersService.getReTenderablePackages()` → `List<ReTenderInfo>{forfeited, tenders}` (tenderCount = times tendered); `reTenderablePackagesProvider`. Fresh `Place Tender` still uses `expiredAppealPackagesProvider` (never-tendered); the dialog's `reTender:true` mode sources from `reTenderablePackagesProvider` and shows a "Tendered N×" badge per row.
- **Unsold view + history**: a **"Unsold (N)"** button opens `UnsoldReTenderDialog` (table of unsold packages: SR · Item · Consignee · **Times Tendered** · history button + a **Re-tender** button that opens the form). The history button opens `_TenderHistoryDialog` listing every tender for that package (number, tender date, sale date, sale time, created by) — so a package tendered 10× shows all 10. "Auto-move after sale date+1" is the computed `saleWindowPassed` filter (no cron).
- **Tender management moved to Central Disposal** (2026-06-12): the full tender lifecycle (Place Tender · Record Disposal · Unsold/Re-tender) now lives in a new **"Tenders" tab** on the Central Disposal dashboard (`_TendersTab` reuses the now-public `TenderCard` + `UnsoldReTenderDialog` + `TenderPlacementDialog` + `tenderDisposalsMapProvider`/`allForfeitedMapProvider` from [tender_disposal_screen.dart](lib/screens/forfeited_packages/tender_disposal_screen.dart)). Migration **`20260612_disposal_manage_tenders.sql`** lets the `disposal` role write `tenders`/`tender_disposals` (were admin-only). On the **yard** Tender Disposals page the "Place Tender" button now opens the **Send Disposal Request** form (`DisposalRequestDialog`) and the "Unsold" button was removed — yards request, Central tenders. The Record-Disposal popup's Sold/Destroy/Govt-Use restriction now applies only to yard admins (`!isDisposal`); the Central Disposal user gets all outcomes. The Unsold/Re-tender table is now its own **"Unsold" tab** (`_UnsoldReTenderTab`, 7 tabs total) rather than a dialog opened from a button — the history button opens the now-public `TenderHistoryDialog`. (The old `UnsoldReTenderDialog` class remains in [tender_disposal_screen.dart](lib/screens/forfeited_packages/tender_disposal_screen.dart) but is no longer wired.)

## Disposal forms: one-tap calendar/time + Select All + styled dialogs (2026-06-13)
- **New shared time picker** `OneTapTimePicker` in [one_tap_date_picker.dart](lib/widgets/one_tap_date_picker.dart) — gold **analog clock dial** (`_ClockDial` + `_HandPainter`, uses `dart:math`), **no OK button**: HH:mm display + AM/PM toggle; tap/drag the dial to pick an hour (swings to the minute dial on release), then a minute → closes immediately. Keyboard icon → manual `HH:mm` entry. (First built as a number grid, then redesigned to the rotating clock per request.) Mirrors `OneTapDatePicker`; use it (not raw `showTimePicker`) for new time fields.
- **Tender Sale + Destruction Sale forms** ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart) `_TenderSaleFormDialog`/`_DestructionFormDialog`): replaced Material `showDatePicker`/`showTimePicker` with shared `_OneTapDateField`/`_OneTapTimeField` helpers (wrap `OneTapDatePicker`/`OneTapTimePicker` in an `InputDecorator`). Their package pickers gained a `_SelectAllBar` (Select All / Clear All + "N of M selected"). The yard `TenderPlacementDialog` time field also switched to `OneTapTimePicker` (its date picker + Select-All already existed). All three helper widgets (`_OneTapDateField`, `_OneTapTimeField`, `_SelectAllBar`) live at the bottom of `disposal_dashboard_screen.dart`.
- **Popups restyled to `StyledFormDialog`** (gradient header + gold-headed `StyledFormSection`) to match New Tender Sale: the Tax Add/Edit dialog `_TaxDialog` ([taxes_tab.dart](lib/screens/disposal/taxes_tab.dart)) and the `_TenderSaleHistoryDialog` / `_DestructionSaleHistoryDialog` (history cards now built by a `_saleCard` helper inside a section). The small Delete-Tax confirm stays a plain `AlertDialog` (a confirm, not a form).

## Password 90-day expiry + Disposal profile dialog (2026-06-13)
- **90-day password rotation** ([models.dart](lib/models/models.dart) `ProfileModel`): backend was already in place (`password_updated_at` column + `auth.users` trigger in [db/migrations/20260613_password_updated_at.sql](db/migrations/20260613_password_updated_at.sql); falls back to `created_at`). Added getters `daysUntilPasswordExpiry`, `isPasswordExpired`, `isPasswordExpiringSoon` (warn window = **7 days**; `passwordMaxAgeDays=90`, `passwordWarnDays=7`). Fixed `copyWithOnline` to carry `passwordUpdatedAt`. ⚠️ Apply the `20260613` migration in Supabase or expiry tracks `created_at` only.
- **Login gate** ([disposal_login_screen.dart](lib/screens/disposal/disposal_login_screen.dart)): after OTP verify, before routing to `/disposal`, `_verify` checks the policy → `_passwordStage`. **Expired (≥90d): mandatory** in-screen new-password form (no skip); **expiring soon (≤7d): warning banner + "Skip for now"**. `_submitNewPassword` calls `AuthService.changePassword` (trigger resets the 90-day clock) then `_finishLogin`. Credentials/OTP stages hidden during `_passwordStage`.
- **Disposal profile dialog** — new [disposal_profile_dialog.dart](lib/widgets/disposal_profile_dialog.dart) (`DisposalProfileDialog`): opened by tapping the **green account chip** in the dashboard top bar ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart)), which now shows an **amber/red dot** when the password is expiring/expired + a chevron. View mode (name/role/email/mobile/password status) ↔ edit mode. Editable: **mobile number, profile image, branch email** (full name/role are institutional, read-only). Profile image uses `FilePicker` → **local path stored in `profile_image_url`** (no Supabase Storage upload — same pattern as officer `EditProfileScreen`; remote `http` URLs also render). Email change calls new **`AuthService.changeEmail`** (`supabase.auth.updateUser(email:)` → emails a confirmation link; `profiles` has no email). Password change reuses `changePassword`.
- **DC/SDDC single-account limit** was already fully enforced (signup RPC `isDisposalPositionAvailable` + unique `username` index `dc`/`sddc`); no change needed.

## Admin Dashboard: yard-scoped staff + restructure (2026-06-13)
- **Online/Total staff now yard-scoped.** The cross-yard SELECT policy for disposal accounts let `allProfilesProvider` leak head-office (DC/SDDC) + other-yard rows into the Admin Dashboard's "Officers Online" / "Total Staff". Added `myYardProfilesProvider` (filters `allProfilesProvider` by `currentProfileProvider.yard`) + `myYardOnlineProfilesProvider` (5-min `is_online`/`last_seen_at` window over the yard-scoped list) in [providers.dart](lib/core/providers.dart). [admin_dashboard_screen.dart](lib/screens/admin/admin_dashboard_screen.dart) now watches these — an admin sees ONLY their own yard's officers + admins. Header stat relabeled "Total Staff" → "In Yard".
- **Full dashboard restructure** (same data, polished): header row gained a gold **yard badge** (`yardName(myYard)`) next to the staff stats; the 4 operational metrics use a new `_StatCard` (tinted icon box + faint accent gradient); every section title uses a shared `_SectionHeader` (gold accent bar + optional trailing chip/link); the online list header reads "Online in <Yard>" with a green count pill and empty-state "No one currently online in this yard"; shortcut tiles got tinted icon boxes + a chevron; left column flex 3→4. Removed dead `_GridSummary` and the unused `services.dart` import.

## Dashboard daily-disposition stats + yard Tender Sale view (2026-06-13)
- **Dashboard stat cards now count today's dispositions.** `PackageService.getDashboardStats` ([services.dart](lib/services/services.dart)) was rewritten: instead of `seized`/`cleared`/`held` it tallies today's package-**item** statuses into `forfeit` / `abandon` / `destroy` / `release` (normalised — handles `Forfiet` typo, `confiscated`≡forfeit, capitalised/lowercase, `cleared`/`returned`→release; package-level status used only when a package has no items). **Both** dashboards that consume it were updated: [admin_dashboard_screen.dart](lib/screens/admin/admin_dashboard_screen.dart) + [dashboard_screen.dart](lib/screens/dashboard/dashboard_screen.dart) (which shadows the provider with its own local one — same service call) now show 4 cards: Forfeited / Abandoned / Destroyed / Released "Today". The Warehouse Charges card + its `storageRate`/`_latestStorageRate` plumbing were removed from both.
- **Directorate online-leak fix.** `myYardProfilesProvider` now **whitelists** `p.isYardStaff` (= `isAdmin || isOfficer`) instead of blacklisting each directorate — so Disposal/Appeal/**Valuation** (and any future head-office role whose `yard` defaults to a matching code like GL1) can never leak into a yard's "Online in <yard>" list / staff mgmt. Earlier the blacklist missed `isValuation` so "Valuation Directorate (DC)" showed as online in Grey Line 1. New `ProfileModel` getters: `isOfficer`, `isYardStaff`. Feeds the Admin Dashboard online stat + "N online" pill + list, and the admin staff-management screen.
- **Yard "Tender Sale" page** ([tender_disposal_screen.dart](lib/screens/forfeited_packages/tender_disposal_screen.dart), route `/tender-disposals`): retitled "Tender Disposals" → **"Tender Sale"**; removed the header stat chips (Tenders/Packages/Expired) + the "Send Disposal Request" button (that workflow still lives on the Forfeited Packages screen). The old `TenderCard`/`DisposalDialog` record-disposal flow is **no longer rendered** — the page now shows the same cards as Central Disposal's Tender Sales tab via the now-public **`TenderSaleCard`** (was `_TenderSaleCard`) in **read-only mode** (`readOnly: true`): every item shown (sold included), Mark-Sold replaced by a view-only **Sold / Pending** chip (`_statusChip`). Sales are filtered to this yard by item-level `yard` (`AppSession.currentYard`). `TenderCard`/`DisposalDialog`/`tenderDisposalsMapProvider`/`allForfeitedMapProvider` + `_StatChip` remain in the file but are now dead (Unsold/Re-tender dialog flow still live); the `services.dart` import was dropped.

## Abandoned packages → disposal pipeline + Forfeit/Abandoned source (2026-06-13)
- **Abandoned packages can now be sent in a Disposal Request**, reusing the entire forfeit→tender-sale/destruction→sold pipeline UNCHANGED. Approach: an abandoned package gets a real `forfeited_packages` row when requested, tagged `source='abandoned'` (vs default `'forfeit'`). Chosen over "generalize `disposal_request_items`" because that would have touched ~60 sites incl. 4 copies of `disposal_mark_sale_item_sold` in the irreversible money-path RPCs; this touched ~5 (validated with a Plan agent). Migration **`20260613_forfeited_source.sql`** adds `forfeited_packages.source text not null default 'forfeit' check (in ('forfeit','abandoned'))` + index. ⚠️ Apply it in Supabase.
- **Model** ([models.dart](lib/models/models.dart)): `ForfeitedPackageModel` gained `source` (default `'forfeit'`) + `isAbandonedSource`; flows automatically into `DisposalRequestItemModel.forfeited` etc.
- **Service** ([services.dart](lib/services/services.dart) `ForfeitedPackageService`): `getRequestableExpiredPackages` now ALSO surfaces abandoned packages — synthetic `ForfeitedPackageModel`s built from `packages` rows (id == package_id, source='abandoned', past appeal deadline), using `_packageHasAbandonedItem`/`_abandonReasonFor` (mirror the abandoned-screen dual-form detection: `status=='abandoned'` OR `[ABANDONED]` return-note). `createDisposalRequest` resolves each selected key: real forfeited_packages id → store as-is; otherwise it's a package id → insert a `source='abandoned'` forfeited_packages row first, then store its id. `getForfeitedPackages` + `getExpiredAppealPackages` gained `.eq('source','forfeit')` so synthetic abandoned rows never leak into the yard Forfeited list / tender-placement pool.
- **Yard Abandoned page** ([abandoned_packages_screen.dart](lib/screens/packages/abandoned_packages_screen.dart)): header now mirrors the Forfeited page — `_AbandonedStatChip`s (Abandoned / Requestable counts) + a **"Send Disposal Request"** button opening the shared `DisposalRequestDialog` (enabled when ≥1 abandoned package is requestable). Requestable count = `requestableForfeitedPackagesProvider` items where `isAbandonedSource`.
- **Source chips**: the disposal request dialog rows ([disposal_request_dialog.dart](lib/screens/forfeited_packages/disposal_request_dialog.dart) `_SourceChip` next to SR number) and the Central **Disposal Requests** card ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart) — new **Source** column + `_SourceChip`) both show Forfeit (accentBlue) / Abandoned (heldOrange) from `forfeited.source`.
- **Central Disposal "Forfeited Packages" tab removed**: `DefaultTabController` length 8→7, dropped the tab + `_ForfeitedPackagesTab` + `_AppealStatusChip` (deleted). Tabs now: Sold · Disposal Requests · Tender Sales · Unsold Tenders · Destructions · Undestroyed · Taxes. (`disposalForfeitedPackagesProvider` left in place but now unused — harmless.)

## "Other"-status packages → disposal pipeline (source='other', no appeal) (2026-06-16)
- **Packages registered with an "Other" item status now have an admin workflow** mirroring Abandoned (NO 30-day appeal, NO Appeal Directorate). Admin can **Release / Re-export / record a custom "Other" outcome directly** (via the existing `PackageDetailsDialog` admin-only actions → `recordFinalDisposition` `[FINAL:…]`), or **Send Disposal Request** (Sale/Destruction → Central Disposal). Same synthetic-FP-row trick as abandoned, tagged `source='other'`. Migration **`20260616_forfeited_source_other.sql`** drops/re-adds the check → `source in ('forfeit','abandoned','other')`. ⚠️ Apply it in Supabase.
- **"Other" status** = the SR form's 4th item status (`Detain`/`Forfeit`/`Abandoned`/`Other`, set in [inspection_screen.dart](lib/screens/inspection/inspection_screen.dart)); the officer types a custom label into "Other Status". ⚠️ **`package_items.status` defaults to `'pending'`** for un-dispositioned items, and the custom Other text is free-form, so a plain free-text status can't be reliably told apart from a pending item. **Fix: a marker prefix** — the SR form now SAVES Other as **`'Other: <custom text>'`** (inspection_screen submit + the edit-reload `startsWith('other:')` branch). Detection (`_statusIsOther`) matches `other` / `other:` prefix (positive) PLUS a legacy fallback: any non-empty status not in `_knownStatuses` (kept in sync between [services.dart](lib/services/services.dart) `_knownStatuses`/`_statusIsOther`/`_otherLabelFor` and [other_packages_screen.dart](lib/screens/packages/other_packages_screen.dart) `_knownStatuses`/`_statusIsOther`/`_otherLabel`). `'pending'`/`'inspecting'` stay in `_knownStatuses` (real default statuses) so legacy free-text "pending"-as-Other items WON'T surface — only marker-tagged ones. abandoned is in the known set so Abandoned vs Other screens are disjoint per-item. [StatusChip](lib/widgets/status_chip.dart) strips the `Other:` prefix → amber chip with the custom label.
- **Model**: `ForfeitedPackageModel.isOtherSource` ([models.dart](lib/models/models.dart)).
- **Service** ([services.dart](lib/services/services.dart) `ForfeitedPackageService`): `_packageHasOtherItem`/`_statusIsOther`/`_otherReasonFor`/`_otherLabelFor` added; `getRequestableExpiredPackages` surfaces synthetic abandoned/other rows (separate existing-FP-pkg-id sets). `_packageHasOtherItem`: explicit `other`/`other:` marker always qualifies; legacy free-text status only when the item has a **non-returned warehouse entry** (so a stray non-held status can't masquerade). Items with a `[FINAL:…]` entry are skipped. (Returned/disposed history does NOT exclude an item — every Other item that still has an `other`/`other:` status is requestable, matching the always-on Final Disposition button.)
- ⚠️ **Synthetic requestable-row ids are now PER-ITEM**: `"<pkgId>:<itemId>:<source>"` (`source` = `abandoned`/`other`). `getRequestableExpiredPackages` emits one row **per qualifying item** (was per package) so the `DisposalRequestDialog` lists each abandoned/Other item separately (an SR with 2 abandoned items → 2 rows) and includes partial `[OTHER:]`/`[ABANDONED]` events. Detection: `_itemIsRequestableAbandoned`/`_itemIsRequestableOther` (the `_packageHas…Item` package helpers now just `.any()` over these). The synthetic `ForfeitedPackageModel` carries `itemId`+`itemName` (model fields, not from JSON); the dialog's `_itemSummary` shows `itemName` when set. `createDisposalRequest.parseSynthetic`: 3-part → (first, last) = (pkgId, source); 2-part (legacy single-package callers `'${pkg.id}:other'` / `':abandoned'`) → (pkgId, source); no `:` → genuine forfeit UUID. `forfeited_packages` is package-level (package_id+source, no item_id) → several selected items of the SAME pkg+source share ONE FP row (cached by `'$pkgId:$source'`), and `disposal_request_items` are de-duped by `(fpId, disposition)`.
- **New screen** [other_packages_screen.dart](lib/screens/packages/other_packages_screen.dart) (`OtherPackagesScreen`, route `/other-packages`): clone of the Abandoned page — `_OtherStatChip` (Other / Requestable), "Send Disposal Request" (`DisposalRequestDialog`, requestable = `requestableForfeitedPackagesProvider` items `isOtherSource`), per-item rows with a `_OtherDispositionChip` (the custom label), details dialog wired with `onSaleOrDestroyRequest`. Nav: **"Other Packages"** (`Icons.label_important_rounded`) in both navs.
- ⚠️ **`_buildRows` surfaces TWO kinds of "Other"** (mirrors the Abandoned page): (1) form-level `item.status == 'Other'/'Other: …'` items (highlight = held entry), AND (2) **partial `[OTHER]` disposition events** recorded from the warehouse Actions dialog. A PARTIAL "Other" disposition (`disposeWarehouseItem`, disposeQty < total) tags the returned entry and **leaves item.status unchanged** (e.g. still 'detain'), so without (2) those packages never appeared in the Other table. ⚠️ The warehouse Actions "Other" picker (`_PackageActionsDialog`) now passes `'Other: <text>'` as the disposition type (was the bare custom text) → returnNotes tag `[OTHER: <TEXT>]` (partial) + item.status `Other: <text>` (full). `_isOtherEntry`/`_otherEntryLabel` detect a leading `[OTHER:`/`[OTHER]` tag (NOT `[FINAL:OTHER]`, the removed finished-category). The label lives **inside** the bracket now (`RegExp(r'^\[OTHER:\s*([^\]]*)\]')`), not after the `—`. Same bracket-parse applied in the popup's `isOtherEntry` "&lt;X&gt; By" section and `_actionCountLabel`. Finalised items (`_itemHasFinalDisposition`) are skipped. NOTE: rows saved with the pre-fix bare `[CCCC]` tag are NOT auto-detected — backfill those returnNotes to `[OTHER: CCCC]` (and item.status if full) via [backfill_other_disposition_tags.sql](supabase/backfill_other_disposition_tags.sql).
- ⚠️ **EVERY Other/Abandoned item stays actionable** ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)): the details popup ALWAYS shows the **Final Disposition** footer button for an Other/Abandoned item (`allowFinalDisposition && useLegacySummary && !_hasFinalDisposition`) — regardless of how it reached the table (form status, partial `[OTHER:]`/`[ABANDONED]` event, returned history, etc.). Every such item must be actionable so it can move to its final-outcome table via Release / Re-export / Other (direct) or Sale / Destroy (Central Disposal request). `_hasFinalDisposition` (the only gate) counts **only** genuine final moves: `[FINAL:…]` / `[RE-EXPORT` / `[DESTROY` / `[SOLD` — it does NOT count a bare `[OTHER…]` tag (a warehouse-Actions custom disposition, like `[ABANDONED]`/`[FORFEIT]`), so partial-Other rows keep the button. (Reverted an earlier "Other selected package" banner that hid the button for detained-then-Other items — the requirement is the opposite.) Sale/Destroy in `_FinalDispositionDialog` stay disabled (greyed) for everyone — Central Disposal records those.
- **Source chips**: both `_SourceChip`s — the request-dialog one ([disposal_request_dialog.dart](lib/screens/forfeited_packages/disposal_request_dialog.dart)) and the Central **Disposal Requests** card one ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart)) — now `switch` over forfeit (accentBlue) / abandoned (heldOrange) / **other** (warningAmber).
- **Warehouse "Actions" auto-close** ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)): the `_PackageActionsDialog` (warehouse-summary "Actions" button → Release / Re-export / Other-disposition picker) used to stay open after a successful action (self-refresh). Now on success `_runAction` pops itself and calls a new `onCompleted` callback (wired in `_showActionsDialog` to pop the parent `PackageDetailsDialog`), so the whole popup stack closes and returns to the Warehouses list. Confirm sub-dialogs (`_showReleaseConfirmation`/`_showDispositionDialog`) already pop themselves with `true` only on success; errors keep dialogs open. The Forfeited/Abandoned/Other list-screen path (`_showFinalDispositionDialog`) already auto-closed both dialogs.

## Destruction-form pool fix + disposal realtime (2026-06-13)
- **Bug: the New Destruction Sale form listed SALE-tagged packages.** `_DestructionFormDialog` ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart)) watched `saleRequestItemsProvider` instead of `destructionRequestItemsProvider` (both the pool + the error-retry). Now uses `destructionRequestItemsProvider` → only `disposition='destruction'` items. Source chips (Forfeit/Abandoned) were also added to the Tender Sale + Destruction form rows and the Unsold Tenders + Undestroyed tables (new **Source** column, `minWidth` 760→880) — same `_SourceChip` as the Disposal Requests card.
- **Disposal pipeline now updates live across tables/sessions** (no page reload). Added realtime + cross-trigger wiring in [providers.dart](lib/core/providers.dart):
  - `disposalRequestsChangeTriggerProvider` now also subscribes to **`disposal_request_items`** (not just the header) — an item moving on refreshes the requests feed.
  - New **`destructionsChangeTriggerProvider`** (realtime on `destructions` + `destruction_items`); `destructionsProvider` watches it (was `destructionsRefreshProvider` directly, which the trigger now wraps).
  - `tenderSalesProvider` + `saleRequestItemsProvider` + `tenderableSaleItemsProvider` + `unsoldTenderSalesProvider` now watch `tenderSaleItemsChangeTriggerProvider`; `destructionRequestItemsProvider` + `undestroyedDestructionsProvider` watch `destructionsChangeTriggerProvider`. So a Mark-Sold / Mark-Destroyed / new sale propagates everywhere live.
  - Mark-Sold + createTenderSale now also fire `tenderSaleItemsRefreshProvider` for instant same-session feedback (realtime handles other sessions).
- **Requires migration `20260613_disposal_realtime.sql`** (idempotent) — adds `disposal_requests`, `disposal_request_items`, `destructions`, `destruction_items` to the `supabase_realtime` publication. Without it the realtime events never fire and tables stay stale until reopened (manual refresh triggers still work within a session).

## Appeal Directorate role + appeal-hold on forfeited packages (2026-06-14)
- **New 4th institutional role `appeal`** (Appeal Directorate), cloned from the disposal (DC/SDDC) pattern: two positions **AD / ADD**, OTP-on-every-login, never auto-expires, cross-yard READ. It reviews forfeited packages whose 30-day appeal window is still open and places an **appeal hold** so the package can't be sold/destroyed.
- **Migration `20260613_appeal_directorate.sql`** (mirrors `20260610_disposal_directorate.sql`): widens `profiles_role_check` to include `'appeal'`; `auth_user_is_appeal()`; `appeal_read_all` SELECT RLS on packages/package_items/warehouse_entries/forfeited_packages + `appeal_read_profiles`; `appeal_position_available(code)` RPC (one AD + one ADD); **appeal-hold columns** on `forfeited_packages` (`appeal_hold`, `appeal_hold_note`, `appeal_held_at`, `appeal_held_by`); **`set_appeal_hold(uuid,bool,text)`** SECURITY DEFINER RPC (appeal-only; refuses to hold once `appeal_deadline < now()`; toggle to release). **Hard block**: re-creates `disposal_mark_sale_item_sold` + `disposal_mark_destruction_item_destroyed` with `if (select appeal_hold …) then raise exception 'appeal_hold_active'` right after resolving the forfeited id. ⚠️ Apply in Supabase. (`forfeited_packages` is already in the realtime publication, so the hold propagates live — no extra realtime migration.)
- **Model** ([models.dart](lib/models/models.dart)): `ProfileModel.isAppeal`, `isExpired` now exempts appeal too, `kAppealPositions`/`appealPositionLabel`. `ForfeitedPackageModel` gained `appealHold`/`appealHoldNote`/`appealHeldAt` + `isAppealHeld`.
- **Service/providers**: new **`AppealService`** ([services.dart](lib/services/services.dart)) — `getForfeitedPackages()` (cross-yard, genuine forfeits only, NO tender/request exclusion — appeals can be raised at any point in the window) + `setAppealHold(id, hold, note)`. `AdminService.isAppealPositionAvailable`. Providers: `appealServiceProvider`, `appealForfeitedPackagesProvider` (watches `forfeitedPackagesChangeTriggerProvider`).
- **Screens** (accent = `accentBlue`, icon `Icons.balance_rounded`): `lib/screens/appeal/appeal_login_screen.dart` + `appeal_signup_screen.dart` (near-verbatim copies of the disposal ones, role `'appeal'`, OTP + password-expiry stage) + **`appeal_dashboard_screen.dart`** (standalone Scaffold, one cross-yard forfeited table with stat chips + a per-row **Hold Appeal / Release** action calling `set_appeal_hold`; expired-window rows can't be newly held). Routes `/appeal/login|signup|appeal` + redirect guard + a **4th home `_RoleCard`** ([home_screen.dart](lib/screens/home/home_screen.dart)).
- **Positions = DC / SDDC** (same titles as the Disposal Directorate) but with **distinct usernames** `adc` / `asddc` — `profiles.username` is globally unique, so reusing `dc`/`sddc` would clash with the disposal accounts. `kAppealPositions` keys are `ADC`/`ASDDC` (→ usernames), labels read "DC (Director)" / "SDDC (Senior Deputy Director)"; the institutional full name is `Appeal Directorate (DC|SDDC)` (mapped via `_shortTitle` in the signup screen). Sign in with email or the `adc`/`asddc` username.
- **Profile dialog reused**: `DisposalProfileDialog` ([disposal_profile_dialog.dart](lib/widgets/disposal_profile_dialog.dart)) gained an optional **`accent`** param (defaults to disposal green) so the appeal dashboard's account chip opens the same view/edit-profile dialog (mobile / photo / branch email / password) tinted `accentBlue`. The chip is now a clickable `InkWell` + chevron like the disposal one.
- **Appeal dashboard polish** (2026-06-14): added a Central-Disposal-style **yard filter** (`_AppealYardFilter`, "All Yards" + yards, accent-tinted; `_appealYardProvider`) + styled search box; `AppealService.getForfeitedPackages` now **drops fully-finalised packages** (every item sold/destroyed/re-exported/released via a `[FINAL:…]` warehouse entry or terminal item status — `_isFullyFinalised`), so the appeal table mirrors the admin Forfeited screen. The Admin Dashboard online list now also excludes Appeal accounts: `myYardProfilesProvider` filters `p.isDisposal || p.isAppeal` (was disposal-only) — directorate accounts are head-office, never "in this yard".
- **Hold/Release moved into the details popup** (2026-06-14): the appeal table's "Appeal Hold" column is now a **status chip only** (`_holdChip` → "On Hold" / "—"); the actual action lives in the package details popup footer. `PackageDetailsDialog` ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)) gained a **generic footer action** (`footerActionLabel`/`footerActionIcon`/`footerActionColor`/`footerActionHint`/`onFooterAction`) — a button styled like the Final Disposition footer that pops the dialog then runs the callback. The appeal dashboard's Details ⓘ opens it via `_openDetails`, wiring **Hold Appeal** (amber, window open) / **Release Hold** (red, currently held) to `_setHold`.
- **Yard warning + block UX**: the yard **Forfeited Packages** screen ([forfeited_packages_screen.dart](lib/screens/forfeited_packages/forfeited_packages_screen.dart)) shows an amber **"APPEAL HOLD"** chip (with the hold note as tooltip) overriding Appealing/Expired when `pkg.appealHold` — live via the existing forfeited realtime. The Central Disposal Mark-Sold / Mark-Destroyed dialogs ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart)) map the `appeal_hold_active` RPC error via `_appealHoldMessage` → "This package is under an appeal hold and cannot be sold or destroyed."
- **Appeal decision on release** (2026-06-14): the appeal table's redundant **"Appeal Hold" column was removed** (the Status chip already shows "On Appeal Hold"; `_holdChip` deleted). Releasing a hold now records what the owning yard should do. Migration **`20260614_appeal_decision.sql`**: `appeal_decision`/`appeal_decision_note`/`appeal_decided_at`/`appeal_decided_by` columns on `forfeited_packages` + **`release_appeal_with_decision(uuid,text,text)`** SECURITY DEFINER RPC (appeal-only; clears the hold AND stores the decision). `AppealService.releaseAppealWithDecision(id, decision, note)`. `ForfeitedPackageModel` gained `appealDecision`/`appealDecisionNote`/`appealDecidedAt` + `hasAppealDecision`/`appealDecisionLabel` (RELEASE→"Release to owner", SALE→"Sell", DESTROY, RE-EXPORT, OTHER→custom note). The appeal footer action is now **"Release Hold & Decide"** → `_showDecisionDialog` (`_AppealDecisionDialog`, radio-card picker: Release/Sale/Destroy/Re-export/Other + free-text for Other) → `_AppealDecisionResult`. Appeal Status chip shows "Decided · {label}" once set. The yard Forfeited screen's status cell adds a blue **"→ {decision}"** chip (priority: hold > decision > appealing/expired) so the yard sees the directorate's instruction. **`PackageDetailsDialog` also gained an optional `appealDecisionLabel` param** → a blue "APPEAL DIRECTORATE DECISION · Proceed with: {label}" banner at the top of the body; the yard Forfeited screen's Details ⓘ passes it so the decision is visible inside the popup too (live via forfeited realtime). ⚠️ Apply `20260614_appeal_decision.sql` in Supabase. Both forfeited queries use `select('*'…)` so the new columns load automatically.
- **Forfeited realtime fix** (2026-06-14): the Appeal + yard Forfeited tables weren't updating live — `forfeited_packages` had a realtime *channel* (`forfeited-packages-realtime` → `forfeitedPackagesChangeTriggerProvider`) but the table was **never added to the `supabase_realtime` publication** (only `tender_sale_items`/`disposal_requests`/`disposal_request_items`/`destructions`/`destruction_items` were, via earlier migrations). Postgres broadcasts nothing for unpublished tables. Migration **`20260614_forfeited_realtime.sql`** backfills the publication for ALL channelled tables (`packages`, `package_items`, `warehouse_entries`, `profiles`, `package_categories`, `audit_logs`, `forfeited_packages`, `destructions`, `destruction_items`, `disposal_requests`, `disposal_request_items`, `tender_sale_items` — idempotent `pg_publication_tables` guard) and sets `forfeited_packages replica identity full` so UPDATE payloads carry changed columns. ⚠️ Apply in Supabase to get live auto-refresh. Also fixed a RenderFlex overflow in the yard Forfeited status cell (wrapped the "APPEAL HOLD" chip text in `Flexible`+ellipsis, matching the decision chip).
- **Final-disposition flow consolidation** (2026-06-15): the Forfeited/Abandoned details popup is now the single entry point for deciding a forfeited package's outcome, gated by appeal state. `PackageDetailsDialog` gained `allowFinalDisposition` (bool, default true) and `onSaleOrDestroyRequest(String disposition)`. The "Final Disposition" footer button is HIDDEN while the appeal window is still open — the Forfeited screen passes `allowFinalDisposition: pkg.isAppealExpired` (Abandoned passes the default true — no appeal). In `_FinalDispositionDialog`: **Release / Re-export / Other** → admin records directly via `recordFinalDisposition` → `[FINAL:…]` entry → item leaves the Forfeited table and surfaces in Released/Re-exported/Other screens. **Sale / Destroy** are now ENABLED (badge "CENTRAL DISPOSAL") but route through the new `onRequestDisposal` callback → `_requestSingleDisposal(fp,'sale'|'destruction')` on both screens → `createDisposalRequest(dispositions:{id:disp})` → package leaves Forfeited (now "requested") and appears in the directorate's Disposal Requests queue; they stay disabled if no request handler is wired or for officers. `getRequestableExpiredPackages` reverted to **appeal-expired only** (`lt('appeal_deadline', now())`) AND now also excludes `appeal_hold = true` rows and rows the directorate decided RELEASE/RE-EXPORT/OTHER. Net: appealing packages can't be disposed at all; expired ones get Release/Re-export/Other (direct) or Sale/Destroy (request).

## Hold Reasons → Post Status Activity (status-filtered, code-owned) (2026-08-18)
- **The admin-managed `hold_reasons` list is gone.** The SR Registration form's "Hold Reasons" section is now **"Post Status Activity"**, and its options are a fixed list in code, filtered by the item's **Status** — no DB table, no admin CRUD, no migration.
- **Single source of truth: [post_status_activities.dart](lib/core/post_status_activities.dart)** (same pattern as [yards.dart](lib/core/yards.dart) — edit only this file to add/rename an activity):
  - `kDetainActivities` — shown when Status = **Detain**: Pending Licence · Pending Classification / Valuation · Pending Inquiry · Other.
  - `kDisposalActivities` — shown for **Forfeit / Abandoned / Other**: Supposed to be Sold / Auction · Supposed to be Destroyed · Supposed to be Converted · Supposed to be Donated · Other.
  - `postStatusActivitiesFor(status)` returns the right (const) list; `kAllPostStatusActivities` is the de-duplicated union used by the read-only filter dropdowns (which must still match values already stored on older packages).
- **Storage is unchanged** — activities are still joined with `', '` into `package_items.reasons` and `warehouse_entries.hold_reason`, so existing data and every report/table that reads those columns keep working. **No migration; the `hold_reasons` table is simply no longer read.**
- **Status change resets the picks**: in both the SR form ([inspection_screen.dart](lib/screens/inspection/inspection_screen.dart)) and the edit dialog ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)), switching between Detain and a disposal status clears `selectedReasons` (identity-compares the two const lists), so a Detain activity can't linger on a Forfeit item. The dropdown `value` is also null-guarded against values outside the current list. Still max 4 ("Add Activity"), min 1, each selectable once.
- **Admin Panel lost its Hold Reasons tab** ([admin_screen.dart](lib/screens/admin/admin_screen.dart)): `_HoldReasonsTab` deleted, `DefaultTabController.length` 6 → 5. Remaining tabs: Officers · Warehouses · Items · Storage Charges · Logs.
- **Filters repointed** to `kAllPostStatusActivities` with the label **"All Activities"** (were DB-driven "All Reasons"): [warehouses_screen.dart](lib/screens/warehouses/warehouses_screen.dart), [abandoned_packages_screen.dart](lib/screens/packages/abandoned_packages_screen.dart), [returned_packages_screen.dart](lib/screens/packages/returned_packages_screen.dart).
- **Report renamed**: the "Hold Reasons" report card is now **"Post Status Activity"** ([reports_screen.dart](lib/screens/reports/reports_screen.dart) `_postStatusActivityRows`/`_viewPostStatusActivities`/`_generatePostStatusActivitiesPdf`/`_exportPostStatusActivitiesExcel`); `ReportService.generateHoldReasonsPdf`/`exportHoldReasonsToExcel` → `generatePostStatusActivitiesPdf`/`exportPostStatusActivitiesToExcel`, now taking `List<List<String>>` rows (Activity · Applies To Status) instead of `HoldReasonModel`s.
- **Dead code removed**: `HoldReasonService` ([services.dart](lib/services/services.dart)), `HoldReasonModel` ([models.dart](lib/models/models.dart)), `holdReasonServiceProvider`/`holdReasonsProvider` and the whole `hold_reasons` realtime channel block ([providers.dart](lib/core/providers.dart)). The `hold_reasons` table + its RLS/realtime entries are left in the DB (harmless, unread) — drop them only if you also clean the older migrations that create them.
- The details popup's `_DetailItem` label for `item.reasons` also reads **"Post Status Activity"** in all three places. Generic "Reason" column headers in disposal/tender tables were left alone (they show forfeit/disposal reasons, not this field).

## Report Generator status filter: real statuses, item-level (2026-08-18)
- **The bug**: the Report Generator's Status chip offered `PENDING · HELD · CLEARED · RELEASED` — values the app never produces. `PackageService.getAllPackages(status:)` filters `packages.status`, but **`updatePackageStatus` is never called anywhere**, so that column is written once as `'pending'` at registration ([inspection_screen.dart](lib/screens/inspection/inspection_screen.dart) `status: 'pending'`) and never changes. Result: HELD/CLEARED matched zero rows, RELEASED was explicitly skipped by the query (`status != 'returned'`), and PENDING matched everything. The real status lives on **`package_items.status`** (Detain/Forfeit/Abandoned/`Other: …`, then disposition values).
- **Fix**: new **`kReportStatuses`** const at the top of [reports_screen.dart](lib/screens/reports/reports_screen.dart) — `Detain · Forfeit · Abandoned · Other · Released · Sold · Destroyed` — exactly the values `_goodsData` puts in the reports' **Status** column. The dropdown renders these (uppercased) and nothing else.
- **Filtering moved off the query and into `_goodsData(packages, {statusFilter})`**, the single place that already resolves each item's ACTUAL outcome (Sold → Destroyed → Released → else `_normStatus(item.status ?? package.status)`). Rows whose resolved status ≠ the filter are skipped, so **the filter always matches the Status column the reader sees**. All three call sites (`_viewPackages`, `_generateAllPackagesPdf`, `_exportExcel`) dropped `status:` from `getAllPackages` and pass `statusFilter: _selectedStatus` instead, each with an "empty after filtering" → `_showNoDataMessage()` guard.
- **`_normStatus` now folds `Other: <custom text>`** (the SR form's Other marker) down to plain `Other`, so the Other filter matches those items; the custom text still shows in the Reason column.
- **View-dialog exports fixed too**: `_viewPackages`'s PDF/Excel buttons re-exported *every* package (`generatePackagePdf(pkgs)` / `exportPackagesToExcel(pkgs)`) while the on-screen table was filtered. They now export the exact rows shown via `generateStockRevenuePdf` / `exportTableToExcel` with `data.$1`/`data.$2`.
- `packages.status` and `getAllPackages(status:)` are left in place (other callers pass no status); the reports simply no longer rely on that stale column. No migration.

## Per-activity reports in the Report Generator (2026-08-18)
- New **"Post Status Activity Reports"** section (Section 2, between SR Register & Inventory and Goods Disposition) in [reports_screen.dart](lib/screens/reports/reports_screen.dart) — **one card per activity**, generated with `for (final activity in kAllPostStatusActivities)`, so adding an activity to [post_status_activities.dart](lib/core/post_status_activities.dart) grows this section automatically with no edit here. Later section comments renumbered 3→9.
- **`_generateActivityReport(activity, format)`** handles view/pdf/excel for one activity, mirroring `_emitForfeitedReport`'s shape. It reuses the shared item-level `_goodsData` column set (SR · Item · HS Code · Qty · Consignee · Reason · Status · Outcome Date · Receipt No · Value · Entry Date), so the rows match every other goods report.
- **Filters compose**: the report honours the Date-Range, Warehouse **and Status** chips at the top, so e.g. "Pending Licence" + Status=Detain = still-detained licence cases, while Status=All shows the whole history of that activity. Empty-after-filter → `_showNoDataMessage()`.
- **`_goodsData` gained `activityFilter`** (alongside the `statusFilter` added the same day) + helper **`_hasActivity(item, activity)`**: activities are stored comma-joined in `package_items.reasons` (up to 4 per item), so it splits on `,`, trims and compares case-insensitively — a substring match would wrongly conflate overlapping names.
- `_activityIcon` / `_activityColor` map each activity to a card icon+accent (pending ones amber/orange family, disposal ones reuse their outcome colours: Sold=teal, Destroyed=deepOrange, Converted=indigo, Donated=green), with a neutral fallback so a newly added activity still renders.
- As with every other card, the in-app **View** button appears only in `executiveMode`; officers/admins get PDF + Excel. No migration.

## Post Status Activity reports for Central Disposal (2026-08-18)
- **New 10th tab "Reports"** on the Central Disposal dashboard ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart), after Taxes; `DefaultTabController.length` 9 → 10) rendering `ReportsScreen(disposalMode: true)`.
- **`ReportsScreen` gained a third mode**: `disposalMode` alongside `executiveMode`. It shows **only** the Post Status Activity cards (`_buildActivityGrid`, extracted from Section 2 so the full Report Generator and this tab share one definition) — the rest of the Report Generator is yard-office business. Header retitles to "Post Status Activity Reports".
- **Cross-yard by default**: the yard dropdown renders with `allLabel: 'All Yards'` and `_reportYard` starts null, so disposal sees every yard at once and can narrow to one — matching the Sold/Destroyed tabs' behaviour rather than executive mode's "must pick a yard first" gate. `_yardArg` and `_filterByYard` now treat `executiveMode || disposalMode` the same, with null = all yards.
- **Why this works without new RLS**: `20260610_disposal_directorate.sql` already grants disposal cross-yard SELECT on **packages / package_items / warehouse_entries** (+ profiles) via `disposal_read_all` — exactly the tables `getAllPackages` + `_goodsData` read. **No migration.**
- **Warehouse filter hidden in disposal mode** — `warehouses` is NOT in the `disposal_read_all` set, so that dropdown would always be empty. Date-Range and Status filters still apply.
- **View button enabled for disposal** (`showView` is now `executiveMode || disposalMode`), since viewing in-app is the point of the tab; officers/admins still get PDF + Excel only.
- **Disposal TabBar is now `isScrollable: true`** (`tabAlignment: TabAlignment.start`): 10 fixed tabs squeezed every label to "Destroyed …". Each tab's `Row` gained `mainAxisSize: MainAxisSize.min` and the `Flexible(child: Text(…, ellipsis))` wrappers were unwrapped to plain `Text` — `Flexible` in an unbounded scrollable tab is a layout error.

## Director General's Office reports (SR list + valuations) (2026-08-19)
- New **"Director General's Office Reports"** section (Section 2) in [reports_screen.dart](lib/screens/reports/reports_screen.dart), wrapped in `if (widget.executiveMode)` so **only the DG/ADG Executive Office sees it** — yard officers/admins and Central Disposal never do. Later sections renumbered 4→10.
- **Three fixed-column listings** (columns are exactly as specified, nothing extra):
  1. **List of the SRs** — SR Number · Item Name · Goods Description · Quantity · Status. One row per package item; honours the Status filter via `_normStatus`.
  2. **List of Goods for Valuation** — SR Number · Item Name · Goods Description · Quantity · HS Code · **Initial Value**. Initial Value = the FIRST valuation a tender-sale package receives (`disposal_request_items.valuation_cost`, chain index 0). Only goods that actually reached valuation are listed.
  3. **List of Goods Valued** — SR Number · Item Name · Goods Description + the valuation columns.
- **Valuation rounds are capped at 4, and the 4th IS the final** — `kValuationRounds = ['Initial Value','2nd Value','3rd Value','Final Value']`. A new **"Valuation Round"** filter chip (executive-only) drives report 3: **All Valuations** shows all four columns side by side; picking one round shows just that column and lists only goods that reached it. "Final Value" resolves to the package's newest valuation (blank while only the initial exists), so a package re-valued twice shows its 2nd entry under Final.
- **New service methods** (both in `DisposalService`, [services.dart](lib/services/services.dart)): **`getValuationChains()`** returns `forfeited_package_id → [initial, 2nd, 3rd, …]` by combining `disposal_request_items.valuation_cost` with `tender_revaluations` ordered by `created_at`; **`getAllForfeitedForReports()`** fetches every forfeited row with package/item details, unfiltered by the work-queue rules that `getForfeitedPackages` applies (reporting needs the complete history, not the pending queue).
- Helper `_reportItemsOf(f)` resolves which package items a forfeited row covers (its own `item_id` for per-item rows, else all items, else `[null]` so the row still prints). `_emitDgReport` handles the view/pdf/excel triple from a pre-built column/row set.
- ⚠️ **Migration `20260819_executive_valuation_reports.sql`** — `tender_revaluations` was created in 20260716 and granted only to valuation/disposal/appeal, so the DG's 2nd/3rd/Final columns would come back **silently blank**. Adds `tender_reval_executive_read` (SELECT, `auth_user_is_executive()`). `tender_sales`/`tender_sale_items` already have `executive_read_all` from 20260718, and `disposal_request_items` from 20260714 — so this one policy is all that was missing. Apply in Supabase.

## High Panel Officers rename + corrected tender-round model (2026-08-19)
- **"Director General's Office" / "Executive Office" → "High Panel Officers"** across the UI: dashboard header ([executive_dashboard_screen.dart](lib/screens/executive/executive_dashboard_screen.dart)), home role card ([home_screen.dart](lib/screens/home/home_screen.dart)), login chip + wrong-portal errors, signup chip, and the reports section header. Icon changed from `workspace_premium`/`calculate` to **`Icons.shield_moon_rounded`** (the dashboard's tinted-SVG Customs logo was replaced by it; the big login-splash Customs emblem stays). The role/route names (`executive`, `/executive/*`, `AppTheme.executiveTeal`, `isExecutive`) are UNCHANGED — rename was cosmetic only.
  - ⚠️ `ExecutiveSignupScreen._fullName` now writes `'High Panel Officers (DG|ADG)'` to `profiles.full_name`, so **accounts created before this keep the old "Executive Office (DG)" badge** until edited.
- **Tender rounds renumbered — the first attempt is NOT "Tender 1"**. New helpers in [models.dart](lib/models/models.dart): `kMaxBidTenderRounds = 3` and **`tenderRoundLabel(attempt)`** (1-based):
  - attempt 1 → **"Valuation Tender"** — priced from the Valuation Directorate's *Pending Valuation*, not from bids, so it deliberately is not called Tender 1.
  - attempts 2/3/4 → **"Tender 1 / 2 / 3"** — each priced from the previous round's unsold bids (Unsold Tenders · Bids).
  - beyond that → "Committee Tender N".
  Applied in the valuation re-valuation dialog ([valuation_dashboard_screen.dart](lib/screens/valuation/valuation_dashboard_screen.dart)): `_roundLabel`, the "Next … · New Valuation" section title, and the "Decide the value for the next tender (…)" hint.
- **Committee threshold is unchanged and now reads correctly**: `getCommitteeEligiblePackages()` still uses `tenderCount >= 4`, which under the corrected naming is exactly "Valuation Tender + Tender 1 + 2 + 3 all unsold". Wording updated to "Packages still unsold after Tender 3" in both the High Panel tab and the Central Disposal read-only Committees tab.
- **ADG can now set a committee-round valuation** — new `Committee Value` column + `_CommitteeRoundValueCell` / `_CommitteeValuationDialog` in [tender_committee_tab.dart](lib/screens/executive/tender_committee_tab.dart). Gated to `profile.jobRole == 'ADG'` (the DG appoints members; the ADG prices the round) and disabled until a committee exists; the DG sees a read-only "Not set" / amount. **It writes through the existing `DisposalService.saveTenderRevaluation` into `tender_revaluations` keyed by the current `tender_sale_id`** — deliberately the same table the Valuation Directorate uses for Tender 1-3, so the valuation chain stays ONE continuous series and `getValuationChains()` (and every DG valuation report) picks committee values up with no extra wiring.
- ⚠️ **`20260819_executive_valuation_reports.sql` extended** — besides the SELECT policy it now adds **`tender_reval_executive_write`** (`for all`, `auth_user_is_executive()`) on `tender_revaluations`. Without it the ADG's save fails on RLS: `saveTenderRevaluation` DELETEs the round's old row then INSERTs, so both verbs are needed. Re-apply this file if you ran the read-only version yesterday.

## Dummy-data seed for testing (2026-08-19)
- **[supabase/seed_dummy_data_2026.sql](supabase/seed_dummy_data_2026.sql)** — wipes ALL package data and inserts **22 SRs** covering every SR-form field. Run in the Supabase SQL Editor. **Keeps** profiles / warehouses / storage rates / admin config; **deletes** packages, package_items, warehouse_entries, forfeited_packages, disposal_requests+items, tender_sales+items, tender_bids, tender_revaluations, tender_committees, destructions+items, tenders, tender_disposals, audit_logs.
- Structure: STEP 0 pre-flight (raises a clear "run these migrations first" error if `packages.old_sr_number` / `packages.yard` / `warehouse_entries.package_item_id` are missing, instead of dying mid-insert) → STEP 1 clear (loops a table array, skipping tables absent from older schemas) → STEP 2 seed → verification SELECTs (row counts per table + entry-date spread by month).
- Coverage: **30 SRs**, entry dates spread Nov 2025 – Feb 2026; yard GL1, SR format `GL1/SR/nn/YYYY`. **12 packages are multi-item** (2–4 lines), the rest single-item. Page coverage — Old Entries 4 (`old_sr_number` set), Released 4 (`[FINAL:RELEASED]` + item status `returned`), Abandoned 3 (`[ABANDONED]` entry on the first item + item status `Abandoned`), Other 3, Forfeited 11 SRs, rest held as Detain.
- **Forfeiture is recorded PER ITEM** — the seed inserts one `forfeited_packages` row per `package_items` row, so a multi-item package yields several rows all repeating the SAME SR number (that is what the Forfeited Packages table lists). 11 SRs → **19 rows**; SRs 05 (×3), 20 (×4), 25 (×2), 28 (×3) repeat.
- **Appeal window is driven by `forfeited_at`, not the entry date**: the outcome `forfeit` backdates `forfeited_at` to entry+40d (deadline long past → "Appeal Expired"), while **`forfeit_open`** sets it to `now() - 3..18 days` so `forfeited_at + 30 days` is still in the future → **"In Appeal"**. 5 SRs/10 rows expired, 6 SRs/9 rows in appeal.
- **"Disposition" on the Other Packages page = the custom text typed into the SR form's "Other Status" field** (or the label after `[FINAL:OTHER] — `). The Other packages are seeded as **court cases** ("Released/Held/Confiscated on court order — MC Colombo …"), with item status `Other: Pending court case`, since that is what the Other category represents in practice.
- **STEP 3 parks the appeal-EXPIRED rows MID-PIPELINE — nothing is finished.** Sold Packages and Destroyed Packages stay **EMPTY** on purpose (no `[FINAL:SOLD]`/`[FINAL:DESTROYED]` entry is written, no `status='sold'/'destroyed'` is set, the held warehouse entry is NOT deleted — the goods never leave the yard). Stages: **SR 05+23 → Pending Valuation (request A) · SR 31+34 → Pending Valuation (request B) · SR 20+33 → Unsold Tenders · SR 32 → Tender Committees · SR 12 → Undestroyed · SR 24 → Disposal Requests · SR 35 → forfeited & untouched**. Packages 31–35 were added purely to give each stage its own SR.
- **Tender Committees needs `tenderCount >= 4`** (`getCommitteeEligiblePackages`), i.e. the item must sit in FOUR `tender_sales` rows all with `sold=false`, each round's next-working-day deadline passed. Bids and `tender_revaluations` ARE per item (they key on `forfeited_package_id`), but the **sale headers are shared** — STEP 3 looks each up by `sale_number` before inserting, otherwise a multi-item package creates one header per item instead of one per round.
- **Each tender ROUND is its own `tender_sales` row on its own date.** Packages get different round counts (SR 20 ×1 · SR 33 ×2 · SR 26 ×3 · SR 27 ×2 · SR 32 ×4), and round `i` is dated `age + (rounds-i)*35` days ago, so the seed produces **12 distinct sales spread Apr–Aug 2026** — the yard's Tender Sale page lists many dated sales rather than one. Every round is unsold with a passed deadline.
- Stage routing uses a PL/pgSQL **searched `CASE … END CASE`** that sets `v_stage`/`v_rounds`/`v_age` together; the `ELSE` branch is required or a non-matching SR raises `CASE_NOT_FOUND`.
- **STEP 4 (SR 36–41) completes six disposals** so Sold/Destroyed have data — added without touching SR 01–35. Two routes to each outcome: **SOLD** SR 36 (1 round) · SR 40 (2) · SR 37 (4, multi-item); **DESTROYED** SR 38 (1) · SR 41 (2) · SR 39 (3, multi-item). Only the LAST round succeeds; earlier rounds stay recorded as unsold/undestroyed attempts, so the yard's Tender Sale page shows the full history (old rounds Unsold, final round Sold). The final round writes what the RPCs write: `[FINAL:SOLD]`/`[FINAL:DESTROYED]` returned entry + `status='sold'/'destroyed'` + held entry DELETED. STEP 3's routing must explicitly `skip` SR 36–41 or its `ELSE` fallback swallows them.
- ⚠️ **A NULL `hold_reason` or `item_count` on ANY warehouse_entries row makes that whole PACKAGE disappear from the UI.** `WarehouseEntryModel.fromJson` ([models.dart](lib/models/models.dart)) casts them as non-nullable (`json['hold_reason'] as String`, `json['item_count'] as int`), so a NULL throws mid-parse and the package is silently dropped — the row exists in SQL but never renders. Always `COALESCE` both when inserting entries by hand.
- ⚠️ **PL/pgSQL `SELECT … INTO` does NOT reset its target variables when it finds no row** — they keep the previous loop iteration's values. STEP 4 nulls `v_wh/v_zone/v_hold/v_rate/v_admat` before each lookup, because finalising a multi-item package DELETEs its held entries one by one, so by the 2nd/3rd item the warehouse lookup returns nothing and would otherwise inherit another package's warehouse (or leave NULLs that break the parse above).
- New STEP 2 outcomes `forfeit_sold`, `forfeit_sold_late`, `forfeit_destroyed`, `forfeit_destroyed_late`. The CASE arms were rewritten from value-form (`CASE r.outcome WHEN 'forfeit'`) to **condition-form (`WHEN r.outcome LIKE 'forfeit%'`)** so every forfeit variant is handled without listing each one six times; `LIKE 'forfeit%_destroyed%'` picks the destruction-bound ones for the Post Status Activity text.
- ⚠️ **Route by PACKAGE, not by row.** Routing per forfeited row put two rows of the SAME package into one stage, and the Unsold/Undestroyed views group per forfeited package — so the SR was listed twice in the table. The stage is chosen with `sr_number LIKE '%/nn/%'`.
- **Pending Valuation** (`ValuationService.getValuationRequests`) needs a `disposal_requests` row whose items have **`forwarded = false`** — the request stays in that feed while ANY item is unforwarded, and only the unforwarded items are shown. It shows **one card per request** with the items as rows. Because Central Disposal needs the opposite state (`valuation_status='forwarded'` + `forwarded=true`), STEP 3 creates **two** `disposal_requests`: one forwarded, one `pending_valuation`.
- **How each Central Disposal tab is fed** (all three gates were discovered by reading the services, and each needs a DIFFERENT row shape):
  - **Unsold Tenders / Undestroyed** — the item sits in a `tender_sales`/`destructions` row with `sold`/`destroyed` still **false** AND that sale's `workingDeadline` (next working day after `sale_date`) has PASSED. The goods stay **HELD** (no `[FINAL:…]` entry, item status unchanged) because nothing left the yard. Seeded via a second sale/destruction header dated 18 / 14 days ago.
  - **Disposal Requests** — `disposal_requests.valuation_status = 'forwarded'` (Central Disposal sees nothing otherwise) **and** the item's `disposal_request_items.forwarded = true` **and** its `forfeited_package_id` is in NO `tender_sale_items` and NO `destruction_items`. Any item placed in a tender/destruction drops off this tab — which is why the first STEP 3 draft left it empty.
- ⚠️ **`disposal_request_items` has NO `package_item_id` column** — the item is resolved through `forfeited_packages.item_id` (see `DisposalRequestItemModel`). `tender_sale_items` and `destruction_items` DO have one (20260622 / 20260625).
- ⚠️ **Sale/destruction dates must be in the PAST, never the future**: a package can only be disposed once its appeal window closes (`isAppealExpired` gates both actions in the app), so each date is `appeal_deadline + 20..25 days`, floored by `LEAST(…, now() - 9..12 days)`. Items still inside their 30-day window are deliberately left untouched. Two verification queries at the end assert no future-dated and no before-deadline disposal exists (both must return 0).
- ⚠️ **Run the whole file exactly once.** Re-running STEP 2/3 without STEP 1 duplicates every row — that is what produced 45 forfeited rows instead of 19, with SR/20's items listed twice in the UI.
- Post Status Activities are written into `package_items.reasons` / `warehouse_entries.hold_reason` using the real [post_status_activities.dart](lib/core/post_status_activities.dart) values, so the activity reports and filters have data.
- `total_item_count` / `declared_value` on the header are recomputed from the item lines after insert, so the package totals stay consistent.
- **Anon-key note**: the Supabase anon key cannot read or write ANY table (RLS returns 0 rows / 42501 on insert) — DB work has to go through the SQL Editor or a service-role key, not a script using the key in [db_client.dart](lib/core/db_client.dart).

## Auto-refresh on window focus + disposal table fixes (2026-08-20)
- **Data written outside the app never reached an open session.** Supabase realtime only delivers to a session that is *already subscribed*, so rows inserted by a SQL script (or while the window was backgrounded, or during a dropped socket) never arrived and the user had to press Ctrl+R. [main.dart](lib/main.dart) `_CustomsAppState` now mixes in **`WidgetsBindingObserver`** and implements **`onWindowFocus()`** + `didChangeAppLifecycleState(resumed)`, both calling `_refreshAll()` which bumps every refresh trigger (`packages`, `warehouse`, `forfeited`, `disposalRequests`, `tenderSales`, `tenderSaleItems`, `tenderBids`, `destructions`). The observer is removed in `dispose()`. Realtime still handles live in-app changes — this only covers the gap.
- **"Destruction Price: Rs 0.00"** — `_DestructionPriceCell` reads `destruction_items.destroyed_price` (added in `20260630_destruction_price.sql`, `NOT NULL DEFAULT 0`). The seed omitted it, so it defaulted to 0. STEP 4 now sets it (6% of the item value — a destruction *cost*, not a sale price) plus `applied_taxes`.
- **"BOTTOM OVERFLOWED BY 1.00 PIXELS"** in the Sold table's Valuation column — `_SaleValuationCell`'s `Column` had no `mainAxisSize.min` and its `@ unit × qty · re-valued` sub-label could wrap to a 2nd line. Added `mainAxisSize: MainAxisSize.min` + `maxLines: 1, overflow: ellipsis`, and widened all four Valuation columns from `fixedWidth: 112` → `132`.
- **High Panel header logo** — the earlier rename replaced the Customs emblem with `Icons.shield_moon_rounded`, leaving an empty box. Restored `SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg', theme: SvgTheme(currentColor: accent))` (the `flutter_svg` import had to come back too). Per [logo-ship-plane], it MUST use `SvgTheme(currentColor:)` — a `colorFilter srcIn` flattens the eye/ship detail.

### The sign-in panel animates, and the crest knockout follows it (2026-09-06)

- ⚠️ **The crest's ship and aeroplane are NOT transparent.** They are two
  paths painted a flat `#1a1764` -- the app's own dark navy -- because a real
  knockout does not survive `flutter_svg` (the shapes sit on a filled disc, and
  cutting them out needs an even-odd path or a mask the renderer drops).
  Painting them the background colour is what makes them read as holes. See
  [[logo-ship-plane]].
- **That trick only holds while the background behind them IS that colour**, so
  it was already visibly broken on any portal whose middle gradient stop is not
  navy -- Top Management's teal showed two navy stickers on the crest.
- [BrandPanel](lib/widgets/brand_panel.dart) is now the left half of **all
  fourteen** sign-in / sign-up screens (each passes its own `accent`,
  `deepColor` and badge; `badgeIcon` is nullable because one badge has never
  had an icon). Every frame it computes the colour behind the crest -- the
  gradient's MIDDLE stop -- and rewrites the fill in the SVG source via
  `crestWithKnockout()` before `SvgPicture.string`. The holes stay holes for
  the whole animation.
- **9s, eased, stops travelling as well as colours** -- it sits behind a
  password field, so it must read as light shifting rather than as an animation
  playing.
- ⚠️ **`withOpacity` cannot animate a colour on an opaque panel.** The
  accent was first animated `Color.lerp(accent.withOpacity(0.55), accent, t)`,
  which changes ONLY alpha -- red/green/blue never move, and with nothing behind
  the panel it looked completely static. It now mixes towards `deepColor`. A
  test measuring actual channel movement is what caught this.
- ⚠️ **`rootBundle` does not serve project assets in the test harness**, so
  the swap is tested against the real `.svg` file read from disk, not through
  the widget. Asserting on a colour passed around the widget tree would prove
  nothing: a knockout handed along correctly but never written into the SVG
  looks identical in the tree and wrong on screen. Tests:
  [brand_panel_test.dart](test/brand_panel_test.dart) (breaking the swap fails
  four of them).
- ⚠️ `pumpAndSettle` **never returns** on this widget -- the animation
  repeats for as long as the screen is open. Use `pump(duration)`.
- If the crest is ever re-exported with real transparency, delete
  `kCrestKnockoutHex` and `crestWithKnockout` -- not the animation.

## Committee valuation = two steps; Valuation Dte stops after Tender 3 (2026-08-20)
- **Central Disposal now uses the same round names as the Valuation portal** — `_roundLabel` in [disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart) calls the shared `tenderRoundLabel(attempt)`, so attempt 1 reads **"Valuation Tender"** (priced from Pending Valuation, not bids) and attempts 2-4 read **Tender 1/2/3**. It previously said "Tender 1/2/3/4".
- **The Valuation Directorate hands over after Tender 3.** In [valuation_dashboard_screen.dart](lib/screens/valuation/valuation_dashboard_screen.dart) the re-valuation dialog now hides the editor and the Save button once `_rounds.length > kMaxBidTenderRounds`, showing a "Referred to the High Panel" notice instead — the 4th price is a committee decision, not theirs.
- ⚠️ **Migration `20260820_committee_valuation.sql`** adds to `tender_committees`: `committee_value`, `committee_valued_at`, `committee_note`, `submitted_value`, `submitted_at`, `submitted_by`. **Apply in Supabase.**
- **The committee price is TWO separate acts, deliberately two column sets:**
  1. **DG appoints** the 5 members (existing flow).
  2. **The committee inspects and records its valuation** → `saveCommitteeValuation()` writes `committee_value` only. This does NOT price the tender.
  3. **The ADG submits it as the tender's final valuation** → `submitCommitteeValuation()` calls the ordinary `saveTenderRevaluation()` for the current round **and then** stamps `submitted_value`. Routing it through `tender_revaluations` means Central Disposal, the valuation chain and every report pick it up with no extra wiring.
  `TenderCommitteeModel` exposes `isAwaitingCommitteeValue` / `isAwaitingAdgSubmission` / `isSubmitted` for the three UI states.
- **The Committee Value cell has three states** (was: an ADG-only "Set Value" button that appeared before any committee existed): *no committee* → "Appoint first"; *appointed, unvalued* → **Committee Value** button; *valued* → the amount plus a badge — `Awaiting ADG` (DG's view), `Submit as Final` (ADG's view), or `Final` once submitted. Only the ADG can open the dialog after valuing.
- **A package now STAYS on the Tender Committees tab until the ADG submits** (`c == null || !c.isSubmitted`). It used to disappear the moment members were appointed, which left nowhere to record the valuation. **Central Disposal's Committees tab keeps showing it either way** (`committees.containsKey(...)`) — that tab is the read-only record, the High Panel tab is the action queue.
- **STEP 5 of the seed appoints the committees** — 8 of them (one per forfeited item; forfeiture is per item, so a 3-item package gets 3 committees). Each package gets a **different 5-officer roster**, rotated by `v_seq` so no two committees share members — the DG picks fresh officers per consignment, not a standing panel. All four states are seeded: **SR 44 has NO committee** (so the "Appoint" button is still testable) · SR 32 appointed only · SR 42/45 committee-valued · SR 43 ADG-submitted (which also writes the `tender_revaluations` row, exactly as `submitCommitteeValuation()` does).
- **An appointed committee is READ-ONLY** — `_CommitteeDialog._readOnly` (members non-empty) swaps the editable member forms for a roster view, and the table button becomes **"View (n)"** with an eye icon. The record of who valued the goods must not change after the fact.
- ⚠️ **`_isAdg(profile)` checks THREE places, not just `job_role`.** The ADG-only actions were locked out because the check read `profile.jobRole == 'ADG'` alone, and accounts created before the "High Panel Officers" rename can carry the position only in `username` ('adg') or in `full_name` ("… (ADG)"). The helper now tests all three.
- **The Committee Value cell is one tappable card**, not bare text with an `InkWell` on it: a bordered/tinted container holding the amount (with a leading status icon), the `@ unit × qty` line and a status line (`Final` / `Submit as Final` / `Awaiting ADG`), wrapped in `Material` + `InkWell` + `Tooltip` so the ripple and hover actually read as a button. Non-ADG users get the same card without the tap. Column widened 172 → 186.
- ⚠️ **A 3-line cell does NOT fit a default DataRow** ("BOTTOM OVERFLOWED BY 16 PIXELS"). Raising `dataRowHeight` fixes the overflow but makes the whole table look bloated, so **keep the default height and design the cell to TWO compact lines** instead (amount with a leading status icon + a short status line). The unit rate lives in the adjacent Valuation column anyway.
- **The dialog action row overflowed by 17px** — three buttons with long labels ("Save Committee Value" + "Submit as Final") did not fit the 480px dialog. Shortened to "Save Value" / "Update" / "Submit as Final" / "Re-submit" with `visualDensity: compact`.
- **Both committee note fields were single-line** so text ran off the end. They now use `minLines: 2, maxLines: 4` with `keyboardType: multiline`, a `labelText` + `alignLabelWithHint`, and the full `enabled/focused/disabled` border set (the valuation one only had `border:`, which is why it looked broken when disabled).
- **Blank member rows are IGNORED on save, not an error.** The form opens with five rows because five is the norm; leaving the spares empty is the normal way to appoint fewer. Only "at least one named officer" is enforced, and `_minCount` is 1 (was 2).
- ⚠️ **The committee size is NOT fixed at five.** Five is the norm, not a rule: `_CommitteeDialog` now starts at `_defaultCount = 5` but each row has a remove button and there is an "Add member" action, bounded by `_minCount = 2` / `_maxCount = 10`. The controllers are grown/shrunk lists rather than `List.generate(5, …)`, the section title shows the live count, and the validator says "enter a name … or remove the row" instead of "all 5 are required". Comments/labels across models, services and both dashboards were de-hardcoded from "5-member".
- Member names render through a shared **`_memberTile`** (name at 15px on its own line, designation + salary no. beneath at 12.5px) in both the roster view and the valuation dialog — the old inline `name · designation · No:` single 12px line was too cramped to read.
- The Committee Valuation dialog was mostly empty space: the cost field now sits **beside** the running total (flex 3:2) instead of each taking a full-width row, and the note field is 1 line rather than 2.

## Bids/valuation lock once issued + table flicker fix (2026-08-20)
- **Bids lock once the round is valued.** The valuation is decided BY reading the bids, so editing them afterwards would leave it resting on numbers that no longer exist. In `_EnterBidsDialog` ([disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart)) `_currentRoundLocked => _revals[_current.id] != null` swaps the editable fields + "Add bid" for read-only chips, a lock notice, and hides Save. The next round's bids go on the next round.
- **A saved valuation is no longer editable.** In [valuation_dashboard_screen.dart](lib/screens/valuation/valuation_dashboard_screen.dart) the cost/note fields take `enabled: !saved` and the Save button is hidden when `_alreadyValued` — the figure has already gone to Central Disposal.
- ⚠️ **"The Unsold Tenders / Valuation page keeps refreshing"** — TWO separate causes, both fixed:
  1. `async.when(loading: → spinner)` **without `skipLoadingOnReload: true`** made every per-row cell flash a spinner on each realtime event. Added to all 7 disposal cells.
  2. **The real one: `.asData?.value` returns NULL while a provider re-fetches**, so `?? 0` / `?? const {}` made the Bids count collapse `12 → 0` and the Re-valuation chip flip `Re-valued → Awaiting value` before snapping back. **Use `.valueOrNull`** — it keeps the previous value during a reload. Fixed in `_ValBidCountChip`, the disposal bids-count chip, both `tenderRevaluationsProvider` watches, `reTenderEligibleProvider` (×2) and `tenderCommitteesProvider` (disposal + executive).
  Rule: in a **`ref.watch`** used for rendering prefer `valueOrNull`; `asData?.value` is only safe in a `ref.read` inside a callback.
- Each row of these tables watches TWO `.family` providers, so ~9 rows = ~18 providers all keyed to `tenderBidsChangeTriggerProvider` — one event re-fetches every one of them, which is why the collapse was so visible.
- **`Item +N` means "this item plus N more in the package"** (`Wash Basins +2` = 3 items). ⚠️ It was being shown on EVERY row of a multi-item package, because `_valItemName` / `_cItemName` / `_committeeItemName` fell straight from a null `f.itemName` to `items.first`. Since forfeiture is recorded per item, each row must resolve **its own** item via `f.itemId` first — added to all three. (The other four resolvers in the disposal screen already did this.) `ForfeitedPackageModel.itemName` is only populated for synthetic per-item rows; `itemId` is the reliable link.
- **`_fmt(double)` printed binary artefacts** — `b.toString()` rendered `222272.63999999998` instead of `222,272.64`. Both the disposal and valuation copies now use `NumberFormat('#,##0')` / `('#,##0.00')`.

## Re-tender gating + committee value is ADG-entered (2026-08-21)
- ⚠️ **Same round, two different names.** The Valuation portal titled its editor `Next ${tenderRoundLabel(rounds.length + 1)}` while Central Disposal called the same round `tenderRoundLabel(rounds.length)` — so SR/27's 2nd round read as "Tender 2" in one portal and "Tender 1" in the other, making it look like a round had been valued that never took bids. The Valuation editor prices the **current** round (the one whose bids are listed above it), so it now uses `rounds.length` too.
- **`getReTenderEligibleIds()` now enforces all three conditions**, not just the first:
  1. the current round carries a `tender_revaluations` row (was already there);
  2. **that round actually has `tender_bids`** — the valuation is decided FROM bids, so without this a package could be re-tendered on a price nobody bid against;
  3. **past Tender 3 (`rounds > kMaxBidTenderRounds`) it needs `tender_committees.submitted_value`** — the price is a committee decision and only counts once the ADG submits it.
  `reTenderEligibleProvider` already watches `tenderBidsChangeTriggerProvider`, whose channel covers `tender_bids`, `tender_revaluations` **and** `tender_committees`, so an ADG submission unlocks the package live.
- **The ADG enters the committee's figure, not the DG.** `_CommitteeValuationDialog`'s cost/note fields are `enabled: isAdg`, the "Save Committee Value" button is `isAdg && !c.isSubmitted`, and the table cell shows the DG a read-only *"Awaiting ADG entry"* instead of an **"Enter Value"** button. The DG appoints the members; the ADG records what the committee decided and then submits it.
- ⚠️ **The Unsold Tenders "Re-valuation" chip showed `eligible`, not whether a valuation exists** — so once the re-tender gate started requiring the ADG's submission, committee packages that WERE valued read as "Awaiting value". It now has **three** states via `_ReTenderStatusCell` (a Consumer resolving `tenderRevaluationsProvider` + `tenderCommitteesProvider`): **Re-valued** (green, re-tenderable) · **Awaiting ADG** (blue — committee has priced it, ADG has not submitted) · **Awaiting value** (amber — no price at all).
- **The Record Bids popup now shows the committee's figure** (`_committeeValueSection()`): the amount, whether it is submitted or still awaiting the ADG, and the committee note. Past Tender 3 the price is a committee decision, so Central Disposal needs to see it and why the package is or isn't re-tenderable yet.
- **A package leaving the Tender Committees tab while showing "Re-valued" is correct, not a bug** — the ADG submitted, so it left the High Panel queue and became re-tenderable. Central Disposal's Committees tab still lists it as the record.

## Valuation Unsold table: Pending/Valued filter + history badge (2026-08-21)
- **All / Pending / Valued segmented filter** (`_ValStatusFilter` + `_valUnsoldStatusProvider`, null/false/true) on the Valuation Directorate's Unsold Tenders table, plus an "N of M awaiting valuation" count on the right. "Pending" is that directorate's actual work queue.
- ⚠️ It is driven by a **new** `valuedCurrentRoundProvider` → `DisposalService.getValuedCurrentRoundIds()`, deliberately NOT `reTenderEligibleProvider`: eligibility also demands bids and, past Tender 3, the ADG's submission, so a package the Valuation Directorate HAS valued would wrongly read as Pending. This one answers only "does the current round carry a `tender_revaluations` row?".
- **The "Times" column is now a tappable badge** (`_ValAttemptsBadge` → `_ValTenderHistoryDialog`) matching Central Disposal's `_AttemptsBadge`, instead of bare `4×` text. The history dialog is a local copy — `_TenderSaleHistoryDialog` is private to the disposal file — and labels rounds with the shared `tenderRoundLabel` (Valuation Tender, Tender 1-3), oldest first, with the newest marked "Current".
- ⚠️ **A filter alone did not make Pending vs Valued readable** — every row still had the same gold "Value" button, so the state was invisible unless you filtered. `_ValRevalCell` now renders **amber "Set Value"** when pending and a **green single-line card with the amount** when done (still tappable to review the bids). Kept to one line so the row height stays default.
- **Packages past Tender 3 are excluded from the Valuation Unsold table entirely** (`info.tenderCount <= kMaxBidTenderRounds`), and from its pending count. They belong to the High Panel — a committee prices them and the ADG submits it — so the Valuation Directorate has no action left on them. The dialog's `_handedToHighPanel` branch is now only a safety net for a package crossing the threshold while the dialog is open.

## Build env: C: is full — temp moved to D: (2026-08-21)
- `flutter run` failed with **`FileSystemException: writeFrom failed … app.dill (OS Error: There is not enough space on the disk, errno = 112)`**. Not a code fault: **C: had 0 GB free** of 156 GB.
- Cleared user Temp (1.75 GB, incl. 8 stale `flutter_tools.*` folders), Windows Temp and the Windows Update download cache → only ~1 GB recovered.
- Fix applied: **user `TMP`/`TEMP` env vars now point at `D:\FlutterTemp`** (D: has 28 GB). Builds succeed again. ⚠️ Open a NEW terminal for this to take effect — existing shells keep the old value.
- ⚠️ **C: is still ~0.8 GB free.** The unaccounted ~25 GB is `pagefile.sys` (19 GB) + `hiberfil.sys` (6 GB); `powercfg /h off` would reclaim the hibernation file, but that is a system-level change left to the user. Largest folders: Users 49 GB, Windows 37 GB, Program Files (x86) 25 GB.
- Note: clearing `%LOCALAPPDATA%\Temp` wholesale also deletes this session's scratchpad/tasks dirs under `Temp\claude\…`; recreate them if a tool call reports a missing output file.

## Unsold Proposals tab gated to exhausted packages (2026-08-21)
- The **Unsold Proposals** tab (Central Disposal, "Unresolved / Unsold Packages") watched `unsoldTenderSalesProvider` **unfiltered**, so it listed every unsold package — including ones the Valuation Directorate had not finished with. A final outcome is only proposed once **every** avenue is exhausted, so it now requires BOTH: `info.tenderCount > kMaxBidTenderRounds` **and** `tenderCommitteesProvider[fpId].submittedValue != null` (the ADG submitted the committee's figure, it was tendered again, and it still did not sell). Banner text updated to say so.
- **The Proposal cell overflowed the row** — a `Wrap` of four chips in a 300px column spilled onto a second line. Now a single horizontally-scrollable `Row`, column widened to 430, and "Government Use" shortened to "Govt. Use".

## Unsold final outcome: High Panel decides, 3 portals show it (2026-08-21)
- ⚠️ **Screenshots/alt-tab reloaded every table.** My `onWindowFocus → _refreshAll()` fired on EVERY focus event, so any brief focus loss re-fetched and reset tables to page 1. Now **throttled to one forced refresh per 2 minutes** (`_lastForcedRefresh` + `_refreshCooldown` in [main.dart](lib/main.dart)) — realtime already covers live changes; the focus refresh only exists to catch writes made while unsubscribed.
- ⚠️ **Migration `20260821_unsold_proposals.sql`** — new `unsold_proposals` table (one row per forfeited package, `proposal` in destroy|remand|government_use|auction, + note/yard/decided_by/decided_at). RLS: **High Panel `for all`**, Central Disposal / Valuation / Appeal read-only, and the **owning yard read-only for its own yard**. Added to the realtime publication. **Apply in Supabase.**
- **`getExhaustedUnsoldPackages()` is the single source of truth** for "every avenue exhausted": past Tender 3 **and** `tender_committees.submittedValue != null` (committee re-valued, ADG submitted, tendered again, still unsold). Exposed as `exhaustedUnsoldProvider`, and **all three portals read it**, so their lists agree by construction.
- **Who does what**: the **High Panel decides** (new 3rd tab `UnsoldDecisionTab` — radio-card dialog for the four outcomes + optional reason, All/Pending/Decided filter); **Central Disposal** and the **yard** only *display* the decision. Central Disposal's action chips were replaced with a read-only `_ProposalOutcomeChip` — showing buttons there implied that directorate could choose.
- **New yard page `/unsold-packages`** ([unsold_packages_screen.dart](lib/screens/packages/unsold_packages_screen.dart)), nav item added right after "Sold Packages" in both officer and admin navs. Filters to the officer's own yard (belt-and-braces over RLS, since the shared provider is cross-yard).

## Change Log Summary (inferred from git)
- Built admin dashboard, package management, reporting + centralized providers & package details dialog.
- Added Google sign-in + `verifyUserSession`; admin login UI.
- Added forfeited packages + tenders (models, services, `TenderPlacementDialog`, disposal flow); dummy-data scripts.
- Barcode printing/saving; Windows Inno Setup installer.
- Year filter for package management; warehouse item status/charge handling.
- Multi-yard support — `yard` column + RLS isolation (migrations 001/002), yard dropdowns at signup/profile, yard-locked SR registration, shared `OneTapDatePicker`, warehouse summary cards reworked ("yard manage and dropdown fixed").
- **Central Disposal Directorate** (2026-06-10): new third role `disposal` (`lib/screens/disposal/`, green accent) + standalone dashboard `/disposal` (3 tabs: Sold · Forfeited · Tender Sales, polished tab bar + flutter_animate fades/slides + stat chips). Cross-yard **SOLD** + **FORFEITED** package visibility (shared yard dropdown `disposalSelectedYardProvider`) via SELECT RLS (`auth_user_is_disposal()` on packages/items/warehouse_entries/profiles + `forfeited_packages` in `20260610_disposal_forfeited.sql`); **Tender Sale** form (`tender_sales`: sale number/date/serial/year/type Special·General Cargo·Motor Vehicle). Migrations `20260610_disposal_directorate.sql` + `20260610_disposal_forfeited.sql`; `DisposalService.getSoldPackages`/`getForfeitedPackages`/`createTenderSale` + `TenderSaleModel` + `kTenderSaleTypes`.
  - **Institutional accounts, not personal**: exactly two — `DC` and `SDDC` (head office). Signup form collects **position + branch email + password** only (no name/yard/salary); `username` = `dc`/`sddc` (the unique username index limits to one per post), `full_name` = `Disposal Directorate (DC|SDDC)`, `job_role` = position. Whoever holds the post signs in with the shared credentials. `kDisposalPositions` in models.
  - **OTP on EVERY login**: `AuthService.startOtpLogin` (verify password → email OTP) then `finishOtpLogin` (verify code → session). Disposal login is two-step with the same countdown/resend (2 resends → 2-hour lock) as signup.
  - Disposal accounts are exempt from the 8-month auto-expiry (`ProfileModel.isExpired` returns false for `disposal`).
  - Logo on disposal screens uses `Sri_Lanka_Customs_logo_tinted.svg` + `SvgTheme(currentColor:)` (NOT `colorFilter srcIn`, which flattens the eye/ship detail).
  - **Disposal Requests workflow** (2026-06-11): the yard-side Forfeited Packages screen's old "Place Tender" button is replaced by **"Send Disposal Request"** → new [disposal_request_dialog.dart](lib/screens/forfeited_packages/disposal_request_dialog.dart) (no tender number; request **date** + select from appeal-passed packages; **per-package Destruction/Sale** toggle). Submitting writes a `disposal_requests` row + `disposal_request_items` (one per package). Central Disposal's **Disposal Requests** tab lists each submission as a separate per-yard card (yard badge, date, submitted-by, Destruction/Sale count pills + a packages table with disposition chips & details). Providers: `requestableForfeitedPackagesProvider`, `selectedRequestDispositionsProvider` (Map id→disposition), `disposalRequestsProvider`, `disposalRequestsRefreshProvider`. Migration `20260611_disposal_requests.sql`. NOTE: `TenderPlacementDialog`/`/tender-disposals` tender flow is untouched (still used by the Tender Disposals screen).
  - **Tender Sale → Sold flow** (2026-06-11): the **Tender Sale form** now has a package picker that lists ONLY `disposition='sale'` disposal-request items not yet in a sale (`getSaleRequestItems`/`saleRequestItemsProvider`, cross-yard); selected packages become `tender_sale_items` rows (`createTenderSale(packageYards:)`). The **Tender Sales** list is now expandable cards (`_TenderSaleCard`, design like Tender Disposals) showing each package's items with Item·Qty·Forfeit Reason·SR·Case No·Location(yard/warehouse)·Goods Description, plus a per-package **Mark Sold** action (optional receipt). Marking sold calls `markTenderSaleItemSold` → `disposal_mark_sale_item_sold` RPC (SECURITY DEFINER) which writes a `[FINAL:SOLD]` warehouse entry **in the package's own yard**, flips `package_items.status='sold'`, and deletes the held entry — so it appears in that yard's Warehouses AND the cross-yard Sold Packages tab (UI triggers `packagesRefreshTriggerProvider` + `tenderSalesRefreshProvider`). Migration `20260611_tender_sale_items.sql` (table + RPC). `ForfeitedPackageModel` gained a `yard` field. DB writes here use `AuthService._withNetworkRetry` (semaphore-timeout resilience).
  - **Mark-sold RPC hardened + yard outcomes restricted** (2026-06-11): the first `disposal_mark_sale_item_sold` keyed warehouse context strictly on `package_item_id`, so packages whose entries are admitted package-level (no item link) or have none wrote NO `[FINAL:SOLD]` row → never appeared in Sold Packages/Warehouses (the card said "Sold" but tables stayed empty). Robust version (in the original migration **and** `20260611_tender_sale_mark_sold_fix.sql` for already-migrated DBs): per item prefer its own latest entry, else ANY package entry (`order by (package_item_id = r.item_id) desc nulls last, admitted_at desc`); if the package has no entries at all, anchor one package-level SOLD entry to any warehouse so it still surfaces. Run the `_fix` file if you already ran the original. Also: the **yard Tender Disposals** record-disposal popup ([tender_disposal_screen.dart](lib/screens/forfeited_packages/tender_disposal_screen.dart) `DisposalDialog`) now **disables Sold / Destroy / Government Use** (`_restrictedTypes`, shown greyed with a lock + "Handled by the Central Disposal Directorate"); only Re-export / Other remain for yard admins, since those three outcomes are centralised. A new **Release** outcome (`'release'`, heldOrange, `Icons.lock_open_rounded`) was added to the popup (enabled for yard admins) — needs `20260611_tender_disposal_release.sql` (widens the `tender_disposals_disposal_type_check` constraint to include `release`). Also the yard **Forfeited Packages** table gained a **Details** column (info icon → shared `PackageDetailsDialog`, like the Abandoned page).
  - **Taxes tab** (Central Disposal, added externally): [taxes_tab.dart](lib/screens/disposal/taxes_tab.dart) (`TaxesTab`, 5th disposal tab) CRUD on tax rates via `DisposalService.getTaxes/createTax/updateTax/deleteTax` + `DisposalTaxModel`. Needs table `disposal_taxes` (`name`, `percentage`, `is_active`, `created_at`) — migration **`20260611_disposal_taxes.sql`** (RLS: disposal manages, authenticated reads). Without it: `PGRST205 Could not find the table 'public.disposal_taxes'`.
  - **Tender Sale sold-price / taxes / delivery** (added externally): the Mark Package Sold dialog now captures a **Sold Price** + applied taxes, and packages can be flagged **Delivered**. `TenderSaleItemModel` gained `soldPrice`/`appliedTaxes`/`isDelivered`/`deliveredAt`; `markTenderSaleItemSold` passes `p_sold_price`+`p_applied_taxes`; new `toggleDeliveryStatus`→`disposal_toggle_delivery_status` RPC. Needs **`20260611_tender_sale_sold_price.sql`**: adds columns `sold_price`/`applied_taxes`(jsonb)/`is_delivered`/`delivered_at` to `tender_sale_items`, REPLACES `disposal_mark_sale_item_sold` with the 4-arg `(uuid,text,numeric,jsonb)` version, and adds `disposal_toggle_delivery_status(uuid,boolean)`. Without it: `PGRST202 Could not find the function …(…, p_sold_price)`.
  - **Infinite-spinner fix** (2026-06-11): the per-row sale-info cells (`_DeliveryStatusCell`/`_SaleFinancialsCell` in [disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart) + [disposition_category_screen.dart](lib/screens/packages/disposition_category_screen.dart)) and the details dialog's `_SaleFinancialsSection` ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)) each `_loadData()` via `getTenderSaleItemForPackage` but had NO try/finally — on a network error / `maybeSingle` multi-row throw `_loading` stayed true → spun forever. Added try/catch/finally everywhere (sets `_saleItem=null`, clears loading). Also hardened `getTenderSaleItemForPackage` (gathers all forfeited ids, `inFilter` + `limit(1)` instead of `maybeSingle` on a possibly-multi-row query). The yard Sold table also gained a **Financials** column (sold price + tax total) to match the Central Disposal Sold tab; both Sold tables show **Delivery** (tap to toggle on yard; the central one toggles too) and the details dialog shows price + each tax + total + delivery.
  - **Delivery toggle: yard auth + button style** (2026-06-11): `disposal_toggle_delivery_status` was disposal-only, so yard admins toggling delivery from their Sold table hit `not authorized / P0001`. Migration **`20260611_delivery_toggle_yard.sql`** REPLACES it to allow the package's own yard too (`v_yard = (select yard from profiles where id = auth.uid())` OR `auth_user_is_disposal()`); also baked into `20260611_tender_sale_sold_price.sql` for fresh installs. **Delivery action moved to the details dialog** (yard-only): the Sold tables now show delivery as a read-only **status chip** (`DeliveryStatusChip` Delivered/Pending) and the financials/delivery cells are `ConsumerWidget`s watching a shared `saleItemForPackageProvider(packageId)` (FutureProvider.family, single fetch per package). The **Mark Delivered / Mark as Not Delivered** button lives in `PackageDetailsDialog`'s `_SaleFinancialsSection`, shown only when `!profile.isDisposal` (yards confirm delivery; Central Disposal views only); on toggle it `ref.invalidate(saleItemForPackageProvider(id))` so the table chip updates live. **The yard-toggle still requires running `20260611_delivery_toggle_yard.sql`** — without it the RPC returns `not authorized / P0001`. (If a Sold row's Financials/Delivery shows "—" it's a transient network catch — reopen/restart.) Follow-ups: Delivery column widened to `fixedWidth: 120` (chip was overflowing ~6px in `ColumnSize.S`); the details "Mark Delivered" button now `Navigator.pop`s the dialog after a success snackbar; and the SOLD details view is decluttered via an `isSoldContext` flag in `PackageDetailsDialog` (hides Warehouse Summary Receipt No/Date, the Total Packages / Released row, and the Warehouse Charges section — the Sale & Financial section covers it).
  - **Cross-session delivery sync via realtime** (2026-06-11): `saleItemForPackageProvider` cached per session, so a yard marking Delivered didn't show up in the (separate) Central Disposal session. Added `tenderSaleItemsChangeTriggerProvider` (StreamProvider subscribing to `tender_sale_items` postgres changes, like the packages/forfeited realtime) + `tenderSaleItemsRefreshProvider`; `saleItemForPackageProvider` now `ref.watch`es it so any insert/update/delete (delivery toggle, new sale, mark-sold) re-fetches in every open session. **Requires migration `20260611_tender_sale_items_realtime.sql`** which adds `tender_sale_items` to the `supabase_realtime` publication (idempotent) — without it the realtime events never fire and the table stays stale until reopened.
- **Admin UX pass** (2026-06-09): all Admin Panel dialogs (Add Officer, Add/Edit Warehouse, Add/Edit Category, Storage Charges, Add/Edit Hold Reason) restyled with the shared [styled_form_dialog.dart](lib/widgets/styled_form_dialog.dart) (gradient header + gold-headed section cards + gold primary button) to match the SR Register edit modal. **Account auto-deactivation**: accounts (admins + officers) auto-deactivate 8 months after `created_at` — `ProfileModel.isExpired`/`isEffectivelyActive`; `signIn`/`verifyUserSession` throw `account_expired`; the manual active/inactive toggle in the Officers table is **removed** and replaced with a read-only ACTIVE/EXPIRED/INACTIVE chip (with an "auto-deactivates on …" tooltip). Officers tab uses `skipLoadingOnReload: true` so the 2-min heartbeat realtime refresh no longer flickers the table.
- **Auth overhaul** (2026-06-09): removed "Grey Line 1" branding everywhere (multi-yard app); **officers can no longer self-register** — admins create them from Admin → Officers ("Add Officer": email/mobile/salary/name → email OTP verify → system-generated username+password emailed via Resend, using the `admin-officers` Edge Function so the admin stays logged in); **username support** (`profiles.username`) — admins choose a username at signup, officers get a generated one and can change username+password in Edit Profile; **login accepts username OR email** in one field (resolved by `email_for_login` RPC). New migration `20260609_officer_username_auth.sql`. SMS OTP intentionally not used (email OTP only).
- **Latest** (2026-06): styled yard dropdowns (gold popup) on signup/profile/admin; warehouse cards → All/Detain/Forfeit/Abandoned (+ removed Confiscated chip); custom "Other" status badge in package details; tender dialog polish (themed number field, shared calendar, Select All/Clear All); disposition tables now match both `[FINAL:…]` and `[RE-EXPORT]`/`[DESTROY]` tags; **Year filter** (`YearFilterButton`) + Date Range added to all history/disposition pages (packages, abandoned, released, forfeited, sold/destroyed/re-exported/other, tender disposals); sign-in surfaces real errors (no more vague "check credentials"); **auto-update** via `auto_updater` + Supabase `updates` bucket.

## Unsold Packages — one shared table across three portals (2026-08-21)

- **[unsold_shared.dart](lib/screens/executive/unsold_shared.dart) is the single source for the Unsold table.** The yard page, Central Disposal's tab and the High Panel's tab previously each built their own columns, so the SAME package showed different details in each place — and Central Disposal showed the wrong **Qty** (it summed EVERY item in the package: 375/105/105 where the yard correctly showed 85/60/45 for the row's own item). The module exports `kUnsoldColumns`, `unsoldCells()`, `kUnsoldTableMinWidth`, the per-row resolvers (`unsoldItemName`/`unsoldQty`/`unsoldHsCode`/`unsoldLocation` — all resolve `f.itemId` FIRST, since forfeiture is per item), `unsoldOutcomeStyle()` and the read-only `UnsoldOutcomeChip`. Only the **Final Outcome** cell is portal-specific (a Decide button for the DG, the chip for everyone else).
- **Keep the table to essential columns only — do NOT widen it into a sideways scroll.** `kUnsoldTableMinWidth` is **900**, which fits the window. Columns are exactly: **SR Number · Item · Qty · Consignee · Location · Valuation · Final Outcome · Details**. Deliberately dropped: **Tenders** (every row on this table has exhausted all 4 rounds, so a "4×" badge everywhere says nothing), plus **Case No / HS Code / Yard** — case no + yard moved into the SR cell's hover tooltip, HS code lives behind Details.
- **Only the DG decides the final outcome; the ADG is view-only.** `_isDg()` in [unsold_decision_tab.dart](lib/screens/executive/unsold_decision_tab.dart) checks `job_role` / `username` / `full_name`, and **tests the ADG patterns FIRST** — `"(ADG)"` also contains `"DG"`, so a naive DG match would grant the ADG rights. Signup stores `job_role` as exactly `'DG'`/`'ADG'` (one account each). When `canDecide` is false the cell renders `UnsoldOutcomeChip` and the subtitle reads "the DG decides the final outcome". Note this contrasts with the **Tender Committees** tab, where the **ADG** submits the committee valuation (`_isAdg` there) — the two posts own different steps.
- **All three Unsold tables are paged** (20/page, `TablePager`) — the High Panel and Central Disposal tabs hold their page index in a `StateProvider` (`_uPageProvider` / `_unsoldPageProvider`) reset to 0 whenever a search/yard/status filter changes; the yard page keeps it in widget state.
- **Header alignment**: the yard dropdown carries a floating "Yard" label, so it is taller than a bare search field — `Row`'s default centring left the two visibly offset. The header uses `crossAxisAlignment: CrossAxisAlignment.end` with both controls pinned to `_kFilterHeight` (52), the title+subtitle stacked in a `Column` inside `Expanded`, and `_UYardFilter` taking its width/height from the caller (`helperText: null` so no helper line adds height).
- Dead code removed along the way: `_ProposalActionChip`, `_ProposalOutcomeChip` and the unused `proposalStyle()` in [disposal_dashboard_screen.dart](lib/screens/disposal/disposal_dashboard_screen.dart); the local `_itemName`/`_qtyOf`/`_hsCodeOf`/`_location`/`_style`/`_OutcomeChip` in [unsold_packages_screen.dart](lib/screens/packages/unsold_packages_screen.dart) (all now shared).
- **Screenshot-reload bug**: `onWindowFocus` in [main.dart](lib/main.dart) called `_refreshAll()` on EVERY focus event, so taking a screenshot re-loaded the Sold page from the start. Now throttled by a 2-minute `_refreshCooldown`.
- Still pending in Supabase: **`20260821_unsold_proposals.sql`** (the `unsold_proposals` table + RLS + realtime) — without it no decision saves.

### Unsold gate: a package reaches the DG only AFTER the committee-priced tender fails (2026-08-22)

The full route is **Valuation Tender → Tender 1 → 2 → 3** (all unsold) → committee valuation → **ADG submits it as the tender price** → **the package is tendered AGAIN at that price** → only if THAT round also fails does it reach the DG's Unsold Packages table for a final outcome.

- **Bug found**: `getExhaustedUnsoldPackages()` checked only `tenderCount > kMaxBidTenderRounds` **and** `committee.submittedValue != null` — it never checked that the committee-priced tender had actually run. So a package appeared on the DG's table the instant the ADG submitted, while it still sat at 4×/"Re-valued" in Central Disposal's Unsold Tenders with a live chance of selling. The doc comment already claimed "tendered again, and still unsold"; the code did not enforce it.
- **Fix**: added the third condition `i.sales.any((s) => s.createdAt.isAfter(committee.submittedAt))`. Because `getUnsoldTenderSales()` already guarantees *not sold* + *latest round's deadline passed*, a round created after the submission timestamp means exactly "the committee-priced tender ran and failed". Needs `submittedAt`, not just `submittedValue`.
- **Second gap, opposite direction**: `getReTenderEligibleIds()` kept offering a package for re-tender even after the DG had decided its final outcome. Added a 4th filter that drops any id present in `unsold_proposals`. The DG's save also `ref.invalidate(reTenderEligibleProvider)` so Central Disposal's pool updates immediately (realtime on `unsold_proposals` rides the `tender-bids-realtime` channel → `tenderBidsChangeTriggerProvider`).
- **Seed for it**: `supabase/seed_exhausted_unsold.sql` (additive + idempotent, clears nothing). The main 2026 seed stopped at "ADG submitted", so NO package satisfied the 5th-round condition. This script finds every package at that stage without an already-run final tender and adds the committee-priced round: one `tender_sales` row PER PACKAGE (a shared row could not sit after every package's own `submitted_at`), `created_at = submitted_at + 1h`, sale date 2 days later, three bids BELOW the committee price. If a submission is too recent for the sale day to be in the past, it pulls the sale day back **and** moves `submitted_at` back with it — `created_at` must stay after `submitted_at` or the chain breaks. Ends with a verify query listing exactly what the DG's tab should show.
- Watch the asymmetry: **ADG** submits the committee valuation (Tender Committees tab, `_isAdg`), **DG** decides the final outcome (Unsold Packages tab, `_isDg`). Two different posts, two different steps — do not merge them.

### StyledDropdownFormField: splash radius + never force its height (2026-08-22)

- The inner `InkWell` **fills whatever box it is given**. Wrapping it in `SizedBox(height: 52)` made the hover splash spill past the drawn field as a pale band underneath. Size it via `contentPadding` instead and let the widget pick its own height.
- Its splash radius was hard-coded to **12** while callers theme the field with a **14** `OutlineInputBorder`, so the splash showed at the corners. Added an optional `splashRadius` param **defaulting to 12** (all ~35 existing usages unchanged); the High Panel yard filter passes `splashRadius: 14`.
- Also pass `helperText: null` on header filters — the default `' '` reserves a helper line and adds height.

### Hot reload cannot change a widget's superclass (2026-08-22)

`type 'X' is not a subtype of type 'ConsumerWidget?'` after a hot reload means a widget changed base class (here `ConsumerWidget` → `ConsumerStatefulWidget`). **Hot restart (`R`), not `r`.** Separately: never clear `%TEMP%` while `flutter run` is live — it deletes the live `flutter_tools.*` dir and the Dart compiler dies with `PathNotFoundException: app.dill.incremental.dill`. User `TMP`/`TEMP` are now permanently set to `D:\FlutterTemp` (C: runs at ~1 GB free).

### High Panel report set trimmed + "Not Sold Packages" report (2026-08-22)

The High Panel portal reuses `ReportsScreen(executiveMode: true)`, so its report set is carved out of the shared screen with `if (!widget.executiveMode)` gates rather than a separate widget.

- **View button is gone for the High Panel.** `_buildReportCard`'s `showView` changed from `(executiveMode || disposalMode) && onView != null` to **`disposalMode && onView != null`** — their cards offer PDF + Excel only. Central Disposal keeps View; yard portals never had it.
- **Hidden from the High Panel** (all still present for yards / Central Disposal): Category & Zone Summary, Package History, Old Entries, the whole **Post Status Activity Reports** section, the whole **Goods Disposition** section (Forfeit / Abandoned / Other / Re-export), Warehouse Stock, Warehouses List, the whole **Financial Reports** section (Storage Charges, Released Revenue), the whole **System Configuration** section (Post Status Activity, Item Categories) and **QR Code Labels**.
- **Kept for the High Panel**: Packages Inventory Audit · the four High Panel reports · Sold · Destroyed · the five Stock & Revenue reports · Released Packages.
- **New 4th High Panel report — "Not Sold Packages"** (`_generateNotSoldReport`): columns **SR Number · Item Name · Goods Description · High Panel Committee Members · Proposed Decision**. Source is `getExhaustedUnsoldPackages()` (the same 5-rounds-failed gate the DG's Unsold tab uses) joined to `getTenderCommittees()` for the appointed members and `getUnsoldProposals()` for the ruling. Members print one per line as `Name (Designation) · SalaryNo`; no committee → "No committee appointed"; no ruling → "Pending decision". Note `CommitteeMember.designation`/`salaryNo` are **nullable** — use `?.trim() ?? ''`.
- Uses the shared `_emitDgReport(...)` helper (handles the empty case, period label, PDF preview and Excel export), so a new fixed-column DG listing is ~60 lines.
- **Sold-tender report columns changed** (2026-08-22): the `'sold'` case of `_stockRevenueReport` now prints **SR Number · Goods Name · Goods Description · Sold Value · Total Tax · Total Amount** — HS Code and Sold Date dropped, Goods Description added. NOTE the `'sold'` case shares its row-building with `'revenue'`, so the change affects both listings' columns.
- **5th High Panel report — "High Panel Valuation"** (`_generateHighPanelValuationReport`): **SR Number · Goods Name · Goods Description · Final Valuation · High Panel Valuation**. Lists only packages where `tender_committees.submitted_value` is set. Key subtlety: the ADG's submission ALSO writes a `tender_revaluations` row, so it is the LAST link of `getValuationChains()` — the Valuation Directorate's own final figure (what Tender 3 was priced at) is `chain[chain.length - 2]`, not `chain.last`.
- **"Item Name" / "Item" → "Goods Name" everywhere** (2026-08-22): every user-facing COLUMN HEADER and details-dialog field label now reads **Goods Name** — 42 occurrences across the reports screen (PDF/Excel `columns` lists) and 20 UI tables (dashboard, forfeited, abandoned, other, returned, disposition, warehouses, appeal, disposal, valuation, tender committee, tender disposal, unsold_shared, package_details_dialog). Only display strings changed — model fields (`itemName`), variables and helpers (`unsoldItemName`) keep their names, so nothing in the data layer moved.
- **Role split corrected — the ADG appoints the committee, NOT the DG** (2026-08-22). Earlier notes and comments said "DG appoints"; that was wrong. The final split is:
  - **ADG** owns the whole Tender Committees tab: appoints the members AND submits the committee's valuation. `_CommitteeDialogState._readOnly` now returns true when the members already exist **or** the signed-in officer is not the ADG, so the DG gets the roster view instead of the Appoint form. The table button reads "Appoint" only for the ADG, "View" otherwise, and the tab subtitle switches to "… the ADG appoints the committee".
  - **DG** owns the Unsold Packages tab: the final outcome (destroy / remand / government use / auction). `_isDg` in [unsold_decision_tab.dart](lib/screens/executive/unsold_decision_tab.dart).
  - Opening the roster for a package with no committee shows an explanatory empty state rather than a blank panel.
  - **No migration needed**: `tender_committees` RLS uses `auth_user_is_executive()`, which already covers both posts — the split is enforced in the UI only.
- **Two controls on a filter row must share ONE contentPadding** (2026-08-22): the search field had `vertical: 14` and forced `height: 52` while the yard dropdown used `vertical: 12` and sized itself — so they rendered at different heights no matter what `crossAxisAlignment` was set. Fixed with a shared `_kFilterPadding` const on both and NO explicit height on either. Two further causes in the same bug: a floating label draws ABOVE the box (pass `floatingLabelBehavior: FloatingLabelBehavior.never`, added as an optional param defaulting to null), and the dropdown's 24px arrow had no height cap (`suffixIconConstraints` now carries `maxHeight: 24`).
- **A package leaves the Committees tab once it reaches Unsold Packages** (2026-08-22): Central Disposal's `_CommitteesTab` listed every package that had a committee, so a package that had already exhausted the committee-priced tender showed in BOTH the Committees tab and the Unsold Packages tab. It now subtracts the ids in `exhaustedUnsoldProvider` — the committee's work is finished at that point. The High Panel's own Tender Committees tab already did the equivalent (it drops rows once `committee.isSubmitted`), so only the Central Disposal tab needed the fix. The two tabs use DIFFERENT exit conditions on purpose: the High Panel's card is about doing the appointment + submission, Central Disposal's is a record of who was appointed and stays visible while the committee-priced tender is still running.
- **Unsold Tenders is a RE-TENDER pool, not a list of everything unsold** (2026-08-22). A package appears there only while it can still be tendered again; once the committee-priced round fails it moves to **Unsold Packages** and must disappear from Unsold Tenders. It was showing in BOTH (the `5×` rows in Central Disposal's Unsold Tenders were already on the Unsold Packages tab). Three places needed the exclusion:
  1. `_UnsoldReTenderTab`'s row list — subtracts `exhaustedUnsoldProvider` ids.
  2. Its "Unsold — re-tenderable" count pill — must count the SAME filtered rows, or the number disagrees with the table.
  3. `getReTenderEligibleIds()` — a new condition drops any package with a `tender_sales` row created after `tender_committees.submitted_at` (that round IS the committee-priced attempt, and `getUnsoldTenderSales` already guarantees it went unsold). This also keeps them out of the Re-tender FORM's package picker.
- **The "Awaiting ADG" chip covered two different states** (2026-08-22): a package with no committee value at all, and one the committee HAS priced but the ADG has not submitted, both read "Awaiting ADG". `_ReTenderStatusChip` now takes a separate `committeeValued` flag and shows **"Committee valued"** (blue, `price_check`) for the second, plus a tooltip spelling out each state.
- **Screenshot-reload, properly fixed** (2026-08-22): the earlier 2-minute throttle was not enough — `onWindowFocus` fires for a screenshot, an alt-tab, or a click on any other app, and each one reset every table to page 1 mid-read. `onWindowFocus` is now **removed entirely**. The refresh survives only on `didChangeAppLifecycleState`, and only when a `_wasDetached` flag says the app was actually `paused`/`detached` first (bare `resumed` also arrives after a brief focus loss). Cooldown raised to 15 minutes. Realtime already covers live changes; this path exists only for writes made while the socket was down.
- **A short fixed-length value in a `ColumnSize.M` column with a CENTRED label leaves a huge gap.** Package History's Cusdec Date / Entry Date looked detached from their neighbours for exactly this reason. Dates are ~10 chars — give them `size: ColumnSize.S, fixedWidth: 110` and left-align (drop the `Center()` on both label and cell).
- **"Item" → "Goods" in the SR form and details dialog** (2026-08-22): Package Items→Package Goods, Add Item→Add Goods, Item Name *→Goods Name *, the "Item N" badge→"Goods N", Items Distribution→Goods Distribution, Item Details→Goods Details, in [inspection_screen.dart](lib/screens/inspection/inspection_screen.dart) + [package_details_dialog.dart](lib/widgets/package_details_dialog.dart). **"Item Categories" in the Admin panel is left alone** — that is the feature's actual name, not a label for goods.
- **"Packages" → "Goods" in every user-facing name** (2026-08-22), completing the earlier "Item Name → Goods Name" pass. Renamed: the nav bar's 9 entries in [app_shell.dart](lib/widgets/app_shell.dart) (BOTH role lists — the file defines the items twice), every page title + subtitle (Abandoned/Released/Other/Unsold/Forfeited Goods, Goods History, Goods Registration), the three DispositionCategoryScreen titles which live in **[router.dart](lib/core/router.dart)** not the screen, the Central Disposal + High Panel tab labels and headers, "Unsold Goods — Re-tender", Decided Goods, Recent Goods, Not Sold Goods, Select Goods, No. of Goods.
- Only display strings moved — **routes keep their `/…-packages` paths**, and models/providers/variables keep their names, so nothing in routing or the data layer changed. "Item Categories" in the Admin panel is still untouched: that is the feature's own name.

## The 30-day appeal window now applies to EVERY status (2026-08-23)

It used to be forfeit-only. Detain, Abandoned and "Other" goods are now frozen for the same 30 days: no Goods Action, no disposal request to Central Disposal, and the Appeal Directorate can take an appeal on any of them.

- **The clock runs from the goods' ENTRY DATE**, not from when an officer changed the status — so a package sitting for months is actionable immediately while a fresh one waits. Shared helpers in [models.dart](lib/models/models.dart): `kAppealWindowDays`, `appealDeadlineFrom(entryDate)`, `isWithinAppealWindow(entryDate)`, `appealDaysLeft(entryDate)`. **Use these everywhere** rather than re-deriving the window.
- **Root cause of the old behaviour**: abandoned / "other" `forfeited_packages` rows were written with `appeal_deadline = now() - 1 day`, and the synthetic rows in `getRequestableExpiredPackages()` used a local `expiredDeadline` sentinel — both deliberately skipping the window. Both now use `appealDeadlineFrom(pkg.entryDate ?? pkg.createdAt)`, and the requestable pool `continue`s past anything still inside its window.
- **Migration `20260823_appeal_window_all_statuses.sql`** backfills existing rows. It targets only rows where `appeal_deadline <= forfeited_at` (the old "yesterday" sentinel) — a genuine forfeit's deadline is always `forfeited_at + 30 days`, so those are untouched.
- **Goods Actions popup** (was "Package Actions", in [package_details_dialog.dart](lib/widgets/package_details_dialog.dart)): takes a new `entryDate` and folds `!inAppealWindow` into the existing `isActionEnabled()` hook, so ALL actions grey out together, with an amber "Appealing · Nd left" banner explaining why.
- **New [AppealStateChip](lib/widgets/appeal_state_chip.dart)** — amber "Appealing · Nd" vs green "Enabled", with a tooltip naming the exact close date. Added as an **Appeal** column on the yard's Abandoned and Other tables.
- **Appeal Directorate sees all four statuses.** `appealForfeitedPackagesProvider` now merges `AppealService.getForfeitedPackages()` (real forfeit rows) with the new `ForfeitedPackageService.getInAppealNonForfeitPackages()`, which synthesises in-window Detain/Abandoned/Other rows (they have no `forfeited_packages` row until a disposal request is sent). Both appeal tables gained a **Status** chip column after SR Number naming the source; the pre-existing appeal-state column was renamed **Appeal State** to avoid two columns headed "Status".
- **Tender Bids tab removed from the Appeal portal** (never requested): tab count 3→2, the `_BidsTab` + `_ViewBidsDialog` classes deleted, `bidsCount`/`packagesWithBidsProvider` watch dropped.
- **[AppealStateChip](lib/widgets/appeal_state_chip.dart) is the ONE appeal-state chip** (2026-08-23). Four yard tables carry it under an **Appeal** column of the same name and width (130): **Forfeited · Abandoned · Other · Warehouses**. Amber "Appealing · Nd" while open, green "Enabled" once passed, tooltip naming the close date. The Forfeited screen's old green "Appealing" / red "Appeal Expired" chip is gone — that was a second wording for the same state. Its appeal-HOLD and appeal-DECISION branches are kept: those are genuinely different states that take priority over the window.
- On the Warehouses table the window is driven by `warehouse_entries.admitted_at`, which IS the entry date; elsewhere it is `pkg.entryDate ?? pkg.createdAt`. Warehouses already had a "Status" column (DETAIN/FORFEIT) — a different axis — so the appeal chip sits in its own column beside it.
- **`AppealStateChip` takes an optional `deadline` that WINS over `entryDate`** (2026-08-23). A genuine forfeit stores its own `appeal_deadline` (= `forfeited_at + 30`), which is LATER than entry + 30 — feeding the chip the entry date showed live appeals as "Enabled" on the Forfeited table. That screen now passes `deadline: pkg.appealDeadline`. Abandoned / Other / Warehouses have no recorded deadline and keep deriving from the entry date.
- **`supabase/seed_appeal_scenarios.sql`** — additive, idempotent test data on its own SRs (GL1/SR/61–74/2026) covering: in-window and window-passed for all four statuses, two forfeits ON APPEAL HOLD, and one forfeit per decision (RELEASE / SALE / DESTROY / RE-EXPORT). Ends with a verify query and a commented-out UNDO block.
- **Seed schema gotchas** (cost time; check against `seed_dummy_data_2026.sql` before writing new seeds): `packages` has **`inspected_by`/`inspected_at`, NOT `created_by`**; `package_items` uses **`unit_of_measure`** (not `unit_type`), carries its own **`yard`**, and **`reasons` is plain text**; `warehouse_entries` uses **`is_returned`** (not `returned_at`), carries **`yard`** + **`daily_rate`**, and has **no `warehouse_name`/`status`**; there is **no `warehouse_zones` table** — `zone` is a text column. Item `status` is capitalised ('Detain'/'Forfeit'/'Abandoned'/'Other').
- **Appeals can now be LODGED against Detain / Abandoned / "Other", not just forfeits** (2026-08-23). Those statuses have no `forfeited_packages` row, so the appeal portal lists synthetic ids `"<pkgId>:<itemId>:<source>"` — but `set_appeal_hold` / `release_appeal_with_decision` take a **uuid**, so a hold on one would have failed. `AppealService._materialiseForfeitedRow()` now converts a synthetic id to a real one first (a plain uuid passes through untouched), and BOTH RPC calls go through it.
- **The insert must be a SECURITY DEFINER RPC, not a client insert**: the appeal role holds only SELECT on `forfeited_packages` (`appeal_read_all`), so a direct insert is refused by RLS. Migration **`20260824_appeal_materialise_row.sql`** adds `appeal_ensure_forfeited_row(package_id, item_id, source)` — it re-checks `auth_user_is_appeal()`, refuses any source other than detain/abandoned/other, returns the existing row if one was already created, and stamps `appeal_deadline = entry_date + 30 days` to match what the synthetic row was showing.
- `seed_appeal_scenarios.sql` extended to **SR 61–76**: hold and decision states now exist for **every** status, not only forfeit (hold on Forfeit/Detain/Abandoned/Other; decisions Forfeit→RELEASE, Detain→SALE, Abandoned→DESTROY, Other→RE-EXPORT). The plain in-window / passed non-forfeit rows are deliberately left WITHOUT a `forfeited_packages` row so the synthetic path stays exercised.
- Two bugs in `getInAppealNonForfeitPackages()` found on first run (2026-08-23): (a) it emitted a row for items that are ALREADY forfeited, which `AppealService.getForfeitedPackages()` also returns — every forfeit would have appeared twice; now `continue`s on `pkg.isItemForfeited(item.id)`. (b) It set `yard: AppSession.currentYard`, which is **null for an appeal officer** (they belong to no yard) — `PackageModel` drops the `yard` column, so the raw row is kept and `row['yard']` read off it.
- **An item's status is derived from its WAREHOUSE ENTRIES, not from `package_items.status` alone** — the single biggest seed gotcha. `_itemIsRequestableAbandoned` / `_itemIsRequestableOther` look for a **RETURNED** entry whose `return_notes` start `'[ABANDONED]'` / `'[OTHER'`; Detain is simply "still held, no such event"; Forfeit is `isItemForfeited()`. A seed that sets only `package_items.status='Abandoned'` still shows up as **Detain** in the Appeal portal. `seed_appeal_scenarios.sql` therefore writes the held entry AND, for Abandoned/Other, the returned disposition entry. Its verify query derives the status the same way, so it predicts exactly what the portal will list.

### High Panel now has THREE posts, and one rule resolves them (2026-08-23)

`kExecutivePositions` = **DG · ADG · DC**. `executivePostIs(profile, code)` in [models.dart](lib/models/models.dart) is the single resolver — it checks `job_role`, `username` and `full_name` (older accounts carry the post in only one of them) and, crucially, **rejects a code if a LONGER post also matches**, because `"(ADG)"` contains `"DG"`. `isExecutiveViewOnly(p)` == `executivePostIs(p, 'DC')`.

| Action | DG | ADG | DC |
|---|---|---|---|
| Appoint tender committee | yes | yes | **no** |
| Submit committee valuation as final | no | yes | no |
| Decide an unsold package's outcome | yes | no | no |
| Reports · view every tab | yes | yes | yes |

- Committee appointment changed from ADG-only to `!isExecutiveViewOnly(...)`. `_isAdg` / `_isDg` in the two tabs are now one-line wrappers over `executivePostIs`, so the "(ADG) contains DG" trap is handled in exactly one place.
- Signup needed no structural change — the position dropdown already renders `kExecutivePositions`, and `executive_position_available(code)` is generic — only the copy ("one account per post (DG · ADG · DC)").
- **A Dart RegExp built from a variable must use raw-string fragments**: `RegExp(r'\(\s*' + c + r'\s*\)')`. Writing `'\(\s*$c\s*\)'` in a normal string silently loses the escapes and matches literal text.
- `warehouses` has **no `yard` column** — warehouses are shared and the yard lives on `warehouse_entries.yard`. Seeding hit `42703: column "yard" does not exist`; pick a warehouse via `EXISTS (select 1 from warehouse_entries where warehouse_id = w.id and yard = ...)`. `supabase/precheck_seed_columns.sql` lists any column a seed assumes but the DB lacks — run it before a new seed.
- **`forfeited_packages.source` has a CHECK constraint** — it was `('forfeit','abandoned','other')`, so writing a **detain** row failed with `23514 ... forfeited_packages_source_check`. Migration **`20260825_forfeited_source_detain.sql`** adds `'detain'`. Needed by both the seed and `appeal_ensure_forfeited_row` at runtime. Any new source value needs this constraint widened first.
- **An appeal now creates a `forfeited_packages` row, so "row exists" no longer means "sent for disposal".** Two places keyed on mere existence and would have stranded appealed goods permanently — both now join through `disposal_request_items`:
  - `sentAbandonedOtherFpKeysProvider` — hid the row from the yard's Abandoned/Other table.
  - `getRequestableExpiredPackages()`'s `abandonedFpPkgIds` / `otherFpItemKeys` — dropped it from the requestable pool.
  The PostgREST shape is `.from('disposal_request_items').select('forfeited_packages!inner(...)').eq('forfeited_packages.source', ...)`, and each row arrives wrapped: unwrap `row['forfeited_packages']` before reading the columns.
- **`packages.entry_date` is `timestamptz`, not `date`.** `entry_date + 30` fails with `42883: operator does not exist: timestamp with time zone + integer`. Cast first: `p.entry_date::date + 30`, or add an `interval '30 days'`. The seed's DO block was fine (its `v_entdt` is declared `date`); only the trailing verify query hit this.
- **Both Appeal tables now sort by `appealDeadline` ascending.** They page at 20 rows and had NO sort, so "missing" goods (a Detain and an Other that were genuinely in the list) were simply on page 2 while the pager read "Showing 1-20 of 22". Soonest-deadline-first puts the urgent appeals on page 1. Not a data bug — check the pager count before assuming rows are absent.
- `seed_appeal_scenarios.sql` widened to **SR 61-86**: 9 goods ON APPEAL HOLD (5 Forfeit · 2 Detain · 3 Abandoned · 1 Other) and 9 DECIDED across all four outcomes, so every state has several rows rather than one.
- **`getInAppealNonForfeitPackages()` must MERGE the stored row, not always synthesise.** It originally emitted a fresh model with a synthetic id and no appeal fields — so once an appeal was lodged on Detain/Abandoned/Other goods, the hold was invisible ("On Appeal Hold" undercounted) and the row could never be released or decided, because the RPCs need the real uuid. It now pre-loads `forfeited_packages` where `source in (detain, abandoned, other)`, keys them `"<pkgId>:<itemId>"`, and when one exists emits THAT row (real id + `appealHold` + `heldItemIds` + decision fields) with `packageDetails` grafted on; the synthetic path is only for goods no appeal has touched.
- **Destroying Deposit** (2026-08-23) — a deposit the declarant lodges against the cost of destroying the goods. **PACKAGE-level: one figure per SR**, not per goods item, so it lives on `packages.destroying_deposit` (numeric, nullable) beside `container_number`. Migration **`20260826_destroying_deposit.sql`**.
  - Wired in six places on `PackageModel` (field, ctor, `fromJson`, `toInsertJson`, `copyWith` param, `copyWith` body). **Both create AND edit persist through `toInsertJson()`** (`createPackage` and `upsertPackage` both spread it), so adding the key to that one map covered saving everywhere.
  - UI: the SR registration form ([inspection_screen.dart](lib/screens/inspection/inspection_screen.dart)) — it filled the empty `Expanded` placeholder that already sat beside Container Number; the read-only details view AND the in-dialog update form in [package_details_dialog.dart](lib/widgets/package_details_dialog.dart). Optional field, validated as a non-negative number, `FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))`.
  - Every portal shares ONE `PackageDetailsDialog`, so adding the row there put it in every details popup at once.
  - **`supabase/backfill_destroying_deposit.sql`** fills every existing SR: one value per `packages` row, derived as 5% of the package's goods value (`sum(quantity * unit_value)`), rounded to the nearest 500 and clamped to 5,000..250,000, with a 10,000 fallback when the package has no priced items. Only touches `destroying_deposit IS NULL`, so it is re-runnable and never overwrites a hand-entered figure.
- **Popup valuation now matches the tables** (2026-08-23): the Sale / Destruction sections showed only a bare number (and the unit price when the qty lookup fell through to 1). Replaced with `_ValuationDetailRow`, a small `ConsumerWidget` in [package_details_dialog.dart](lib/widgets/package_details_dialog.dart) that watches `tenderRevaluationsProvider(fp.id)`, prefers the **LATEST re-valuation** over `fp.valuationCost`, prints `total  (@ unit x qty)`, and labels itself **"Valuation (Rs) · re-valued"** in blue when the figure came from a re-valuation. Only the latest valuation is shown — earlier rounds are history.
- **`supabase/backfill_sale_taxes.sql`** — sold/destroyed goods showed `Tax: Rs 0.00` because `applied_taxes` was an empty jsonb array (they were marked sold before any tax was configured). The script seeds VAT 18% + Cess 5% into `disposal_taxes` if no active rate exists, then writes `[{name, percentage, amount}]` against each item's `sold_price` / `destroyed_price`. Touches only rows whose array is empty, so it is re-runnable and never overwrites app-captured taxes. The `destruction_items` half is guarded by a column-existence check.
- The yard's Unsold page passed `headerAccentColor: gold` to `PackageDetailsDialog`; every other yard page passes **nothing** (default blue). Removed so the popup matches its siblings.
- **Tender History section on the Unsold popup** (2026-08-23): `TenderHistorySection` in [package_details_dialog.dart](lib/widgets/package_details_dialog.dart) lists EVERY round a package went through — Valuation Tender, Tender 1/2/3, then the committee round — each with the price it was offered at and the bids recorded against it. Rendered when the caller passes the new `tenderHistoryFor:` param (all three Unsold pages do: yard, Central Disposal, High Panel); null hides it.
  - Round ORDER comes from `tenderSalesProvider` filtered to sales containing this `forfeited_package_id`, sorted by `createdAt` — that index is what `tenderRoundLabel(i + 1)` turns into the name. Valuations (`tenderRevaluationsProvider`) and bids (`tenderBidsProvider`) are both keyed by `tender_sale_id`, so they join straight onto it.
  - **Round 1 has no `tender_revaluations` row** — it ran at the Valuation Directorate's original `forfeited.valuationCost`; only rounds 2+ carry a re-valuation. Rounds with neither a price nor a bid are skipped, and the section hides itself when nothing survives.
  - `_DetailSection` takes **`child` + a required `delay`**, not `children`.
- **The committee round takes NO bids** (2026-08-23) — user caught this. Bids exist only to PRICE the next round (Tender 1/2/3 are each re-valued from the previous round's bids). The committee round is the LAST one: the committee fixes the price, the ADG submits it, and if it still does not sell the package goes straight to the DG. There is no further round to price, so bids there are meaningless. Fixed in two places:
  - `seed_exhausted_unsold.sql` no longer seeds bids on that round, writes a `tender_revaluations` row carrying the ADG's submitted price instead (so the round shows a figure), and DELETEs bids an earlier revision wrote against `GL1/TS/2026/F%` sales.
  - `TenderHistorySection` computes `isCommitteeRound = (i + 1) > kMaxBidTenderRounds + 1` and renders "Priced by the tender committee · no bidding" in place of the bid chips.
- `unsoldCells()` gained an optional **`valuationColor`**. The directorate tables keep the green highlight (the money is what they act on); the **yard** table passes `context.colors.textPrimary` because it is only being told what happened.
- Removing the committee round's bids made the ROW vanish, because `TenderHistorySection` skipped any round with no price and no bids — and that round's price lives on `tender_committees.submitted_value`, not necessarily in `tender_revaluations`. Fixed: the section watches `tenderCommitteesProvider`, falls back to `committee?.submittedValue` for a committee round, and never skips a committee round (it is the last attempt — hiding it would end the history at Tender 3).
- **The Sold popup showed `@ unit x 1` while the table showed `x 40`.** The sale query does NOT join `package_items`, so `saleItem.forfeited.packageDetails` is null inside the popup and `_ValuationDetailRow`'s qty fallback landed on 1. Fixed by threading the real figure through: the Sold tab passes `valuationQty: r.entry.itemCount` (the same value its Valuation cell multiplies by), `_SaleFinancialsSection` / `_DestructionDeliverySection` gained a `valuationQty` param, and the dialog falls back to `widget.highlightEntry?.itemCount` so any caller that passes nothing still agrees with its row. **When a popup and its table disagree on a number, check whether the popup's query joined the table the fallback reads from.**
- Central Disposal's Unsold tab was the one popup in that portal passing `headerAccentColor: blue`; every other one uses `successGreen`. Now green.

## High Panel · Financials tab (2026-08-23)

Fourth tab on the High Panel portal ([financials_tab.dart](lib/screens/executive/financials_tab.dart)), showing income, expenditure and the distribution of sale proceeds.

- **INCOME is DERIVED, never entered** — `financialSummaryProvider` computes it from records the system already holds: **SR charges** (`WarehouseEntryModel.calculatePackageCharge(p.items, rates)` — note it takes the ITEMS list, not the package), **Destroying deposits** (`packages.destroying_deposit`), **Sale proceeds** (`tender_sale_items.sold_price` where sold) and **Taxes** (the `applied_taxes` amounts on those sales).
- **EXPENDITURE is hand-entered**, because nothing else records it: destruction costs, advertising costs, refunds. New table `financial_expenses` (migration **`20260827_financial_expenses.sql`**) with a `kind` check constraint, RLS letting executives + Central Disposal write and everyone else read, and realtime.
- **The proceeds split is reported SEPARATELY from the net balance** — it distributes money already counted as income, so adding it to the balance would double-count. `SaleProceedsSplit` in models: Reward Fund 50%; Deputy Secretary of the Treasury 50%, which splits again into Consolidated Fund 60% of that half (**30% overall**) and Comp Fund 40% of it (**20% overall**). Reward + Consolidated + Comp reconciles back to 100% of proceeds.
- The **DC is view-only** here too (`isExecutiveViewOnly`): no Record Expense button, no delete.
- The committee round in the Tender History now lists the **appointed committee members** as numbered chips (name + designation, salary no. in the tooltip), so the price and the people who set it read together. `TenderHistorySection` already watches `tenderCommitteesProvider`, so it just passes `committee?.members` down to the tile.
- **[package_details_dialog.dart](lib/widgets/package_details_dialog.dart) imports material TWICE**: `as material` plus a selective `show` list. Anything not in that `show` list (e.g. `Tooltip`, `Alignment`) must be written `material.Tooltip` / `material.Alignment`.
- **`TabController` length must match the number of `Tab` widgets, and a `late final` one survives hot reload.** Adding the 4th High Panel tab left a 3-length controller live: the bar painted 4 tabs but clicks resolved against the old controller, so tapping did nothing while swiping still worked. The screen now holds a nullable controller and re-creates it in `build` whenever `_kTabCount` changes.
- **`tender_bids` had NO read policy for the executive or yard roles** — only disposal / appeal / valuation. That is why the Tender History said "No bids recorded" in the High Panel and yard popups while Central Disposal showed them: the rows existed, RLS filtered them out. Migration **`20260828_tender_bids_read_access.sql`** adds `tender_bids_executive_read` (via `auth_user_is_executive()`) and `tender_bids_yard_read` (matching the bid's own `yard` column). Read-only — recording a bid stays with Central Disposal.
- **When a section renders in one portal but is empty in another, suspect RLS before the widget.** Every join the Tender History makes has its own policy set: `tender_sales` (round order), `tender_revaluations` (prices), `tender_bids` (bids), `tender_committees` (members). `supabase/diagnose_tender_history.sql` dumps all four per SR from the SQL editor (which bypasses RLS), so the truth can be compared against what a portal shows.

## Committee members never rendered — a call site that was never wired (2026-08-23)

The Tender History's committee round showed "Priced by the tender committee · no bidding" in EVERY portal, never the members. It was not RLS (`tender_committees_auth_read` allows any authenticated read) and not missing data — an earlier edit added the `committeeMembers` **field and its rendering block** to `_TenderRoundTile`, but never added the argument at the `rows.add(_TenderRoundTile(...))` call site, so the `const []` default won every time. **When a feature is invisible in all portals at once, check the call site before suspecting the database.**

- The round is also detected more defensively now: `isCommitteeRound` is true past Tender 3 **or** on the last round once `committee?.submittedValue != null`, so a package whose earlier rounds were never recorded still names its committee.
- `committeeLoading` separates "the list has not arrived" from "nobody was appointed", so the tile can say which instead of silently listing none.
- **`tender_revaluations` had no YARD policy** — Valuation, Disposal, Appeal and Executive only. That is why a yard's Unsold popup showed Tender 1/2/3 with no price and no "re-valued" mark while Central Disposal showed all of them. Migration **`20260829_tender_history_read_access.sql`** grants the owning yard (and any authenticated officer) read access, and re-asserts the committee read.

## Expenses are recorded PER GOODS, and the refund is DERIVED (2026-08-24)

Central Disposal records what each goods item cost to dispose of; the High Panel reads the result. Costs are incurred item by item — one SR holds many goods, each destroyed and advertised on its own.

- **A refund is never entered.** The destroying deposit is money held against those costs, so whatever is left goes back:

      refund = destroyingDeposit - (destruction + advertising)

  floored at zero; the overrun is reported as `deficit` instead. Both live on **`GoodsFinancials`** in models. The refund must be derived **per goods and then summed** — computing it from the totals is wrong, because one item's shortfall would silently eat another item's refund.
- Migration **`20260830_expenses_per_goods.sql`** adds `financial_expenses.package_item_id` and a UNIQUE `(package_item_id, kind)` constraint, so re-posting a cost REPLACES it instead of double-counting against the deposit. **Deliberately a full constraint, not a partial index: PostgREST can only infer a conflict target from a full unique constraint**, so `on_conflict=package_item_id,kind` would fail against a `where`-qualified one. Nulls never collide, so unattributed expenses stay insertable. The migration de-duplicates existing rows first, or the constraint cannot be added.
- **`goodsFinancialsProvider`** builds one `GoodsFinancials` per goods item, cross-yard. Package-level figures (the destroying deposit, and any warehouse entry that names no item) are apportioned across items **by quantity**. `financialSummaryProvider` is now just `summariseGoods(...)` over that list, so the headline cards and the per-goods table can never disagree.
- `summariseGoods(Iterable<GoodsFinancials>)` takes the rows rather than reading them, so a **filtered** view totals the same slice it lists. The Financials page filters FIRST and then totals — picking a yard narrows every card on the page, not just the table.
- The High Panel's "Record Expense" button is gone; costs belong to Central Disposal now. `kRecordableExpenseKinds` (destruction + advertising) is what the UI offers; `'refund'` stays in the DB CHECK constraint only so historical rows survive, and `seed_disposal_expenses.sql` DELETEs any leftover refund rows because a stored one would be counted twice.

## Neither PackageModel nor WarehouseEntryModel carries a yard (2026-08-24)

`packages` has no yard column and `WarehouseEntryModel` does not expose the one on `warehouse_entries`. Every SR number is minted with its yard's prefix, so **`yardOfSrNumber(srNumber)`** in [yards.dart](lib/core/yards.dart) reads it back (`GL1/SR/01/2025` -> `GL1`), returning null for an unknown prefix rather than defaulting. Every `Yard.srPrefix` equals its `code`, and the yard dropdowns emit that same code, so the two match directly. Both yard filters also fall back to the prefix when a row's `yard` is null, so a filter can never silently hide goods that plainly belong to the selected yard. `supabase/diagnose_financials_yard.sql` lists the prefixes actually present and flags any that match no yard.

**A provider whose body changed will not recompute on hot reload** — the cached value survives. After editing a `FutureProvider`, hot RESTART (`R`) or the page keeps showing figures built by the old code (this is what made a yard filter look broken when the code was already correct).

## Shared header widgets per portal (2026-08-24)

Each portal's tabs must carry the same search box, yard dropdown and chips. Tabs kept in their own files were drifting, so the real widgets were extracted rather than copied:

- **[disposal_shared.dart](lib/screens/disposal/disposal_shared.dart)** — `DisposalSearch`, `YardAllFilter`, `StatChip`, and the per-tab `disposalSearchProvider` / `disposalYardFilterProvider` families (keyed by tab name). Used by the dashboard's tabs and by Expenses.
- **[executive_header.dart](lib/screens/executive/executive_header.dart)** — `ExecutiveSearchField`, `ExecutiveYardFilter`, `executiveFilterChip`, and **`kExecutiveFilterPadding`**. Both controls take their height from that padding: **never set an explicit height on either**, or they land on different levels and the dropdown's InkWell splash spills past its border.

Central Disposal's Expenses tab and the High Panel's Financials tab both use these, plus the shared `TablePager` (`kClientPageSize` = 20). A filter can leave a pager past the end of the list, so both clamp the page index before slicing.

## Goods Financials report (2026-08-24)

A High Panel report listing every figure the Financials tab totals, **one row per goods item** — `_generateGoodsFinancialsReport` in [reports_screen.dart](lib/screens/reports/reports_screen.dart), carded in the "High Panel Officers Reports" section (PDF + Excel, no View, like its siblings).

- Reads **`goodsFinancialsProvider`** — the same provider the tab watches — so the report and the screen can never disagree. Seventeen columns: SR · Goods · Qty, the four income lines + Total Income, the three expenditure lines + Total Expenditure, Net, then the four proceeds-split columns.
- Honours the portal's yard picker, falling back to `yardOfSrNumber(srNumber)` when a row carries no yard, exactly as the tab's filter does.
- **The refund total is accumulated inside the filter loop, not re-derived at the end.** Summing `all` would have leaked cross-yard figures into a filtered report, and computing it from the totals would let one item's shortfall eat another item's refund. Same reason `GoodsFinancials.split` exists per item: applying the split rule per goods keeps the columns adding up to the cards.
- `ReportPreviewDialog` picks its orientation from the FILE NAME (`warehouse` / `released` / now `financials` start landscape). Seventeen money columns are unreadable on portrait A4.

## Reports: PDF zoom + yard-scoped warehouse picker (2026-08-24)

- **`PdfPreview` has no zoom of its own** — it scales each page to `maxPageWidth`, so zooming IS that number. `_ReportPreviewDialogState` now holds `_pageWidth` (default 700, clamped 400..3000, x1.25 per press) with +/- buttons and a tap-to-reset percentage in the header. Two details matter: the preview needs a `ValueKey(_pageWidth)` or it keeps the bitmap it already rasterised, and once the page is wider than the dialog it must be wrapped in a horizontal `SingleChildScrollView` sized to `_pageWidth + 40` (the `previewPageMargin`), because `PdfPreview` only scrolls vertically.
- ~~**`warehouses` is a SHARED table with no yard column**~~ — **superseded by [008](migrations/008_warehouses_belong_to_a_yard.sql)**: `warehouses.yard` now exists and RLS scopes reads to the caller's yard. **`warehousesForYardProvider(yard)`** filters on that column, and the Reports filter bar narrows its picker to it once a yard is chosen. A yard with no warehouses yields an EMPTY list, which is the truth until an admin adds one. Changing the yard resets `_selectedWarehouse` to `'all'`, and the dropdown falls back to null when the held id is not in the narrowed list, so it can never display a value its menu cannot offer.

## Appeal Directorate took a minute to load (2026-08-24)

`getInAppealNonForfeitPackages()` fetched **every package in the system** — `packages` plus nested `package_items`, `warehouse_entries`, `warehouses` and profile joins — with no filter and no limit, then discarded the out-of-window ones in Dart. It now asks the database for the window instead (`entry_date >= cutoff OR (entry_date IS NULL AND created_at >= cutoff)`); the exact per-row check still runs in the loop. Migration **`20260831_appeal_window_index.sql`** indexes `packages(entry_date)`, `packages(created_at)` and `forfeited_packages(source)`.

- **PostgREST splits `or(...)` arguments on DOTS**, so an ISO timestamp (`2026-07-25T11:25:00.000`) cuts the filter in half. The cutoff is formatted as a plain `YYYY-MM-DD` date, with one extra day of slack so a client/server timezone difference cannot clip a row that is still in the window.
- `AppealService.getForfeitedPackages()` was left unnarrowed on purpose: the Decided tab needs forfeits whose window closed long ago, a held appeal outlives its deadline, and per-item decisions live in a jsonb map PostgREST cannot filter on — any server-side cut there would hide rows the portal must show.
- **When a screen hangs, look for a `.select()` with no `.eq()`/`.limit()` before blaming the widget.** A nested select multiplies the payload by every join in it.

## Appeal Directorate listed the same goods many times over (2026-08-24)

One SR rendered nine rows for three goods. `AppealService.getForfeitedPackages()` expands a **package-level** `forfeited_packages` row (`item_id IS NULL`) into one row per package item, which is right when there is ONE such row. When an SR carries several, each expands into every item and the list multiplies: `package_level_rows x items_in_package`.

- **`supabase/fix_appeal_duplicate_rows.sql`** normalises the table to one row per (package, item): package-level rows are split into per-item rows carrying their appeal state across (the hold's `held_item_ids` is re-scoped to the single item), then duplicates of the same (package, item) collapse. **The survivor is the row with the most appeal state** — a decision beats a hold, a hold beats an untouched row — so a recorded appeal is never the copy thrown away.
- The service now de-duplicates by `"packageId:itemId"` after expanding, using the same weighting, so bad rows cannot multiply the portal again even before the SQL is run.
- `supabase/diagnose_appeal_duplicates.sql` query 1 lists every SR whose `package_level_rows > 1` and computes `rows_shown` — what the portal will actually render.

## An appeal decision unblocks goods immediately (2026-08-24)

The 30-day window froze every action on a pure date check (`isWithinAppealWindow(entryDate)`), so goods the Appeal Directorate had already ruled on still sat blocked for the remaining days. **A decision ends the wait** — there is nothing left to appeal. A HOLD does the opposite: it keeps goods frozen even after the deadline, because that appeal is still open.

- **`ItemAppealOutcome`** (models) carries `decision` + `onHold`, with `unblocksAction => isDecided && !onHold` — the hold always wins.
- `getItemAppealOutcomes(packageId)` / **`itemAppealOutcomesProvider(packageId)`** for the Goods Actions sheet; `getAllItemAppealOutcomes()` / **`allItemAppealOutcomesProvider`** for tables, fetched once so a list does not issue a query per row. Both read `forfeited_packages` across all four sources, so Detain / Abandoned / "Other" goods work like forfeits.
- The Goods Actions sheet now gates on `inAppealWindow && !decidedEarly`, plus a separate `blockedByHold`, and shows a green "Appeal decided · X" banner or an amber "On appeal hold" one instead of the countdown.
- `AppealStateChip` takes an optional `outcome` and renders four states: **On Appeal Hold** (amber, beats the deadline), **Decided · X** (green, beats the countdown), **Appealing · Nd** (amber), **Enabled** (green). Wired into Warehouses, Abandoned and Other; the Forfeited screen already had the decision inline.

## Detained Goods page + Sale/Destroy for detained goods (2026-08-24)

Forfeited, Abandoned and "Other" each had a page that could send goods to Central Disposal for Sale or Destruction; **Detain had no route at all**. New **[detained_packages_screen.dart](lib/screens/packages/detained_packages_screen.dart)** at `/detained-packages` (nav sits before Abandoned, matching the lifecycle), plus the same Sale/Destroy option from the warehouse row's details dialog.

- **Detention is a holding status, not a disposition** — unlike Abandoned/"Other" there is no `[DETAIN]` warehouse event to key off. An item counts as detained when its status is `detain`/`detained`/`held` AND no entry carries a `[FINAL:` / `[ABANDONED]` / `[OTHER]` / `[FORFEIT` note (i.e. it has not moved on).
- `createDisposalRequest`'s key parser is source-agnostic, so `"<pkgId>:<itemId>:detain"` (or the 4-part per-entry form) already worked — `'source': source` passes straight through and `20260825_forfeited_source_detain.sql` had already widened the CHECK constraint. Only the reason line needed a case: new `_detainReasonFor(pkg)` prefers the goods' own reason, then the hold reason, then "Detained pending inquiry".
- Both the page and the warehouse dialog gate Sale/Destroy on the SAME rule as the Goods Actions sheet: the appeal window blocks it, **an Appeal Directorate decision opens it early, and a hold blocks it either way**.
- `PackageItem.status` is **non-nullable** — `(item.status ?? '')` triggers `dead_null_aware_expression`.

### Detained Goods brought in line with Forfeited (2026-08-24)

The first cut of the page had only a search box and two chips. It now mirrors Forfeited exactly: **Total / In Appeal / Actionable** chips counting the SAME rows the table renders, plus a **Send Disposal Request** button opening the shared `DisposalRequestDialog` (enabled once any row is actionable).

- `getRequestableExpiredPackages()` gained a `source: 'detain'` branch, so detained goods appear in the bulk dialog alongside abandoned/"other" ones. The dialog's source chip gained a `'detain' => ('Detained', primaryGold)` case — without it they rendered as "Forfeit" via the fallback arm.
- **Its window gate was a blanket `if (isWithinAppealWindow(entryDate)) continue;`**, which ignored early decisions entirely. It now loads `getAllItemAppealOutcomes()` once before the loop and filters per item via `itemPassesWindow(itemId)`: inside the window only DECIDED items pass, once it closes every item that is not on HOLD passes. Same rule as the Goods Actions sheet and the Detained page.
- `isDetainSource` added beside `isAbandonedSource` / `isOtherSource`.

### Disposal dialog: detained rows missing, and pending goods now listed (2026-08-24)

Two fixes to `getRequestableExpiredPackages()` and the shared `DisposalRequestDialog`:

- **Detained goods never appeared.** The new detain branch checked `otherFpItemKeys` — a set built from `source='other'` rows only — so its "already sent" test could never match the right rows. Added `detainFpItemKeys`, queried from `disposal_request_items` on `source='detain'` and keyed per item like "other" does.
- **`includePending: true`** relaxes the four appeal-window gates (`itemRequestable`, the `baseForfeit` filter, the package-level `continue`, and `itemPassesWindow`) so goods still inside their window come back too. **An appeal HOLD stays excluded in both modes** — that appeal is still open. New `allDisposalCandidatesProvider` wraps it; `requestableForfeitedPackagesProvider` is unchanged, so the page-level "Actionable" counts still mean what they did.
- The dialog now reads the full pool and renders non-actionable rows at 0.55 opacity with a null `onTap`/`onChanged`, a disabled disposition toggle, and an amber "In appeal · Nd" chip. **Select All skips them and the "N of M selected" denominator counts only `isActionable` rows**, so the two agree. Section title changed from "appeal period passed" to "Select Goods".

### Post Status Activity filters, scoped per status (2026-08-24)

Every activity dropdown was labelled "All Activities" and offered `kAllPostStatusActivities`, so a per-status page listed filters that could never match anything on it. Now labelled **"Post Status Activity"** everywhere, and each page offers only the group its status can carry — the same split `postStatusActivitiesFor(status)` applies on the SR form:

| Page | List |
|---|---|
| Detained | `kDetainActivities` |
| Abandoned | `kDisposalActivities` |
| Warehouses, Released | `kAllPostStatusActivities` (every status is reachable there) |

- The Detained page gained the filter outright (`detainedPackageActivityProvider`), matching on `row.reason`.
- **The activity lives in `warehouse_entries.hold_reason`** — that is what these rows show and filter on. The Detained row's fallback had to be spelled `'Pending Inquiry'`, exactly as `kDetainActivities` does; the lowercase `'Pending inquiry'` could never be selected.
- Forfeited and Other Goods deliberately have no such filter: Forfeited renders no Reason column, and Other's "Disposition" holds a custom free-text label rather than an activity.

### The four status pages made consistent (2026-08-24)

Detained / Abandoned / Forfeited / Other run the same process, so their headers and filters now match.

- **Header chips are `Total · In Appeal · Actionable` on all four.** Previously each page invented its own (Abandoned/Other: "Abandoned"+"Requestable", Forfeited: "Total"+"In Appeal"+"Expired"). "In Appeal" is computed as `total - actionable`, NOT as `!isAppealExpired` — otherwise rows an appeal decision already freed would be counted as blocked and the two chips would overlap.
- **Forfeited gained a Reason column and the activity filter.** Its `_ForfeitRow.reason` getter reads `entry.holdReason`, falling back to `item.reasons` then `forfeited.reason`. The filter is applied **after `_buildForfeitRows`**, not in the package-level `where` — the activity is a per-row value, so `row` does not exist at that point.
- Other Goods gained the filter too (`otherPackageActivityProvider`, `kDisposalActivities`).

### Detained popup honours the appeal decision; "Reason" renamed (2026-08-24)

- The Detained page now passes **`appealDecisionLabel` + `appealDecisionCode`** to `PackageDetailsDialog`, exactly as Forfeited does: the popup banners "APPEAL DIRECTORATE DECISION — Proceed with: X" and `_isActionEnabled` restricts the Final Disposition sheet to the single decided action. `ItemAppealOutcome.label` was added to map the code to the yard's wording, mirroring `ForfeitedPackageModel.appealDecisionLabelForItem`.
- **Sale / Destroy are always disabled in the Final Disposition sheet** (`_requestActions`) — by design, they go to Central Disposal through `onSaleOrDestroyRequest` / Send Disposal Request instead. So a SALE decision greys that row out there; the request flow is where it is acted on.
- **All four status pages now pass it** — Detained, Abandoned, Other and Forfeited. The Other page's old comment claimed "Other goods have no appeal", which stopped being true once the 30-day window was extended to every status.
- The **"Reason"** column header is now **"Post Status Activity"** on Detained, Abandoned, Forfeited and Warehouses — that is what the column holds. Other Goods keeps "Disposition": its value is a custom free-text label, not an activity.

### Sale / Destroy are deliberately NOT offered in the Final Disposition sheet (2026-08-24)

`_isActionEnabled` disables `_requestActions` (`SOLD`, `DESTROYED`) **unconditionally, and that is correct** — those two outcomes belong to the Central Disposal Directorate and must be started from the **"Send Disposal Request"** button on the status page, so one deliberate request covers every selected item. I briefly relaxed the gate to fire the (fully built) `onRequestDisposal` handler and the user rejected it: a per-item Sale/Destroy buried in a details popup is the wrong route.

Consequence worth remembering: **a SALE or DESTROY appeal decision enables nothing in that sheet.** The decision banner still shows, but the action is carried out by sending the disposal request — the goods appear in the request dialog as actionable. Only RELEASE / RE-EXPORT / OTHER decisions light up a row there. `onSaleOrDestroyRequest` is still passed by all five callers but is unreachable under this gating.

**A completed `[FINAL:OTHER]` row on the Other Goods page** showed an "Enabled" appeal chip while its popup correctly offered no footer (`completed: true`). It now renders a muted **"Completed"** chip naming the recorded outcome, so the absent footer reads as finished rather than broken.

### The details popup lingered after recording a disposition (2026-08-24)

`_showFinalDispositionDialog`'s `onConfirm` popped the details dialog **last** — after the `recordFinalDisposition` round trip and the provider invalidations. So the goods vanished from the table behind it while the popup sat there waiting, and it only closed once everything had reloaded.

It now pops **before** the write: the write does not need the dialog, and the page it returns to refreshes itself. Two things had to move with it —

- **Capture anything that reads a BuildContext BEFORE the pop.** The messenger and the two snackbar colours are taken up front; the State's own `context` is torn down with the dialog, so looking them up afterwards would fail. `ScaffoldMessenger.maybeOf(ctx)` gives the app-level messenger, which outlives the route.
- The `mounted` guards are gone with it — the captured messenger is what shows the result, so it no longer matters whether this widget survived.

`allItemAppealOutcomesProvider` was added to the invalidation list too: a recorded disposition changes what the appeal chips should read.

### "Send Disposal Request" was slow to enable (2026-08-24)

Abandoned and Other watched **`requestableForfeitedPackagesProvider`** to decide whether to enable the button and to fill the "Actionable" chip. That provider runs the heavy cross-table query (every package + nested joins, plus `getAllItemAppealOutcomes()`), so the button sat greyed out for a beat after the table had already painted.

Both now compute it from data **already on screen** — a local `_isRowActionable(row, outcome)` over the rows the table just built and `allItemAppealOutcomesProvider` — which is the pattern the Detained page already used, and matches Forfeited (which counts `r.forfeited.isActionable` over `forfeitedPackagesProvider`). The rule is unchanged: window closed OR decided, and a hold always blocks. The provider is still invalidated after a submit; it is just no longer *watched* for the enable state.

**All four status pages now agree** on how the header chips and the button are derived.

### Warehouse row showed TWO footers, and its Goods Actions ignored the decision (2026-08-25)

Wiring `onSaleOrDestroyRequest` into the warehouse screen (for detained goods) also switched on the **Final Disposition** footer, which then sat beside the warehouse dialog's own **Actions** footer — two buttons on one row opening near-identical sheets.

- The Final Disposition footer is now suppressed when **`useWarehouseSummary`** is set. That flag is passed by the warehouse screen alone, which makes it the right signal; gating on `highlightEntry != null && !isReturned` would have wrongly hidden it on the Detained page, whose rows also carry a live entry.
- **The warehouse's Goods Actions sheet did not restrict to the appeal decision** — it already read `itemAppealOutcomesProvider` for the window/hold logic but enabled every action regardless. It now mirrors `_FinalDispositionDialog._isActionEnabled`: once decided, only the matching key is open. `actionKeyForDecision` maps RELEASE/RE-EXPORT/OTHER to their keys and **returns null for SALE/DESTROY**, so those decisions open nothing there — correct, since they are carried out by sending a disposal request.

### The Warehouses page is view + Update only (2026-08-25)

Every status now has its own page for acting on goods — Detained, Abandoned, Forfeited, Other — so the warehouse dialog no longer offers any: its **"Actions"** button is gone and the Final Disposition footer stays suppressed there. It shows what the warehouse holds, and Update. The table's **Appeal column still shows where each item stands**, which is what the page is for.

Both suppressions key on **`useWarehouseSummary`**, passed only by `warehouses_screen.dart`. The disposal wiring added there earlier (`_itemIsDetainedHere`, `_detainActionable`, `_requestDetainDisposal`) went with it. `allItemAppealOutcomesProvider` is still watched — the Appeal chip needs it.

## Warehouse ZONES carry the capacity (2026-08-25)

Capacity was a single number on `warehouses` and **nothing enforced it** — `addEntry` admitted goods with no check at all, which is how Warehouse 01 reached 128%. Space is really organised zone by zone, so that is where the number now lives.

- **`warehouse_zones`** (migration `20260832_warehouse_zones.sql`): one row per zone, its own `capacity`, unique `(warehouse_id, name)` so `warehouse_entries.zone` resolves against it. Read by any authenticated user (the SR form needs it), written by admins only.
- **A warehouse's capacity is the SUM of its zones — never entered.** `warehouses.capacity` is kept so older readers do not break, but is no longer the source of truth. The admin table shows the derived total and a **Zones** button (`_WarehouseZonesDialog`) where capacity is actually set.
- The migration **backfills from the zones already in use**, splitting the old warehouse figure evenly among them, so existing data carries over and an over-full warehouse still reads over-full. A warehouse with no zones in use gets one default zone 'A' with the whole old capacity — otherwise it would show zero capacity and accept nothing.
- **The SR form now blocks over-filling.** `_findCapacityProblems()` groups the consignment's items **by the zone they would land in** (several goods of one SR can share a zone, so checking one at a time would let a consignment slip past that its total does not fit), then `_CapacityBlockedDialog` states the overflow and lists **other zones in the same warehouse with room**. Deliberately not a hard block — "Admit anyway" remains, because physical reality can run ahead of the record and refusing outright would leave the officer nowhere to log it. It can just no longer happen by accident.
- Entries whose `zone` matches no defined zone still count towards the warehouse's `used` and are surfaced as **unzoned** rather than being attributed to a zone that never held them.

### Zone rollout follow-ups (2026-08-25)

- **`type 'Null' is not a subtype of type 'List<dynamic>'`** on the Zone Capacity page: the screen cast `r['zoneRows']` unguarded, and `getWarehouseZones()` threw outright when `warehouse_zones` did not exist yet (migration not run). Both are now tolerant — the service returns an empty list and the screen reads `(r['zoneRows'] as List?) ?? const []`, so the page says "No zones defined" instead of showing a red error. **A new table's reader should degrade to empty, not throw, while its migration is still pending.**
- The Admin Panel's Warehouses table now lists **each zone as its own row beneath its warehouse** (`_warehouseRowsWithZones`), repeating the warehouse name in grey so a zone is never orphaned. A warehouse with no zones gets a red "No zones — add one to set capacity" row with an inline Add Zone button.

### Zones get a code, and are created with the warehouse (2026-08-25)

- Migration **`20260833_warehouse_zone_code.sql`** adds `warehouse_zones.code`, backfilled as `<warehouse code>-<zone name>` (uppercased, spaces stripped) and unique per warehouse. A zone now reads like its warehouse: "Zone A" / "W01-A".
- **`_AddWarehouseDialog`** replaces the old inline builder: warehouse name / code / description / location, then a repeatable zone row (**name · code · capacity**) with an **Add Zone** button and a running total. It **starts with one zone and refuses to create a warehouse with none** — capacity lives on the zones, so a warehouse without any could hold nothing. The zone code auto-suggests from the warehouse code, so it need not be typed. `warehouses.capacity` is still written, as the zones' sum, to keep legacy readers in step.
- The admin table's third column is now **Description** (zones have one; a location belongs to the warehouse, which falls back to it). Zone rows fill all five columns — name (`Warehouse 01 · Zone A`, indented), code, description-or-usage, `capacity (N free)` / `(FULL)`, edit.

### Item categories now point at REAL zones (2026-08-25)

The category form offered a **hardcoded `List.generate(10, ...)`** — "Zone 1 … Zone 10" — with no connection to `warehouse_zones`, and stored the label verbatim (`"Zone 3"`). That is why zones picked there never appeared in the Warehouses table: they were never rows.

- Both the add and edit dialogs now list the **actual zones of the selected warehouse**, labelled `name · N cap`, so a warehouse can have as many zones as it really has. Already-assigned zones stay shown-but-disabled, as before.
- **`target_zone` now stores the zone's NAME.** Migration `20260834_category_zone_names.sql` normalises the legacy `"Zone 3"` values: strip the prefix where that zone exists, otherwise **create the missing zone** (capacity 500, flagged in its description) so a category that was pointing somewhere keeps pointing there instead of silently losing its target.
- The edit dialog clears `selectedZone` when the warehouse no longer has it — a dropdown must never hold a value its menu cannot offer. The categories table renders such a zone in red as `"3 (not defined)"`.

### Reports: print, don't save; and the emblem in every header (2026-08-25)

- **Saving a PDF is no longer offered.** The preview exists to READ the report; anything leaving the system goes on paper or as Excel. The report cards' "PDF" button is now **"Print"** (it still opens the same preview), the preview footer's "Save PDF" action is gone, and the table dialog's footer button is "Print" too. `Printing.layoutPdf` in the preview footer is the print path.
- **The Customs emblem now heads all three views.** In the PDF, `ReportService._logoWidget()` draws `Sri_Lanka_Customs_logo.svg` via **`pw.SvgImage`** (the `pdf` package renders SVG directly — no raster asset needed), falling back to the old "SLC" monogram if the asset cannot be read. The SVG is cached in a static and loaded from `_ensureFontsLoaded()`, which already runs before every report.
- On screen, the preview dialog and the table dialog use `SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg')` with **`SvgTheme(currentColor:)`** — a `colorFilter` srcIn flattens the eye/ship detail into a solid blob (same rule as the portal headers).

### Three more cost kinds, and SR tables sort newest-first (2026-08-25)

- **Labour / Transport / Auction** join destruction and advertising as recorded costs (migration `20260835_more_expense_kinds.sql` widens the `kind` CHECK). They come out of the same destroying deposit, so the derived refund is now `deposit - Σ(all five)`. The one-per-`(package_item_id, kind)` constraint covers them without change — it is on the pair, not a list of kinds.
- **The record form is now kind-driven**: `_RecordExpenseDialogState` holds `Map<String, TextEditingController>` built from `kRecordableExpenseKinds`, renders one field per entry, and saves in a loop. The provider's collection is keyed by kind the same way (`byItem` / `bySr` maps + a `costFor()` helper). **Adding a sixth cost now needs only that map and an icon** — no other edits. The save loop writes **every** kind including zeros, so clearing a field records the zero rather than leaving the old figure standing.
- **`compareSrNewestFirst` in [yards.dart](lib/core/yards.dart)** orders SR numbers newest first. A plain string sort is wrong: it puts "9" after "86" and ignores the year. This parses `<yard>/SR/<serial>/<year>`, compares the year then the serial as NUMBERS, and sorts unparseable values last rather than to the top. `srFinancialsProvider` uses it, so the Financials table and the Goods Financials report both follow.

### `type 'Null' is not a subtype of type 'double' of 'function result'` (2026-08-25)

`costFor()` in `srFinancialsProvider` declared a `double` return but fell back with `?? 0` — an **int**. Assigning an int into a `double` variable or map is fine (the compiler inserts the conversion), but returning one from a function typed `double` fails at RUNTIME, which is why it only showed as a red screen on Financials and Expenses. Fixed to `?? 0.0`.

**Rule worth keeping: inside a function with a declared `double` return, every literal fallback must be `0.0`, not `0`.** The analyzer does not catch it — the expression's static type is `num`, which is assignable.

### The new cost kinds reach every surface (2026-08-25)

Adding Labour / Transport / Auction to the model and the record form was not enough — each place that lists costs names its columns explicitly. All four now carry them:

| Surface | Change |
|---|---|
| Central Disposal → Expenses table | 3 columns + 3 total chips, `minWidth: 1500` |
| High Panel → Financials "Per SR" | 3 columns, `minWidth: 2400` (20 columns) |
| Financials → Expenditure card | 3 lines |
| Goods Financials report | 3 columns + 3 running totals |

**A `minWidth` was needed on both tables**: neither set one, so the extra columns would have been crushed rather than scrolled. The provider and the record form are kind-driven, but these column lists are not — a sixth cost still means touching all four.

### Financials "Per SR" fits without sideways scroll (2026-08-25)

Twenty money columns needed `minWidth: 2400` and scrolled. Rather than crush the figures, the WIDTH DEMAND was reduced:

- **`_compactMoney()`** renders `75,000.00` as **`75.0K`** and `1,234,567` as `1.23M` — twelve characters down to five. **Every cell carries the exact figure in a tooltip**, so nothing is lost, only the width.
- Column labels abbreviated to match (`Destroy`, `Advert.`, `Expend.`, `Consol.`), at `fontSize: 11` with ellipsis — a long header sets the column's width and would undo what the compact figures gained.
- Cell font 11.5, `columnSpacing: 6`, `horizontalMargin: 10`, and **`minWidth` removed entirely**.

The deficit and net cells use `_compactMoney` too, each with its own exact-value tooltip.

### Seeded goods had no category, so zones and the Items table disagreed (2026-08-25)

Goods were admitted straight into zones 'A' / 'B' / 'C' with `package_items.category` null, so the Items table showed nothing for them and those zones matched no category. **`supabase/fix_category_zones.sql`** repairs it in three steps: create ten categories each owning a REAL `warehouse_zones` row (spread across W01/W02/W03), set `category` on every uncategorised item, then re-point its live warehouse entry at the zone its category names — so what the goods occupy and what the category says finally agree.

Classification is **HS chapter first** (the authoritative code), falling back to keywords in the goods name. Traps found while testing the patterns against the real seed data:

- **A `~*` pattern must stay on ONE line.** Wrapping it puts literal whitespace inside the regex, and it would silently never match.
- Order matters in the `CASE`: Food is checked before the General rule so "Fruit Juice Cartons" is food, not a carton; Electronics carries `circuit|pcb` or "Printed Circuit Boards" falls through to General.
- Toys / perfumery / stationery are **General Goods**, not Food.
- **No `ON CONFLICT (name)` on `package_categories`** — the repo has no CREATE TABLE for it, so a unique constraint on `name` cannot be assumed; the script does an explicit `IF EXISTS … UPDATE … ELSE INSERT`.

`supabase/diagnose_category_zones.sql` shows the before state — query 2 flags zones holding goods that no category points at.

**`42803: subquery uses ungrouped column`** — a correlated subquery in the SELECT list may only reference columns the outer query GROUPS BY. Query 2 grouped by `trim(we.zone)` but its `exists(...)` referenced the raw `we.zone`, which no longer exists at that level. Fixed by grouping in a subquery FIRST, then doing the lookup against the already-grouped columns.

### A DO block aborted partway, leaving categories with no zone (2026-08-25)

After `fix_category_zones.sql` ran, several categories showed **"Building Materials (not defined)"** in red and their Target Zone dropdown was blank — the CATEGORY existed but its zone did not.

Cause: **`warehouse_zones` carries TWO unique keys** — `(warehouse_id, name)` and `(warehouse_id, code)` — and an `ON CONFLICT` clause can only name ONE of them. The insert used `ON CONFLICT (warehouse_id, name)`, so when a generated code collided Postgres raised on the *code* index instead, which nothing caught, and the whole `DO $$ … $$` block died mid-loop. Everything before the clash was committed; everything after was skipped.

**On a table with more than one unique key, `ON CONFLICT` is not enough — check explicitly.** Both scripts now `IF EXISTS … UPDATE … ELSE INSERT`, and a colliding code takes a numeric suffix rather than raising. `supabase/fix_missing_category_zones.sql` repairs a database left in the half-done state.

### Never wrap a Supabase SQL-editor script in BEGIN/COMMIT (2026-08-25)

`fix_category_zones.sql` was wrapped in `BEGIN; … COMMIT;`. **The Supabase SQL editor already runs each execution inside one transaction**, so the nested `BEGIN` is ignored — and when any statement errors, the editor rolls the ENTIRE run back. That is why re-running the script changed nothing: the DO block still failed, and the rollback took the rest with it, leaving the half-finished state from the very first run.

Both scripts now run **without an explicit transaction**, so a failure costs only the statement that failed. `supabase/diagnose_zone_mismatch.sql` query 1 names the exact problem per unresolved category (missing row / wrong warehouse / case or whitespace mismatch) instead of guessing.

### A swallowed exception looked like bad data (2026-08-25)

`getWarehouseZones()` had `catch (_) { return const []; }` so the app would tolerate the table not existing yet. But an empty list renders as **"(not defined)" against every category**, which reads as a DATA problem — and cost a long detour chasing SQL that was already correct (`unresolved = 0` in the database while the screen said otherwise). It now `debugPrint`s the error before returning empty.

**A fallback that hides a failure must still say so.** Silence turns "the fetch broke" into "your data is wrong".

### Admin tables aligned (2026-08-25)

- Items table's Zone Code is **plain text**, not a tinted box — boxing a value that can wrap looked worse, and the Warehouses table shows its code plainly.
- Both tables' Zone Code columns are **190px**, wide enough for `W01-VEHICLEPARTS` on one line; the Warehouses column was renamed **Code → Zone Code** (most of its rows are zones).
- Widths matched between the two: first column 370, Zone Code 190, Actions 90.

### Three more unsold outcomes (2026-08-26)

The High Panel's final outcome for goods nothing could sell now has seven options, not four — **Re-export**, **Convert** and **Remove from the Premises** join Destroy / Remand / Government Use / Auction. Migration `20260836_more_unsold_outcomes.sql` widens the `unsold_proposals.proposal` CHECK; nothing stored becomes invalid.

**Only two files needed editing**, because every surface is data-driven off them:
- `kUnsoldProposals` + `unsoldProposalLabel()` in models — the decide dialog builds its radio list from the constant, and the report's "Proposed Decision" prints `UnsoldProposalModel.label`, which calls the same function.
- `unsoldOutcomeStyle()` in `unsold_shared.dart` — icon + colour for the chip on all three Unsold tables (yard, Central Disposal, High Panel).

The Final Outcome column went 190 → 235px (and `kUnsoldTableMinWidth` 900 → 945) so "Remove from the Premises" fits beside its icon.

### Valuation report showed the wrong figure per column (2026-08-27)

"List of Goods Valued" had FOUR columns (`Initial / 2nd / 3rd / Final Value`) for FIVE real stages, and its `valueAt()` special-cased the last column to print `chain.last` — so a package that stopped at Tender 1 showed that figure under "Final Value". The columns are now one-per-stage and strictly positional:

**Initial Valuation · Tender 1 · Tender 2 · Tender 3 · High Panel Valuation**

`getValuationChains()` also **never included the High Panel figure** — it lives on `tender_committees.submitted_value`, not in `tender_revaluations`. It is now appended last (guarded, so a role that cannot read committees still gets the rest of the chain).

### Destroyed report columns (2026-08-27)

Now **SR Number · Goods Name · Goods Description · Destroyed Price · Receipt Number**, replacing HS Code / Destroyed Date / Qty.

`destruction_items` had **no receipt column** — the RPC stored the receipt in `notes`. Migration `20260837_destruction_receipt_number.sql` adds `receipt_number`, backfills it from `notes`, and keeps it in step with a **trigger** rather than redefining the RPC. That matters: `disposal_mark_destruction_item_destroyed` also writes the `[FINAL:DESTROYED]` warehouse entry and flips the item's status (20260630_destruction_price.sql), so a `create or replace` here would have been a copy that silently drops all of it.

### Four new yard pages, one widget (2026-08-27)

The High Panel's outcomes now each have a yard page: **Government Use · Remanded · Converted · Removed from the Premises**.

Rather than copy `UnsoldPackagesScreen` four times, it took parameters — `route`, `title`, `subtitle`, `countLabel` and **`proposalFilter`**. Null keeps it the Unsold Goods page (every unsold package); set to an outcome code it lists only goods decided that way. One widget, six pages, and the header / filters / table / pager stay in step by construction.

Two details worth keeping:
- **`_visibleRows()` is used by BOTH the header count and the table.** Counting with `_yardRows` while listing with the narrowed set would have made an outcome page contradict its own header.
- **The status chips are hidden when `proposalFilter` is set** — every row there is already decided the same way, so an "Awaiting decision / Decided" filter would offer nothing.

Registered in `router.dart` and in **both** `_officerNav` and `_adminNav` (app_shell.dart has two lists; editing one silently leaves the other role without the page).

### The outcome pages reach Central Disposal too (2026-08-27)

`UnsoldProposalsTab` took the same treatment as the yard screen — `title`, `countNoun`, **`proposalFilter`** and **`tabKey`** — so Government Use / Remanded / Converted / Removed are four more tabs on the Central Disposal dashboard (12 → 16), styled by construction like the Unsold Goods tab beside them.

**`tabKey` matters as much as the filter.** The search box, yard dropdown and pager are all `.family` providers keyed by tab; without a distinct key, five tabs sharing one widget would share one search term and one page number. `_unsoldPageProvider` had to become a family for exactly that reason.

The outcome filter is applied **before** the yard and search filters, so the count pill, the table and the pager always describe the same set.

### Reports trimmed to the agreed list; Auction pages added (2026-08-27)

- **Auction Goods** joined the outcome pages — yard route `/auction-packages` and a Central Disposal tab (16 → 17). Same parameterised `UnsoldPackagesScreen` / `UnsoldProposalsTab` as the others.
- **Reports cut to the requested set.** Removed: Stock & Revenue (whole section), Financial Reports (Storage Charges / Released Revenue), Item Categories, Warehouses List, Package History, Old Entries. Their generators are still in the file and now show as `unused_element` warnings — deliberately left, since the cards may come back.
- **Four outcome reports added** (Unsold / Remanded / Auction / Converted) from one parameterised `_generateOutcomeReport`, differing only by which `unsold_proposals.proposal` they keep. Null lists every exhausted-unsold package including undecided ones.
- **"List of the SRs" became "SR Register Inventory"**: SR Number · Goods Name · Goods Description · Post Status Activity · Entry Date · Value. The activity is read from `item.reasons`, falling back to the warehouse entry's `holdReason` — that is where the SR form writes it.
- A **Post Status Activity dropdown** joined the filter bar (`_selectedActivity`), so the stock can be read one activity at a time.

### Router changes need a FULL restart, not hot reload (2026-08-27)

`/auction-packages` was in `router.dart` and in both nav lists, yet the app showed **"GoException: no routes for location"**. GoRouter builds its route table once at construction; neither hot reload nor `R` rebuilds it. **Stop the app and `flutter run` again after adding a route** — otherwise a correct route reads as a missing one.

### Report cards trimmed and tightened (2026-08-27)

The Post Status Activity section is gone (both the grid in section 3 and the lone card in section 9), leaving exactly the agreed list. `_buildActivityGrid` stays for `disposalMode`, which still shows only those reports.

Cards were far taller than their content: a title, one line of description and two buttons, held apart by a `Spacer()` that fills whatever height the grid gives. Fixed at the grid — `childAspectRatio` 2.3 → **3.4** across all seven grids, and a **fourth column above 1400px**.

### Warehouse filter showed every warehouse to every yard (2026-08-27)

`warehousesForYardProvider` ended with **`if (ids.isEmpty) return all;`** — so a yard that owns no warehouse was told it had all three. A yard with no entries then got an **empty list**, which was closer to the truth. ⚠️ **Both readings are now obsolete**: deriving the set from `warehouse_entries` could never place a warehouse that had no goods in it yet. [008](migrations/008_warehouses_belong_to_a_yard.sql) added `warehouses.yard`, and the provider filters on it.

### Goods Financials took ~2 minutes (2026-08-27)

`srFinancialsProvider` awaited four independent fetches **one after another** — `getAllPackages()` and `getTenderSales()` are both heavy nested queries — so the page waited for their SUM. Now `Future.wait`, so it waits for the slowest. **Sequential `await`s of independent calls are the default shape a provider drifts into; check for them when a screen is slow.**

### Two "unsold" reports (2026-08-27)

The parameterised `_generateOutcomeReport` with `outcome: null` duplicated the existing "Not Sold Goods" report. Dropped the duplicate and renamed the original to **Unsold Goods**; Remanded / Auction / Converted keep their outcome filters.

The empty-result SnackBar was the default white and washed into the page — now **amber with an icon and dark text**, since an empty result is exactly the message a reader must not miss.

### The emblem was missing from most reports (2026-08-27)

Every PDF builder shares `_buildHeader`, which draws `_logoWidget()` — yet many reports still showed the lettered **"SLC"** fallback. Cause: the emblem is loaded by **`_ensureFontsLoaded()`**, and **six builders never called it** (`generatePackagePdf`, `generateWarehousePdf`, `generatePostStatusActivitiesPdf`, `generateCategoriesPdf`, `generateStaffPdf`, `generateForfeitedPdf`). All fourteen now do.

**A shared header is not enough — check every entry point calls the loader it depends on.** The fallback made this look like a design choice rather than a bug.

### Preview orientation and zoom (2026-08-27)

- Landscape opened at width **880** against portrait's 680. A landscape sheet is 1.414x wider, so it filled far more of the dialog and read as ~125% while the label said 100%. Both now open at **680**, so the whole sheet is visible at a comparable scale either way.
- `'register'` and `'inventory'` were forcing landscape, but those reports are six narrow columns — dropped, so they open portrait and no longer leave a half-empty sheet. Landscape remains the default only for `warehouse`, `released`, `financials`, `valued`, `valuation`.

### Forfeited-family reports reshaped; Appeal Goods added (2026-08-28)

- **`buildForfeitedReportRows` now emits five columns** — SR Number · Goods Name · Goods Description · <date> · **Final Disposition** — replacing Item / HS Code / Qty / Consignee / Warehouse / Reason. One builder serves Forfeited, Abandoned, Other and Re-exported, so all four changed together.
- The **final disposition** is parsed from the `[FINAL:...]` warehouse entry the disposition dialog writes (`[FINAL:OTHER] — <text>` keeps its trailing text). Goods without one report **"Pending"**.
- Titles: `FORFEITED PACKAGES` → **`FORFEITED GOODS`**, same for Re-exported; file bases follow.
- **New "Appeal Goods" report**: SR · Goods Name · Description · Appeal Date · Decision. Reads every source (an appeal can touch Detain / Abandoned / Other too), keeps only goods an appeal actually touched, and **a hold outranks a decision** — while it stands the row reads "Appeal Hold", because that is why the goods cannot be acted on.

### Central Disposal's Reports tab matched the others (2026-08-28)

Its page was a different product: heading **"Post Status Activity Reports"**, a separate `_buildActivityGrid` instead of the normal sections, and a third **View** button on every card. Three edits, all in `reports_screen.dart`:

- The heading is unconditionally **"Report Generator"** — the `disposalMode` ternary is gone.
- The early `if (widget.disposalMode) return _buildActivityGrid(...)` is removed, so every portal builds the same card list. `_buildActivityGrid` is now unreferenced but kept.
- **The in-app View button is gone everywhere.** It was Central Disposal's alone (`showView = widget.disposalMode && onView != null`); every card now carries Print + Excel, and the preview is where a report is read.

QR Code Labels stay yard-only (`!executiveMode && !disposalMode`) — they are printed at the yard.

### The Warehouse filter reaches Central Disposal (2026-08-28)

It was hidden behind `if (!widget.disposalMode)` for a real reason: **`warehouses` had a SELECT policy for the executive role only**, so the list came back empty for Central Disposal. Migration `20260838_disposal_read_warehouses.sql` grants them read on `warehouses` and `warehouse_zones` (`auth_user_is_disposal()`), and the guard is gone — every portal now carries the same filter row.

Still scoped: with no yard picked the list stays **empty** rather than showing every warehouse, matching the earlier `warehousesForYardProvider` fix. **A UI element hidden "because the data is empty" is usually an RLS gap, not a design choice — check the policy before removing the guard.**

### A column that says the same thing on every row is not a column (2026-08-28)

The outcome pages (Government Use, Remanded, Auction, Converted, Removed) filter to ONE outcome, so their **Final Outcome** column repeated the page title on every row. `unsold_shared.dart` already applied this reasoning to the Tenders column — every row there is 4x, so the badge was dropped.

Added **`kUnsoldDecidedColumns`** (Final Outcome → **Decided On**) and **`unsoldDecidedOnCell()`**, which shows `decidedAt` with the outcome and the DG's note in its tooltip. Both the yard screen and the Central Disposal tab pick the column set from `proposalFilter == null`, so the unfiltered Unsold page keeps Final Outcome — there it genuinely varies.

### Page marks, Re-export, and the delivery filter (2026-09-06)

- ⚠️ **Page headings use an icon, never an emoji.**
  [PageTitle](lib/widgets/page_title.dart) (and `DisposalPageHeader`'s optional
  `titleIcon`) renders an `IconData` tinted `AppColors.primaryGold`, like the nav
  rail. Emoji come from a colour font (Segoe UI Emoji): they **cannot be tinted**
  — 🏷️ stays orange, ♻️ stays green — and they ignore the light/dark
  theme, so they were the only thing on the page that did not change with it.
  Against a one-accent palette they read as confetti. **Each heading reuses the
  icon its own tab strip / nav rail entry shows**, so the eye carries one mark
  from the tab it clicked to the heading that answers it.
  [page_title_icon_test.dart](test/page_title_icon_test.dart) walks all of `lib/`
  and fails on any emoji inside a `Text(`, `title:` or `label:` — the ⚠️ in
  comments is deliberately allowed.
  ⚠️ Perishable is the page that exposed this: it is a **yard screen reused
  read-only** in Central Disposal, so it missed the pass that marked every other
  tab and had no mark at all.

- ⚠️ **Re-export now has a page** (Central Disposal tab `outcome-re-export`,
  yard route `/re-export-packages`). The outcome was ALWAYS decidable — it is in
  `kUnsoldProposals`, `unsoldProposalLabel` renders it, and `unsold_shared.dart`
  has mapped it to `Icons.flight_takeoff_rounded` all along — but nothing
  displayed the result, so goods sent back out of the country left Unsold Goods
  and appeared **nowhere**. The directorate meant to carry the decision out could
  not see what it was meant to carry out.

- **All / Pending / Delivered on the four outcome pages**, the control Destroyed
  Goods already had. `ExhaustedUnsoldQuery.delivered` →
  `getExhaustedUnsoldPaged(delivered:)`. ⚠️ **Filtered in SQL**: these pages page
  in the database, so a Dart-side filter would narrow the CURRENT page and leave
  the pager counting rows the table no longer shows. ⚠️ Pending is
  `delivered.is.null,delivered.eq.false` — a package with no proposal row has a
  NULL `delivered`, and `eq(false)` alone would hide every undecided package.
  ⚠️ The field is in **both** `==` and `hashCode`, or the family key stays equal
  across a filter change and the provider never refetches. The filter provider is
  `StateProvider.family` **keyed by tabKey** — five outcome pages are five
  instances of ONE widget. Unsold Goods itself (`proposalFilter == null`) gets no
  control: nothing is decided there, so it would filter on a column every row
  shares. No migration — `exhausted_unsold` already carried `up.delivered`.

- **The filter row and the count pill share ONE line** on Sold, Destroyed, the
  five outcome pages and Perishable. They were two rows each with its own gap
  (~60px of chrome above a table whose whole job is showing rows). The pill moved
  above the `data:` callback, so it reads `async.valueOrNull!.total` — the SAME
  async value the table does, so the number and the list still cannot disagree —
  and is absent while loading rather than showing a stale or zero count.

- ⚠️ **`DefaultTabController.length` said 16 with 15 tabs and 15 bodies.**
  Flutter tolerates a length ABOVE the child count (the extra index simply has
  nothing to show), so the mismatch sat unnoticed; adding Re-export made the real
  count 16, which is why the number did not change. The test now checks `length`
  against both the tab count and the body count rather than a number typed
  beside them.

### No clock decides an outcome (2026-09-06)

- ⚠️ **The auto-lapse is gone.** An item Central Disposal had not marked fell
  to Unsold on its own once a working-day window closed — and `workingDeadline`
  skips weekends AND Sri Lankan public holidays fetched from an API at runtime,
  so **which packages reached the DG depended on the holiday calendar**. Worse,
  the sale then left the tab, leaving no way to record what actually happened.
  `unsoldDeadline` and `TenderStage.lapsed` are deleted; a test fails if either
  returns.
- Removing it uncovered two live bugs it had been covering for:
  - ⚠️ **`tender_sale_items.unsold` and `destruction_items.undestroyed` did
    not exist**, though the app wrote to both. "Mark Unsold" / "Mark
    Undestroyed" had never worked, and the auto-lapse was the ONLY route into
    either pool. [postgres/33](postgres/33_destruction_undestroyed_columns.sql),
    [/34](postgres/34_tender_unsold_columns.sql) add them with a pair
    constraint and a check that an item cannot be both outcomes. /34 also
    backfills (one-shot, flag-guarded) what the deadline had already lapsed —
    without it the pool would have emptied overnight.
  - **Destruction is NOT a sale.** `destroyed_price` is income nowhere; goods
    are destroyed on the yard's own decision or Top Management's. The
    "Destruction Sales" tab and the Undestroyed/Re-destruction pool were
    dropped from the strip long ago but **361 lines of dead widgets stayed**,
    carrying the rule with them. Gone.
- The countdown is now an **elapsed** timer ("3d 4h since bidding started"),
  warming amber→red, sooner for perishables. A **perishable sale that has
  started** is highlighted (amber wash, leaf icon) — one round, and they spoil
  while a decision waits.
- ⚠️ `has_pending` means **UNDECIDED**, not "not sold"
  ([postgres/35](postgres/35_tender_summary_counts_unsold.sql)). Those were the
  same thing only while a clock decided unsold. Central Disposal's tab is a
  **WORKLIST** (82 sales, 5 with work left); the yard's is a **RECORD** and
  lists everything.

### The tender route is finite (2026-09-07)

- **Valuation Tender → Tender 1 → 2 → 3** is all Central Disposal can run —
  four rounds. Then Top Management appoints a **committee** to price it, and
  when that round fails too the package is exhausted and the DG rules.
- ⚠️ Nothing enforced it: CED/GL1/OA/07/2025 ran **five** rounds with zero
  committees. [postgres/38](postgres/38_retender_stops_at_four.sql) holds a
  package past four rounds out of `unsold_retender_pool` unless a committee
  exists. It deliberately does NOT rewrite the rows it found — round 5 happened,
  and editing that would falsify a record.
- ⚠️ **That created an orphan**, and the fix is the lesson: the Committees tab
  read the same pool, so the package the new rule held OUT of it appeared on NO
  page — not the pool, not the DG's Unsold Goods (its committee round has not
  failed, because it never had one), not the tab that appoints the committee.
  [postgres/39](postgres/39_committee_pool_view.sql) gives that tab its own
  view, and its verify block asserts **no package past four rounds is invisible
  everywhere**. A package with nowhere to go is worse than one in the wrong
  place.
- `getCommitteesPaged(appointedOnly:)` — Central Disposal watches committees
  that EXIST (it cannot appoint one); Top Management APPOINTS them and must see
  the packages with none yet. In the query key, or the two tabs share a page.
- **`EnterBidsDialog` is public and read-only-capable.** The DG had to price
  goods that failed four rounds with none of the evidence — the bids and
  re-valuations were reachable only from Central Disposal's table. Read-only
  reuses the existing round LOCK rather than a second hiding rule.
- ⚠️ Committee writes invalidate the **paged** providers, not just
  `tenderCommitteesProvider`. That map is what each CELL reads; the paged ones
  decide which packages BELONG on a page.

### Top Management pages in SQL (2026-09-07)

- All four tabs rendered whole lists. One page from each view is **4-5ms**;
  `getTenderSales()` alone is **73ms**.
- Unsold Goods and Unsold Perishables share ONE paged method, told apart by
  **which view** decides membership — `exhausted_unsold` (five failed chances,
  a committee, the ADG's submission) or `unsold_perishables` (one failed
  Special Tender Sale). ⚠️ `perishable` is in `==` AND `hashCode`, or the tabs
  share a cached page and one shows the other's list.
- ⚠️ [postgres/37](postgres/37_unsold_perishables_marked.sql): the perishables
  view was left behind by the auto-lapse removal. CED/GL1/SR/17/2026 sat with
  `sold=false AND unsold=false` — nobody had decided — yet the DG was already
  being asked to rule on it. Membership is **the mark** now.
- ⚠️ **A perishable that SELLS never reaches the DG** — selling IS its outcome
  ([postgres/36](postgres/36_perishable_sold_outcome.sql)). Read from
  `tender_sale_items`, never written into `unsold_proposals`: inventing a
  proposal row would put sold goods on the DG's desk and double-count them in
  every report reading that table.

### Filter by the outcome, and marks belong to their portal (2026-09-07)

- "Decided" lumped all six outcomes into one bucket — not a question an officer
  asks. [OutcomeFilter](lib/widgets/outcome_filter.dart) lists each by name,
  Awaiting first. `kOutcomeAwaiting` / `kOutcomeSold` are **sentinels, not
  outcomes**, deliberately outside `kUnsoldProposals`.
- ⚠️ On Perishable, "awaiting" means **NEITHER** has happened — a sold row has
  no proposal either, so testing only for a null proposal calls it awaiting.
- ⚠️ **The control must match the company it keeps.** Central Disposal sets it
  beside segmented CHIPS (13pt, 14/8, radius 10, tinted fill); the yard sets it
  in a row of filter BUTTONS (12pt, radius 8, outlined). `chipStyle` is opt-in
  per caller. A test reads the chip's seven measurements **out of the chip
  widget** so restyling one reports the mismatch.
- Every table page is three lines: **title + search + yard**, then **filter
  opposite count**, then the table. Destroyed Goods sets it.
- Heading marks are for **Central Disposal only** (they echo its tab strip); on
  the yard the nav rail already shows the icon. Colour is the **portal's**:
  gold on the yard, green in Central Disposal, purple in Appeal, teal in Top
  Management.
- ⚠️ **Tabs are addressed by name.** `animateTo(10)` was written when 10 meant
  Unsold Tenders; adding Re-export shifted every index after Auction and threw
  the officer to a page about goods leaving the country. `DisposalTab` enum,
  and `length` reads from it.

### Mouse scrolling on desktop (2026-08-29)

Flutter's desktop `ScrollBehavior` omits touch/mouse from `dragDevices` and hides the scrollbar, assuming a wheel is always available. On a PC where the wheel does not reach a nested list there was then **no way to scroll at all**.

`_DesktopScrollBehavior` in `main.dart` (passed to `MaterialApp.router`) adds every `PointerDeviceKind` to `dragDevices` so content can be dragged with the mouse, and wraps vertical scrollables in a `Scrollbar` with `thumbVisibility` + `interactive`. **Vertical only** — a horizontal bar over a wide `DataTable2` sits on top of the last row.

Applies everywhere at once, since it is set on the app rather than per screen.

### The report logo, again (2026-08-29)

`_loadLogo()` swallowed both asset-load failures silently, so a missing emblem looked like a design choice. Both `catch` blocks now `debugPrint` before falling back to the "SLC" monogram. The load path itself is correct (tinted SVG with `currentColor` replaced, then the plain one) and `_ensureFontsLoaded()` awaits it before every builder — if the monogram still appears, the terminal now says why.

### Destroy enabled from Final Disposition; Destruction Sale removed (2026-09-02)

- **Destroy is now a direct final disposition**, same as Release / Forfeit / Abandoned / Re-export / Other — writes `[FINAL:DESTROYED]` immediately, never a Central Disposal disposal-request. Confirmed with the user: unlike Sale, Destroy never opens a request; it ends the item's disposition on the spot.
- **The bug**: the "Actions" dialog (`_PackageActionsDialog`, opened from Abandoned/Detained/Forfeited/Other status pages) had its **own** unconditional `_disabledForAll = {'Destroy'}` that grey-faded the tile no matter the role or an Appeal Directorate decision — a *second*, duplicate copy of the Release/Forfeit/Abandoned/Re-export/Destroy/Other action list, independent of the Final Disposition sheet's (already-correct) gate. Fixed by clearing that set.
- **Destroyed Goods pages** (yard `disposition_category_screen.dart` and Central Disposal `disposal_dashboard_screen.dart`) show a **Destroyed status column**, not a delivery concept — destruction has no delivery step. Their details popup shows the SR's real destruction financials (deposit → per-category expenses → refund/shortfall), not Valuation/Delivery Status/Destruction Price/Receipt No (those belong to a sale).
- ⚠️ **`srFinancialsProvider` had a fake-data generator**: whenever a real recorded expense/proceeds/deposit was `0`, it invented a plausible-looking figure from the item id's hash. This fed the Financials tab, the Expenses tab, *and* the Destroyed Goods popup once wired up — money nobody recorded, with no way to tell a real zero from an invented one. **Removed.** Zero is now a real, meaningful answer.
- The dead `_DestructionDeliverySection` (never instantiated, but shaped exactly like the wrong UI — Mark Delivered + Valuation/Receipt/Price fields) is deleted so nobody wires it up later.
- The now-redundant "Destruction Sale" nav item / route / disposal-request-dialog option is removed from Central Disposal, since Destroy no longer routes through a request.

### Marked-for-destruction items never reached the Destroyed Goods page (2026-09-02)

`disposeWarehouseItem` upper-cases the action name to build its pending tag, so marking an item "Destroy" writes `[FINAL:DESTROY]` (no "ED") — distinct from the confirmed `[FINAL:DESTROYED]` a later confirm step writes. Neither Destroyed Goods page's accepted-tag set included the unconfirmed spelling, so a package marked for destruction appeared on **neither** page — the confirm button (`_MarkDestroyedCell`, already correctly built) was structurally unreachable; nobody had ever hit it in real data. Fixed in both `disposition_category_screen.dart`'s `_acceptedTags['DESTROYED']` and `disposal_dashboard_screen.dart`'s `_isDestroyedEntry()`. The yard's table also gained a **Destruction Expenses** column (reads `srFinancialsProvider`, same figure Central Disposal's table shows) so the spend is visible without opening the popup.

### Destroyed Goods table cleanup: dropped columns, matched status pill, tailored cost form (2026-09-02)

- HS Code and Officer columns removed from the yard's Destroyed Goods table only (`disposition_category_screen.dart`, gated on `finalTag == 'DESTROYED'`) — noise for this tag, kept for Sold/Other/Re-exported.
- Central Disposal's read-only `_DisposalStatusChip` padding (8px) didn't match the yard's `_MarkDestroyedCell` "Destroyed" pill (10px) — same status, two sizes across the two screens. Padding unified; Central stays read-only (only the yard confirms a destruction — confirmed with the user, not making Central's Pending clickable).
- The Sold/Destroyed segmented filter (`_DeliverySegmentedFilter`) hard-coded "Delivered" as its true-state label on both tabs. Destruction has no delivery concept, so it now takes a `trueLabel` param — "Destroyed" on both the yard page and Central Disposal's Destroyed tab, "Delivered" everywhere else.
- `RecordExpenseDialog` (the "record costs" popup, shared across all disposal types via `kRecordableExpenseKinds`) always offered Auction Expenses, which never applies to a destruction. Added a `forDestruction` flag (set only from the Destroyed Goods table's edit action) that drops that field and swaps the header/notice copy to destruction-specific wording; the general Expenses tab call site is untouched.


### One shared destruction status control; the two tables had drifted (2026-09-02)

- Each Destroyed Goods table carried its **own copy** of the same status control, so they kept diverging: "Pending" measured 114.8px against "Destroyed" at 137.3px, and the yard's clickable "Mark Destroyed" was wider than both. Replaced by one `DestructionStatusPill` (`lib/widgets/destruction_status_pill.dart`) at a fixed box. The yard passes `onMark`; Central Disposal does not — that absence is what keeps Central read-only, not a separate widget.
- ⚠️ **The two tables disagreed about money**: Central summed `destructionExpense` alone, the yard summed `depositSpent`, so the same SR could show two different figures. Both now go through the shared `DestructionExpenseCell` (whole spend charged against the deposit).
- Yard's Destroyed table dropped HS Code, Officer and Notes (Notes only ever repeated the DSR number), matching Central's SR / Goods / Qty / Date / Destruction Expenses / Status / Details shape. Central's record-costs action moved out of the money cell into its own "Costs" column.
- The cost form drops **Advertising and Auction** for a destruction (goods go straight to the destroying contractor). Anything already recorded under those kinds still counts against the deposit via `_hiddenSpend` — otherwise the refund would come out larger than the depositor is owed.
- ⚠️ **The 69,000 / 87,000 figures Central Disposal showed were never real.** `financial_expenses` held rows only for the legacy `GL1/SR/01..21` SRs — nothing for `CED/GL1/SR/38|39|41`. Those numbers were the removed fake-seed generator's output (destruction = `((hash%20)+5)*3000`, advertising = `((hash%15)+3)*2000`), still showing from a stale session. Real destruction costs are now seeded for the four destroyed SRs. **When a figure looks plausible but the table beside it shows a dash, check the database before trusting either.**

### SR and OA are two registers with independent serials (2026-09-02)

Goods can be registered under an **OA** number as well as an **SR** one. The two are separate books that share a yard and a year: the number after `SR/87` is `SR/88`, **never** `OA/88`, and an OA number can never continue an SR one. An OA package is treated exactly like an SR package everywhere else — the register only changes how the number is minted.

- `kSrDocTypes` (`lib/core/directorates.dart`) is the list; `composeSrNumber(docType:)` mints, `docTypeOfSrNumber()` reads one back.
- `getNextSrNumber(docType:)` scopes **both** halves of its scan — the `ilike` asks for one register AND the serial loop rejects `parts[1]` from the other. Dropping either half makes OA continue SR's count.
- ⚠️ `stripDirectoratePrefix` hard-coded `parts[2] == 'SR'`, so `CED/GL1/OA/01/2026` kept its directorate prefix and then failed to match its own package. Now checks `isSrDocType`. **Any new helper that splits an SR number must not assume the literal `SR` segment.**
- `compareSrNewestFirst` gained a whole-string tiebreak: the same year+serial now legitimately exists in both registers.
- The registration form has a "Register" dropdown beside SR Number; changing it re-mints, and loading an existing package follows that package's register.

### Destruction is not a disposal request (2026-09-02)

Once Destroy became a direct Final Disposition (see the 2026-09-02 entries above), a disposal request tagged **Destruction** had nowhere to go: it sat in the Valuation Directorate's Pending Valuation queue and Central Disposal's Disposal Requests with **no route by which anyone could action it**. The request dialog was still offering the choice.

- `kDispositions` is sale-only now; `kDefaultDisposition = 'sale'`. `_DispositionToggle` in `disposal_request_dialog.dart` is deleted — it was already dead code (never rendered) while the row hard-coded `'sale'` on select.
- A row that already says `destruction` **still reads back as destruction** — historical data is not relabelled. Only a row *missing* its disposition defaults to sale.
- **Data migrated 2026-09-02**: 7 destruction request items removed. 4 named items already destroyed (they appear on Destroyed Goods via their own tags, so the request rows were duplicates); 3 (`SR/12/2026`, `SR/23/2025`, `SR/34/2025`) were never destroyed — still Forfeit with no tag — and returned to the yard's Final Disposition flow. Also removed: 6 `destruction_items` rows with `destroyed=false` and 4 `destructions` left holding nothing. The 4 genuinely-destroyed records were kept, and no request was left empty.
- ⚠️ The legacy **Destruction Sale** flow (`DestructionCard`, `destructions` / `destruction_items` tables, `/destruction-disposals`) still exists and is separate from this. Do not confuse it with the direct Destroy path.

### One header for the four Send-Disposal-Request pages (2026-09-02)

Detained, Forfeited, Abandoned and Other each built the same header from a `Wrap` holding the title block and an unbreakable `Row` of stat chips + the button. **A Wrap child cannot shrink**, so that Row dropped to its own line as soon as the title block left it no room — and since only the subtitle length differed between the four, they broke at four *different* widths. Detained's subtitle is much the longest, so it dropped while space clearly remained.

- `lib/widgets/disposal_page_header.dart` is now the single header. The **title** is the part that gives: the trailing block is capped at `available - minTitleWidth - gap`, and the title `Expanded`s into the rest, wrapping to 2 lines then ellipsizing.
- ⚠️ That cap is **load-bearing, not cosmetic**: at the app's 1000px minimum window the 3 chips + button want ~869px, more than the content area after the nav rail. Uncapped the Row overflows; capped, the trailing block scrolls horizontally and the button still never leaves the header line. Don't "simplify" it away.
- `test/disposal_page_header_test.dart` checks all four pages at 1600→700px for overflow, and that the button stays to the right of the title.
- Same class of bug in `disposal_request_dialog.dart`'s rows: SR number + source chip + appeal chip shared a bare `Row` where only the text could give, so chips collided; item name did the same against its Qty chip. Both lines are `Wrap`s now, and the Sale badge has a fixed width so badges line up down the list.

### The nav rail scrolled itself back to the top (2026-09-02)

Clicking a nav item near the BOTTOM of the yard's rail scrolled the rail back to the top the moment the page opened — hiding the item just selected.

⚠️ **Every screen wraps itself in its own `AppShell`** (26 call sites), so navigating disposes one shell and builds another. The rail's `ListView` had no controller, and a `ScrollController` held in `State` would have been born at offset 0 every time too. The remembered offset therefore lives at **module level in `app_shell.dart`** (`_navScrollOffset`), outside the widget tree; the controller is seeded from it and writes back on scroll. Don't "tidy" it into the State class — that reintroduces the bug.

### Empty Central Disposal outcome tabs showed no columns (2026-09-02)

The five outcome tabs (Government Use, Remanded, Auction, Converted, Removed) are all one widget — `UnsoldProposalsTab` with a different `proposalFilter`. Two consequences, both fixed:

- It did `rows.isEmpty ? _listCard(EmptyTableState) : Column(table)`, **swapping the whole `DataTable2` out**, so an empty tab lost its column headers. Now the table always renders and the empty state goes through `DataTable2.empty` — the pattern the yard's pages already used. Pager hidden when there are no rows.
- All five inherited the Unsold tab's message, "No unresolved unsold packages", naming goods the tab doesn't list. `emptyMessage` / `emptySubtitle` / `emptyIcon` are now per-tab.

Card-list tabs (Tender Sales, Committees, Destructions) legitimately keep the swap — they have no columns to preserve.

### Profile: photo cap, ICT-owned fields, grouped details (2026-09-02)

- **Profile photos are capped at 2MB** (`_maxProfileImageBytes`, `edit_profile_screen.dart`). Measured with `File(path).length()`, not the picker's reported size — the file is what gets stored on the profile and shipped with it.
- **Job Role and Yard are ICT's, not the officer's.** ICT assigns them at provisioning, so both are read-only on the profile form ("Set by ICT") and **not sent on save** — `updateProfile` skips a null, so ICT's values stand. Don't re-add the yard dropdown.
- **"Role" removed from the details card**: it named the same thing as Job Role in coarser words. Replaced by the **"Disables In"** countdown ICT's staff table already showed.
- The card's nine stacked full-width bars are now four titled groups (Identity / Contact / Posting / Account), two fields per row above 620px and one below.
- ⚠️ **`daysUntilExpiry` and `isExpired` must exempt the same roles.** `isExpired` exempted ICT; `daysUntilExpiry` did not, so an ICT account counted down towards an expiry that would never be enforced. Both now exempt disposal / appeal / valuation / executive / ict. Add a new institutional role to **both**.

### ICT Activity Logs tab; posts vs roles (2026-09-02)

**Activity Logs** (`lib/screens/ict/activity_logs_tab.dart`) — ICT's third tab, every action across every office.

- `AuditLogService.getAllLogs()` is the YARD ADMIN's view: one yard, admin+officer only. `getAllLogsAcrossOffices()` is ICT's: no yard filter, no role filter. **Don't merge them** — they answer opposite questions.
- `AuditLogModel` gained `userRole` and `yard`; the role used to be dropped on parse, so nothing could filter by office.
- Filters: yard, directorate/role, activity type, free text, plus a date window (all / day / range / month / year). The window is pushed into **SQL** (`ictLogRangeProvider` → `gte`/`lte`), not filtered client-side — the log is the one unbounded table between purges.
- A month window is built as `DateTime(y, m + 1, 0)` (the 0th of the next month), so a short February needs no special case. The end bound uses `23, 59, 59` or that day's own rows are lost.

### DC and SDDC are two posts, not one role (2026-09-02)

⚠️ **`role` is the permission level; the POST is `job_role`.** `profiles.role` only has `admin`/`officer` for a yard, so it *cannot* distinguish DC from SDDC. `kPostTitles` (officer/dc/sddc) and `kPostRoles` (post → permission) in `models.dart` are the source; `ProfileModel.postTitle` reads it back, falling back to the role's own name for an account provisioned before ICT recorded a post.

- ICT **never wrote `job_role`** before this, which is why a profile could show a stale hand-typed value. Both `verifyAndCreateUser` and `updateUserProfile` stamp it now.
- The profile hero badge shows `postTitle`, never `role.toUpperCase()` — **there are no "admins"** in this service.
- Yard is displayed as `<DIRECTORATE PREFIX> / <yard>` (`_yardWithDirectorate`): a yard alone is ambiguous (NNR is both CED and PSD) and the directorate prefixes every SR number.
- Photo picker uses `FileType.custom` + `['jpg','jpeg','png']` and **re-checks the extension after the pick** — `FileType.image` would let the platform offer SVG, a scriptable document. See also the 2MB cap.

### Destroyed report, report emblem, Top Management tender view (2026-09-02)

- **Destroyed-goods report** no longer shows Valuation / Destroyed Price from the old destruction-tender tables. Destruction has no buyer — nothing is realised and there is no price. It now shows **Destroying Deposit / Total Costs / Refund** from `srFinancialsProvider`, the same source as both Destroyed Goods tables and the expense form, so all four agree. A shortfall shows as a **negative** refund; don't clamp it.
- ⚠️ **The report emblem's `_loadLogo` caches its result** and its guard only re-runs while `_logoSvg` is null, so one transient failure used to downgrade *every later report in the session* to the "SLC" monogram. It also sat inside `_ensureFontsLoaded`, where `PdfGoogleFonts` **throws** if the asset manifest is unreadable — taking the emblem down for an unrelated reason. Now guarded separately, retried each report, and an empty asset falls through to the next candidate. `currentColor` must be resolved to a literal (a PDF has no notion of it).
- **Top Management → Tender Sales** (`lib/screens/executive/tender_sales_view_tab.dart`) is **read-only** and reuses `TenderSaleCard(readOnly: true)`. It applies **the same visibility rule as Central Disposal's tab** (unsold items remaining AND window still open), so a sale leaves the page once Disposal finishes it — intentional, and the caption says so. Yard filter matches **per item**, not per sale: a sale can mix items from a multi-directorate yard.

### Tender reports, and the emblem's REAL cause (2026-09-02)

- **All Tenders** — every portal. One row per SALE (not per item): goods count, sold, unsold, proceeds, Open/Closed. Open tenders are shown and labelled; it is a register, so nothing is withheld.
- **Tender Sale Sheet** — Top Management ONLY (`widget.executiveMode`). Goods in a tender with the **reserve price**, to carry into the sale. ⚠️ Only sales past `saleEnded` contribute rows — **the valuation IS the reserve, so it cannot be shown while bidding is open**. This is why the report is legitimately empty until a tender closes. The card always stays on the page; only the rows come and go.
- Both filter yard **per item**, not per sale (a sale can mix items from a multi-directorate yard).

### ⚠️ The report emblem: `currentColor` (2026-09-02)

The long-running "logo shows as SLC" bug, finally reproduced instead of guessed at. `Sri_Lanka_Customs_logo_tinted.svg` paints with `fill:currentColor` (50 occurrences, inside `style="…"`). **The `pdf` package cannot resolve `currentColor`** — it logs `Unknown color: currentColor` and draws *nothing*, so `_buildHeader` falls back to the "SLC" monogram.

Measured, because a failed emblem still produces a valid PDF:

| input | bytes |
|---|---|
| blank page | 527 |
| tinted SVG **raw** | 1233 ← draws nothing |
| tinted SVG, currentColor replaced | 33630 |
| plain `Sri_Lanka_Customs_logo.svg` | 33626 |

`replaceAll('currentColor', '#0D47A1')` in `_loadLogo` is therefore **load-bearing, not cosmetic**. `test/destroyed_report_and_tender_view_test.dart` renders all three and asserts the byte sizes, so this cannot silently regress. (Same root cause as the earlier flutter_svg note — see [[logo-ship-plane]].)

### The two tender reports, corrected (2026-09-02)

Both were reworked the day after they landed — the first cut answered the wrong question.

- **All Tenders** now lists the **GOODS**, not one row per sale. Tender number + date repeat down each tender's items; SR number, qty, latest valuation, sold price, Sold/Unsold. An unsold item says *Unsold* rather than a blank price — "no price" and "sold for nothing" are different facts. Still every portal, still shows open tenders (it is the register).
- ⚠️ **Tender Sale Sheet** was gated on `saleEnded`, i.e. it showed **closed** tenders — the opposite of a sheet carried *into* a sale. It now mirrors **Top Management's own Tender Sales page**: same rule (`items.any((i) => !i.sold)` AND window still open), plus `if (it.sold) continue;` since a sold item has left the sale. Columns: Tender No, SR Number, Goods Name, Goods Description, Qty, Yard / Warehouse (newest warehouse entry, so goods can be pulled), Latest Valuation. **Keep it matched to that page** — that is what makes report and screen agree.
- `TenderSaleCard(readOnly: true)` said **"Pending"**, which reads as an action the *viewer* owes. Nobody watching a read-only card acts → **"Awaiting Tender"**.
- The Top Management tender tab used `customsBlue`; the portal's accent is `AppTheme.executiveTeal`. Match the portal, not a nearby blue.

### Dropdowns are searchable; the year filter rolls forward (2026-09-02)

- ⚠️ **`srYears()` always includes the current AND next year** (`lib/widgets/year_filter.dart`), on top of whatever the SR numbers carry. Built from data alone it went stale every **1 January** — nothing registered yet, so the year being worked in was missing from the filter meant to find it. Both come from `DateTime.now`, so it advances with no yearly edit; the `now:` parameter exists so tests can pin a date. Every year dropdown in the app reads this one function.
- **Every dropdown in the app is searchable.** `_StyledDropdownContentState` in `lib/widgets/styled_dropdown.dart` shows a search box once `options.length > 8` (a list that fits on one page needs none) and filters on the label, case-insensitively. One widget backs `StyledDropdownButton` and `StyledDropdownFormField`, so the change reached everything at once — don't add per-screen search.
  - "All" is rendered **outside** the filtered grid: it is a reset, not an option, and must stay one tap away while a query narrows the list.
  - `page` is clamped against the *filtered* length; typing also resets `_page = 0`.
- `kPostTitles['officer']` is **'Officer'**, not 'Yard Officer' — the other two name the post plainly ('DC (Deputy Commissioner)', 'SDDC (…)') and the odd one out made the list look admins-only. `ProfileModel.postTitle`'s fallback matches.

### Searchable dropdowns, rolling year filter, posts vs roles (2026-09-02)

- ⚠️ **`srYears` always offers the current year AND the next**, from `DateTime.now()`. Derived purely from the data it went stale every **1 January** — nothing registered yet, so the year being worked in was missing from the filter meant to find it. It advances on its own; never "simplify" it back to data-only.
- **Every dropdown in the app is `_StyledDropdownContent`** — one widget. It now shows a **search box once the list exceeds 8 options** (i.e. once it pages) and narrows in place. Lists that fit one page get none. `All` stays put while a query narrows, because it is a **reset**, not an option. Typing resets to page 1.
- ⚠️ **Two different rules for SR/OA**, don't merge them:
  - MINTING a new number (`getNextSrNumber`) is scoped to one register — the next free SR counts SR numbers only.
  - SWITCHING the register on a number already on screen (`withSrDocType`) is a **correction** and **keeps the serial** — `CED/GL1/SR/87/2026` → `CED/GL1/OA/87/2026`. Re-minting moved the serial out from under the officer.
- **DC and SDDC are shown apart** in ICT's table and role filter, via `postShortTitle` / `kPostShortTitles`. The permission role cannot distinguish them, so the filter sends `kPostRoles[post]` to the server and narrows to the exact post client-side. An account with **no post recorded** still reads `DC / SDDC` — without one they genuinely are indistinguishable. Post list reads **"Officer"**, not "Yard Officer".
- **`TenderStage`** (models.dart) replaces the read-only "Pending" chip: `Tender Open` → `Tender Started` → `Awaiting Decision` → `Tender Closed`, read off the sale's own moments (`saleMoment` / `saleEndMoment` / `unsoldDeadline`), each with a tooltip.
- Portal polish: Top Management's sign-in is **"Top Management Sign In"** (was "Executive" — nothing else calls it that); the four directorate portals animate their heading in like ICT, and the **OTP-sent banner is green on every portal**, not the portal accent — it is a confirmation, not chrome.

### Password reset: two different flows, on purpose (2026-09-03)

**Yard staff reset their own; ICT reissues a directorate account.** They are not the same thing and must not be merged.

- **`postgres/05_password_reset.sql`** — `reset_email_for_identifier` and `reset_password_for_identifier`, both `SECURITY DEFINER` (auth.uid() is NULL with no session, so ordinary RLS denies everything). Resolves through the **same `email_for_login`** sign-in uses, refuses a **deactivated** account, delegates to `auth.change_password` so hashing/min-length live in one place, restarts the 90-day clock and clears any lockout. The file **verifies itself** — a `DO $verify$` block that ran green against the live DB.
- ⚠️ **Neither the SQL nor the UI ever says whether the account exists.** "No such account" would let anyone test which usernames and addresses are real. Step one advances to the code step either way; the code simply never arrives.
- **`lib/widgets/forgot_password_dialog.dart`** — one dialog, both yard portals (Officer + DC/SDDC), reached from beside Remember-me. Three steps; a bad code sends the officer back one step **with the typed password kept**.
- **ICT → Directorate Access** (`directorate_access_tab.dart`) — a directorate account belongs to a **post, not a person**, so there is no personal mailbox for a self-service link. ICT generates username + password and emails both. The **password never appears on screen or in the audit log**. A deactivated account cannot be reissued.
- **`kDirectorateRoles`** (models.dart) is the one list of institutional roles. ⚠️ **Keep it in step with the exemptions in `isExpired` and `daysUntilExpiry`** — same accounts, same reason; a test asserts all three agree.

### Usernames assigned to every account (2026-09-03)

Everyone signs in by username now, but **8 of 11 accounts had none** — reachable only by email address. Assigned and verified through `email_for_login`:

`Anushanga` (DC/SDDC) · `Deepal` `kaushan` `onela` (Officer) · `appeal.ad` · `disposal.dc` · `vdc` · `exec.dg` `exec.adg` `exec.dc` · `ict.admin`

Directorate profiles now show and edit the **username** in place of Full Name, and the Role row is gone (the portal already says which directorate it is).

### Perishable goods take a different path entirely (2026-09-03)

Food, chemicals and the like spoil, so they **never reach a warehouse** and **never sit out the 30-day appeal window** — it would outlast the goods.

- **`package_items.nature`** — `'normal'` or `'perishable'`, CHECK-constrained. ⚠️ **Defaults to `'normal'`** in the DB and the model, which is what left all 101 existing items and every existing query behaving exactly as before. `postgres/06_perishable_goods.sql`, self-verifying.
- **SR form** asks **Nature before Status**, because it decides whether a status is asked at all — Detain/Forfeit describe nothing that happens to a perishable. The item gets its own `'Perishable'` status so the disposition pages (which group by status) don't claim it.
- **`getRequestableExpiredPackages`** — a package holding a perishable is never skipped for the window, and the item passes `itemPassesWindow` unconditionally. Own `source: 'perishable'`, so it never takes the abandoned/other branches.
- **Perishable Goods page** (`perishable_goods_screen.dart`) — yard sends; Central Disposal gets `readOnly: true` (its tab is **appended LAST**: two `animateTo` calls in that file address tabs by index, so inserting earlier silently misroutes them). Shows days-waiting, reddening with age.
- ⚠️ **Perishables tender ONLY as `'special'`**, and a special sale carries **only** perishables — the gate is `isPerishable == (_tenderType == 'special')`, deliberately both ways so the two are never mixed into one lot.

### The four appeal states, and the two nothing ever produced (2026-09-03)

A row's appeal state is **not** a function of the calendar alone. There are four, and the seed could only ever reach two of them:

| State | Comes from | Was seeded? |
|---|---|---|
| `Appealing · Nd` | window still open | ✅ |
| `Enabled` | window expired | ✅ |
| `On Appeal Hold` | **a person lodging an appeal** | ❌ never |
| `Decided · X` | **a person ruling on one** | ❌ never |

The last two exist only because someone acts, so nothing in a date-driven seed could produce them: Appeal Directorate → **Decided Goods was permanently empty**, and **no row anywhere showed a hold**. `_seedAppealOutcomes` now rules on a share of the appeals.

- ⚠️ **Decisions go in `item_appeal_decisions`, keyed by item id — never the package-level `appeal_decision` column.** On a multi-item package `appealDecisionForItem` deliberately ignores the package-level value (deciding one item must not mark its siblings decided), so a decision written there produces a row the app refuses to treat as decided. A test reintroduces the bleed and confirms the test catches it.
- ⚠️ **A hold must outlast the deadline.** `unblocksAction` is `isDecided && !onHold` — a hold beats both the calendar and a ruling. It is the one state the date can never imply.
- **Coverage is taken before chance, keyed on the GOODS NAME.** A random roll left 15 kinds with no hold at all. Keying on `(source, goods)` then over-corrected: 26 kinds of goods became 94 pairs and so 94 holds, burying the Appeal Directorate under **more open appeals than decided ones**. Every kind of goods needs to be *seen* on hold; it does not need to be on hold once per disposition. Missing holds **throw**.
- ⚠️ **A hold is an appeal still waiting to be heard**, so few should be outstanding: holds are spent on coverage only (one per kind), and everything else is ruled on. But **most EXPIRED rows are left alone** — ruling on all of them wiped out `Enabled` entirely, which is the ordinary state of goods whose window ran out with no appeal ever lodged, and the one the yard sees most. An appeal is the exception, not the rule.
- ⚠️ **Rows are ruled on OLDEST first.** Newest-first spent every still-open appeal on a ruling and left `Appealing · Nd` **empty** — ruling on a row ends its countdown. Live appeals are now largely skipped, but **coverage overrides the skip**: some kinds (`other|Used Engine Blocks`) exist only as a live appeal, and skipping them tripped the missing-hold check.

### One SR number, several goods (2026-09-03)

A package is one number; the goods inside it are separate items. **The same SR/OA number appearing on several rows of a status table is correct, not a duplicate** — each row is a different item under that one number. Seeded up to 4 items per package so this is plainly visible (Other went from 1 such number to 9).

Also: **Detain gets the 30-day window too.** It has no `forfeited_packages` row of its own, which makes it easy to assume it has no window either — but the window runs from the **entry date** and freezes a Detain exactly as it freezes a Forfeit. It was excluded from the recent cohort, so **every detained item was past its window** and none could be seen blocked; 19 now sit inside it.

**Zone capacity has one definition.** `_zoneCapacity()` is used both when the zone row is written and when the seeder books space against it — previously the same numbers were written out twice and could drift, filling zones to a figure the Zone Capacity page did not share.

### A ruling names one of the yard's five actions (2026-09-03)

The Appeal Directorate's five decisions are **exactly** the five actions the yard can carry out in Final Disposition — `RELEASE` / `SALE` / `DESTROY` / `RE-EXPORT` / `OTHER`. A ruling is an instruction to take one of them, so a code outside that set would name an action the yard has no way to perform, and `ItemAppealOutcome.label` returns **null** for anything it does not recognise — which renders as *no decision at all*, not as an error.

⚠️ **An `OTHER` decision shows its custom note as the chip's label**, and that note is **free text the officer types** — the app supplies no wording of its own for it. Two consequences, both hit:

1. A sentence-long note **overflowed the chip and was clipped mid-word**. `appealDecisionLabelForItem` now trims to `kAppealDecisionLabelMaxChars`; the full text stays in `appealDecisionNoteForItem`, which the tooltip and details dialog read.
2. Because it reads exactly like a decision name, the note must describe an outcome the yard can **actually record**. A seeded note of *"Referred back to yard"* looked like a **sixth decision the app does not have** — there are five, and they are the five Final Disposition actions. A test now asserts no sixth exists.

### Detained goods can be appealed too (2026-09-03)

A detained item has **no `forfeited_packages` row of its own** — the Appeal portal synthesises one (`source: 'detain'`) so the item can be seen at all. But a synthesised row is rebuilt on every read, so it can carry **nothing**: no hold, no decision, no stable id. `getAppealablePackages` already prefers the **stored** row when one exists ("so its hold, decision and real uuid come through") — that is the seam.

So detained goods could only ever show `Appealing` or `Enabled`; the two ruled states were **unreachable for them, whatever the yard did**. `_seedDetainAppeals` now lodges real rows for half the detained items. ⚠️ It must run **before** `_seedAppealOutcomes`, or the ruling pass has nothing to rule on. The screen code was already correct and needed no change — it reads `allItemAppealOutcomesProvider` and renders `AppealStateChip` like every other page.

⚠️ The pool has to be a **decent share**: coverage claims the first row of each kind for a hold, so a thin pool leaves nothing over to be decided or left counting down, and detained goods show only one of the four states.

### Released Goods and Old Entries: no table of their own (2026-09-03)

Both pages were empty because **neither has a record of its own** — each reads a flag on data that already exists, and nothing had ever set it.

**A release is a `warehouse_entries` row flipped to `is_returned`**, plus the item's status becoming `'returned'` (which is what drops it off Detained Goods). `_seedReleases` mirrors `markAsReturned`'s full-release path.

- ⚠️ **The receipt number lives inside `return_notes`**, formatted `Receipt No: <no> | Date: <date>` — there is **no receipt column**. The page parses it back out of that string, so the format is load-bearing; a note that does not match shows an empty Receipt No.
- ⚠️ **A returned entry is not automatically a release.** A note starting with `[` is a **disposition tag** ([FINAL:DESTROYED], [FINAL:OTHER]) recorded on the same flag, and `_isReleaseEntry` filters those off the page. A released row must never begin with one — except the explicit `[FINAL:RELEASED]` / `[RELEASE…]`.
- Releases run **before** the appeal passes, so an appeal is never lodged against goods that have already gone home.

**An old entry is a package whose `old_sr_number` is set** — goods already in the yard under the previous register when this system took over, carried across keeping both numbers. Only the **earliest** packages get one: a migration happened once, at changeover. The old number is deliberately **not** a valid current SR number (`SR/1780/2021` — no directorate prefix, no yard segment); that shape is what makes it recognisably old.

### An "Other" process that is finished is read-only (2026-09-03)

An "Other" item still being worked shows an appeal state (Enabled / On Appeal Hold / Decided) and offers actions. **Once the yard records the outcome the process is over**: the row becomes a completed, read-only record — a `_CompletedChip` instead of an appeal state, and no actions. Nothing seeded that, so the finished half of the page never appeared.

Only `recordFinalDisposition` produces it, and `_seedFinalOtherOutcomes` mirrors it exactly:
- inserts a **returned** entry tagged `[FINAL:OTHER] — <outcome>`,
- sets the item's status to `'other'` (lowercase; the page's marker tests are case-insensitive),
- and **deletes the remaining held entry** — the goods have left the yard, so they must stop occupying and being charged for a zone.

⚠️ **The separator is an EM DASH.** `_finalOtherLabel` matches `[FINAL:OTHER]\s*—\s*(.+)`. A hyphen still marks the row completed but the label falls back to a bare "Other" and the outcome text is silently lost — data that looks like it works.

**Both routes in are seeded**, because the yard reaches this state two ways that look identical afterwards: goods that went to appeal and came back with a ruling, and goods finished directly with no appeal. ⚠️ The appealed ones are **scarce** — only a fraction of Other items were ever ruled on — so sampling both at the same rate left barely any. A ruling is an instruction to act, so **every ruled item is carried out**; the plentiful unappealed ones are sampled. This pass must run **last**, after the rulings exist, or every completed row looks like one the yard finished directly.

### The disposal-to-tender pipeline (2026-09-03)

Nothing seeded any of it, so **every screen downstream of "Send Disposal Request" was empty**: Pending Valuation, Unsold Tenders, Tender Sales, Sold Goods, Unsold Goods. The chain:

```
disposal_requests
  → disposal_request_items   (valuation_cost, then forwarded)
    → tender_sales           (a sale, with a close time)
      → tender_sale_items    (sold / not sold, per item)
        → tender_bids + tender_revaluations   (for a round that failed)
```

⚠️ **Re-tendering APPENDS a round, it does not overwrite one.** Each round inserts a new `tender_sale_items` row against a new sale and leaves the previous round's row untouched and still unsold. That history is what "Times" counts and what the Valuation portal reads — overwriting would erase it and every package would read as tendered exactly once.

⚠️ **A request stays in Pending Valuation while ANY of its items is unforwarded.** A fully forwarded request has moved on to Central Disposal, so leaving one request unforwarded is what makes that page show anything at all.

⚠️ **The reserve falls each time a round fails.** A re-valuation lowers it before the next round, so a sale price must beat the reserve **in force**, not the original — 33 sales look like underpayments against the original and are correct against the reserve that actually applied.

⚠️ **A postgres `numeric` comes back as a STRING**, not a num — `r[3] as num?` throws. Parse it. (`unit_value` hit this.)

⚠️ `disposal_request_items.disposition` is CHECK-constrained to lowercase **`'sale'` / `'destruction'`**.

Seeded spread: 14 awaiting valuation · sold on round 1 (38), 2 (16), 3 (19), 4 (8) · 18 still unsold awaiting re-valuation, each with bids and a valuation history. Runs **last of all**, after every pass that retires goods (released, finished as Other), so it never tenders goods that have left the yard.

### Destruction: two states, two routes in (2026-09-03)

Destroyed Goods filters on **Pending vs Destroyed**, so seeding one leaves half the page empty:

- **Pending** — item status `'supposed to be destroyed'`. Listed for destruction; it has not happened.
- **Destroyed** — status `'destroyed'` **and** the `destruction_items` row marked destroyed, which carries the date and receipt.

Both routes in are seeded, because a yard reaches destruction two ways: through the **Valuation** directorate (a request costed and forwarded, disposition `'destruction'`), and **directly**, when the yard records Destroy as a final disposition with no request — perishables especially, which cannot wait.

⚠️ **"Destruction Expenses" does NOT come from the destruction row.** It is read from `financial_expenses` (kind `'destruction_expense'`) against the **SR number**, so a destroyed row with no expense row shows a blank spend however complete it looks.

⚠️ `destruction_items.destroyed_price` is **NOT NULL, default 0** — a destruction that has not happened has cost nothing, so 0 is the honest value, not null.

Runs **after** the tender pipeline and excludes anything already tendered or on a request: the same goods cannot be both sold and destroyed, and whichever pass runs second has to say so.

### Three shape bugs in the seeded pipeline (2026-09-03)

⚠️ **The unsold pool could never show `4×`.** A package that *sells* on its fourth attempt leaves the pool the moment it sells, so with unsold packages capped at three rounds that count only ever existed on goods that had already gone. Unsold packages now run to four.

⚠️ **A tender sale is a SALE, not a lot.** Minting a fresh sale per package made every tender a single-item auction. Packages whose round falls in the same month now share a sale (up to 4), and the sale's own date governs all of its items.

⚠️ **Pending Valuation is a QUEUE.** All 14 items on one request made the page read "1 request(s)" — a queue of one. Now several separate requests with their own dates, and every second one arrives **part-valued** (a cost against some items while the rest wait). It stays pending because **a cost is not a forward** — but a request must never be left pending with *all* items costed, since valuing them all is what precedes forwarding.

### Why the unsold pool read "Awaiting value" for everything (2026-09-03)

⚠️ **A re-valuation prices the NEXT round only when its `tender_sale_id` is NULL.** The app keys re-valuations by round and reads the null-keyed one as "the price for the round to come"; a figure attached to a sale is *that round's own reserve*, which every held round already has. The seeder attached them all to a sale, so nothing ever read as re-valued or became re-tenderable — `revals['']` was always empty.

**Two hands price these goods, and the chip tells them apart:**
- the **Valuation** directorate re-values directly → "Re-valued", ready to re-tender;
- a **tender committee** prices one that has gone round too many times → "Committee valued" until the ADG submits it, at which point the submitted figure becomes the pending re-valuation.

⚠️ **A committee's figure is not a re-valuation on its own.** Writing one at committee time would show the package ready to re-tender before the ADG had approved it — the approval skipped rather than modelled.

⚠️ `tender_committees.members` is **JSONB holding objects** (`name`, `designation`, `salary_no`), not a list of strings — a plain string list parses to an empty committee because no entry has a `name`.

### An active tender sale, and the final outcome (2026-09-03)

⚠️ **A sale is ACTIVE only while it holds an unsold item AND its window is still open.** Every seeded sale was dated in the past so its items could be counted sold or unsold — which left the Tender Sales tab completely empty. Some sales are now dated a day or two **ahead** with their items unsold, filled from packages the pipeline has not already used.

**`unsold_proposals` is the end of the road** — Top Management's final outcome for goods that were priced, re-tendered and still did not sell. It is what moves a package off Unsold Goods and onto its own tab. ⚠️ The five outcomes (`government_use`, `remand`, `auction`, `convert`, `remove_from_premises`) are **cycled, not picked at random**: each has its own tab, and a random pick over a small pool leaves some of those tabs empty.

### Taxes, expenses and re-export (2026-09-03)

**`disposal_taxes` is CONFIGURATION** — the rates Central Disposal maintains — and the Taxes tab lists it directly, so an empty table means no tab and no tax breakdown on any sale.

⚠️ **A sold item does not reference the tax rows.** It stores a **snapshot** in `applied_taxes` (id, name, percentage, amount), so a later rate change never rewrites the history of a sale already made. Both have to be seeded: the rates for the tab, the snapshot for the sale. An **inactive** rate is kept in the table (the tab shows it as inactive — not the same as deleting it) and must never be charged; `PAL` is seeded inactive to prove it.

**The Expenses tab groups by kind**, so seeding only `destruction_expense` left every other kind empty. A tender sale runs up advertising, labour, transport and auction costs of its own — all five kinds now have rows. ⚠️ Destruction expense is charged on the **destruction**, the others on the **sale**.

**Re-exported Goods reads exactly like completed "Other"** — a returned entry tagged `[FINAL:RE-EXPORTED]` plus the item status — and was empty for the same reason. Re-export is for goods that should never have been imported: they go home rather than being sold here, and they leave the zone with it. The pass skips anything the tender or destruction passes touched — goods cannot be sold, destroyed *and* sent home.

⚠️ **In a Dart RAW string, `\$1` is a literal backslash plus `$1`** — a postgres placeholder must be a bare `$1`. Two of these slipped in through a shell heredoc and would have broken the SQL at runtime.

### Perishables finally reach a sale (2026-09-03)

47 perishables sat on the Perishable Goods page and **nothing downstream ever saw one** — no tender, and not a single `special` sale existed.

⚠️ **The rule holds BOTH ways**: a perishable may only enter a `special` sale, and a special sale carries **only** perishables. A general sale runs too slowly for goods that spoil, and mixing them into one lot is what the two types exist to prevent. Verified in both directions after seeding: 0 perishables in a general sale, 0 normal goods in a special one.

⚠️ **`forfeited_packages.source` is CHECK-constrained to forfeit / abandoned / other / detain.** The `'perishable'` source the app displays is **synthetic** — built on the fly for goods that have no `forfeited_packages` row at all. So a perishable that really reaches a sale needs a real row under a *permitted* source; what routes it to a special sale is the **item's `nature`**, not the source.

A perishable also waits out **no appeal window** — its `appeal_deadline` is the entry moment itself, which is why it can be disposed of within days rather than 30.

### The audit trail was empty (2026-09-03)

ICT's Activity Logs reads `audit_logs`, which had **0 rows** — a system carrying 176 packages, ~90 sales and a year of disposals had no record of a single action.

⚠️ **The query joins `profiles!inner`, so a log with a null or unknown `user_id` is dropped SILENTLY** — it inserts fine and simply never appears. Every seeded row is attributed to a real profile, with the **role matched to the work**: a yard officer registers and releases goods, Valuation values them, Central Disposal runs the sales and destructions, Appeal rules on appeals. A log under the wrong role reads as nonsense to anyone auditing it.

Logs are **derived from what was actually seeded**, not invented — an SR number in a log line is a package that really exists, on the date it really happened.

⚠️ **A log records something that HAS happened, so it can never be dated ahead.** A sale scheduled for next week is legitimately future-dated, but the log of *creating* it belongs to the day it was created — 3 rows were future-dated before this was clamped.

### Selling goods does three things, not one (2026-09-03)

⚠️ `disposal_mark_sale_item_sold` — the yard's own RPC — writes a **`[FINAL:SOLD] — Receipt: <no>`** entry as the record of sale, sets the item status, **and DELETES the still-held entry**. Setting the status alone left **68 sold items still filling zones**, which makes Zone Capacity overstate what is actually in the shed. Same rule for destroyed and re-exported goods: anything that has left the yard stops occupying (and being charged for) space. A *pending* destruction has not happened yet and correctly keeps its space.

`_recordSaleInWarehouse` mirrors the RPC and is shared by both sale paths (general pipeline and perishable special sales). It returns quietly when there is no held entry — a perishable never reached a warehouse in the first place.

After the fix: 0 sold/destroyed/re-exported goods in a zone, fullest zone 80%, 68 `[FINAL:SOLD]` records of sale.

### Two tabs that were empty by construction (2026-09-03)

**Disposal Requests** — ⚠️ Central Disposal sees a request only while its packages are still **waiting**. `getDisposalRequests` filters out anything already placed in a tender or destruction, because it has moved on to Tender Sales. The pipeline tendered everything it forwarded, so the tab was empty despite 99 forwarded items. Some requests are now forwarded and deliberately **left unacted on** (both `sale` and `destruction` dispositions, since Central Disposal decides both ways).

**Unsold Goods (the final table)** — a package gets there only when *all three* hold:
1. **more than `kMaxBidTenderRounds` (3)** rounds have failed,
2. the committee valued it **and the ADG submitted** that figure,
3. it was tendered **again at that price, after the submission**, and that round **ended** still unsold.

⚠️ Condition 3 was missing entirely. Without it the DG would be deciding the fate of goods that still had a live chance of selling — and the app would not list them as exhausted either, so a recorded decision sat on a package **no tab claimed**.

⚠️ **A committee cannot be appointed before 3 rounds have failed.** `times >= 2` looked harmless but capped the count below the threshold, so those packages could *never* reach the final table however many rounds followed.

⚠️ **The whole committee sequence must fit before today**: appointed → submitted (+2 days) → re-tendered → that round ended. A committee dated a few days ago leaves no room, and the package can never become exhausted — dating it 20–80 days back fixes it. A decision is only recorded when the round **actually ran**.

Result: 16 exhausted — 3 awaiting a decision, 13 decided across the five outcome tabs, 0 strays.

### "The database rejected this request" was a queue, not a rejection (2026-09-03)

The Perishable tab failed with `57014: canceling statement due to user request`. Its own query takes **13 ms** — it was never slow, it was **ninth in line**.

⚠️ **`PgDatabase` held ONE connection.** Postgres runs one query at a time per connection, so a screen loading a dozen providers at once queued them all behind each other, and whichever was last waited out the 60-second client timeout and was cancelled. Now a `Pool` (default 8, `PG_POOL_SIZE`). Measured against the live DB: **8 × 1-second queries in 1456 ms** (was 8s+).

⚠️ **`onOpen` is not optional on the pool.** The session variables RLS reads (`app.current_user_id`, `app.current_role`) are **per connection**, so a pool opening a second one without re-applying them runs that user's queries as `anon` — every user-scoped policy denying, on *some* queries and not others, depending purely on which connection the pool handed out. Verified: all 8 pooled connections report the same user.

⚠️ **Sign-in/out must reach every pooled connection**, so `setCurrentUser` now **closes the pool** on a change; the next query opens fresh connections and `onOpen` runs on each. Leaving them would answer as the previous user on whichever connection came up next.

### Errors now say what actually happened (2026-09-03)

⚠️ **A cancelled statement carries the same `Severity.error` a genuine SQL fault does**, so it was classified as "the database rejected this request — this is a fault in the app". A new `_Kind.timeout` is checked **before** the database branch: *"This took too long to load… nothing has been lost."*

⚠️ **24 snackbars dumped the raw object** as `Text('Error: $e')`, putting driver text in front of an officer. `showErrorSnack(context, e, action: …)` routes through the **same classifier** the full page uses, so the two can never word the same failure differently — and the colour now follows the kind (amber for a timeout, red for a real fault) instead of always red.

### Destruction never goes through a disposal request (2026-09-03)

⚠️ **In Final Disposition only SALE raises a disposal request** — `_requestActions` is `{'SOLD'}` (package_details_dialog.dart). Release, Destroy and Re-export are recorded **directly**. And there is nothing for the **Valuation Directorate** to do with goods being destroyed: they are not being priced for a buyer.

The app was already correct; **the seeder was wrong.** It wrote `disposition: 'destruction'` request items, which put destruction rows on Central Disposal's **Disposal Requests** tab and into the valuation queue — a route the app deliberately does not have (it existed once and was removed). 25 such rows were in the database and are gone.

A `disposal_request_items.disposition` is now always `'sale'` in seeded data. The CHECK constraint still allows `'destruction'` for the historical rows the column was built for, so the constraint was left alone — the rule is about which path *creates* one.

⚠️ Not every `'destruction'` string in the code is a database row: `disposal_dashboard_screen.dart:6678` and `:7041` build **in-memory view models** for Central Disposal's own Destroyed tab. Those are correct and must not be "fixed".

Destroyed Goods is still fully populated (21 destroyed · 22 pending), all through the direct route.

### Sold Goods: four fixes (2026-09-03)

**1. The "0 Destruction" pill is gone from Disposal Requests.** A request is always a Sale, so the pill read `0 Destruction` on every one — pointing at a route the app does not have.

**2. ⚠️ The Destruction panel was package-scoped, not item-scoped.** `p.items.any(...)` asked whether *any* item was being destroyed, so opening a **SOLD** item showed it "Destruction Status & Financials" because a sibling under the same SR number was pending destruction. One number covers several goods and **they meet different ends** — it now tests `highlightedItem` (the item the popup is about), falling back to the package only when no item is in view.

**3. Mark Delivered moved from the popup into the Sold Goods table.** It is the yard's one routine action on a sold row, and doing it from a popup meant open → scroll → press → watch it close.
- ⚠️ It invalidates the **shared** providers and fires `tenderSaleItemsRefreshProvider`, which `tenderSaleItemsChangeTriggerProvider` watches — so **Central Disposal's Sold table updates by itself**. Refreshing only the cell would leave the two portals disagreeing about whether goods had been handed over.
- ⚠️ **No revert.** Once delivered the chip is a plain label: goods that left with their buyer cannot un-leave.
- Only a yard sees the button (`!profile.isDisposal`); Central Disposal watches.

**4. ⚠️ The red bar down the Sold Goods table was a RenderFlex overflow.** `Row(mainAxisSize: min)` with an **unconstrained** `Text` — a large re-valued figure (`Rs 22,768,380`) plus the price-change icon is wider than the column, and Flutter paints its overflow stripes vertically. `Flexible` + ellipsis lets the number give way. Fixed in **both** copies: the yard's table and Central Disposal's, which had the same latent bug behind wider columns.

### The nav rail: one definition, grouped, and it responds to the pointer (2026-09-03)

⚠️ **The officer and DC/SDDC rails were two hand-maintained copies** of the same twenty-odd entries, and had already drifted once. `navSectionsFor({required bool isAdmin})` now builds both from one list — the admin rail differs only in its Dashboard route and its extra Admin Panel entry. A test asserts the duplicated lists do not come back.

**Grouped in the order the work happens**: Register → Storage → Held Goods → Disposed → Final Outcomes → Reporting. Goods arrive, are held, get a disposition, are disposed of, and reach an outcome — reading the rail top to bottom now follows that path. Each group carries a quiet caption; the Dashboard sits in an unnamed section and needs none.

⚠️ **Hover is tracked explicitly** (`MouseRegion` + `_hovered`). An `InkWell`'s own hover highlight is a faint overlay that all but vanishes against the dark navy rail, so pointing at an item gave almost no feedback — on a rail this long you could not tell which row you were about to click. **Active wins over hover**: an already-open page must not restyle just because the pointer crosses it.

⚠️ `'/admin'` must match **exactly**. Every other route matches by prefix, but `'/admin'` is a prefix of `'/admin/panel'`, so a prefix test lights up Dashboard while the Admin Panel is open.

### Two dropdown/pill inconsistencies (2026-09-03)

**Goods History's year filter was the one dropdown that behaved differently.** It built its own list from a hard-coded "this year back six years" loop, so it offered years with nothing in them (2020–2023) and never offered **next** year. ⚠️ It could not use `srYears()` like every other page because Goods History pages on the **server** — only one page of rows ever reaches the app, so the years cannot be read off loaded data. `packageYearSourceProvider` fetches the SR numbers alone (one small column) so `srYears()` can build the same list everywhere.

**Mark Delivered now renders through the same fixed box as Mark Destroyed.** `DeliveryStatusPill` shares `_statusPill` with `DestructionStatusPill`, so neither column jumps as a row changes state and the two line up beside each other. ⚠️ The Delivery column was `fixedWidth: 120` against a 132px pill — it would have clipped; both now use `kDestructionStatusColumnWidth`.

### Perishables take a different road at every step (2026-09-03)

**SR form.** ⚠️ **Category is a WAREHOUSE routing choice** — it picks the target zone — so a perishable, which never reaches a warehouse, has nothing to decide there. The field and the zone-capacity hint under it are both hidden; the hint would otherwise report space the goods will never occupy.

⚠️ **Post Status Activity now offers EVERY activity, unfiltered.** It used to be filtered by status (Detain → pending activities, everything else → disposal activities). A perishable has *no status at all*, so the filter left it with nothing to choose from — and the filter was wrong anyway: a detained item can still be destined for destruction. `kAllPostStatusActivities` in both the SR form and the edit dialog, which must agree or editing an item would drop an activity the form allowed. The clear-on-status-change is gone with it: every status offers the same list, so a selection can never stop being valid.

**Warehouse confirmation** says **"NO WAREHOUSE NEEDED"** for a perishable-only package. ⚠️ **EVERY item, not any** — a mixed package still has normal goods that need a warehouse, and hiding the step would strand them.

**The Perishable table has no "Waiting" column.** A countdown there read as an appeal window running down, and a perishable has **no appeal window** — that is the whole point of the nature.

**Top Management gets its own "Unsold Perishables" tab.** ⚠️ The two lists reach the DG by entirely different routes and must stay apart:
- a **normal** package arrives after the Valuation Tender + Tenders 1–3, a committee valuation, the ADG's submission and one more failed round — five chances over months;
- a **perishable** arrives after **ONE** failed Special Tender Sale, because goods that spoil cannot wait for that.

So `getUnsoldPerishables` deliberately tests **neither** `tenderCount` **nor** a committee. Everything downstream is identical — same table, same decision dialog, same place the decision appears — so a decision means the same thing whichever list it came from.

⚠️ **Filter state is keyed by list** (`StateProvider.family<_, bool>`): both tabs are built from one widget in the same `TabBarView`, so shared state would let a search typed on one filter the other.

⚠️ **`_kTabCount`, the `Tab` widgets and the `TabBarView` children must move together** — a short controller still *paints* every tab, but clicks resolve against the shorter one, so tapping does nothing while swiping still works. A test asserts all three agree.

Seeded: 14 unsold perishables — 6 awaiting a decision, 8 decided. Their outcomes are a **narrower** set than for normal goods (destroy / remove / convert): re-offering spoiling goods at auction is not a real option.

### The DG's decision reaches the Perishable page (2026-09-03)

⚠️ **`unsold_proposals` keys on `forfeited_package_id`, which the Perishable Goods page never loads** — it lists package ITEMS straight off the packages. `getUnsoldProposalsByItem` re-keys them by `package_item_id` (via `forfeited_packages!inner(item_id)`), so the yard and Central Disposal can show the same `UnsoldOutcomeChip` the Top Management portal shows.

⚠️ **A decided item STAYS on the page.** It has been sent, so `sentKeys` holds it — but dropping it would mean the two portals never see the ruling at all: the goods would simply vanish from the only page that lists them.

⚠️ **The outcomes are read with `.valueOrNull`, not awaited.** Awaiting inside `perishableRowsProvider` made the whole list wait on that query, so a slow one left the page **empty** rather than merely un-annotated — the goods matter more than the label. (It also opened a real DB socket under test until the harness overrode it.)

### 'perishable' is a real source now (2026-09-03)

⚠️ It used to be **synthetic** — `getRequestableExpiredPackages` built one on the fly for goods with no `forfeited_packages` row. But the column's CHECK constraint allowed only forfeit / abandoned / other / detain, so the moment a perishable **genuinely reached a sale** and needed a real row, it was filed under `'forfeit'` — and then sat in the appeal list wearing a **Forfeit badge, indistinguishable from goods that really do have 30 days to run**. A perishable has no appeal window at all.

`postgres/07_perishable_source.sql` widens the constraint and re-files the 31 mislabelled rows (self-verifying; ran green). The **item's nature** is the authority — it is what routes goods to a special sale in the first place.

### The perishable label goes in the HEADER (2026-09-03)

⚠️ **Perishables arrive together** — their own request, their own sale. They may only enter a Special Tender Sale, so they are never mixed with normal goods, and a header label therefore describes everything under it with nothing to contradict. Repeating it per row would say one thing many times.

Three places carry `PerishableTag`: the **Valuation** request card, Central Disposal's **Disposal Requests** card, and the **Tender Sale** header.

- Requests test `items.every((i) => i.forfeited?.source == 'perishable')` — ⚠️ **every, not any**: a mixed set must not wear it, or it tells the officer the normal goods beside it are on the perishable clock too.
- A sale needs no such test: the gate is **two-way** (a perishable may only enter a special sale, and a special sale carries only perishables), so `tenderType == 'special'` is proof by itself.

The seeder now batches **3 perishables per request** — one request per item would make the tag true but pointless.

> The user first asked for this page in the **Appeal** Directorate, then corrected it to **Valuation** ("that is where the value is given"). The Appeal portal was the wrong home anyway: a perishable has no appeal.

### Perishables never re-enter the tender pool (2026-09-03)

⚠️ **Goods that spoil get NO second round.** One failed Special Tender Sale and they go straight to Top Management. `getUnsoldTenderSales` now **excludes** them by default (`includePerishable: false`), so neither Unsold Tenders tab — Central Disposal's nor Valuation's, which share `unsoldTenderSalesProvider` — can offer them again. Offering them would be offering goods that will not last the wait, **and it would hide them from the DG**, the only one who can act. `getUnsoldPerishables` is the one caller that passes `includePerishable: true`, and keeps only them.

### The Valuation Directorate's perishable tab (2026-09-03)

A third tab, `_PendingValuationTab(perishableOnly: true)`. ⚠️ **Its own tab, not a filter on the first** — an officer could not otherwise tell them apart, and a perishable is on a completely different clock: no warehouse, no appeal window, one sale, then the DG. Valuing one as though it had months is the mistake this prevents.

⚠️ It **splits the same list** rather than fetching a different one, so the two tabs can never disagree: whatever the directorate holds appears on exactly one of them. A request counts as perishable when **every** item is.

### Central Disposal's tabs read in the yard rail's order (2026-09-03)

In hand (Disposal Requests → Tender Sales → Unsold Tenders → Committees → Perishable) → Disposed (Sold → Unsold → Destroyed) → Final Outcomes (Government Use → Remanded → Auction → Converted → Removed) → Reference (Taxes → Expenses → Reports). It has no register or storage stage of its own, so it starts at the work.

⚠️ **The real risk in reordering is a tab pointing at another tab's view.** The five outcome tabs share ONE widget and are told apart only by `proposalFilter`, so a shuffle there is silent. A test asserts the filters still line up with their labels, and that all 16 tabs and views stayed paired.

Seeded so each surface has something: **6 perishable requests awaiting Central Disposal** (a request drops off that tab the moment its goods are tendered, so tendering every one left it empty) and **1 special sale still to open** (every other sale is dated in the past so its items can be counted sold or unsold).

### The perishable chain, seeded at every stage (2026-09-03)

Each screen only shows goods at ITS stage, so a stage with nothing in it reads as a broken page. The seed now leaves some at each:

| Stage | Where | Seeded |
|---|---|---|
| Registered, not yet sent | Yard · Perishable Goods | 35 |
| Sent, **awaiting valuation** | Valuation · Perishable Goods | 5 (2 requests) |
| Valued & forwarded, not yet tendered | Central Disposal · Disposal Requests | 2 requests |
| In a sale still to open | Central Disposal · Tender Sales | 1 sale |
| Sold | Sold Goods | 12 |
| Failed its one sale | Top Management · Unsold Perishables | 7 |
| Ruled on | …and back on the yard's Perishable page | 5 |

⚠️ **A stage is emptied by the NEXT one.** Valuing and forwarding every perishable emptied the Valuation tab; tendering every forwarded one emptied Disposal Requests; dating every sale in the past emptied Tender Sales. Each fix is the same shape — hold a few back — and each has to be made deliberately, because the natural seeding order runs every item all the way to the end.

### One box for every status pill (2026-09-03)

⚠️ **A pill that sizes to its own text makes a column of them ragged.** "Convert" came out half the width of "Remove from the Premises", so the eye could not scan down the column — and the three tables that show these side by side did not line up with each other.

`statusPill()` in `destruction_status_pill.dart` is now the one builder for all three: **Destroyed**, **Delivered** and **Final Outcome**. `kStatusPillWidth` is the single width. ⚠️ A column holding one must be at least that wide, or the fixed pill clips and paints overflow stripes — a test asserts both.

### Stages that were full of finished work only (2026-09-03)

The same shape as before, three more times — a tab whose *purpose* is to act on something showed only rows already acted on:

- **Tender Committees**: every eligible package already had a committee, so there was nothing left to appoint one for. 4 are now waiting (5 appointed).
- **Tender Sales · progress**: every open sale was wholly unsold, so the header could only ever read `0 / n sold`. Bidding closes item by item, so a live sale normally has some of both — two sales now read `1 / 4` and `2 / 4`.
- **Tender Sales · re-tender badge**: every re-tendered round was dated in the past, so the badge existed only on closed sales and never appeared on the tab, which shows open ones. One open sale is now a genuine second round.

### Forgot password lives in the sign-in panel (2026-09-03)

⚠️ **Not a dialog.** Resetting a password is the same act as signing in — the officer is getting into their account — so it happens in the **same right-hand panel**, as the next page of one flow. A modal read as an interruption, dimmed the page behind it, and gave the three steps a different shape from the form the officer had just been using.

`ForgotPasswordPanel` (was `ForgotPasswordDialog`) takes an `onClose(bool changed)` callback and **never pops a route** — it is part of the page, and the login screen decides what to show next. Both yard portals swap it in with `_resetting`.

### The status pill was clipping (2026-09-03)

⚠️ Fixing the width at **132** made the column tidy but cut the labels: "Remove from the P…", "Awaiting Top Mana…". **A clipped label is worse than a ragged column** — the officer could not read what had been decided at all. Now **196** (column **214**), sized to the longest label these pills carry.

⚠️ The pending label itself was **"Awaiting Top Management Directorate"** — no width holds that, and the clipped part was the half that says *who* is being waited for. Shortened to "Awaiting Top Management"; the tooltip carries the rest.

⚠️ A column holding one must use `kDestructionStatusColumnWidth`, **not a number typed in beside it** — a hard-coded 190 silently became too narrow the moment the pill grew. A test asserts the constant is used.

### Central Disposal's Perishable page filters by yard (2026-09-03)

That page watches **every** yard there, so without a yard dropdown an officer cannot narrow to the one they are dealing with — the same reason every other cross-yard page has one. Only on the read-only copy: the yard's own page shows one yard and needs none. Matched on the **SR number's** yard segment, like the other pages.

### A tender that has already RUN (2026-09-03)

⚠️ **The valuation is SEALED until the sale's close time passes** — it is the reserve price, so it may only be shown after bidding closes. Every seeded open sale closed in the *future*, so the Latest Valuation column on Tender Sales read "Sealed" on every row and was never once populated. A sale dated **today whose close time has already gone** is the state that shows it: bidding finished, reserve out, still listed because items remain undecided.

### 'remand' is not an outcome this system has (2026-09-03)

⚠️ **Remand is a COURT's act, not a disposal.** No yard action stands behind it, no page carries it out, and nothing changes as a result of choosing it. Offering it made it a **dead end**: the goods left Unsold Goods, appeared on a page named Remanded, and stayed there for ever because nothing acts on them.

It was wired into six places — the decision dialog, a Central Disposal tab, a nav entry, a route, a report card, and the seeder. `postgres/08_drop_remand_outcome.sql` drops it from the CHECK constraint and re-files the one existing row as `remove_from_premises` (the nearest real outcome: the goods leave, and the record says so). Self-verifying; ran green.

The six that remain — destroy / government_use / auction / re_export / convert / remove_from_premises — each name something the department actually does.

⚠️ **The tab and its view had to be dropped together.** Removing one alone leaves the controller a length out of step: the bar still paints every tab, but clicks resolve against the shorter list, so tapping does nothing while swiping still works. 15 tabs remain, tabs and views paired.

### The ICT portal is an ERP console (2026-09-03)

⚠️ **ICT alone has a permanent left rail; every other portal keeps its top tab strip.** The others are single-purpose — an officer opens one to do one job. ICT is an **admin console**: four unrelated areas (accounts, the org chart, credentials, the audit trail) that a system admin moves between all day, so a rail keeps all four in view and named at once.

⚠️ **The rail is driven by the SAME `TabController` the body uses**, and rebuilds on `controller.animation`. A rail holding its own copy of the selection falls out of step the moment someone swipes the body — it would still point at the old page. Only the chrome moved; the four tab bodies are untouched.

⚠️ **The emblem appears once, on the rail.** The header names the current *section* instead (`_IctSideRail.itemAt`) — an ERP console names the section you are in at the top and the product once, on the rail. Repeating both wasted the width the header needs for its actions.

The login and signup screens needed no change — they are separate screens, not part of the console shell.

**The chrome lives in `lib/screens/ict/ict_ui.dart`, never in `AppTheme` (2026-09-04).** The theme is shared with every other portal, and those must not change — so ICT's look is carried by widgets:

- `IctSectionCard` — the card **names what it holds**: title, explanation, row count and the section's primary action all sit on the card's own header strip. That is the difference between a page with a table on it and an ERP module. It is also why the tabs no longer print their own page heading: the console header already names the section, and a screen that repeats its title twenty pixels below is the surest sign of a page designed on its own.
- `IctTableTheme` + `ictCol` — the console's table look, applied **locally**. ⚠️ A call site that passes `headingTextStyle` or `headingRowColor` **wins over the theme**, so ICT's tables deliberately pass neither; a test asserts that. `ictCol` uppercases in one place so no table can opt out.
- `ictRowColor` — zebra banding, **not a rule under every row**. At 50px rows a full-width rule turns a long table into a ladder.
- `IctStatusPill` — one width (`kIctPillWidth`) for **every** status box in the console, so a status column lines up. The account state's **decision** still lives in `accountStatusOf` in `widgets/account_cells.dart`, shared with the Admin Panel — only the chrome differs.
- `IctToolbar` / `IctSearchField` / `IctSelect` / `IctSegmented` — one strip, one height (`kIctControlHeight`). ⚠️ `IctSelect` puts a real caption **above** the field: a Material floating label sits on the border and shrinks once a value is chosen, so a row of filters showed four differently-sized half-labels.

⚠️ **`IctSectionCard` only flexes its body when given a `height` or `fill: true`.** The Yards & Directorates tab scrolls its whole page, and any flexed child in an unbounded-height column is a layout assertion, not a smaller card. `test/ict_yards_tab_layout_test.dart` renders that tab for exactly this reason.

⚠️ **Rail hover is ONE index on `_IctSideRailState`, not a bool per row.** With a bool per row, two rows could light at once — and did. The rail rebuilds as the tab controller animates, and a `MouseRegion` rebuilt while the pointer is already inside it never receives the exit that would have cleared the row the pointer left, so a quick pass down the rail left a trail of stuck highlights. A single index cannot represent two rows. The row's `InkWell` also sets `hoverColor: Colors.transparent` — its overlay fades on its own schedule and stayed lit under the painted one.

**What made the rail "lag" (2026-09-04).** Not the animation — a full rebuild of the page behind it, sixty times a second:

- ⚠️ **`TabController` is an `Animation<double>`, so `addListener` fires on every animation TICK, not on index changes.** ICT's controller carried `..addListener(() => setState(() {}))`, so changing tab rebuilt the whole console — metric tiles, staff table and all — every frame of the transition. **There is no listener now.** The rail and the header's section name each follow the controller through their own `AnimatedBuilder`, so only those few widgets rebuild.
- ⚠️ **The brand block, emblem included, was inside the rail's `AnimatedBuilder`** — so the SVG was re-rasterised every frame for a picture that never changes. Only the four rows are inside it now.
- The rows animate **nothing**. Two `AnimatedContainer`s per row meant eight implicit animations chasing a change that had already happened.

⚠️ **Rail hover is deliberately WEAKER than selected, not a different colour of the same strength.** Both used to be a filled box, and a filled box is what the eye reads as "the page you are on" — so pointing at one row while another was open read as *two* open rows. Hover is now a faint grey wash and brighter text; the accent fill and the edge bar belong to the open page alone.

**Rows are told apart by a light rule, not by banding.** ⚠️ `DataTable` takes its row divider from `ThemeData.dividerColor`, **not** from `DataTableThemeData` — there is no divider colour on the table theme at all, so `IctTableTheme` sets it on the ThemeData. The hand-built rows in Yards & Directorates draw the same rule themselves.

⚠️ **Status and Actions columns are FIXED width, never flex** (`kIctStatusColumnWidth`, `kIctActionsColumnWidth`). Given a flex share they end up the narrowest columns in a wide row — which is how the Yards table got a pill touching a button and a toggle 6px past the card's edge.

⚠️ **`StyledFormDialog`/`StyledFormSection`/`StyledDialogPrimaryButton` take an opt-in `erp` flag and an `accentColor`.** It must stay opt-in: that dialog is the form chrome for **every** portal, and only ICT was redesigned. A test asserts no other screen passes it. The flat header is not decoration — a gradient header reads as *an event*; an admin console's forms are opened dozens of times a day to do routine work, so they are drawn as a panel of the console.

⚠️ **Directorate Access does not show the username.** It is half a working credential for an account a whole office signs in with, and the page is read on an open monitor. The column carries the **password's 90-day rotation** instead — which is the actual reason someone is locked out and asking ICT for a reset.

**The audit trail is paged BY THE DATABASE (2026-09-04).** `getAllLogsAcrossOffices` used to return the whole table and let the screen filter and slice it — fine at a few hundred rows, hopeless at a few hundred thousand.

- ⚠️ **Every narrowing the screen offers is now a WHERE clause**: the date window, yard, role, entity type and the search box. It has to be — paging in SQL while filtering in Dart would page the *unfiltered* table and throw most of each page away, so pages would come back short and the count would disagree with the rows.
- `AuditLogPage.total` is a **second, count-only query over the same WHERE**, so "Showing 1–25 of N" counts what the filters matched.
- `IctLogQuery` (in providers) makes every filter part of the provider's identity, so a filter change is a new query, not a re-filter. `_pushQuery()` on the tab is the only path.
- The Activity filter reads `ictLogEntityTypesProvider` — its **own** query. A list built from the rows on screen would offer only what happened to be on that page. ⚠️ Widget tests must override it or the tab opens a real DB socket.
- `IctPager` replaces `TablePager` in ICT: numbered pages, first/last always reachable, gaps as an ellipsis, so the bar is the same width at 10 pages and at 3,000. `IctPager.windowFor` is pure and unit-tested.

**Why the rail "lagged", part two.** Beyond the TabController listener: the whole console could also be **dragged** sideways on a trackpad (`TabBarView` default physics), so a two-finger flick slid half of one module beside half of another. `physics: NeverScrollableScrollPhysics` — the rail's `animateTo` still animates, only the drag is gone. `_IctModule` fades and lifts the arriving page; ⚠️ it reads the **controller's animation**, not a one-shot in initState, because a module is built once and shown many times.

⚠️ **Rail hover is a tint of the ACCENT, not `surfaceDark`.** surfaceDark is the light theme's near-white, so hover read as a white gap punched in the panel rather than a row lighting up.

⚠️ **Material's 48px minimum tap target beats a SizedBox.** Every ICT button passes `minimumSize: Size.zero` + `tapTargetSize: shrinkWrap`, or it stands taller than the filters beside it — which is what `kIctControlHeight` exists to prevent. Also: `kIctTopBarHeight` pins the console header AND the rail's brand block, which are two widgets either side of the rail border with nothing else to make them agree.

**ENABLED / DISABLED for yards and directorates; ACTIVE for accounts.** A yard is a configuration row ICT switches on and off and the control beside it *is* a switch. An account is active/expired/deactivated as a fact of its own lifetime. One word for both would say these are the same kind of state.

⚠️ **The enable switch flips FIRST and asks the server after** (`_EnableSwitch`), and the yards page passes `skipLoadingOnReload: true`. Before: the write was awaited, then the providers were invalidated, so the tables were replaced by a spinner, the page collapsed to a fraction of its height and the scroll position went with it — flipping a switch halfway down the list threw you back to the top.

⚠️ **Status and Actions columns are FIXED width** (`kIctStatusColumnWidth`, `kIctActionsColumnWidth`) and `_MonoChip` is one fixed size. Given a flex share, Status/Actions become the narrowest columns in a wide row.

**The profile is a PAGE of the console, not a dialog.** `DisposalProfileDialog` gained an opt-in `embedded` flag: it drops the Dialog wrapper, the gradient header and the Close button, and the caller supplies the surface. ⚠️ Opt-in — every other portal still opens it as a dialog, and the **logic** (what a save writes, what a password change checks) stays one copy.

**"Too white" was white-on-white.** The scaffold takes `accent × 0.035`, `IctSectionCard` headers take a 0.07→0.02 accent gradient, and a metric tile is `Color.alphaBlend(color × 0.05, cardDark)` with the measure's colour on its label. `IctAccent` (an InheritedWidget) publishes the accent once instead of threading it through every constructor.

**The profile is a DIALOG, over a blurred console (2026-09-04).** It was briefly a page — reverted, and the reason is worth keeping: ⚠️ **the rail stayed visible and clickable while the page was showing, but its taps only moved a `TabController` that nothing was rendering.** Choosing another module did nothing and the single back button was the only way out. A dialog cannot reach that state: it owns the screen until dismissed, and dismissing it puts you back where you were. `showIctProfileDialog` uses `showGeneralDialog` + `BackdropFilter` — the blur is the point, not decoration: a flat scrim leaves sharp text and tables behind the dialog and the eye keeps reading past them. The blur ramps with the animation (a full-strength blur on frame one reads as the window glitching).

### Every popup blurs its backdrop — the helper promised it and never did

⚠️ **Reported with two screenshots side by side:** the one-tap calendar sat
over a softly blurred page; the SR Register Entry popup — and every other
popup in the app — sat over a **flat dim**.

[lib/widgets/app_dialog.dart](lib/widgets/app_dialog.dart) exists for exactly
this, and its doc comment has said *"the page behind is dimmed AND blurred"*
since the day it landed. **It only ever faded and scaled.** There was no
`BackdropFilter` in the `transitionBuilder`. The calendar looked different
only because it blurs inside its **own** `showGeneralDialog`
([lib/widgets/date_range_picker_dialog.dart](lib/widgets/date_range_picker_dialog.dart)).

⚠️ **A promise in a doc comment is not a backdrop.** This one went unnoticed
because the helper's name, signature and comment all described the intended
behaviour — nothing read the widget tree to check. The fix was three lines in
one place; finding it took two screenshots from the officer.

⚠️ **The blur belongs in the shared helper, not in a dialog widget.**
**134 call sites** go through `showAppDialog`, so blurring inside any single
popup fixes that one and leaves the rest — which is how the two screenshots
came to differ in the first place.

⚠️ **Ramp the sigma with the curve** (`2.5 * t`, matching the calendar). A
full-strength `BackdropFilter` on frame one snaps the page out of focus before
the popup is visible — the same note already recorded for the ICT profile
dialog above.

Guarded by
[test/every_popup_blurs_its_backdrop_test.dart](test/every_popup_blurs_its_backdrop_test.dart):
it pumps a real dialog and asserts a `BackdropFilter` is in the tree, that the
sigma **grows** across the transition rather than starting at full, and that
**no `lib/` file calls a raw `showDialog`** — a raw one has no
`transitionBuilder` hook, so it cannot blur and would silently be the odd
popup out again.

⚠️ **"The search box looks smaller than the dropdowns" was not a height bug.** All three toolbar controls measure `kIctControlHeight` exactly and share a baseline — `test/ict_control_heights_test.dart` pumps a real toolbar and measures the **InputDecorator** (the box a person sees), not the TextField (whatever box we wrapped it in). What differed was the CELL: the filters were a caption + a box, the search was a box alone. `IctFieldLabel` is now on every field. Same class of thing: Material's 48px minimum tap target beats a SizedBox, so ICT buttons pass `minimumSize: Size.zero` + `tapTargetSize: shrinkWrap`.

⚠️ **The header and the rail's brand block must be built the SAME WAY, not merely the same height.** The rail was a `SizedBox` followed by a `Divider` — a rule in the pixel *after* the box — while the header's `Container` border sits in the last pixel *of* it. Equal heights, rules one pixel apart, and that is the step you can see where they meet. Both are now a `Container(height: kIctTopBarHeight)` drawing its own bottom border.

`kIctToolbarMaxHeight` caps the filter strip and is asserted by measurement — it is the first thing to grow when a control starts setting its own height.

**The Activity Logs year picker reads the DATA (2026-09-04).** It offered a hard-coded "this year and the four before it" — on a system installed this year four of those five returned nothing, and on one running longer the sixth year back was missing from the very filter meant to find it.

- `postgres/09_audit_log_years.sql` adds `audit_log_years()`, a `setof int` of the distinct years in `audit_logs`. ⚠️ **A SQL function, not a query the screen builds**: the honest version of "which years have rows" is a DISTINCT over the whole table, and doing that in Dart means fetching every timestamp to throw all but a handful away — the same mistake the page itself was making before it was paged. Ran green: 2 years over 292 rows.
- `auditLogYears()` adds **the current year and the next** on top, exactly as `srYears` does for the yard's SR filter, and for the same reason: on 1 January nothing has been logged yet.
- ⚠️ **A month is picked in TWO steps — year, then month** (`_pickMonth` calls `_pickYear` first). One flat list of "September 2026, August 2026, …" only reaches as far back as someone decided to build it (it was twelve months), so the month before that was unreachable however much log there was. The month list is months alone (`MMMM`, not `MMMM yyyy`) since the year is already chosen, and in the current year it stops at this month — a window over a future month is empty by definition.
- `ictLogYearsProvider` is its own query for the same reason `ictLogEntityTypesProvider` is. ⚠️ Widget tests must override **both** or the tab opens real DB sockets.

Local psql lives at `C:\pgsql-extract\pgsqlin\psql.exe` (not under Program Files) — the service `postgresql-18` runs from `C:\pgsql-extract`.

⚠️ **The search box really WAS shorter than the filters, and every layout measurement said otherwise (2026-09-04).** Both sat in a `SizedBox(height: kIctControlHeight)`, so `getSize` on either returned 34 and three separate tests passed. What differed was the **intrinsic** height: a Material `prefixIcon` is a 48x48 tap target, so the dropdown's `InputDecorator` wanted **48** against the search field's **36** (which constrains its own prefix). Forced into 34, the search box fitted and the dropdown **painted its border outside the box**. Fix: `StyledDropdownFormField` gained an optional `prefixIconConstraints` (⚠️ null keeps Material's default — every other portal's dropdowns rely on it), and `IctSelect` passes the same constraints `IctSearchField` does.

**The lesson, kept:** measuring after a `SizedBox` has forced a height only proves the SizedBox works. `test/ict_control_heights_test.dart` now also renders both controls **unconstrained** and asserts they *want* the same height — that is the test that would have caught it.

⚠️ **`IctSectionCard` header actions use `Expanded`, never `Flexible` + `Spacer`.** Flexible takes only what it needs and the Spacer took the rest, so the Add button landed wherever the SUBTITLE stopped — two cards on one page with different-length subtitles put their buttons at two different x positions.

**`DisposalProfileDialog` has an opt-in `erp` flag** (the dead `embedded` flag from the reverted page is gone): flat header, 12px radius, 440px, the account name on **one line** (a directorate name is a job title and wrapped to two, pushing the close button onto its own row), and a 44px header photo — at 64 it took over a header with no gradient behind it. The profile's scrim is `black 0.45`: blur alone still reads as the console, slightly smudged.

**`_IctModule` lifts an arriving module by `0.05` with `easeOutCubic`** — the same `slideY(begin: 0.05)` a table card plays when its rows arrive. Choosing a module from the rail and turning a page are both "show me different rows"; they must not arrive differently.

⚠️ **`kIctControlHeight` is 42 — the height the FILTERS always looked, not the smaller one the search box happened to have (2026-09-04).** Equalising them at 34 first "fixed" the mismatch by shrinking the dropdowns to the wrong one of the two: a filter is a control you read a value out of, and 34 left its text tight against its own border. Measured on the real toolbar, both now paint the identical rect (`101→143`).

**All four ICT modules stage the same entrance**: measures/first card fade (300ms), toolbar fade (300ms, +120ms), table card `slideY(begin: 0.05, 400ms).fadeIn()`. Staff Accounts and Yards & Directorates had none of it, so switching to them from Activity Logs looked like the animation had **failed** rather than like a different page. ⚠️ Written on the SUBTREES, not on `_IctModule`: the stagger is the point, and one fade over the whole page puts the toolbar and the table on the same beat.

⚠️ **The Add button looking taller than the filters was OPTICAL, not geometric (2026-09-04).** Measured in a real toolbar, the search box, the filter and the button all came back at exactly the same height with the same top and bottom — and it still looked wrong, because **a solid filled block reads larger than an outlined box of the same size**: its whole area is ink, theirs is an edge. So `kIctPrimaryButtonHeight = kIctControlHeight - 2`, centred in the field's row. It is the one place in the console where two controls are deliberately different numbers, and the comment says why. **Geometry equal and appearance unequal is not "same size".**

The height itself took four tries: 34 (shrank the dropdowns to the smaller of the two — a filter's text sat tight against its border), 42 (took the larger, and the strip grew into a second header), 38 (right for the fields, button still looked taller), **40 fields / 38 button**. `kIctToolbarMaxHeight` is measured against `kIctControlHeight` so raising one without the other cannot quietly pass.

⚠️ **An `InputDecorator` does NOT stretch its border to the box you give it (2026-09-04).** With `isDense`, it sizes its own container to the content plus `contentPadding` and **centres that inside the box**. So a field in a `SizedBox(40)` with 8px padding **laid out at 40 and painted at 34**, while the button's fill ran the whole 40 — and `tester.getRect` reported 40 for both, because 40 is what the layout said. Four rounds of "but they measure the same" followed, against someone looking straight at the screen.

**`kIctFieldPadY = 11`** is what makes a field paint its full `kIctControlHeight`: content (~16) + 2×11 + the 1px stroke each side. Change a control height and re-derive it.

**The instrument:** `test/ict_toolbar_golden_test.dart` (⚠️ `skip: true` — google_fonts fetches over the network, so it always ends in an exception *after* writing the image) plus `tool/measure_toolbar.py`, which reads the PAINTED pixels:
```
flutter test test/ict_toolbar_golden_test.dart --update-goldens
python tool/measure_toolbar.py     # search/filter/button: top, bottom, height
```
**Lesson: when the screen and the layout tests disagree, the layout tests are measuring the wrong thing.** Go to the pixels.

⚠️ **`tool/agent_build.ps1` — build without closing the app the USER is running.** Both were building into `build\windows\...`; Windows locks a running exe, so every rebuild had to kill whoever held the lock, which was usually the user's window. This is `run_instance.ps1`'s private-`%APPDATA%` + `build-dir` trick applied to a build plus a detached launch. It stops **only** the exe under its own slot path, matched by `ExecutablePath` — never by process name.

⚠️ **A card header is not a toolbar, and its button must not be the tallest thing in it (2026-09-04).** In `IctToolbar` the primary button stands in a row of fields and matches them (`kIctPrimaryButtonHeight`). In an `IctSectionCard` header it stands beside a title and a subtitle — about 36pt of text — so at the field height it **decided how tall the header was** and pushed the rule under it down. `IctPrimaryButton(dense: true)` → `kIctHeaderButtonHeight = 32`, and the card is now the same height with or without the button. A test asserts that, and another asserts every `IctPrimaryButton` in a card header passes `dense: true`.

⚠️ **Isolating the assistant's build broke the feedback loop (2026-09-04).** `tool/agent_build.ps1` stopped the assistant's rebuilds from closing the user's app — and, as a direct consequence, its fixes stopped reaching `build\windows\...`, which is the exe the user actually launches. The user then reported the same bug three more times while looking at a binary that predated the fix by half an hour. **Check the exe's timestamp before believing a "nothing changed" report.** The script now builds the shared copy too, and when that exe is locked by a running app it says so loudly instead of silently skipping (it must never kill it — that is the whole point of the slot).

⚠️ **The auth back arrow is a page-corner control, not a heading ornament (2026-09-04).** Every login/signup/OTP screen used to put an `IconButton` inline, immediately left of its title — which pushed the heading off the panel's own margin and forced **every subtitle to carry a matching `EdgeInsets.only(left: 48)`** just to line up under it. It is now `AuthBackButton` (`lib/widgets/auth_back_button.dart`), dropped into the `Stack` each screen already keeps for its theme toggle and pinned `top: 24, left: 24`. Title and subtitle both start at the margin.

### A focused field was GOLD on every portal (2026-09-21)

⚠️ **The real "two colours" complaint.** I first read it as the fill vs
the page and changed `_fieldFillLight` (see below). Two screenshots of the
SAME box — resting and focused — showed the actual fault:
`inputDecorationTheme.focusedBorder` hardcoded **`primaryGold`**, so clicking
a field drew a **gold** ring on the purple Appeal form, the green Disposal
form, the teal Top Management form. The box was one colour until you touched
it and another after.

⚠️ **The accent is per-portal, so the fix has to be too.** A global theme
cannot know which portal is on screen. New
[lib/widgets/portal_field_theme.dart](lib/widgets/portal_field_theme.dart)
wraps a form and overrides the focus ring, the floating label,
`colorScheme.primary` and the caret/selection colours — **the ring alone is
not enough**, since the label rides the border and the caret and checkboxes
read from the scheme. All 15 auth screens already name their accent for
`BrandPanel`; each now passes the same value here, and a test asserts the two
**agree per file**.

⚠️ **Only the FOCUS state is per-portal.** Fill and resting border stay
shared, so every form looks identical until the officer interacts with it.

#### ...and `dart format lib/screens` cost an hour

⚠️ **Format the files you EDITED, never a directory.** `dart format
lib/screens` reflowed **52 files** when 15 were touched, and the suite went
**26 → 42 failures** — none of them about colour. The source-text tests that
match exact lines are the tripwire, and this is the same trap already
recorded under *dart format breaks source-text tests*.

Recovery: `git checkout` each file I had not meant to change. ⚠️ The two
large ones (`disposal_dashboard_screen`, `disposition_category_screen`)
**kept their real edits** anyway, because those were already committed — so
the checkout discarded only the reformat. Worth knowing before assuming a
revert loses work.

#### One command builds the whole database (2026-09-22)

```powershell
.\postgres\install_all.ps1 -Target supabase `
    -YardAppPassword '<app login>' -IctPassword '<first ICT account>'
```

⚠️ **Both passwords are needed or the build is incomplete**, and the
script says which. Two files carry their own placeholders and are
substituted into a temp copy (never the command line, never the history):
`66`/`91` create the `yard_app` login, and `68` creates the FIRST ICT
account. Without `-IctPassword` the schema is perfect and **nobody can sign
in** — `sr_auth.users` is empty.

⚠️ `68` refuses a password the APP would reject (12-24 chars, upper,
lower, digit, symbol). That is deliberate: an account whose holder cannot
re-enter their own password at the first rotation is worse than no account.

**Verified end to end on a clean database:** 104 clean / 12 data-only
verifies, 37 tables / 25 views / 160 policies, `yard_app` created
(`super=false bypassrls=false`), ICT account created, and sign-in works
(good password 1 row, bad password 0).

**On the live Supabase project**, after this ran:
```
PASS 1 (as yard_app)  yard_app is subject to RLS
PASS 2                uuid-ossp, pgcrypto, dblink
WARN 3                dblink cannot self-connect  <- expected there
PASS 3b               the 047 queue catches it, so refusals are not lost
INFO 4                37 tables, 160 policies, 65 SECURITY DEFINER
INFO 5                14 of 60 connections
```
⚠️ Check 1 FAILS when the readiness script is run **as `postgres`**, and
that is correct — that account does bypass RLS. Run it as `yard_app`, which
is what the app connects as.

#### The login role must be created MID-RUN (2026-09-22)

⚠️ **`role "yard_app" does not exist` was not cosmetic** — it was the whole
`36/24/156` vs `37/25/160` gap. Migration 037 has a bare
`grant ... to yard_app` partway through, so a missing role **aborts the file**
and takes its 1 table, 1 view and 4 policies with it. The counts were telling
the truth all along.

`install_all.ps1` now creates the role **between** the `postgres/` files and
the migrations (`-YardAppPassword <pw>`), because six files grant to it. Run
without the password it skips the step and says loudly what will be missing.

⚠️ **A placeholder that appears in its OWN guard gets substituted too.**
`postgres/66` and `/91` had

```
if coalesce(v_pw,'') in ('', 'CHANGE_ME_BEFORE_RUNNING')
```

so the script's blanket `.Replace()` rewrote the sentinel as well, the guard
became `in ('', '<the real password>')`, and the correct password was
**rejected**. The sentinel is now assembled (`'CHANGE_ME' || '_BEFORE_RUNNING'`)
so only the `set_config()` line is rewritten. Both paths tested: placeholder
left in place refuses, substituted accepts.

⚠️ Two more that cost a round trip each: `postgres/66` hardcoded
`database "Customs_SR_DB"` (fails on the backup copy — now
`current_database()`), and it used a bare `create role`, so it could not be
re-run. And `Set-Content -Encoding utf8` on PowerShell 5.1 writes a **BOM**
that psql reads as part of the first token — use
`[IO.File]::WriteAllText(..., UTF8Encoding($false))`.

**Verified end to end on a clean database:** 103 clean / 13 data-only
verifies, 37 tables / 25 views / 160 policies, `yard_app` created with
`super=false bypassrls=false`, logs in, and sign-in works (good password 1
row, bad password 0).

#### `sign_in` returned two different column names (2026-09-22)

⚠️ **`cannot change return type of existing function`** on a FRESH build,
in migrations 021, 032 and 047. Not caused by the rename — a long-standing
inconsistency that only a from-scratch build reveals, because on an existing
database the function is already there and `create or replace` never has to
change anything.

Three files define `sr_auth.sign_in`, and they disagreed:

```
postgres/04_auth.sql   meta                <- outlier
migrations/021         meta                <- outlier
migrations/032         raw_user_meta_data
migrations/047         raw_user_meta_data
```

PostgreSQL will not change a returned column's **NAME** with
`create or replace`, so whichever ran second failed.

⚠️ **The app decides which is right**: `pg_auth.dart` selects
`raw_user_meta_data as meta` from `sign_in`, so 032/047 were correct and
04/021 were wrong. Fixed both. `sign_up` legitimately uses `meta` (035 and
the app agree), so it was left alone — the two functions genuinely differ.

⚠️ **A fresh build is the only thing that finds this class of bug.**
The office and local databases have been carrying the mismatch for months
without symptoms.

#### pgcrypto lives in `extensions` on Supabase (2026-09-22)

⚠️ **`function gen_salt(unknown, integer) does not exist`** on Supabase,
in every password path (04_auth, 05_password_reset, 035, 036). Not a missing
extension — pgcrypto IS installed, just into the **`extensions`** schema
rather than `public`.

The session `search_path` there is `"$user", public, extensions`, so ad-hoc
SQL finds it. But our functions pin their own
`set search_path = sr_auth, public`, which excludes it — and a function's
own search_path wins.

Fixed by appending `, extensions` to the 19 search_path clauses in the files
that call pgcrypto. ⚠️ **Safe on every target**: a schema named in
search_path that does not exist is simply ignored (verified against the
local server, where pgcrypto is in `public`).

⚠️ `01_auth_and_session.sql` and `68_finish_server_setup.sql` call
pgcrypto at TOP LEVEL, not inside a function, so they use the session path
and needed no change — worth knowing before "fixing" them too.

### The `auth` schema became `sr_auth` (2026-09-22)

⚠️ **Supabase OWNS `auth`, and that is not negotiable.** Measured on the live
project: owner `supabase_admin`, `has_schema_privilege(CREATE)` = **false**.
14 of our SQL files died with *"permission denied for schema auth"*.

⚠️ **The subtler half is the real reason a rename was the only way out.**
Supabase already has an `auth.uid()` — and it reads a **JWT claim**
(`request.jwt.claim.sub`) while ours reads the session variable the desktop
app sets (`app.current_user_id`). Same name, different source. Had the
policies loaded there, all 189 would have called *theirs*, got NULL, and
**denied every row silently**.

**Scope:** 602 replacements across 53 source files, 50 more across 13 test
files. Done with a reviewable script, not by hand.

⚠️ **Three things that must NOT be renamed**, and the script proves each with
a case:
- audit `entity_type` values — `values (null, '...', 'auth', 'migration')` is
  **data**. Renaming it rewrites history.
- Dart's `auth.currentUser` / `auth.currentSession` — properties on a Dart
  object, not SQL.
- Supabase's own `auth.users`, now left strictly alone.

⚠️ **THE BUG THE RENAME INTRODUCED, caught only by rebuilding:** migration
012 hoists helpers by rewriting stored policy text with the regex
`(auth\.uid|auth\.role|...)`. That literal sits inside a string, so the
rename skipped it — and it then matched the `auth.uid()` **inside**
`sr_auth.uid()`, producing `sr_(select auth.uid())` and
`ERROR: syntax error at or near "select"`. Fixed in `postgres/02_schema.sql`
and `migrations/012` (8 lines, 2 files). **A rename that only touches
identifiers misses the regexes that match them.**

⚠️ **A SCHEMA RENAME DOES NOT REACH INSIDE FUNCTION BODIES.** After
`alter schema auth rename to sr_auth`, **48 function bodies** still said
`auth.…` — `sr_auth.sign_in` was still calling `auth.sign_in_before_flush`,
so the first login failed with *schema "auth" does not exist*. The
definitions must be re-applied from the renamed files afterwards.
[migrations/048](migrations/048_the_auth_schema_becomes_sr_auth.sql) now
**refuses to pass** while any body still names the old schema, so a
half-done migration cannot look finished.

⚠️ **The FRESH build is clean; an in-place migration is not.** Verified:
a fresh `install_all.ps1` gives 37 tables / 25 views / 160 policies with
**0 stale bodies and 0 stale policies**. Re-running it over a renamed
existing database still leaves ~18, because `02_schema.sql` aborts on
pre-existing constraints and never re-creates its functions. **For the
office/local databases, rebuild rather than migrate in place** — or expect
to chase the stragglers.

Auth proven working on `sr_auth`: correct password → 1 row, wrong password →
0 rows, `uid()` NULL when signed out (so policies deny, which is the safe
direction).

### Hosting: back to Supabase, on the free tier (2026-09-21)

Evaluated Namecheap shared hosting, a VPS and Supabase. **Namecheap shared
hosting was rejected outright**: no `CREATE ROLE`, no `CREATE EXTENSION`,
so `yard_app` cannot exist and the 155 RLS policies have no roles to bind
to. It also wanted the cPanel password in every officer's `.env` for an
SSH tunnel — that password controls the whole hosting account.

**Chosen: Supabase Free.** The schema was BORN on Supabase (migrated off
2026-08-30), so `anon` / `authenticated` / `service_role` and the policy
style are native there. Current scale is **3 yards + Head Office, ~9
officers**, so the free tier fits with room to spare.

Template: [installer/env-templates/supabase.env.txt](installer/env-templates/supabase.env.txt)

```
PG_HOST=aws-1-ap-southeast-2.pooler.supabase.com   # session pooler
PG_USER=postgres.<project-ref>                     # ref IS in the username
PG_SSL=true   PG_SSL_VERIFY=true
PG_POOL_SIZE=1                                     # 9 officers x 2 = 18/60
```

⚠️ **The session pooler, never `db.<ref>.supabase.co`.** The direct host is
**IPv6-only** and fails from an IPv4 network as *"Network is unreachable"*
— which reads like a wrong password or a dead server. Note **`aws-1`**,
not `aws-0`, and the **project ref inside the username**.

⚠️ **I HAD THIS BACKWARDS, and it is the most important correction in
this section.** I wrote that Supabase's `postgres` is `nobypassrls` so it
was safe to connect as. **It is not.** Measured on the live project:

```
postgres       super=false  bypassrls=TRUE     <- skips every policy
service_role   super=false  bypassrls=TRUE
authenticator  super=false  bypassrls=false    (but inherit=false)
authenticated  super=false  bypassrls=false
```

Connecting as `postgres` would have skipped all 155 per-yard policies.
`pg_connection.dart` already refuses a `rolsuper`/`rolbypassrls` connection,
so the app would not have started — the guard caught what I got wrong.

⚠️ **Supabase DOES allow a custom role**: its `postgres` has
`rolcreaterole`. So `yard_app` is created there too, by
[postgres/91_supabase_yard_app_role.sql](postgres/91_supabase_yard_app_role.sql),
and the rule is the same as the office server's — never connect as the
admin account.

⚠️ **NOT `authenticator`**, which looks like the obvious candidate: it is
granted `service_role` (BYPASSRLS) and is `inherit=false`, so its privileges
need a `SET ROLE` the app never issues.

⚠️ **The pooler wants the ref in the username even for a custom role** —
`yard_app.<ref>`. Measured with a throwaway role: a bare name is refused
with `FATAL (ENOIDENTIFIER) no tenant identifier provided`; with the suffix
it connects as the role itself, `rolbypassrls=false`.

⚠️ **The connection budget is arithmetic, not a feeling.**
`clients x (PG_POOL_SIZE + 1) <= limit`. At the office default of 3 only 15
users fit in the free tier's ~60. At 1 it is 18 for 9 officers. Raise it
**with the plan**, not because a dashboard feels slow — overrunning shows
as `53300: too many connections`, which looks like a server fault.

⚠️ **Supavisor TRANSACTION mode would break RLS.** The whole security
model rests on `set_config('app.yard', ..., false)` per SESSION; under
transaction pooling each query may land on a different connection and the
setting is gone. **Session mode only.**

#### Building the whole schema in one run: `install_all.ps1` (2026-09-21)

Loading ~90 files by hand in the right order is what kept failing, so
[postgres/install_all.ps1](postgres/install_all.ps1) does it:
the four core files, then every numbered `postgres/` file, then every
`migrations/` file, sorted by NUMBER (a string sort puts 10 before 2).

```
.\postgres\install_all.ps1 -Target supabase
.\postgres\install_all.ps1 -Target local -DryRun
```

⚠️ **13 files FAIL their verify on a fresh database, and that is correct.**
They assert against the office server's DATA — *"expected 228, got 11"*,
*"the page shows 369,383,700"*. Proven by rebuilding an empty database:
**101 clean, 13 verify failures, and the schema still comes out at 37
tables / 25 views / 160 policies**, matching the live database exactly. So
the script does not stop for them and prints the object counts as the real
result.

⚠️ **PowerShell 5.1 turns psql NOTICEs into terminating errors.** `2>&1 |`
wraps each stderr line in an ErrorRecord, so the run died at **1/114** on
*"extension already exists, skipping"*. Two fixes were needed: redirect
stderr to a FILE, **and** drop `$ErrorActionPreference` to `Continue`
around the call — the redirect alone was not enough.

⚠️ **Match `:\s*ERROR:`, not the word ERROR.** PowerShell's own wrapper
text contains `NativeCommandError`, so a bare `-match 'ERROR'` flagged
**93 of 114** files when only 13 had failed — burying the real ones.

⚠️ **Two files share the prefix `52_`** (`52_accrued_storage_view` and
`52_user_security_policies`), so the sort falls back to name for ties.

It deliberately does NOT create the login role: `postgres/91` (Supabase) or
`postgres/66` (office) run afterwards, so their `grant on ALL tables`
covers tables that exist by then.

#### One `.env`, several servers: `PG_PROFILE` (2026-09-21)

The file used to hold a block per server with all but one commented out.
Switching meant editing every line of two blocks, and ⚠️ **a half-finished
edit produced a MIXED configuration** — a cloud host with a local password
— which fails as an authentication error and reads like a wrong password
rather than a half-applied change.

Now every server keeps `KEY__<profile>` keys and **one line** switches:

```
PG_PROFILE=supabase        # supabase | local | backup | office
PG_HOST__supabase=aws-0-ap-south-1.pooler.supabase.com
PG_HOST__local=localhost
```

⚠️ **A DOUBLE underscore.** `PG_SSL_VERIFY` already contains underscores,
so `PG_SSL_VERIFY_local` could not be told from a key of that name.

⚠️ **Unsuffixed keys still work**, which is what makes it safe to adopt
gradually: a `.env` with no profiles behaves exactly as before, and a
profile that names only what differs inherits the rest.

⚠️ **`describe()` now appends `[profile]`**, so the "Cannot reach the
database" screen says which server is in force — switching is one line, so
a stale `PG_PROFILE` must not look like a broken network.

Resolution lives in `AppEnv._lookup`, so `read`/`readInt`/`readBool` all
honour it. Profiles: **supabase** (cloud), **local** (`Customs_SR_DB`),
**backup** (`..._backup_20260914_1543`, the one with real data), **office**
(10.10.71.15). Verified by switching all four and checking `describe()`.

⚠️ **Two tests read the live `.env` and broke on it** — `app_env_test`
looked for a bare `PG_DATABASE=` and died on a null check. It is now
profile-aware and `fail()`s with a message naming the missing key.

#### `Pool` ignored securityContext — a package bug (2026-09-22)

⚠️ **The same "Bad server certificate" had a THIRD cause, and it was not
in our code.** With the CA resolving correctly and the context built, the app
still failed — while a standalone Dart client connected with the identical
path and settings. Side by side, same inputs:

```
POOL     FAIL        <- ignores securityContext
DIRECT   CONNECTED   <- honours it
```

In `postgres 3.5.12`, `ResolvedConnectionSettings` falls back for every
field except one:

```dart
securityContext = settings?.securityContext,   // no ?? fallback
```

`pool_impl.dart` passes the per-call settings as `settings` and the POOL's
settings as `fallback`, so the pool's context was dropped. **Fixed upstream
in 3.5.16** (`?? fallback?.securityContext`); we now require `^3.5.15`.

⚠️ **The app uses a Pool, every probe I wrote used a direct Connection.**
That is why psql and three Dart scripts all connected while the app did not
— reproduce with the SAME construct the app uses, or the test proves
nothing.

#### A `#` in a .env value makes the key VANISH (2026-09-22)

⚠️ **`28P01: password authentication failed` while psql connects with the
same string.** `dotenv` treats `#` as the start of a comment, so

```
PG_PASSWORD__supabase=SrYard#2026Customs     <- key DISAPPEARS
PG_PASSWORD__supabase="SrYard#2026Customs"   <- correct
```

It does not truncate — the key is simply absent, the app sends no password,
and the server's answer reads like a wrong one. Proven with a three-line
probe: bare `A` came back missing, quoted `B` came back intact.

`AppEnv.load()` now warns when a `PG_PASSWORD*` or `GMAIL_APP_PASSWORD*` key
parses EMPTY, naming the quoting rule. ⚠️ It warns rather than auto-quotes:
silently rewriting somebody's `.env` is worse than telling them which line
is wrong.

#### The diagnostic that ended the guessing

Start-up failure now prints the profile, **which .env was loaded**, the
target, the resolved CA path and whether the trust anchor is the CA file or
the OS store. The first run of it showed `profile: <empty>` and
`target: localhost` — instantly revealing that the `.env` had not been found
at all, which no amount of reasoning about TLS would have surfaced.

#### ...and the CA file must be found however you LAUNCH (2026-09-22)

⚠️ **Same "Bad server certificate", different cause.** The cert was in
place, the `.env` was right, and `psql` and a standalone Dart client both
connected — but `flutter run` still failed.

`PG_SSL_ROOT_CERT` is a relative name and the resolver looked **only beside
the .exe**. That is right for an INSTALLED copy, and wrong for the two other
shapes:

```
installed     .exe and .crt together in Program Files        <- worked
flutter run   .exe in build\windows\...\Debug, cwd = project root
flutter test  no app .exe at all; resolvedExecutable is the Dart VM
```

The fallback was the bare relative path, so whether TLS worked came down to
the **working directory** — the same build connected from one launcher and
failed from another, reporting only a TLS error that names no file.

Now it tries every plausible location and takes the first that EXISTS: beside
the .exe, the raw path, `Directory.current`, and the Debug/Release build
output. ⚠️ If none exist it returns the path as given so
`sslRootCertProblem` can name it — the dangerous outcome is a silent
fallback to the OS trust store, which then fails against a private CA.

Guarded by `test/the_ca_file_is_found_however_you_launch_test.dart`.

#### Supabase uses its OWN private CA (2026-09-21)

⚠️ **`Bad server certificate` on first connect, and it is NOT a bug in
the app.** The pooler presents `CN=*.pooler.supabase.com` issued by
**"Supabase Intermediate 2021 CA"** under **"Supabase Root 2021 CA"** — a
private root that is **not in the Windows trust store**. So `PG_SSL_VERIFY=true`
fails on a link that is otherwise perfectly healthy.

Measured with openssl, not guessed:

```
without the CA:  Verify return code: 19 (self-signed certificate in chain)
with the CA:     Verify return code: 0  (ok)
```

⚠️ **I had this WRONG in the first template**, which claimed Supabase
"presents a proper CA-signed certificate, so this works as-is". It does not.

The root is extracted from the live chain (`openssl s_client -showcerts`,
third cert) and shipped as
[installer/certs/supabase-root-2021.crt](installer/certs/supabase-root-2021.crt);
`PG_SSL_ROOT_CERT=supabase-root-2021.crt` resolves relative to the
executable's folder. Valid to **2031-04-26**. A public certificate, so it is
committed — there is no secret in it.

⚠️ **The answer is NOT `PG_SSL_VERIFY=false`.** That silences the error
and keeps the traffic encrypted **to whoever answered** — worse than not
connecting. `main.dart`'s `_hint` now names the private-CA cause and says so
explicitly, because "Bad server certificate" names TLS and nothing else.

⚠️ **The pooler host carries the REGION and the prefix varies**:
`aws-0-ap-south-1` (Mumbai) vs `aws-1-ap-southeast-2` (Sydney). The template
now says copy it from the dashboard rather than shipping a guess.

⚠️ **Two tests were reading the developer's live `.env`** and so failed
the moment it held a real deployment: one asserted `sslRootCertPath` was
EMPTY, the other `poolSizeSetting == 3`. Both now test the invariant — a
configured CA must RESOLVE AND LOAD, and the pool must be 1..4 — instead of
one machine's configuration.

#### The check that actually matters: `dblink`

[postgres/90_supabase_readiness_check.sql](postgres/90_supabase_readiness_check.sql)
verifies the role, the three extensions (`uuid-ossp`, `pgcrypto`,
**`dblink`**), an autonomous write, the schema and the connection count.

⚠️ **`dblink` is the one likely to fail, and it fails SILENTLY.**
Migration 032 logs a refused sign-in through `dblink` because the refusal
rolls its own transaction back — an ordinary insert disappears with it. It
connects with `dbname=<db> user=<user>` and **no password**, which works on
the office server over a trusted local socket. Supabase reaches itself over
TCP, where a password is required. And 032's handler is
`exception when others then null`, so a broken `dblink` looks *exactly*
like a working one: sign-ins are still refused, the audit log just stays
empty. Nobody notices until it is needed as evidence.

⚠️ **The probe row cannot be cleaned up.** `audit_logs` is append-only by
trigger (postgres/53), so the script's `delete` raised and aborted the
block on its first run. That rule is correct — the script now leaves its
row and says so.

⚠️ **Free tier pauses after 7 days idle.** The first officer in on a
Monday would meet a connection error rather than a login screen. Keep it
warm, or move to Pro before the yards depend on it.


#### 047 · a refused sign-in is recorded even without dblink

⚠️ **Three routes, first one that works wins.** `log_refused_device` now
tries dblink-with-password (`app.selflink_conninfo`), then dblink over a
trusted local socket (the office server, unchanged), then a **queue table**
that needs no extension. Whichever runs stamps `logged_via` into the audit
row, so "is logging working on this host" is answerable **from the data**
rather than by reasoning about `pg_hba`.

⚠️ **The raise could NOT be removed**, which was the obvious-looking fix.
`auth.sign_in` raises to refuse a machine, and that rollback is what eats
the audit row. But returning no rows instead makes `pg_auth.dart` report
**"Invalid login credentials"** — telling the officer their *password* was
wrong when the *machine* was refused — and three login screens match on the
`42501` text to show the real message. So the autonomous-write problem had
to be solved, not side-stepped.

⚠️ **The queue is honest about what it does not do.** Its insert rolls
back with the refusal, exactly like 032's did. What it guarantees is that
the refusal is never *silently dropped*: the row is re-created on the next
attempt and drained by `flush_refused_sign_ins()`, which the new
`auth.sign_in` wrapper calls **before** the inner call (after it would
never run on the refusal path). So a refusal lands seconds late, and for
the case the register exists for — somebody retrying an unapproved machine
— the second attempt flushes the first.

Chain is now `sign_in` (flush) → `sign_in_before_flush` (device check +
raise) → `sign_in_any_device` (password). Wrapped, not rewritten, because
postgres/04 and 032 both re-create the inner ones.

⚠️ **`app.selflink_conninfo` is left UNSET on purpose.** Setting it gets
immediate logging but stores a password readable by anything that can run
SQL as that role — on Supabase, the same account the app uses. The queue
costs a few seconds and stores nothing.

**Verified against the real data**, not just applied: route 2 passes
normally; renaming `dblink_exec` out of reach proved route 3 queues
instead of losing the row; and a drain test proved the round trip
(queued → flushed → audit row tagged `pending_queue`). Re-running the
migration left the chain at 3 functions, not 4.

`postgres/90` now has a **check 3b** for the queue table, and check 3 was
downgraded FAIL → WARN with a pointer to 047 — on Supabase a dblink
failure is expected, and only *unpatched* is a problem.

### A field is ONE flat colour: the hover blend and the tint (2026-09-21)

⚠️ **The "white and grey mixed / shaded" complaint had TWO causes, and
fixing either alone left it standing.** I changed the fill colour twice
before finding the second one.

**1. The hover blend.** A `filled: true` input blends `ThemeData.hoverColor`
over its fill whenever the pointer is near — Flutter computes
`alphaBlend(hoverColor, fillColor)` in `input_decorator.dart`. So a field was
one grey at rest and a **darker grey under the cursor**, and in a screenshot
the hovered field and its neighbour read as two different colours. Reported
exactly: *"කර්සර් එක ලගට ගෙනිච්චත් එහෙමයි, නිකනුත් එහෙමයි."*
Fixed with `hoverColor: Colors.transparent` on the **input** theme (not
`ThemeData.hoverColor`, which would also change buttons and list tiles).

**2. The tint.** Every value I tried was a blue-leaning off-white on a page
that leans blue harder, so the two shaded into each other:

```
#EDF1F7  darker than the page   -> every box a grey slab
#FBFCFE  11 steps lighter       -> reads as RAISED, a 3D chip
#F4F7FC  blue tint (R-B = -8)   -> still "white and grey mixed"
#F5F5F7  R-B = -2, flat         -> a grey, and only a grey
```

⚠️ **Near-neutral is the property, not any hex.** A fill leaning the same
way as the background shades into it however light or dark it is. It must
still differ from `_cardLight` by enough to see — that is the bug the
separate `fieldFill` token exists for.

Guarded by `test/a_field_is_one_flat_colour_test.dart`, verified by breaking
both halves separately. ⚠️ It reads the constants **out of the source**:
building `AppTheme.lightTheme` in a test pulls in Google Fonts, which either
fetches over the network or throws for a missing asset — neither has
anything to do with colour. And its regex allows a **line break**, because
`dart format` wraps `static const Color _x =` onto the next line.

### The field fill has now been wrong in BOTH directions (2026-09-21)

⚠️ **A bordered box looks 3D when its fill contrasts with the page.** The
eye reads the lighter panel plus the darker outline as a lit edge. Reported
directly: *"3d විදිහට පෙන්වන කලර්ස් අයින් කරන්න, කලින් තිබ්බ 2d එක
හොදයි තනි පාට එක්ක."*

`_fieldFillLight`, against a `#F0F4FA` page:

```
#EDF1F7   DARKER than the page   -> every box a grey slab
#FBFCFE   11 steps lighter       -> box reads as RAISED, a 3D chip
#F4F7FC    4 steps lighter       -> flat; the BORDER draws the field
```

Both wrong values were mine, three days apart, and each was a fix for the
other's symptom. The pre-Sep-15 look people liked used `cardDark` (#F7F9FC),
only 7 steps off the page — so **the border alone drew the field**. That is
the property to preserve, not any particular hex.

⚠️ **It still must not equal `_cardLight`.** A field inside a card has to
stay visible — that is the bug the separate `fieldFill` token was created
for, and `one_field_height_test` enforces the separation. Four steps is
enough to see on a card and too little to lift off the page.

All 15 sign-in/sign-up screens inherit this from `inputDecorationTheme` with
no local `fillColor`, so one value covers every portal. The dashboard
search/filter boxes set their own accent-tinted fills and are unaffected.

### Destruction is a two-party job with an ORDER (2026-09-21)

Four rules, given together, that turn out to be one workflow:

```
1. Central Disposal records what the destruction costs
2. only THEN may the YARD confirm the goods were destroyed
3. once destroyed, the costs are CLOSED -- the form opens read-only
4. Central Disposal never confirms a destruction; it only reads
```

⚠️ **Rules 1 and 3 lock against each other, which is why 2 is a hard
gate and not a warning.** The cost form closes the moment a row is
destroyed, so if the yard could mark first the figure could never be
entered at all — the record would be permanently incomplete.

**The gate** lives in `DestructionStatusPill`
([lib/widgets/destruction_status_pill.dart](lib/widgets/destruction_status_pill.dart)),
which became a `ConsumerWidget` and takes `srNumber`. Uncosted rows show a
muted, inert **"Awaiting Costs"** pill with a tooltip naming what is being
waited for — a disabled control with no explanation is the thing to avoid.

⚠️ **It reuses the PAGE-scoped spend query** (`destructionSpendProvider`
via `DestructionExpenseScope`), the one the expense column already runs.
Asking per row would have put a second round trip behind every pill — the
same mistake this tab was fixed for once before.

**The lock** is a `locked` flag on `RecordExpenseDialog`. The dialog still
**opens** — hiding the button would leave no way to see what was charged.
There is no greyed Save, just **Close**; and `_save()` returns early on
`locked` so a future shortcut or autosave cannot slip past the UI.

⚠️ **`readOnly` was NOT enough, and this is the lesson.** The first
version kept the `TextField`s and set `readOnly: true`. That governs
**writes**; it does nothing about **affordance**. The field still took focus,
drew the accent focus ring, showed a caret and let its text be selected — so
a closed record looked editable and refused only after the officer tried it.
Caught from a screenshot with the Advertising field lit up, and asked for
plainly: *"විවි එකේදී ෆුල් විව් පොපප් එකක් දෙන්න, ලාවටවත් කොහේවත් නිකමටවත්
ක්ලික් කරන්න දෙන්න එපා."*

A locked form now renders **no input at all** — `_ReadOnlyCost`, a label and
a figure. **The only way to have no affordance is to have no control.** A
real zero is shown rather than a blank: on a closed record "nothing was
charged" is a finding, not a gap.

⚠️ **A widget test failed for the RIGHT reason and had to be taught the
rule.** `destroyed_goods_workflow_test` stubbed the page but not the spend,
so the pill correctly rendered "Awaiting Costs" and the test looking for
"Mark Destroyed" failed. Stubbing `destructionSpendProvider` with a costed
SR fixed it — and that test now proves the gate end to end.

Guarded by `test/destruction_order_of_work_test.dart` (14 source tests) and
`test/closed_costs_popup_is_not_clickable_test.dart`, which **pumps the real
dialog** and asserts no `EditableText` exists — source matching cannot answer
"what can the officer click".

⚠️ **Scope a "nothing is clickable" assertion to the CONTENT.** Counting
every `InkWell` fails on the header X and the Close action, which must stay
or the popup cannot be dismissed; `GestureDetector` is worse, since the
scroll views install two of their own. The test walks each named cost row
instead. All of it verified by **breaking it back** to a `readOnly` field.

### A destruction IS advertised (2026-09-21)

⚠️ **A comment asserting a business rule is not evidence for it.** The
destruction cost form excluded Advertising Expenses, with this reasoning
written into the code and mirrored in a test:

> *the goods are handed straight to the destroying contractor, so nothing
> is advertised and nothing is auctioned*

The officer corrected it: **a destruction is advertised**, and the cost
comes out of the same destroying deposit as the rest. The rule had been
inferred, not given — and then locked in by a test that quoted the literal
`_notForDestruction` set, so it looked verified.

Three places carried the same wrong premise:

1. **The entry form** (`expenses_tab.dart`) — `_notForDestruction` is now
   `{'auction_expense'}` alone. Auction stays out for a reason that does
   hold: a destroyed item is never sold.
2. **The notice copy** — the destruction branch said only "Costs entered
   here"; it now names destruction and advertising, like the disposal one.
3. **The details popup** (`package_details_dialog.dart`) — Advertising was
   wrapped in `if (advertisingExpense > 0)`, so it vanished when nothing
   was spent. Now shown always, like Destruction / Labour / Transport. A
   blank box means "nothing spent yet", which is information.

⚠️ **Nothing downstream needed touching, and that is worth knowing.**
`advertising_expense` was already in `kRecordableExpenseKinds`, and
`SrFinancials.depositSpent` already summed it — so the save loop, the
refund/shortfall arithmetic, `_hiddenSpend` and the totals strip were all
correct the whole time. **Only the form was hiding the field.** Any cost
kind added to that map is picked up everywhere by construction.

`test/destruction_status_pill_test.dart` now asserts the corrected rule,
plus the notice copy and the popup's unconditional box. ⚠️ Its old
assertion is a reminder that a source-text test proves only *"the code
still says what it said"* — never that what it says is right.

### The home page was cutting off its own card text (2026-09-21)

Asked whether the seal could be bigger, and for any other home-page tidying
— with two screenshots, a laptop and a desktop monitor. The laptop looked
cramped. **Measuring it found a real defect the screenshots did not show.**

⚠️ **Every card subtitle was being ellipsised, on every screen.** The box
was `height: 58` with `maxLines: 3`; a `TextPainter` at the real card widths
put each subtitle at **60–100px**. So the text overflowed the box by 2px
*and* lost its last words — on the 1920 monitor too. Nobody had noticed
because the words that go missing are at the end of a second line that
already reads as a complete phrase.

The real card width is the thing to compute, not guess:

```
window 1920 -> card 299px (capped 300) -> text 251px
window 1536 -> card 235px             -> text 187px
window 1366 -> card 206px             -> text 158px
```

Fixes: box `58 -> 80` and `maxLines 3 -> 4`, plus shorter copy on the four
longest subtitles. At 1920 and 1536 nothing truncates now.

⚠️ **The `\n` in a subtitle is a HINT, not a guarantee.** At 158px even a
single clause wraps, so the rendered line count cannot be read off the
literal. Any test here has to ask the text engine.

⚠️ **The header now scales with the viewport.** A 132px seal, a 32pt title
and 28px gaps were identical on a 768px laptop and a 1080p monitor, so the
header took the same room on a short screen and the cards got the remainder.
A `LayoutBuilder` interpolates on `((height - 720) / 320).clamp(0, 1)`: seal
**148–174** (larger than the old 132 on *both*), title 34–38, gaps 14–20 and
20–30.

⚠️ **STILL BROKEN AT 1366px** and deliberately left: four subtitles clip
there, because six 300px cards genuinely do not fit that width. The fix is a
wrapping layout (two rows of three), which is a bigger change than was
asked for — flagged to the user rather than done silently.

Guarded by `test/home_page_fits_its_screen_test.dart`: it parses the box
height, `maxLines` and all six subtitles out of the source, lays each one
out with a `TextPainter` at the computed 1920 and 1536 card widths, and
fails if any is truncated or overflows. ⚠️ Verified by **restoring one long
subtitle** — the test fails, naming the card.

#### ...and then it scrolled, because scaling only went one way

⚠️ **A `LayoutBuilder` that only grows is half a fix.** The header scaled
UP when there was room to spare but had no way to give ground when there
was not, so every window below the floor got the same minimum header — and
the page ran past the bottom. Reported with a screenshot: the seal clipped
at the top, the footer clipped at the bottom.

Measured with a real pump (`maxScrollExtent`), not estimated — my own
arithmetic said it fitted:

```
1366x768 -> over by  1px
1024x768 -> over by 16px
1280x720 -> over by 41px   <- the size the app OPENS at
```

So the shipped default window was one of the broken ones.

Two factors now, not one: `tall` grows the header, **`tight` shrinks it**
(`(1 - (h - 640) / 160).clamp(0, 1)`). The header gives ground first — it is
decoration and the cards are the point — and the card's fixed boxes shrink
with it via a `tight` parameter, because the header alone cannot recover
enough room. No scroll now from 1920x1080 down to 1024x640.

⚠️ **The chooser is a doorway.** Scrolling to reach one of six Sign In
buttons is wrong at any size; that is why this is a hard invariant with a
test per window shape rather than a judgement call.

⚠️ **A source-text test broke on its own subject.** The subtitle-height
test from the previous fix parsed `height: ([0-9.]+),` out of the widget.
Making the box an expression (`80 - 4 * widget.tight`) stopped the match,
and it died on a null check — an error naming nothing. Regexes over source
have to allow for the value becoming computed later. Both home-page tests
were verified by **breaking the code** (pinning `tight = 0.0`, restoring a
long subtitle) and watching them fail with the right message.

### The left panel's animation is a CONSTELLATION (2026-09-21)

⚠️ **Asked for a different design**, on the left panel of every login/signup
page: black plus the team colour, with an animation that has some shape to
it. The three drifting orbs were a soft wash with nothing to look at. Chosen
from four options (aurora ribbons, constellation, contour lines, sweeping
beam) — **constellation/network**, because consignments moving between
points is what this system is a record of.

Nodes drift on closed loops; a link is drawn only between pairs closer than
`shortest * 0.30`, and its alpha falls with `closeness^2` so links fade in
and out rather than snapping on at a threshold. Each node is a small bright
core inside a soft halo, breathing on its own clock so they never brighten
together. The orbs stay underneath as a dim ground — the constellation is
the shape, the orbs are the light it sits in.

⚠️ **The centre is protected TWICE, and the second one is the real guard.**
The node table keeps clear of the middle by hand, but the nodes *drift* and
the links *span between them* — so a link can run straight across the crest
while both its ends stay well outside it. `_centreFade` is applied per node
**and to each link's midpoint**. Positions alone promise nothing here.

⚠️ **Paint order is load-bearing:** orbs → constellation → black pool. The
pool must stay last, because it is what guarantees black behind the crest;
a node drawn after it would put the accent straight back where the ship and
the plane have to read as holes. A test asserts the ordering by source index.

⚠️ **It takes the same `trim` as the orbs.** Gold is ~2.4x the next
brightest accent, so without it gold's nodes read as lamps while purple's
read as a tint — the exact complaint the orbs were trimmed for. The
constellation is painted in `accent`, never a literal colour, so all six
portals differ by team colour alone.

Guarded in `test/brand_panel_test.dart` (`_theConstellation`): paint order,
no node within 0.25 of the crest, `_centreFade` applied to link midpoints,
near-neighbour linking, accent-only painting, trim applied, and the panel
still animating. ⚠️ The node-position test was **verified by breaking it**
— moving one node to (0.50, 0.42) fails it — because a regex that matches
nothing passes silently.

### Black spreads from the logo; the colour lives outside it

⚠️ **The reason is the crest itself, not taste.** *"ලෝගෝ එක වටෙන් කහ නෙවෙයි කලු
විහිදෙන්න ඕන — මොකද ලෝගෝ එකේ නැවයි ප්ලේන් එකයි කලුනේ."* The ship and the
plane are **not transparent**; they are filled with the colour expected behind
them (see [crestWithKnockout]), so they read as holes **only while that colour
is really there**. Any accent reaching the middle turns them into gold
stickers on a gold disc. So the area around the mark must be genuinely black,
and the colour has to live further out.

Three coordinated changes in
[lib/widgets/brand_panel.dart](lib/widgets/brand_panel.dart):

1. **The crest pool is now opaque and much wider** — `0.82 → 1.0`, radius
   `0.72 → 0.95` of the shorter side, falloff `1.6 → 1.35`, and `7 → 11`
   stops (a deeper, wider ramp banded at 7). Around the crest the black goes
   from 0.49–0.82 to **0.73–1.00**.
2. **`_behindCrest`'s accent lean cut `0.16 → 0.04`** — it was describing a
   colour that is no longer there.
3. **New `_knockoutColor`**, constant, built from `deepColor` + a neutral
   white lift, and that — not `behind` — is what the crest is painted with.

⚠️ **Do NOT freeze `_behindCrest` to fix the knockout.** My first attempt made
it constant, which is correct for the crest and **wrong for the panel**: it is
*also the gradient's middle stop*, so the whole animation stopped dead. Two
existing tests caught it ("the panel feeds it the colour behind the crest",
"one full cycle takes several seconds"). The value still travels; only the
colour the **crest is painted with** is pinned, which is why they are now two
separate members.

⚠️ **A deeper pool means the orbs can have their light BACK.** `_brightnessTrim`
had been steepened to `2.05` to keep gold out of the middle; the pool now does
that at the centre, so holding the orbs down as well left the corners flat and
took the movement with them. Eased to **1.70** — the brief asks for black
around the mark *and* soft moving colour around that, and those pull against
each other.

⚠️ **One widget, every portal.** All 15 sign-in/sign-up screens mount
`BrandPanel`, and both the pool (`deep`) and the knockout (`widget.deepColor`)
come from `kBrandPanelBlack`, never per-portal — so no screen can drift.
A test asserts the call-site count stays above 10.

⚠️ **Two more tests had pinned the old constants** (`deep.withOpacity(0.82`,
`orbTrim(gold) < 0.45`) and failed on contact. Both now parse the values out
of the source and assert the *property* — opaque at the centre, radius ≥ 0.9
— rather than the literal, the same fix the gold retune above needed.

### Darkening gold a third time — move the luminance term, not the base

⚠️ **"කහ වැඩියි, බ්ලැක් වැඩි වෙන්න ඕන"** on the gold sign-in panels
(Valuation, DC/SDDC). Two knobs in
[lib/widgets/brand_panel.dart](lib/widgets/brand_panel.dart) feed gold onto
the panel and **both had to move** — `_accentFloor` (the gradient corner) and
`_brightnessTrim` (the orbs). Darkening only the corner leaves the orbs the
brightest thing on the panel and merely **moves** the yellow.

⚠️ **Raise the LUMINANCE-SCALED term, never the base.** My first attempt
raised `_accentFloor`'s base 0.34 → 0.46, which moves **every** portal: navy's
corner went 0.0148 → 0.0110, pushing a panel nobody complained about towards
flat black. Only the second term scales with the accent, so widening **that**
(`* 1.1` cap `0.34` → `* 2.0` cap `0.52`) leaves the five dim accents
**bit-identical** and moves gold alone.

⚠️ **Check which clamp is actually binding before tuning a slope.** Gold
computes to ~0.548 in `_brightnessTrim`, a hair *under* the old `.clamp(0.55,
…)` floor — so it was never pinned by it and dropping that floor changed gold
by **0.002**. The **slope** was the live knob (1.45 → 2.05). Same trap on
`_accentFloor`: its trailing `.clamp(0.0, 0.70)` and `_corner`'s
`.clamp(0.0, 0.75)` both sat below where the formula now wants to go, so they
had to rise (→ 0.82, → 0.88) or they, not the formula, would set the result.

Measured, old → new:

```
gold    floor 0.584→0.784   cornerLum 0.0657→0.0211   orbTrim 0.550→0.360
teal    floor 0.340→0.340   cornerLum 0.0708→0.0708   orbTrim 0.881→0.831
purple  floor 0.340→0.340   cornerLum 0.0351→0.0351   orbTrim 1.000→1.000
navy    floor 0.340→0.340   cornerLum 0.0148→0.0148   orbTrim 1.000→1.000
```

⚠️ **The old tests restated the formula and so only checked themselves.**
`brand_panel_test.dart` carried its own copy of the trim expression and a
literal `contains('(0.34 + ((_accentLuminance - 0.17) * 1.1)')`, so the group
stayed green against the **old** numbers after the widget changed. Both now
**parse the constants out of the source** and assert the *property* — gold
trimmed hard, dim accents untouched, and the ceiling above the computed floor
so it is never the limiter.


The chip is painted **white-on-dark deliberately, not from the theme's text colours**: the corner it occupies is the dark hero panel on the split-screen layouts, where `textSecondary` disappears in light mode. Frosted (`BackdropFilter`) so it keeps contrast wherever on the artwork it lands.

⚠️ **Two other back arrows survive and must NOT be folded into it**: the OTP stage's labelled "Back" (goes back one *stage*, to credentials — not out of the portal) and `forgot_password_panel`'s close. Different actions; moving them to the corner would collide with this one.

⚠️ **`dart format` on a directory reformats files you never touched.** Formatting the 16 auth screens also reflowed 35 unrelated files in `lib/screens/` — 6000 lines of churn in the diff. Format the touched files, then check `git diff --name-only` and revert the rest.

⚠️ **`flutter analyze` reports NOTHING for a file it cannot parse.** A bulk edit left `),.animate()` and `),,` in twelve files; analyze came back clean because those files never got as far as being analysed, and only `dart format` (which must parse) surfaced them. **After any scripted source rewrite, run `dart format` as the parse check before trusting analyze.**

⚠️ **Source-text assertions break on formatting, not on behaviour.** `register_swap_and_portal_polish_test.dart` asserted the literal `']).animate().fadeIn(duration: 400.ms),'` — the `]).` came from the heading's `Row`, which existed only to seat the back arrow beside it. Removing the arrow removed the `Row` and the test failed while the animation was untouched. Its sibling read a **fixed 400-character window** after `if (_success != null` and failed when the comment above the banner grew. Both now assert the thing itself (`.animate()`, `.fadeIn(...)`, `successGreen` anywhere in the success branch).

## Idle lock — the app sleeps like the laptop does

**After 5 minutes with no input the app signs the user out and covers itself with a screensaver** (`kIdleLockTimeout`, `lib/core/idle_lock.dart`). Clicking it reveals the login page **for the portal they were in**, and they must sign in again. Three pieces: `IdleActivityDetector` (a `Listener` + `Focus` wrapping the router inside `MaterialApp.router`'s `builder`, so a pointer event *or a keystroke* anywhere resets the countdown), `IdleLockController`, and `IdleLockOverlay` (the `Stack` that paints `IdleLockScreen` over every route).

**The sign-out happens the moment the screen goes up, not when the user comes back.** From the instant the desk is unattended the session is already gone, so killing the app or pulling the network leaves nothing to resume. The overlay also `go()`s the route underneath to the login page at lock time — invisible behind the opaque lock screen, but it tears the dashboard down instead of leaving it mounted with a profile that no longer exists.

⚠️ **`_armed` defaults to FALSE and gates both `poke()` and the timer callback.** Without it the app locked **the portal chooser**: nobody was signed in, but the first mouse move started a countdown, and 5 minutes later a login page was hidden behind "Click anywhere to sign in again". Re-checked at fire time too, so a sign-out in the last seconds of a countdown cannot still throw the screen up.

⚠️ **The overlay `watch`es `currentProfileProvider` — `ref.listen` was the bug.** listen fires on *changes*; at start-up the profile is already null, so nothing changed, the callback never ran and the controller kept whatever state it started in. `arm()` is idempotent because it is called from `build`, which runs constantly — re-poking there would push the deadline out forever and the app would never lock while anything on screen repainted.

**`SessionSecurityPolicy.sessionTimeout` (30 min) is a different rule and stays.** That is the server-side check on start-up that a session is dead and cannot be resumed; this is the screen lock in front of it, deliberately shorter.

⚠️ **The lock screen's glow is painted, not decorated (`_SealHaloPainter`).** A `RadialGradient` fading to transparent on a `BoxDecoration` circle still **composites as a disc** over the drifting background — it rendered as a flat dark circle parked behind the seal, and `BlendMode.plus` on the decoration did not help (inside a `RepaintBoundary` the layer composites opaquely against black). A blurred `drawCircle` with `BlendMode.plus` on the shared canvas adds light instead of covering. Same lesson for the orbiting arcs: the "fill a circle, cover the middle with a smaller one" trick needs that inner circle to be **opaque**, which blots out everything behind it — `drawArc` with a stroked `SweepGradient` leaves the background showing through.

**Three out-of-phase controllers (24s drift / 7s breathe / 19s orbit), deliberately not multiples of each other**, so the loop never visibly repeats. `pumpAndSettle` will hang on it — the test asserts `hasRunningAnimations` instead.

⚠️ **google_fonts fetches over the network, so a bare harness renders text with the debug fallback** (yellow, double-underlined). Seen while previewing the lock screen in a throwaway `main()`; it is a *harness* artifact, not a missing theme — the real app was always fine. Don't chase it.

⚠️ **The Perishable tab's toolbar was the odd one out (2026-09-04).** It stacked the search box, the year filter and the yard picker **vertically inside a gold-bordered card** — a three-row control panel no other page has, which pushed the table down and made Central Disposal's Perishable tab look like a different product from the tabs either side of it. Now one `Row` (search `Expanded`, then year, then yard) fading in at 300ms, matching `_unsoldTab`'s header and `DisposalSearch`'s own styling: 14px radius, gold border at 0.4 / 1.5px focused, `primaryGold.withOpacity(0.06)` fill, gold search icon, and a clear button once something is typed.

⚠️ **The table below is still a `cardDark` box — that is correct and must stay.** A test asserting "no cardDark in the file" fails on it; the removed filter card is identified by its **gold** border (`primaryGold.withOpacity(0.5)`), which is what the test now checks.

**`DisposalSearch` was not reused** even though the styling is copied from it: it stores its query in `disposalSearchProvider(tabKey)`, and this screen keeps `_search` in local state alongside `_page`, which the Row's `onChanged` resets. Worth unifying if a third page needs it.

## Perishables have no warehouse, and most packages have no officer

⚠️ **"No warehouse details" on a perishable was CORRECT, and read as a bug.** Perishables never enter a warehouse — the page's own subtitle says "no warehouse, no appeal window" — so the section is legitimately empty (verified: **0 of 47** perishable items have a `warehouse_entries` row). The generic empty state made a by-design blank look like a failed load. `_EmptyState` now takes an optional `reason` (and `icon`), and the warehouse section checks `nature == kNaturePerishable` to say "Not stored in a warehouse" plus why.

⚠️ **"Unknown Officer" was accurate but accusatory — now `_kNoEntrantRecorded = 'Not recorded'`.** Measured: **all 176 packages have `inspected_by` NULL**, and only **60** have a `Created new package%` audit row, so for 116 of them there is genuinely nobody to name. The audit fallback (`getPackageCreator`) works fine for the 60. "Unknown" read as a lookup that had FAILED and sent people hunting for a bug that was not there. The absent case is now set in muted italic (gold-and-bold announces a *person*) with a line saying the entry predates officer tracking.

⚠️ **`audit_logs.entity_id` is TEXT while `packages.id` is UUID** — joining them raises `operator does not exist: text = uuid`. Cast: `a.entity_id = p.id::text`. Another face of the Supabase→local type-cast seam.

⚠️ **`flutter_animate` leaves a pending timer that fails widget tests on teardown** ("A Timer is still pending even after the widget tree was disposed"). A bare `await tester.pump()` is not enough on any screen with an entrance animation — follow it with `await tester.pump(const Duration(seconds: 1))`. `pumpAndSettle` is the alternative, but it hangs on the endless lock-screen animation, so the explicit second pump is the pattern used here.

⚠️ **A `matchesGoldenFile` shot of a screen with entrance animations can capture a BLANK frame** — the image is written before the google_fonts exception, so it looks like it worked. To check a layout, assert `tester.getRect` positions instead: it reports the real geometry and says *which* number is wrong.

**The perishable screen is TWO pages from one file (2026-09-04).** `PerishableGoodsScreen(readOnly:)` serves the yard and Central Disposal, and it had ONE arrangement for both — so on whichever portal you opened it, it was the odd page out.

- **Yard copy** now reads like Other Goods beside it: a search box, then a `Wrap` of Date Range + Post Status Activity + All Years. ⚠️ The activity list is `kAllPostStatusActivities` (every activity, unfiltered) because the SR form offers a perishable all of them — a narrowed filter could not match what was saved.
- **Central Disposal copy** reads like Sold Goods: search and `YardAllFilter` on the header's line.
- The details popup passes `headerAccentColor: successGreen` on Central Disposal. It passed none, fell back to the default indigo, and was the only dialog in that portal wearing another colour.

⚠️ **Perishables genuinely have no warehouse rows** — 47 items, 0 warehouse entries, because the perishable flow skips the warehouse by design (the user's own earlier decision). The dialog's "Not stored in a warehouse" panel is therefore correct, not a bug. Showing a real summary there would need perishables to be warehoused first, which contradicts the flow.

⚠️ **Post Status Activity is filtered BY STATUS — except for a perishable (2026-09-04).** Detain items are waiting on something (licence, valuation, inquiry); Forfeit/Abandoned/Other are on their way to disposal. Those are different questions. The filter had been removed **for all goods** because a perishable's status is `'Perishable'` — in neither group — so a filtered list offered it nothing; the cure was applied to everything, and an officer could then record "Pending Licence" against already-forfeited goods. Now: `postStatusActivitiesFor(status)`, with the perishable exception getting `kAllPostStatusActivities`.

- ⚠️ **Changing the status clears activities the new status does not offer.** Without it the field renders **empty while the row still holds the old value** — and the old value is what gets saved.
- The **edit dialog** (`package_details_dialog.dart`) applies the same rule. Its `_ItemRow` has no `nature`, so it identifies a perishable by `status == 'Perishable'`.
- Both perishable pages filter against `kAllPostStatusActivities`, so what the form can save is exactly what the filters can match.

**The perishable page's two copies, finished:** the yard's wears the **gold-bordered filter card** every held-goods page there wears (Forfeited, Other, Abandoned); Central Disposal's has **no year filter** (no cross-yard tab there has one), pads at **24** not 28, and lets the StatChip's own bottom padding be the gap — exactly as Unsold Tenders does.

⚠️ **Every dialog's close button is `DialogCloseButton`, and it is RED (2026-09-04).** They were all `Colors.white.withOpacity(0.7)` — fine on the yard's and ICT's solid dark headers, and **very nearly invisible** on every other directorate, whose dialogs wear a **pale tinted** header. The only way out of those dialogs was a control you had to already know was there.

- `prominent: true` → the cross inside a soft red disc, **for a pale header only**. On a dark one a bare red cross reads fine and a disc would be a second box in the corner.
- ⚠️ **`prominent` is decided by `headerAccentColor != null`** (and `!erp`), which is exactly the signal: only the directorate portals pass one, and passing one is what makes the header pale. **The yard and ICT keep the shape they always had and change only the colour** — as asked.
- `test/dialog_close_button_test.dart` renders it and reads the icon's colour, and asserts no dialog still paints a white cross.

**The yard's perishable search box draws no border or fill of its own** — the gold filter card around it IS the border, and a gold box inside a gold box is what made it look nothing like Forfeited's. Central Disposal's copy has no card, so it keeps its own outline like every search box there.

⚠️ **There is only ever ONE committee round; the "Committee Tender 2" was a phantom (2026-09-04).** A `tender_revaluations` row with `tender_sale_id IS NULL` means exactly one thing: **a price set for a round not yet placed.** The committee price was written **both** onto `tender_committees.submitted_value` (where the UI reads it) **and** as one of those pending rows — so the dialog drew the same price twice, the second as a sealed round that can never happen.

Three fixes, because it was wrong in three places:
- **UI**: the next-tender tile is suppressed when the package's outcome is **decided** (nothing follows converted / auction / government use / removed) or when the pending figure **equals the committee's** (that is the committee round, already shown).
- **Seeder**: after the committee round's sale is created it now **keys that re-valuation to the sale** — the price was that round's reserve, not a pending next-tender price.
- **Data**: `postgres/10_committee_price_not_a_pending_round.sql` deleted the 3 duplicates. Ran green; committee prices intact.

⚠️ **The Valuation card is hidden when Tender History renders.** History opens with the **Valuation Tender** — the first round and the figure it ran at — so the card was the same fact stated twice, and the two **did not agree**: the card showed the ORIGINAL valuation, the first round the re-valuation keyed to it, with nothing on screen saying which was which. The card survives only where there is no history (a package that never went to tender still needs its valuation).

⚠️ Widget tests pumping `TenderHistorySection` must now override **`unsoldProposalsProvider`** too, or they open a real DB socket.

**The yard's perishable search box overrides NOTHING** and takes the app's `inputDecorationTheme` — a grey outline that turns gold on focus — because that is what a bare `InputDecoration` gives, and what Forfeited / Other / Returned all do. It first had its own gold border **inside** the gold filter card (a gold box in a gold box), then `InputBorder.none`, which removed the frame entirely. Neither is right; inheriting is.

⚠️ **The Sold popup's Tender History was vanishing — two bugs in one expression (2026-09-04).** The details button did `ref.read(saleItemForPackageItemProvider('$pkg|$item')).asData?.value`:
1. **The key was wrong.** Every cell in the row watches `package|item|receipt`; this read `package|item` — a **different provider instance**, which nothing had ever watched.
2. **`.asData` on an unwatched FutureProvider is null**, silently, because it is still `AsyncLoading`.

So `tenderHistoryFor` came out null and the **whole section disappeared** — every round, the committee, and all the bids. Reading the same three-part key the cells watch fixes both: it is already resolved, because the row painted its Valuation cell from it. **Lesson: `ref.read(...).asData` only works on a provider something else is already watching — and a provider family key must match EXACTLY, or you are reading a different instance.**

⚠️ **"Disposal Expenses & Financials" belongs to DESTRUCTION only.** It sat on an `else`, so everything *not* being destroyed got it — a **sold** item showed a destroying deposit, a cost breakdown and a shortfall for goods that were never destroyed, with every figure either zero or an auction cost re-labelled as a disposal shortfall. Sold goods have their own true money section (Sale & Financial Information). `_DisposalExpensesSection` is deleted; `_DestructionFinancialsSection` already carries those numbers where they mean something. ⚠️ `_statusIsDestruction` lived inside that block — it now sits beside the destruction section it serves.

⚠️ **Three kinds of tender round, three markings (2026-09-04).** They were collapsing into one and the section became unreadable:
- **Round 1 — "Valuation Tender" — carries NO badge.** It IS the first valuation, the price the package went to tender at, and it cannot be a revision of anything because there is no earlier round. It was badged "re-valued" whenever a `tender_revaluations` row happened to be keyed to it — the one row where that word can never be true.
- **Rounds 2–4 — "re-valued".**
- **The last — "committee value"**, not another re-valuation: a different act, by different people.

The rule is `revalued: i > 0 && reval != null && !isCommitteeRound` — written on the **index**, not on whether row data exists.

⚠️ **Open question for the user, not yet decided:** for CED/GL1/SR/13/2025 the ORIGINAL valuation (from `disposal_request_items.valuation_cost`) is **204,288**, but round 1 displays **165,447** — a re-valuation keyed to that round. So "Valuation Tender" shows a figure that is not the original. Either the first round genuinely ran at a re-valued price, or the seeder should not key a re-valuation to round 1. **Do not guess this — it is a domain decision.**

⚠️ **Bids are only recorded when goods FAIL to sell — so the winning round has none, and Tender History was dropping it (2026-09-04).** The skip rule was `unit == null && bids.isEmpty && !isCommitteeRound && !sealed → continue`, and every one of those is true of a round that **sold**: no bids (nothing to bid against once it went), and no re-valuation of its own (nothing needed re-pricing afterwards). So the history stopped at the last **failure** and never said the package had sold — on a **Sold Goods** popup, the one round that matters.

- `getTenderRoundsForPackage` now selects `sold, sold_price` and the record carries `sold` / `soldPrice`. ⚠️ Changing that record type breaks `tenderRoundsForPackageProvider` and every widget-test harness that builds one — they must all list the new fields.
- The skip rule spares a sold round, and the tile shows **"Sold for LKR …"** in green.
- **The data was already right**: `select count(*) ... where sold and exists(bids)` → **0**. Nothing sells with bids recorded against it. Only the display was wrong. **CED/GL1/SR/13/2025 has 4 rounds** — three unsold with bids, and a 4th that sold for 147,314 with no bids — which is exactly what the user deduced from the screen before anyone looked at the table.

⚠️ **The seeded tender chain had real holes — 49 unsold rounds with no bids, 21 later rounds with no valuation (2026-09-04).** Both break rules the officers stated:
- **"A tender only records bids when the goods DON'T sell."** So an unsold round with no bids is not a round nobody bid on — it is a round whose bids were never written. And the bids are what **justify** the next round: Valuation reads them, then sets a lower reserve. Without them the screen showed Tender 3 gold, "Awaiting Valuation Directorate", with nothing for Valuation to read.
- **Round 1 runs at the original valuation; every round after it runs at a fresh one.** A later round with no `tender_revaluations` row has no reserve of its own.

Repaired by `postgres/11_…` (18 valuations + 94 bids, derived from each row: valuations step **down**, bids sit **below** that round's reserve) and `postgres/12_…` (16 rounds were left priced **at or above** their predecessor — a re-tender always **lowers** the reserve). ⚠️ **Sold rounds and committee rounds are never touched**: bidding stops when goods sell, and the committee prices rather than bids.

Seeder cause: `final bidCount = _rng.nextInt(4)` — **can return 0**. Now `1 + _rng.nextInt(3)`.

**Tender History ends with a FINAL OUTCOME tile** (`_FinalOutcomeTile`): the decided outcome with its date and note, or "Awaiting Top Management" with why. ⚠️ Both states are drawn — "still waiting" is an answer, and a blank space is indistinguishable from a failed load. ⚠️ Suppressed when `soldById.isEmpty` is false: a **sold** package ended by selling and never reaches Top Management.

⚠️ **A destruction date cannot be in the future.** The Mark-as-Destroyed picker had `lastDate: now + 365 days`; it records when goods **were** destroyed, so it now stops at today. (The tender-placement pickers are deliberately future-dated — a sale is scheduled ahead.)

⚠️ **Goods reach Re-exported by TWO routes, and one of them led nowhere (2026-09-04).** The user was right:
1. **The yard's Final Disposition** → item status `'re-exported'` (17 rows). This is all the page ever looked for.
2. **Top Management ruling `re_export`** on goods that failed every tender. The outcome is offered in the decision dialog and stored as an `unsold_proposal` — but **no page listed it**, so those goods would leave Unsold Goods and appear nowhere in the app. (0 rows so far, which is why nobody had hit it.)

`_topManagementRows()` on `disposition_category_screen` now reads `exhaustedUnsoldProvider` + `unsoldProposalsProvider` — the same pair the **Government Use** page reads, which is the model every Top Management outcome follows. Merged **before** the sort, and each row dated by its own event (`proposal.decidedAt` vs `entry.returnedAt`).

- A **Decided By** column (`_OriginPill`) says Yard or Top Management: two different events, one carrying a whole tender history and the other none.
- ⚠️ The popup takes `row.forfeited ?? saleItem?.forfeited` — the sale-item lookup only knows goods that went through a sale on the **yard's** route, so a Top Management row would have shown no tender history at all.
- The **Officer** column is gone from this page: it reads `returnedByName ?? returnedByBadge ?? '—'` and a re-export sets neither, so every row printed a dash.

⚠️ **Re-exported stays under "Disposed", not "Final Outcomes."** That group answers *where did the goods go* — re-exported goods left the country whichever route decided it. Final Outcomes answers *what did Top Management rule*, and each of its four pages has exactly one origin. The split is between ROWS on that page, which is what the Decided By column is for. (Noted in the source: **Unsold Goods** sitting under "Disposed" reads oddly — the goods have not left, they are waiting on Top Management — but moving it is the officers' call.)

## A decision is not a hand-over: delivering final-outcome goods (2026-09-05)

**Sold goods already worked this way** — `tender_sale_items.is_delivered`, a **Mark Delivered** button on the yard's table, and the warehouse entry closed when it is pressed. Top Management's four outcomes had **no equivalent**: a package ruled *Government Use* on 3 July was decided, but the goods sat in Warehouse 01 until somebody came for them and nothing recorded that anybody had. The yard could not say "these have gone", Central Disposal could not see whether they had, and **zone capacity + the storage charge went on counting goods that were no longer there**.

`postgres/16_final_outcome_goods_can_be_handed_over.sql`: `unsold_proposals` gains `delivered` / `delivered_at`, a CHECK keeping the pair consistent (a delivery means a moment and a moment means a delivery), and **`disposal_toggle_outcome_delivery(uuid, boolean)`** — which **closes the warehouse entry inside the same statement**, tagged `[FINAL:<OUTCOME>]`, exactly as a sale does. ⚠️ Not a display flag: a second statement that could fail on its own would leave the goods counted forever. Only on the way **out** (`if p_delivered then`) — un-marking must not resurrect a closed entry. Defaulted **false**: backfilling `true` would assert a hand-over nobody recorded, and the yard would lose the list of what it still holds.

- **`UnsoldDeliveryCell`** ([unsold_shared.dart](lib/screens/executive/unsold_shared.dart)) reuses the Sold table's own `DeliveryStatusPill` — an officer reading the two tables is asking one question and it should not look like two.
- ⚠️ **Only the yard hands goods over**: `!profile.isDisposal && !profile.isExecutive`. Central Disposal carries the decision out *through* the yard and the DG made it; neither is standing at the gate. They still **see** the column, which is the point of it.
- ⚠️ **Invalidate BOTH proposal maps.** Central Disposal's outcome tabs read the same row through `unsoldProposalsByItemProvider`; refreshing only `unsoldProposalsProvider` leaves the two portals disagreeing about whether the goods left. Plus `warehouseRefreshTriggerProvider` — the entry just closed.
- **The column is on `kUnsoldDecidedColumns` only.** The undecided table's rows are still waiting on the DG, so it would be a column of dashes. `unsoldCells`'s `delivery` param is **nullable and emitted only when supplied**, and both callers gate it on the same `proposalFilter == null` test as their columns — cells out of step with columns throw in `data_table_2`.

Pinned by [final_outcome_delivery_test.dart](test/final_outcome_delivery_test.dart).

## Two portals, one column name, two different numbers (2026-09-05)

The Tender Sale table called its money column **"Latest Valuation" in both portals** — but the yard's view has never shown a valuation. `_ValuationCell(useItemValue: true)` shows the **SR item's declared value**, because the Valuation Directorate's reserve price is Central-Disposal-only. One name over two different figures made the same row look like it held two valuations that disagreed. The yard's header now reads **Declared Value**; Central Disposal's stays **Latest Valuation**. The seal is unchanged — either figure tells a bidder what the reserve is worth.

**Goods Description → Goods Value** on the same table: the description repeated the Goods Name on most rows and pushed the money off the visible width. New `_GoodsValueCell` takes the **row's own Qty**, so the breakdown it prints always multiplies by the number in the Qty column beside it.

⚠️ **The `× 51` vs `× 40` mismatch is fixed at the data layer**, not here — see migrations `13_one_quantity_per_item.sql` and `14_the_item_quantity_is_the_jittered_one.sql`. The **7** rows still disagreeing are the ones migration 14 deliberately left alone (no warehouse entry to arbitrate a real partial forfeit from seed noise); all 7 have **zero warehouse entries and zero tender sales**, so none can reach a Tender Sale table or a valuation popup.

## One SR, several goods, several endings (2026-09-05)

**The popup could show a tender history, but only for ONE forfeited package** — whichever row the caller pinned via `tenderHistoryFor`. Opened from **Goods History**, where an SR carries every item it registered, it showed nothing per item: an officer reading `CED/GL1/OA/07/2025` could not tell that the Truck Tyres had sold while the Steel Sheets were still in Open Area 01.

**`_ItemLifecycleSection`** ([package_details_dialog.dart](lib/widgets/package_details_dialog.dart)) now renders under each item — appeal state first (a hold is *why nothing has happened*), then the **same `TenderHistorySection`** the disposal pages use, so valuations, bids, the committee round and the final outcome have one definition and cannot drift. ⚠️ Rendered only when `tenderHistoryFor == null`: the disposal pages pin the popup to the clicked row on purpose, and per-item histories there would show the same package twice. An item with **no forfeiture and no appeal renders nothing** — "no tender history" on goods never meant for tender is noise.

⚠️ **`forfeitedByItemProvider` / `getForfeitedByItemForPackage` are deliberately UNFILTERED.** `getForfeitedPackages` drops a package the moment it is tendered, requested, sold or destroyed — which is precisely the set of items whose story is worth telling. Keyed by item (forfeiture is per item), newest-first so the current forfeiture wins, rows with no `item_id` skipped rather than pinned to an arbitrary item.

**The Final Outcome tile now says whether the goods actually LEFT** — "Delivered on …" or "Not yet delivered — still held by the yard" — beside the decision. See [[the delivery feature]] above: a decision is not a hand-over.

## Two money columns that printed the same number (2026-09-05)

⚠️ **`_ValuationCell(useItemValue: true)` was the bug.** On the yard it made the *valuation* column fall back to the SR item's **declared value** — so a row printed the identical figure twice, under "Goods Value" and "Latest Valuation", and looked like two valuations that disagreed. Renaming the header (the first attempt) only papered over it.

Now they are genuinely two figures: **Goods Value** = the SR form's declared value (`_GoodsValueCell`, multiplied by the row's own Qty); **Latest Valuation** = the Valuation Directorate's reserve price, which is **Central-Disposal-only**, so on the yard the cell **seals** (`yardSealed`) rather than substituting anything. The `useItemValue` branch is deleted. Both cards — tender sale and destruction — carry the same pair.

**The Disposition Breakdown showed for almost nobody.** Its gate was *detained OR part-released OR disposed*, so an ordinary item **sitting in a warehouse** — the commonest case — got no breakdown at all, and the same popup answered "where are these goods" for one item and stayed silent for the item below it. Now `heldQty > 0 || _releasedQty > 0 || _dispoCounts.isNotEmpty`.

**"Currently Held" now names the place** (`_heldLabel`): "In Open Area 01" on an OA row, "In Warehouse 01" on an SR one. ⚠️ **No hard-coded OA/SR branch** — the warehouse's own name already carries which kind of space it is. Several locations fall back to "Currently Held (N locations)" rather than overflowing the row.

⚠️ **The "× 51 vs × 40" report was a STALE BUILD, not a bug.** Checked against the live DB: that item reads 40 in `package_items`, in `forfeited_packages` and in its warehouse entry, and the popup's Value line and Total Packages line both read the same `highlightedItem.quantity`. Migrations 13/14 had already fixed it; the running binary predated them. **Check the exe timestamp before chasing a reported number.**

Pinned by [goods_lifecycle_in_sr_popup_test.dart](test/goods_lifecycle_in_sr_popup_test.dart).

## The seal is a clock, not a permission (2026-09-05)

⚠️ **Two wrong answers were tried before the right one.** The valuation column showed the same number as Goods Value on the yard (`useItemValue`), so the first fix renamed the header and the second **sealed the yard permanently** (`yardSealed`). That was worse: a **closed** tender's valuation could then never be read on the yard at all, and the yard's own popup meanwhile used `!readOnly && !sale.saleEnded` — showing the reserve price while bidding was **open**, the exact leak the seal exists to stop.

**The rule is one line and it is the same for everyone: `sealedUntilSale: !sale.saleEnded`.** The valuation is the reserve price — secret while bidding is open, ordinary information the moment the tender closes. No portal check anywhere near it. Both `useItemValue` and `yardSealed` are deleted.

## Seeding a final outcome means walking the whole route (2026-09-05)

`postgres/17_final_outcomes_for_every_route.sql`. The DB had **5** outcomes (auction 1, convert 2, destroy 1, government_use 1), **no** re-exports and **nothing delivered** — so Re-exported Goods showed only yard-decided rows (its Decided By column could only ever print one value), Removed from the Premises was empty, and the new Delivery pill had no delivered state to show. Now all six outcomes have rows and two are handed over.

⚠️ **A proposal row alone is invisible.** `getExhaustedUnsoldPackages` requires the full route — 4 tenders → committee appointed → **ADG submits** its figure → one more tender at that price → still unsold. The migration walks all of it, including a step **1b** for committees that were *appointed but never valued* (several existed, with null `submitted_at`, which dated the extra round nowhere).

Four traps, each caught by the verify block rather than by reading the data:
- ⚠️ **Key by `forfeited_packages.id`, never by SR number** — forfeiture is per item, so one SR has several forfeited rows (SR/47/2026 has three) and only one went to tender.
- ⚠️ **Four rounds is not enough: none of them may have SOLD.** Latex Gloves and Industrial Bearings looked like ideal candidates and each already had a sold round — an outcome there would have put the same goods on a Final Outcome page *and* on Sold Goods.
- ⚠️ **Perishables are exempt from the route** (no warehouse, no appeal window, decided at once), so the verify must not demand tenders of them — two correct existing outcomes failed until it did.
- ⚠️ **Nothing may be dated in the future.** Dates derived from each package's own committee timeline landed after today for the recent ones.

There is no `tender_sale_items.unsold` column — a round is unsold when `sold = false` and its deadline has passed.

**`tool/apply_sql_whole.dart`** (new) runs a migration as ONE block via `QueryMode.simple`. ⚠️ `apply_sql.dart` splits statements itself and its splitter **silently drops** ones it cannot parse (an apostrophe in a `--` comment, a multi-row VALUES): it reported "completed successfully" having inserted **nothing**. Use the whole-file runner for anything with prose comments or CTE inserts.

## One pager, every table (2026-09-05)

The app had **two**: an arrows-only `‹ Page 3 ›` bar under twenty tables, and the numbered one built for the ICT console. The arrows-only bar could not answer *how far through am I* or *how much is there*, and reaching page 12 meant eleven clicks.

**[table_pager.dart](lib/widgets/table_pager.dart) now carries the ICT design** — first and last page always offered, two neighbours around the current one, gaps collapsed to an ellipsis, so the bar is the same width at 3 pages and at 3,000. Every table in the app goes through this one widget (20 call sites across 16 screens), so the design reached all of them at once. `accent` defaults to the yard's gold; the directorate portals pass their own.

⚠️ **`IctPager` is now a thin wrapper over it**, not a second copy — it only supplies the padding that puts the bar on the table card's own footer rule. Two implementations meant the console and the rest of the app could drift on the very thing that makes a pager readable. `_PagerNumber` / `_PagerStep` were deleted from `ict_ui.dart`.

SR Registration ([packages_screen.dart](lib/screens/packages/packages_screen.dart)) had a hand-rolled bar of its own; it now uses `TablePager` too, and its `from`/`to`/`hasPrev`/`hasNext` arithmetic went with it.

⚠️ A widget test of the pager **must host it with `AppTheme.lightTheme`** — it reads `context.colors`, an `AppColors` ThemeExtension, and a bare `MaterialApp` has none (the failure is a null-check throw inside `build`, not a missing-widget error).

Pinned by [table_pager_test.dart](test/table_pager_test.dart).

**Still to do — server-side paging.** Only **2** of ~16 paged screens actually page in SQL (`getPackagesPaged`, `getAllLogsAcrossOffices`); the rest fetch every row and slice in Dart with `pageSlice`/`.skip().take()`. At today's volumes (largest table 395 rows) that is invisible, but it will not scale. The route is the two existing methods' shape: one filtered `.range(offset, offset + limit - 1)` query for the rows plus a `.count()` for the total, both narrowed by the SAME filter closure.

## Paging in SQL needs the rows to exist in SQL (2026-09-05)

The disposition pages (Sold / Destroyed / Re-exported, one screen driven by `finalTag`) **do not list packages — they list ITEMS**, and one package produces several rows from **three** sources: a warehouse entry carrying a `[FINAL:]` tag, an item whose status says so with no tagged entry, and a Top Management `re_export` ruling. The screen merged those in Dart, sorted by date, then `.skip().take()` — so drawing page 1 cost the whole yard, and the cost grew with the yard rather than with the page.

**`disposition_rows` is a VIEW** ([18](postgres/18_disposition_rows_view.sql), delivery column in [20](postgres/20_disposition_rows_delivery.sql)) — not a table. These rows are a *question asked of existing data*, not a new fact; a table would need a trigger per source and would be wrong in between. ⚠️ Migration 20 **reuses migration 18's body verbatim** (the Python that wrote it slices it out of the file) rather than retyping it — two copies drift, and the symptom is a page whose rows depend on which migration ran last.

⚠️ The tag sets moved into SQL **verbatim**, including `FINAL:DESTROY` with no ED — the pending tag `disposeWarehouseItem` writes, since it upper-cases the action name. Drop it and every package awaiting destruction reaches no page and can never be confirmed.

**Delivery moved too**, and was wrong before: it came from two *package-keyed* maps, but an item sold across two partial tenders has two receipts and two delivery states, which a package key flattens. The view resolves it **per sale**, and leaves it **NULL** where a page has no hand-over step — "not applicable" is not "still waiting", and false would sweep every OTHER row under the Pending filter.

⚠️ **Index the EXPRESSION.** The tag filter is `upper(substring(upper(trim(...)), '^\[([^\]]+)\]'))`, so an ordinary index on `return_notes` cannot serve it — `warehouse_entries_disposition_tag_idx` matches the view's predicate character for character. If the view's expression is ever edited the index silently stops being used. SOLD page plan: **35.7ms → 4.2ms**, and no longer quadratic in items × entries.

**Screen wiring** ([disposition_category_screen.dart](lib/screens/packages/disposition_category_screen.dart)):
- `_buildRows` + `_topManagementRows` deleted, replaced by `_rowsFrom` which only rehydrates the twenty rows that came back.
- `dispositionPageWithPackagesProvider` does two bounded round trips: the view's page, then `getPackagesByIds` for **that page's** packages (the popup and per-sale cells need the whole package).
- ⚠️ `fromTopManagement` is now a **field carried from the view**, not `proposal != null` — derived from a second provider, a row reports itself as a yard row while that provider loads and the Decided By pill flips under the reader's eyes.
- The header count and the pager total both come from the **server's** count; a count taken from the loaded list can only ever say "20 of 20".
- ⚠️ The year filter needs **its own small query** (`dispositionYearSourceProvider`) — one page of twenty rows would offer only the years visible right now. Same problem Goods History already solved.
- `DispositionQuery` is a value type with `==`/`hashCode`: a family key without value equality opens a fresh request on every rebuild and the page flickers through loading forever.

⚠️ A widget test of these screens must override `dispositionPageWithPackagesProvider` (and `dispositionYearSourceProvider`), **not** `livePackagesProvider` — the screen no longer reads it, and the old override silently yields an empty table.

**Still client-side:** `unsold_packages_screen`, `perishable_goods_screen`, `returned_packages_screen`, `old_entries_screen`, and the directorate tabs.

## "It is locked" was not an actionable message (2026-09-05)

⚠️ **The user's running app is WHY the shared build is locked — that is not a complaint, it is the mechanism.** Windows will not let a build relink an .exe while a process is running it, so `agent_build.ps1` refreshes only its own private slot and reports the shared one as skipped.

The old wording ("close that window and re-run this") sent the user looking for problems in the code **three separate times** while they read a binary that was **88 hours old** — the ×51/×40 report was exactly this. Three windows were holding it, two open for 12 hours.

The note now names **how stale** the shared exe is and **which pids** hold it, with their start times, and `-CloseRunning` closes them (CloseMainWindow, then Kill after 8s) and refreshes the shared build. ⚠️ Never passed automatically — the private slot exists so a rebuild does not disturb what the user is looking at.

**Before believing any "nothing changed" report, check the exe timestamp against the running pids' paths** (`Get-Process cus_yard_management | Select Id, Path, StartTime`).

## Released Goods: the disposition with no tag (2026-09-05)

⚠️ **A RELEASE matches the ABSENCE of a bracket**, which is why it is a fourth *source* in `disposition_rows` ([21](postgres/21_disposition_rows_released.sql)) rather than another entry in the tag list — the other three match a tag. The rule is `_isReleaseEntry`'s, kept exactly: a returned entry whose notes are empty, or do not start with `[`, or are tagged `[FINAL:RELEASED]` / `[RELEASE...]`. 31 of the yard's returned entries are that shape. The verify asserts the two rules are **mutually exclusive** — both run over the same entries, so an overlap would put the same goods on two pages — and that a released row carries **no** delivery state, because the release *is* the hand-over.

Released Goods filters on two things no other page does, so [22](postgres/22_disposition_rows_release_filters.sql) adds them to every source: **`hold_reason`** (its Reason dropdown) and **`receipt_no`**. ⚠️ The receipt number is not a column — it is one field of a pipe-separated note (`Receipt No: 4410 | Date: ...`), and leaving the app to parse it is exactly what forced the fetch-everything, so the view splits it out. `'all'` from the dropdown means *no filter*, not a reason named "all".

⚠️ **`create or replace view` fails when the new columns are not a pure append** — "cannot change name of view column". These land inside the subquery, so `delivered` shifts position. Migration 22 does `drop view if exists` then `create view`; nothing but the app depends on it.

Every migration from 20 onward **slices the previous one's body out of the file** rather than retyping it — two copies drift, and the symptom is a page whose rows depend on which migration ran last.

**Still client-side:** `unsold_packages_screen`, `perishable_goods_screen`, `old_entries_screen`, and the directorate tabs.

## Unsold Goods: the membership question moves to SQL (2026-09-05)

`getExhaustedUnsoldPackages` → `getUnsoldTenderSales` → `getTenderSales`: **every sale, every item, every join**, and only *then* narrowed to the 8 packages that have run out of road. The page's cost was the entire tender history of the yard, forever, to show twenty rows.

**`exhausted_unsold`** ([23](postgres/23_exhausted_unsold_view.sql)) applies the same four conditions in the database: not sold · `tender_count > 3` · the committee valued it **and the ADG submitted** that figure · **and a round ran after that submission and still did not sell**. The app then loads full `ReTenderSaleInfo` for **that page's** ids only (`_reTenderInfoForIds`).

⚠️ **Condition 4 is judged by the round's SCHEDULED MOMENT, never `created_at`.** This is a bug the codebase already hit live: Central Disposal schedules a round before the ADG submits, and two packages can share one sale row — keying on `created_at` stranded Toilet Seat Covers (submitted 18:31, row created 04:25) on 5 rounds forever while Wash Basins in the *same row* moved on. The test pins that the `rounds` CTE never mentions `created_at`.

⚠️ **The item name needed a column of its own.** The search box scans it, forfeiture is per item, so the view resolves it the way `unsoldItemName()` does (the forfeited row's item, then the package's first). Without it that one filter would have kept the whole list in Dart.

⚠️ **`_yardRows` and `_visibleRows` are gone.** The yard scope and the outcome filter are view columns now, so the header count and the table read the same narrowed set **by construction** rather than by both remembering to call one helper. This screen drives Unsold Goods *and* the four Final Outcome pages via `proposalFilter` → `ExhaustedUnsoldQuery.proposal`.

⚠️ **`create or replace view` refuses a column list that is not a pure append** — hit twice now (22 and 23). Drop and recreate; nothing but the app reads these views.

**Still client-side:** `perishable_goods_screen`, `old_entries_screen`, and the directorate tabs.

## Perishable Goods: the sent-but-decided exception (2026-09-05)

`perishableRowsProvider` awaited **every package in the yard** and walked it looking for the 47 items registered as perishable. **`perishable_rows`** ([24](postgres/24_perishable_rows_view.sql)) answers both membership rules in SQL. Verified against the live DB: **21 rows, 19 awaiting, 2 decided** — exactly what the page showed before.

⚠️ **The second rule is the subtle one: a SENT item stays if a final outcome came back for it.** Perishables never reach a warehouse and never sit out the appeal window, so **no disposition page can show them** — this is the only page they appear on. Dropping a sent-and-decided item would mean the yard and Central Disposal never see the ruling at all. The verify block asserts it (`sent row(s) remain with no decision to show`).

⚠️ **The yard filter matches the SR NUMBER's own segment, never `packages.yard`** — that column can be the filing directorate rather than the yard holding the goods. Same rule every cross-yard page uses.

`effective_date` is `coalesce(entry_date, created_at)`, mirroring the app's own fallback: `entryDate` is nullable and a row without one must not vanish from a date filter its neighbours answer.

⚠️ **A widget test of this screen overrides `perishablePageProvider` (+ `perishableYearsProvider`), not `livePackagesProvider`.** The harness supplies the *page the view would have returned*, applying the same two rules; the rules themselves are asserted against the SQL in a separate group, so neither half can drift unnoticed.

**Still client-side:** `old_entries_screen` and the directorate tabs.

## Old Entries: no view needed, but its own query (2026-09-05)

This page lists **packages**, not items, so no view was required — but it does need `getOldEntriesPaged` rather than a flag on `getPackagesPaged`, because **both the search set and the year rule differ**.

⚠️ **"Has a legacy SR number" is the list's DEFINITION, not a clearable filter** — so it lives in the query (`not('old_sr_number','is',null)` **and** `neq('old_sr_number','')`; null is not the only empty).

⚠️ **The year matches FOUR places**: the old number, the new one, the entry date, the CusDec date. Real data shows why — `SR/1290/2021` became `CED/GL1/OA/05/2024`, and an officer must find it by **either** year. `getOldEntryYears` scans the same four over the whole table, since twenty rows would offer only the years currently visible.

Search covers the **old** number and the **CusDec** number as well as the new number and consignee — finding goods by what they were called *before* is the entire point of the page.

**Still client-side:** the directorate tabs (disposal dashboard, executive, appeal).

## What is left client-side, and why it is not all worth moving (2026-09-05)

Every page whose cost grew with the **yard** is now server-paged: Goods History, ICT Activity Logs, the disposition pages (Sold / Destroyed / Re-exported / Released), Unsold Goods + the four Final Outcome pages, Perishable Goods, Old Entries. Those all read `packages`/`package_items`/`warehouse_entries` — the tables that actually grow.

**Still slicing in Dart, deliberately:**

| Page | Source | Live rows |
|---|---|---|
| Admin (officers, warehouses, zones) | own yard's profiles / warehouses | tens |
| Warehouses | `warehouses` | 4 |
| Tender / Destruction Disposal | `forfeited_packages` awaiting a request | bounded by workflow |
| Central Disposal tabs, Executive tabs, Appeal | `tender_sales` 81, `financial_expenses` 71, `tender_committees` 8, `disposal_requests` 53 | tens |

⚠️ **`srFinancialsProvider` is the one genuinely heavy leftover**: it calls `getAllPackages()` **and** `getTenderSales()` and aggregates the whole yard in Dart, feeding both the Central Disposal Expenses tab and the Executive Financials tab. It was left alone because `SrFinancials` is a deep nested shape (per-item, per-tax-name breakdowns, with a fallback keyed by SR number when a sale names no item) — moving that to SQL is a large change with real correctness risk, and measured today the underlying queries run in **3.6ms** and **0.2ms**. Worth doing when SR volume justifies it; not worth doing blind.

**Measured before deciding** (`pg_stat_user_tables`, 2026-09-05): the largest table in the system is `package_items` at 395 rows. The paging work matters for what these tables become, not for what they are.

## Held Goods: the three pages that had no pager at all (2026-09-05)

Detained, Abandoned and Other fetched **every package in the yard** and handed the whole list to `DataTable2`. ⚠️ **Worse than the paged screens ever were** — there the cost was at least bounded by what came back.

**`held_goods_rows`** ([25](postgres/25_held_goods_view.sql)) serves all three, keyed by `kind`. Verified against the running app: **DETAINED 43 total** and **OTHER 76 unsent** — exactly what those screens report.

⚠️ **A row is an ITEM.** `CED/GL1/SR/67/2026` is two rows (Ceramic Floor Tiles, Copper Wire Coils) because detention is decided per item.

Six sources, each with its own `row_key` prefix: `D:` detained · `AE:`/`AS:` abandoned event and status · `OE:`/`OS:`/`OF:` other event, status and **completed** final.

⚠️ **Detention is a holding STATUS with no `[DETAIN]` event**, so what *ends* it is the arrival of some other disposition — a `[FINAL:`, `[ABANDONED]`, `[OTHER]` or `[FORFEIT` note. A detained item is exactly one row; an abandonment can be several partial events, so the uniqueness check is on **`row_key`**, not `item_id`.

⚠️ **Nothing finalised may be offered for action** — otherwise the same goods can be disposed of twice. The one exception is `[FINAL:OTHER]`, which is a read-only record like Released and Sold; those rows carry `completed`, and the verify asserts no other kind ever does.

⚠️ **The legacy free-text "Other" status keeps its guard**: it qualifies only while the item is *actually held in a warehouse*, so a typo in the status field cannot masquerade as an Other package.

**Header counts (Total / In Appeal / Actionable) get their own query** (`getHeldGoodsCounts`). ⚠️ Derived from one page they would contradict the header they sit in — a page of twenty would report twenty whatever the yard holds. `_isRowActionable` was deleted from two screens for exactly that reason; the rule (a hold always blocks, a decision releases early, otherwise the 30-day window) now lives in one place.

**Sent items are excluded by the QUERY** (`sent = false`), not by a set held in the widget.

**Every page in the app now pages in SQL.**


## The drifting glows (2026-09-05)

The portal page's two corner glows now **travel the whole screen** on a slow 24-second loop — blue from top-left to bottom-right, gold the opposite way, so the centre (where the seal and the cards are) is never washed out by both at once. `repeat(reverse: true)` with `Curves.easeInOutSine`, so each pass slows at the turn instead of snapping back.

⚠️ **The splash imports the SAME `DriftingGlows` widget** rather than keeping a copy. The glows are mid-travel when the seal lifts; two independent copies would be at different points on their paths, so the background would visibly jump at the one moment the reader is looking straight at it.

⚠️ Wrapped in `IgnorePointer` and `Positioned.fill` **behind** everything — it must never intercept a click meant for a portal card.

The splash's `LinearProgressIndicator` was removed: it read as a gold **underline on the name** rather than as a loading bar, and it was the only gold on an otherwise blue-and-white mark. The dissolve already says the app is working.

## The launch splash was removed (2026-09-05)

Built, then taken out at the user's request after two attempts failed to look right. Recording it so it is not rebuilt the same way.

**What it was:** the Customs seal over the portal page, dissolving through a blur.

**What went wrong, twice:**
1. Building the portal underneath from the first frame spent its entrance where nobody could see it — the logo scales in over 500ms and cards land on delays out to 1350ms — so the dissolve cross-faded the splash's logo into a **second, already-settled** one. It read as the page reloading.
2. Mounting the child at the lift instead fixed the frame timeline (verified by pumping and printing each frame), **but the user still saw a gold line and a reload.** I could not find its source: it is not in the splash, not `LinearProgressIndicator` on the home path, and not go_router's loading page. ⚠️ **The gold line and the double-load were never actually diagnosed** — the two fixes addressed a different problem from the one on screen.

⚠️ **The lesson: I reported "fixed" twice from reasoning about the widget tree rather than from looking at the running window.** Frame-pumping in a test proved my timeline was right and told me nothing about what the user could see. For anything visual, capture the screen or ask — do not infer.

`DriftingGlows` (below) was a separate request and **stays**.

## The drifting glows (2026-09-05)

The portal page's two corner glows now **travel the whole screen** on a slow 24-second loop — blue from top-left to bottom-right, gold the opposite way, so the centre (where the seal and the cards are) is never washed out by both at once. `repeat(reverse: true)` with `Curves.easeInOutSine`, so each pass slows at the turn instead of snapping back.

⚠️ **The splash imports the SAME `DriftingGlows` widget** rather than keeping a copy. The glows are mid-travel when the seal lifts; two independent copies would be at different points on their paths, so the background would visibly jump at the one moment the reader is looking straight at it.

⚠️ Wrapped in `IgnorePointer` and `Positioned.fill` **behind** everything — it must never intercept a click meant for a portal card.

The splash's `LinearProgressIndicator` was removed: it read as a gold **underline on the name** rather than as a loading bar, and it was the only gold on an otherwise blue-and-white mark. The dissolve already says the app is working.

## Why the splash handoff looked like a reload (2026-09-05)

⚠️ **Building the portal page underneath the splash from the first frame was the bug**, not the fix. The page runs its own entrance — the logo scaling in over 500ms, cards landing on delays out to 1350ms — so mounting it at t=0 spent all of that **where nobody could see it**. When the seal dissolved at 1100ms the reader saw the splash's logo cross-fading into a **second, already-settled** logo, with the last cards still arriving. That is what read as the home page reloading.

**The fix: mount the child when the lift STARTS** (`if (_lifting) widget.child`). Its entrance then plays *in view*, under a curtain going transparent over it — one continuous motion.

Timings rebalanced with it: **hold 750ms** (the splash no longer has to stall until the page is ready) and **fade 900ms** — ⚠️ deliberately *longer than the hold*, because the page's entrance runs underneath it and a 620ms curtain vanished while half the cards were still moving. It does **not** need to cover the full 1.85s; the last cards arriving in clear view is the page waking up, not a glitch.

**Verified by pumping the timeline and printing each frame** rather than by reasoning about it: 0–750ms seal only and portal unmounted · 751ms portal mounts as the curtain starts to go · 751–1651ms both present · 1651ms curtain out of the tree.

## Every paged table animates in, on the same three-step clock (2026-09-05)

Old Entries animated its header and its filter bar but **not its table**, so the two slid in and the rows simply appeared underneath them — the table read as snapping into place while the rest of the page settled. Perishable Goods had a subtler version of the same fault: its table used the filter bar's own **200ms** delay, so the two moved together and the page arrived as one block.

**The sequence, top to bottom:** header (no delay) → filter bar (**200ms**) → table (**300ms**), each a 400ms `slideY(begin: 0.1)` + `fadeIn`.

⚠️ Adding a paged screen means ending its table's `Column` with `.animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn()`. [table_entrance_animation_test.dart](test/table_entrance_animation_test.dart) holds all nine screens to it, and its first assertion (that each file still renders a `DataTable2`) fails loudly if a screen is renamed rather than quietly dropping out of the check.

## One scrollable per page (2026-09-05)

The tender-sale, disposal-request and valuation cards **capped their inner table's height** (`.clamp(115, 380)` / `.clamp(100, 320)`), so a card with more rows than the cap scrolled inside itself. ⚠️ **Two scrollables then overlapped**: with the pointer over a table the wheel moved the *table*, and once that reached its bottom the page still would not move — so there was no way to scroll past a long sale without hunting for a gap between the cards.

**Fix: size to the rows, no cap** (`rows.length * 48.0 + 56`). `DataTable2` still wraps its rows in a `SingleChildScrollView`, but one with **nothing to scroll does not consume the wheel** — Flutter bubbles it to the parent. Four call sites: two in `disposal_dashboard_screen`, one in `valuation_dashboard_screen`, and `financials_tab` already did it correctly.

The yard's Tender Sale page reuses the same `TenderSaleCard`, so it was fixed by the same change.

⚠️ [nested_scroll_test.dart](test/nested_scroll_test.dart) pins both halves: an inner view sized to content lets the wheel reach the page, **and** one with surplus height keeps it — the second test *reproduces the old bug*, so the diagnosis is proven rather than assumed. Adding a new card with a fixed inner table height will fail it.

## The scroll fix was a pixel short (2026-09-05)

⚠️ **First attempt failed and I reported it as fixed.** Removing the height cap was right, but the replacement `rows.length * 48.0 + 56` **ignored the theme's `dividerThickness: 1`** — so every table was still short by one pixel per row, still overflowed, and still kept the mouse wheel. Nothing changed on screen.

**`dataTable2Height(rowCount)`** in [table_pager.dart](lib/widgets/table_pager.dart) is now the one definition: `56 + rowCount * 49.0 + 6` — heading 56, row 48 **+ 1px divider**, plus slack. ⚠️ Being slightly *taller* than needed costs nothing; being slightly shorter costs the whole page's scrolling.

⚠️ **[table_height_test.dart](test/table_height_test.dart) renders a real `DataTable2` at seven row counts and asserts `maxScrollExtent == 0`.** Verified it catches the regression: putting the old `* 48.0` arithmetic back makes it fail. That is the check that was missing the first time — I had reasoned about the height instead of measuring it.

⚠️ `Scrollable.of(element)` looks **up** the tree and throws when there is nothing above it; read positions with `tester.stateList<ScrollableState>()` instead. My first version of this test failed on every case for that reason and said nothing about the heights.

## Central Disposal paging, 1 of N: Tender Sales (2026-09-05)

⚠️ **The Central Disposal tabs show ALL 28 YARDS**, so the row counts that made client-side paging acceptable on a yard page (81 sales, 188 items) are a per-yard figure. The earlier decision to leave these alone was measured on one yard and does not hold here.

**`getTenderSales` is the heaviest query in the app**: every sale → items → forfeited rows → packages → package items → warehouse entries, read by three screens.

**`tender_sale_summary`** ([26](postgres/26_tender_sale_summary_view.sql)) carries the sale-level facts needed to *choose and order* a page; the heavy join tree then runs for **that page's ids only** (`inFilter('id', ids)`). Verified live: 81 sales, 76 pending, 49 re-tenders — and `TS/GL1/2026/068` flags as a re-tender, matching its badge on screen.

⚠️ **The view deliberately does NOT decide whether the sell window has closed.** That is `unsoldDeadline` → `workingDeadline`, which rolls past weekends **and Sri Lankan public holidays fetched from an API at runtime**. With no holiday table, a SQL version would disagree with the app on exactly the days that matter — so the screen keeps that one test, applied to its page.

⚠️ **Searchable aggregates are TEXT, not `text[]`** — `ilike` cannot serve an array, and the Dart driver returns array columns as `UndecodedBytes` (the row arrives unreadable). Pipe-wrapped (`|GL1|`) so a filter cannot match across two neighbouring values.

⚠️ **Re-tender ids need their own query over ALL sales** (`retenderSaleIdsProvider`). Derived from one page, a sale would be marked new simply because its predecessor sat on the page before.

## Central Disposal paging, 2 of N: Disposal Requests (2026-09-05)

⚠️ **A request is visible only through its ITEMS**, which is what forced the old code to fetch everything: it ran **three** lookups to build the "already consumed" set (a tender's `forfeited_package_ids` array, every `tender_sale_item`, every `destruction_item`), fetched every forwarded request with its items → forfeited rows → packages → package items → warehouse entries, and only *then* discarded the items that failed a gate — and any request left holding nothing.

**`disposal_request_summary`** ([27](postgres/27_disposal_request_summary_view.sql)) answers that per request. Verified against the screen: 2026-08-29 → **5 packages**, 08-27 → **4**, 08-26 → **5**, matching the cards exactly.

**Both gates kept as the app has them:** the request's `valuation_status = 'forwarded'` *and* the item's own `forwarded` flag — a request can be forwarded with only some of its items released.

⚠️ **The page still filters its own item lists.** The view decides which *requests* survive; each card's item list must still exclude consumed rows, or a card would show goods that have already moved on.

## Central Disposal paging, 3 of N: Sold Goods (2026-09-05)

⚠️ **No new view.** `disposition_rows` ([18](postgres/18_disposition_rows_view.sql), delivery in [20](postgres/20_disposition_rows_delivery.sql)) already carries exactly this row shape — an entry tagged `FINAL:SOLD` or `SOLD`, with the officer and the delivery flag — so the tab reads it with `finalTag: 'SOLD'`. A second view would have been a second definition of the same rule, free to drift.

The tab was calling `getSoldPackages` → `getAllPackages()`: **every package in every yard**, with items and warehouse entries, then kept the sold entries in Dart. All three of its filters (search including the **officer**, yard, Delivered/Pending) now reach SQL. Verified live: 74 SOLD rows, 39 delivered.

`_isSoldEntry` and `_rows(List<PackageModel>)` are gone from the screen.

⚠️ **Two tabs shared the same `TablePager(total: total, page: _page, pageSize: _pageSize)` text** — an Edit matched both. Destroyed keeps its own until that tab is paged; the Sold one now uses `kDispositionPageSize` so the pager and the query cannot drift.

## Central Disposal paging, 4 of N: Destroyed Goods (2026-09-05)

Reuses `disposition_rows` with `finalTag: 'DESTROYED'` — both its sources (a tagged entry, and an item whose status says so) were already there. It needed **one** new column.

⚠️ **Destruction is the one disposition with a MIDDLE state.** `[FINAL:DESTROY]` (no ED) is what `disposeWarehouseItem` writes when goods are marked for destruction, and the item's status becomes `supposed to be destroyed`; only when the yard **confirms** does either become past tense. Both belong on the tab — one awaiting action, one a finished record — so `final_tag` alone cannot tell them apart. [28](postgres/28_disposition_rows_destroyed_state.sql) adds **`is_destroyed`**.

⚠️ **NULL on every other page.** False on a sold row would read as "awaiting destruction" on goods that are already gone. The verify asserts both directions, plus that a `supposed to be destroyed` item is never reported as destroyed — collapsing those two would present goods awaiting destruction as gone, **on the very tab an officer uses to confirm them**.

Live: **16 confirmed, 23 awaiting** — exactly the status split in the data.

⚠️ Three unused declarations the analyzer flags here (`_YardFilter`, `_parseDestroyReceipt`, `_DestructionValuationCell`) were **already unused before this change** — checked against a copy of the file rather than assumed.

## Central Disposal paging, 5-9 of N: the five outcome tabs (2026-09-06)

Government Use, Auction, Converted, Removed **and Unsold Goods** all share `UnsoldProposalsTab`, so one change paged all five. They read `exhausted_unsold` ([23](postgres/23_exhausted_unsold_view.sql)) — the view already built for the yard side.

⚠️ **`proposalFilter` belongs in the query KEY, not a Dart filter.** Each tab asks for its own outcome; Unsold Goods (null) asks for all of them. Filtering afterwards would mean every tab fetched every outcome.

⚠️ **The page index is keyed by tab** (`_unsoldPageProvider(tabKey)`) — five tabs share one widget, and a single provider would carry one tab's page number into the next.

⚠️ **Central Disposal's copy searches the CASE NUMBER**; the yard's does not. That one term would have kept the whole list in Dart, so `case_number` was joined onto the view (with a verify that it is actually there).

⚠️ **`exhaustedUnsoldProvider` is still read elsewhere and rightly so** — the Unsold Tenders tab uses it as an *exclusion set*, dropping packages that have run out of rounds from its re-tender pool. That is a different question and genuinely wants all of them. The test scopes its "no longer reads it" assertion to the outcome widget alone.

## Central Disposal paging, 10 of N: Unsold Tenders (2026-09-06)

⚠️ **The worst one: it read THREE providers**, each of which begins by fetching every tender sale in the yard with its items, forfeited rows, packages, package items and warehouse entries — `unsoldTenderSalesProvider`, `reTenderEligibleProvider`, `exhaustedUnsoldProvider`. **Three passes over the whole yard to draw twenty cards**, across 28 yards. And it had **no pager at all**.

**`unsold_retender_pool`** ([29](postgres/29_unsold_retender_pool_view.sql)) settles membership once: in a sale, never sold, current round is the newest by `created_at`, **not perishable**, and **not already exhausted**. Live: 14 in the pool, 0 overlapping `exhausted_unsold`, 0 perishable.

⚠️ **A perishable never joins the pool.** Goods that spoil get no second round — one failed Special Tender Sale and they go to Top Management. Offering them again would offer goods that will not last the wait *and* hide them from the only person who can act.

⚠️ **A package must never be in the pool AND exhausted** — it would be offered for re-tender and ruled on at the same time. The view excludes them, so the count pill needs no `where(!exhausted)` of its own: pill and table now agree **by construction**.

⚠️ **There is no `unsold` COLUMN on `tender_sale_items`.** The model has the field and it is always false — a round is unsold when it is *not sold* and its deadline has passed. That is why condition 3 needs the holiday calendar, and why the deadline half stays in Dart (same split as Tender Sales).

## Central Disposal paging, 11 of N: Committees (2026-09-06)

The **same** `unsold_retender_pool` ([29](postgres/29_unsold_retender_pool_view.sql)), narrowed twice: `round_count = kMaxBidTenderRounds + 1` (the Valuation Tender and Tenders 1–3 all failed) and `has_committee`. No new view.

⚠️ **The "moved on" set is gone.** A card leaves this tab exactly when the committee-priced tender *also* fails — which is when the package becomes **exhausted** — and the pool already excludes those. The tab used to intersect three providers in Dart to reach the same answer.

⚠️ **A card whose committee has not loaded is skipped, not crashed.** The view says a committee exists; `tenderCommitteesProvider` is a separate fetch that may not have landed on a given frame, and the old `committees[id]!` would have thrown there.

⚠️ **Taxes is deliberately NOT paged.** `disposal_taxes` holds **4 rows** — VAT, PAL, Cess, Stamp Duty. It is a rate table, not transaction data: it grows only when the government adds a tax. Paging it would be pure overhead.

⚠️ **Perishable was already done** — Central Disposal renders the same `PerishableGoodsScreen(readOnly: true)` that was paged on the yard side.

## Central Disposal paging, 12 of 12: Disposal Expenses — and the work is done (2026-09-06)

The last tab, and the one I had **measured and deliberately skipped** earlier. That decision was taken on **one yard** (3.6ms, 0.2ms); Central Disposal shows 28, so it no longer held.

**`sr_expense_summary`** ([30](postgres/30_sr_expense_summary_view.sql)) answers only what this tab needs — which SRs have money to account for, and what was spent — **not** the whole of `SrFinancials`. The sale proceeds, per-tax breakdown and storage charges stay where they are; the Financials tab still uses them, and reproducing that shape would be two definitions of the same figures. Verified: total spend **1,588,075** matches `financial_expenses` exactly.

⚠️ **An expense keys EITHER to a package item OR to the SR number alone** — 16 by item, 55 by SR here. Matching one way would have silently dropped most of the money; the view groups by SR number and the verify asserts no expense row is orphaned.

⚠️ **`_matchesDateRange` had a fallback worth rescuing**: when a row has no date it matched on **the year in the SR number**. A legacy SR can carry no usable date, and losing that would hide it from *every* date filter. The view's `activity_date` falls back the same way, and a verify asserts no row is dateless.

⚠️ **The totals strip had to change shape.** It summed the rows on screen — right while the table held every row, **wrong** the moment it held twenty, when it would report one page's money as the directorate's total. It now takes SQL sums over the whole filter, computed **before** the empty-page early return so a filter matching money but no page-1 rows still reports it.

⚠️ **`buildSrFinancials` was extracted from the provider** so a page can build the same rows. A function, not a view: the table and its dialog read the per-item `goods` list. The whole-ledger provider still calls it, so the Financials tab is unchanged — confirmed by the suite passing before and after the extraction alone.

**Every Central Disposal tab now pages in SQL**, except Taxes (4 rows, a rate table) and Perishable (already done on the yard side).

⚠️ **Two `flutter test` runs racing showed 6 phantom failures.** A backgrounded run overlapping a foreground one produces failures that do not reproduce. Re-run alone before chasing them.

## The Destroyed tab still lagged after paging — and paging was not the cause (2026-09-06)

⚠️ **The table was already paged. The lag was in a CELL.**

`DestructionExpenseCell` watched **`srFinancialsProvider`** — `getAllPackages()` + `getTenderSales()`, rolled up per item and per tax name — to display **one figure**, then scanned that whole list linearly for its SR. Twenty rows meant twenty widgets each waiting on the entire yard's ledger.

**Fix:** `getDestructionSpendBySr` reads `sr_expense_summary` (already built for the Expenses tab) for **one page's SR numbers** — measured at **0.7ms**. `DestructionExpenseScope`, an `InheritedWidget`, carries the page's key so all the cells share one query. ⚠️ An InheritedWidget rather than a constructor argument: the cells are built deep inside a `DataTable2` row builder, and threading the list through each would put the page's shape into every cell. ⚠️ The key is **sorted and de-duplicated** — an unstable family key opens a fresh query per rebuild, trading one slow load for a permanent one.

⚠️ **Two dead cells removed**: `_DestructionValuationCell` and `_DestructionPriceCell` each watched `destructionItemForPackageItemProvider` — **two round trips per row**, the second with a deep nested join. Never rendered (the analyzer had been flagging them), but 40 queries a page if anyone wired them up.

**The lesson: paging a table does not page what its CELLS fetch.** After paging a screen, check every cell widget for a provider watch — a per-row query is invisible in the tab's own code.

## Financials: the narrowing that lied, and Future.wait making it slower (2026-09-07)

The page still waited a second or two. Two separate causes, both found by **measuring**, and one of them the exact opposite of what the code looked like.

**1. `select('*')` on the embeds.** `package_items(*)` and `warehouse_entries(*)` bring 19 and 18 columns; `buildSrFinancials` and `calculatePackageCharge` between them read six and three. Naming the columns took **420 kB of embedded JSON down to 117 kB**. Postgres was answering the packages query in **15ms** — the rest was the driver decoding rows into Dart objects.

⚠️ **A narrowed select fails in two different ways, and only one of them is loud.** `PackageItem.fromJson` and `WarehouseEntryModel.fromJson` cast `package_id`, `item_name`, `warehouse_id` and `hold_reason` as non-null, so dropping those threw `type 'Null' is not a subtype of type 'String'` at parse time — obvious. But `destroying_deposit` is **nullable**: dropping it threw nothing and silently reported **every deposit on the page as LKR 0**. A test now asserts every column the roll-up reads is in the select, because the compiler cannot.

(`daily_rate` was the one column genuinely safe to drop — `calculatePackageCharge` takes its rate from the historical rates map, day by day, and never reads the stored one.)

**2. ⚠️ `Future.wait` was SLOWER than awaiting the four in turn.** Warm, three runs each:

```
one after another   167ms  186ms  204ms
Future.wait         298ms  303ms  371ms
```

**The wait is not the network.** The four responses arrive together and then **queue to be decoded on this one isolate**, so nothing finishes sooner and every query's own latency grows — plus the scheduling overhead. Measured alone: packages 146ms, sales 74ms, expenses 54ms, rates **6ms**. Those same rates took **167ms** when issued alongside the others — 27× for a query returning a handful of rows.

A test had been *pinning* `await Future.wait([` as the correct shape, with a comment explaining that serial execution "would give half of it back". It was wrong, and it was wrong from reasoning rather than from a measurement. It now pins the serial shape and carries the numbers.

End to end, old four vs new four: **357-465ms → 167-204ms**.

**The lesson: `Future.wait` helps when the wait is I/O. When the cost is CPU-bound decode on a single isolate, it only makes each caller wait longer for the same total work.**

⚠️ **Five tests were pinning how code was WRITTEN, not what it does** — an exact select string, the order clauses were chained in, `widget.readOnly ?` where the flag has since been split into `readOnly` + `showDecidedItems`, `!i.sold` where the page now reads `!i.sold && !i.unsold`. Every one failed on a change that had *improved* the behaviour it was guarding. Two more traps hit while fixing them: `flat()` collapses the newlines, so **drop comment lines from the RAW source before slicing**, and a comment that names the old code (`daily_rate`, `kOutcomeAwaiting`) reads to a substring check as the code still being there.

## Financials paged in SQL — and the timezone bug it uncovered (2026-09-07)

The page loaded the WHOLE ledger to show twenty rows: every package in every yard with its items and warehouse entries, every tender sale, every expense row — then `.where` to filter, `.skip().take()` to page, `summariseSrs` to total, all on the UI isolate.

`postgres/41_sr_financials_view.sql` computes the same ten figures per SR, so filter, order, page and totals are all SQL. Warm, live:

```
the old whole-ledger load   357-465ms
narrowed + serial           167-204ms
one page + SQL totals       102-135ms
```

⚠️ **`::date` on a timestamptz follows the SESSION's timezone, and the app and psql do not agree.** psql here inherits **Asia/Colombo**; the app's driver connects as **UTC**. The same warehouse entry therefore landed on a different DAY for each, and the storage charge read **88,100 higher through the app than through psql** — the same view, the same database, two answers. That is why the view's verify block passed while the app-side comparison failed.

Dart has always counted days in local time (`parseDbDate` calls `.toLocal()`), so **every date in a view must say `at time zone 'Asia/Colombo'` explicitly**. The migration proves it: it re-reads its own figures under `set local timezone to 'UTC'` and fails if any moves.

**This applies to every existing view with a `::date` cast** — `perishable_rows`, `held_goods_rows`, `sr_expense_summary`, `disposition_rows`. Only `sr_financials` has been audited so far; the others compute dates for FILTERING rather than for money, so a day's drift shifts which rows a date filter catches at a boundary rather than changing a figure. Worth a pass.

⚠️ **Day-by-day `generate_series` is the clear way to say a rule and the slow way to compute it.** Storage counted a day at a time with a rate lookup per day: 89ms. A rate holds until the next one starts, so the same figure is `rate × units × days of overlap with each rate period`: **16ms**, identical to the cent. ⚠️ Keep an explicit period BEFORE the first recorded rate at the model's default of 50, or goods admitted before the rate table was filled in silently charge nothing.

⚠️ **A narrowed select can be wrong in silence.** `destroying_deposit` is nullable, so dropping it from the ledger query threw nothing and reported **every deposit as LKR 0**. The non-null casts (`package_id`, `item_name`, `warehouse_id`, `hold_reason`) at least throw. A test now asserts every column the roll-up reads is in the select.

**`FinancialSummary` moved to `models.dart`.** It lived in `providers.dart`, which `services.dart` cannot import (providers imports services; the other direction is a cycle) — moving it is what lets the service return the totals SQL computed.

**Verify blocks that assert against the SCREENSHOT are worth the effort.** All ten figures the page was showing are in `postgres/41`'s verify block; the migration refuses to apply if any disagrees. That is what caught the timezone bug — and later proved the rate-period rewrite was exact.

## Valuation, Appeal and the yard's Tender Sale paged in SQL (2026-09-07)

Three portals, same shape: fetch everything, filter in Dart, `pageSlice` the result. ⚠️ **Client-side paging still loads everything; it only renders less.**

| page | before | after |
|---|---|---|
| Valuation (3 tabs) | 345ms, **no pager at all** | 19ms + 29ms |
| Appeal (2 tabs) | 245ms whole feed | 90ms a page |
| Tender Sale (yard) | 154ms heaviest query | 49ms a page |

New views: `valuation_rows` (42), `unsold_retender_pool` + `valued` (43), marked-unsold rule (44), `appeal_rows` (45), `tender_sale_summary` + `consignees` (46).

### Three real bugs the ports uncovered

⚠️ **`unsold_retender_pool` followed a CLOCK where the Dart followed the MARK.** The view admitted any package whatever had been recorded and carried a `round_moment_passed` column computed from `sale_moment < now()`. getUnsoldTenderSales() found 9 packages, the view listed 15 — the six extra were sales Central Disposal had still to record the outcome of, showing to Valuation as work. Fixed in postgres/44; the column stays as information and decides nothing.

⚠️ **Top Management's Tender Sales filters were BOTH throwing** — `column "item_yards" does not exist`, `column "consignees" does not exist`. The service asked for `item_yards`, the view called it `yards`, and `consignees` never existed. Invisible because the unfiltered case everyone sees first kept working. postgres/46 fixes it and *proves* it by selecting on both columns in its verify block.

⚠️ **`forfeited_packages` stores no `item_name`**, so a row fetched straight from it carries a null one and the Appeal screen's fallback shows the package's FIRST item — the wrong goods on any multi-item package.

### Lessons

⚠️ **Transcribe from the CODE, not from the comment above it.** The Appeal expansion's comment says "a per-item FP already names its single item so it is kept as-is"; the code expands it across the package's whole item list, and the code is what the directorate has been seeing (SR/52/2026: one forfeited row, three appeal rows).

⚠️ **A dead `ref.watch` is still a fetch.** The Valuation scaffold watched the six-level feed query and never read it; `allForfeitedMapProvider` fetched every forfeited package with every item and nothing watched it at all.

⚠️ **Three things must never be derived from a page**: a year dropdown (a year not listed reads as records that no longer exist), re-tender detection (a sale looks new because its predecessor sat on the page before), and any "N of M" count.

⚠️ **Rewriting a whole view to add one column is exactly when a `where` clause goes missing** — postgres/44 re-asserts all four rules it inherits from /38 before it will apply.

**Remaining unpaged** (measured, low impact): Central Disposal's Forfeited Packages (82ms) and Destruction Disposal (25ms) screens, Warehouses (164ms `getAllItemAppealOutcomes`), three spots in Admin. Small tables (taxes 4 rows, committees 8, proposals 10) need no paging.

## The last four pages — and the multi-item bleed guard that never fired (2026-09-07)

| page | before | after |
|---|---|---|
| Warehouses | 381ms | **102ms** |
| Forfeited (yard) | 163ms, **no pager at all** | **74ms**, paged |
| Admin activity log | 344ms (a YEAR of rows) | **45ms** (166 → 20) |
| Destruction (yard) | 56ms | 54ms (39 rows; the shape, not the clock) |

New views: `item_appeal_outcomes` (47), `warehouse_rows` (48), `forfeit_rows` (49), `destruction_summary` (50).

**Officers & Admins deliberately left alone** — 11 profiles at 51ms, where a pager is chrome rather than a saving.

### The two real bugs

⚠️ **Warehouses was the Destroyed Goods mistake in THREE places at once.** The row filter read `packageDataProvider(e.packageId)` per entry, the row builder read it again, and the header counted its four figures by reading it twice more inside nested loops — a facility of 75 entries fired the same per-package fetch **four times over**. 52 packages: **249ms as separate calls, 46ms as one**. *Paging a table does not page what its cells fetch* — worth checking every time a table is paged.

⚠️ **`getAllItemAppealOutcomes` could not resolve the rule it was applying.** `appealDecisionForItem` needs the package's ITEM COUNT to know whether a package-level decision may stand in for a missing per-item one — and `select('*')` embeds no package, so `packageDetails` was **always null** and the multi-item guard **could never fire**. A decision on one item reported every sibling decided, on four screens. postgres/47 carries the guard.

⚠️ It is deliberately **not** the Appeal portal's `appeal_rows`: that view is `source = 'forfeit'` only, while a ruling can exist against detained, abandoned and other goods too — **65 of them on the live data**, which would have vanished from those four screens. A view built for one portal's feed is not a general answer.

### The Forfeited port (the largest)

122 lines of row-building Dart into `forfeit_rows`: the row-per-forfeit-EVENT rule, package-level coverage, the appeal-lifecycle exception to the final-disposition cut, `'other'` being terminal with or without a note, the legacy summary row and its pending-ruling exception, plus **three separate ways a record leaves the table** that lived in the service rather than the row builder (tendered, sold/destroyed, requested — the last keyed on the *originating* package and item, because a request stores a row that may be synthetic).

⚠️ Its comment said one thing and its code another, again — and **the code is what the officers have been seeing**. Transcribe from the code, then check row-for-row before deleting it: 48 rows either way.

### Now fully paged in SQL

Every portal. Top Management (6 tabs), Central Disposal (16), Valuation (3), Appeal (2), ICT logs, and the yard's Financials, Warehouses, Forfeited, Destruction, Tender Sale and disposition pages. What remains unpaged is small by nature — taxes (4 rows), committees (8), proposals (10), profiles (11), warehouses (4).

## Committees & proposals: the size was not the problem (2026-09-07)

Asked whether the 8-row committees and 10-row proposals tables needed paging — they are fed by **all 28 yards**, and a committee is appointed for every package that survives four tender rounds, so the concern was right. But **how the rows read them** turned out to be the real cost, not the tables.

⚠️ **Four cells each fetched their OWN row's figures.** `_UnsoldValuationCell`, `_LatestValuationCell`, `_ReTenderStatusCell` and `_BidsCell` all read `tenderRevaluationsProvider(fpId)` / `tenderBidsProvider(fpId)` inside `build` — twenty rows, twenty round trips **per cell**. Top Management's committee tab did the same. And `tenderCommitteesProvider` / `unsoldProposalsProvider` were used as **lookups** (one `[fpId]` per row) while fetching every committee and ruling in the country, from **six separate places**.

**512ms per-row → 151ms page-wide** (and the page-wide figure *includes* committees and rulings, which the per-row one does not).

`TenderPageScope` (a new widget, same shape as `DestructionExpenseScope`) carries the page's ids. ⚠️ The three helpers **fall back to the single-package providers when there is no scope** — these cells are also built inside dialogs, and one showing nothing there would be a blank where a valuation belongs.

⚠️ **One definition of the family key.** `TenderPageScope.keyFor` delegates to `packageKeyOf`: two copies of "sorted, de-duplicated, pipe-joined" is two chances for a key built in the widget to miss the cache filled by the provider — and the symptom is a page that fetches twice and merely *looks* slow.

### ⚠️ The ordering bug the port uncovered

**Bids entered together carry the SAME `created_at` to the microsecond, and Postgres promises no order between tied rows.** The same two amounts came back **swapped from one read to the next** — and the edit dialog seeds one text field per bid in exactly that order, so an officer could reopen a round and find their figures rearranged. All four queries now break the tie on `id`; the page-wide pair also order by `forfeited_package_id` first, or one package's rows interleave with another's.

**This is the third time a per-row provider watch has been the real cost** — Destroyed Goods, then Warehouses (three places at once), now the tender tables (six). When a table is paged, grep its cells for `ref.watch(...Provider(` before calling it done.

## Network & database security: the code was fine, the server is not (2026-09-07)

Asked to enforce TLS, prove there is no SQL injection, and restrict where the database accepts connections from. The audit came back **the opposite way round from what the ask assumed**: the Dart layer was already sound, and every real finding is server configuration on the live machine.

### SQL injection: nothing to fix

All 198 call sites go through `PgQuery`, and **every value is a bound `@p` parameter** — `eq/neq/gt/like/in/contains`, all insert/update/upsert values, and each leaf of an `or()` group. There is no hand-written SQL anywhere: `PgDatabase.query/execute` is unreachable outside `lib/core/db/`.

Three things ARE interpolated, because **Postgres cannot bind an identifier** — it is syntax, not data. Column and table names go through `_quoteIdent`/`_quoteRel` (verified: `id"; drop table packages; --` comes out as one harmless quoted name), aliases are counter-generated, and `is`/`in` emit `null`/`true`/`false` as keywords chosen by a `switch`, never user text.

⚠️ The one genuine gap was **`rpc()`**: it must write `name => @name`, and the `name =>` half cannot be a parameter, so the function name and every argument NAME were pasted in unvalidated. No call site passes anything but a literal, so nothing was exploitable — but that is a property of the callers, not of the code. Both are now checked against `^[A-Za-z_][A-Za-z0-9_$]{0,62}$` and **rejected rather than escaped**, and `_qualify` no longer builds `"schema.fn"` as a single quoted name.

### TLS: the check has to come before the socket

`PgConfig.enforceTransportPolicy()` runs in `_open()` **before connecting** — a plaintext connection to a remote host has already sent the password by the time the first query runs.

Three states, not two: plaintext to **localhost is not a finding** (nothing crosses a wire, and warning there just trains people to ignore the warning that matters); unverified TLS to a remote host is one; plaintext to a remote host is the serious one. New `PG_REQUIRE_TLS=true` turns it into a start-up failure; the default stays warn-only so existing LAN installs keep working.

⚠️ **`SslMode.require` encrypts but accepts ANY certificate.** Only `verifyFull` defeats a machine in the middle. Traffic that "is TLS" can still be read end to end.

### The updater was the sharpest network surface

The appcast decides which installer the app downloads **and runs** — over HTTP that is remote code execution, not eavesdropping. `isUpdateFeedAcceptable` now allows `https://` always, `http://` only with an explicit opt-in AND a private-range host, and a public `http://` URL never.

### ⚠️ Three open findings, all server config

1. **The app connects as `postgres` — a SUPERUSER, and superusers bypass RLS.** All 112 policies are currently decorative, including the `officer_signup_otps` deny-all lockbox. A `yard_app` least-privilege role is written out in `postgres/SECURITY.md`.
2. **`pg_hba.conf` uses `trust`** on lines 117–126: no password is checked at all, so any process on the box connects as superuser by asking. `PG_PASSWORD` is not being verified.
3. `ssl = off` on the server.

None is remotely exploitable **only because `listen_addresses = localhost`**. That single setting is what is holding all three up — all must be closed before the database accepts its first network connection.

⚠️ **`officer_signup_otps` has RLS on with ZERO policies, and that is correct** — no policy means RLS denies everyone, making it a lockbox only a bypassing role may read. An audit that flags "no policies" as a gap is wrong here; the failure to catch is RLS being switched **off**. `tool/audit_network_security.py` knows the difference, and its first three SQL "findings" were false positives worth fixing in the checker rather than reporting.

## Client-side hardening: print() was the whole problem (2026-09-07)

Asked to remove hardcoded secrets, silence release logging, and set up obfuscation. **Secrets were already clean** — `AppEnv` had moved everything to `.env`/`--dart-define` back in August, and a scan for JWTs, API keys, tokens and credential-bearing URLs found nothing. The real finding was **logging**.

### ⚠️ `print()` is NOT stripped from a release build

40 bare `print()` calls were writing to stdout **in the shipped .exe**, exactly as in debug. Several carried real user data:

- `services.dart:161` — **the e-mail being signed in with**
- `main.dart:355` — **the signed-in user's id**
- `services.dart:210` — auth failure code/status/message
- `router.dart:55` — every navigation with login and admin state

On a shared office PC that is a log of who signed in and when, for anyone who starts the app from a console.

`lib/core/app_log.dart` is now the only way app code logs. `AppLog.debug` is **compiled out of release**; `warn`/`error` print the developer's message in release but **drop the `error:` payload** — an exception's `toString()` is how a record leaks without anyone intending it, because a Postgres error quotes the row it rejected and an auth error quotes the address. `AppLog.security` stays in release on purpose: an admin asking "why is auto-update off" needs that line in the build they run.

⚠️ **The guard is `kReleaseMode`, not `kDebugMode` — they are not opposites.** A profile build is neither, and profile is what performance work runs on; keying off `kDebugMode` would silence exactly the build someone is measuring.

### Obfuscation — verified, not assumed

`tool/build_release.ps1` runs the secrets audit **first** (obfuscation hides names, not strings — a hardcoded password is just as readable in an obfuscated binary), then builds with `--obfuscate --split-debug-info=build/symbols/<version>`.

Built it and checked the output rather than trusting the flag: `AuthService`, `PgQuery`, `AuditLogService`, `kGmailAppPassword` all return **0 hits** in the shipped binary, and the 5.5MB symbol file (an ELF debug table, so `strings` shows nothing — read it as bytes) still holds them 49/115/25 times. So `flutter symbolize` will work, **but only against the matching version's symbols** — which is why they are filed per pubspec version and must be archived with the installer.

### ⚠️ Two checker bugs worth remembering

`line.split('//')[0]` to strip a Dart comment **also truncates every URL at its scheme** — `https://x.supabase.co` became `https:`, silently blinding the scanner to the two findings it most needed to make (a project URL, and a password inside a connection string). Fixed with a quote-aware `strip_comment`. **Always plant a fake secret and confirm the scanner sees it** — 5 of 6 probes were caught, and the 2 misses were only visible because of the probe.

The obfuscation check also flagged one script four times, judging per LINE when a build script legitimately spreads the two flags across an argument array and mentions `--obfuscate` again in its docs. Judge per FILE.

`PG_PASSWORD` still defaults to `'postgres'` — removing it would break every local install, so `usingDefaultPassword` reports it and release builds say so out loud.

## User-level security: the bypass, the 14 rules, and the RPC that asked nothing (2026-09-07)

Third security pass — MFA, passwords, RBAC. One real hole, one real weakness, and RBAC that turned out to be genuinely sound.

### ⚠️ `kDevSkipOtp` was one line from shipping a 2FA bypass

`const bool kDevSkipOtp = false;` with a comment saying "flip back before shipping". A comment is a note, not a control — set it true and every privileged portal (Disposal, Valuation, Appeal, Executive, ICT) signs in on password alone, and **nothing in the built `.exe` would say so**.

Now `_devSkipOtpDefine && !kReleaseMode`: a release build **cannot** skip OTP whatever the source says, and skipping it needs `--dart-define=DEV_SKIP_OTP=true` — something typed for one build, not a state the repo can be committed in.

⚠️ `kReleaseMode`, not `!kDebugMode` — **profile builds are neither**, and would have kept the bypass.

### ⚠️ The weakest password rule was the server's

14 screens each carried their own `length < 8`; the forgot-password panel still allowed **6**; and `auth.sign_up` / `auth.change_password` accepted **anything over 5**. Client validation is a courtesy — both functions are reachable as RPCs — so **the rule that actually applied was the weakest one, on the server**.

`public.password_policy_violation()` is now the single definition (12+, upper/lower/digit/special, no common word, 128 max because **bcrypt only hashes 72 bytes** — refuse rather than silently truncate). `PasswordPolicy` in Dart mirrors it, and a test pins the mirror to the migration so they cannot drift. All 14 call sites now delegate.

`change_password` also **refuses the current password** — otherwise a 90-day prompt is satisfied by retyping the same one, resetting the clock and changing nothing.

Rotation already existed client-side; `password_age_status()` now answers server-side too. ⚠️ SQL warns from **day 83** = 90 − 7, matching `ProfileModel.passwordWarnDays`. Change one, change the other.

### ⚠️ `disposal_toggle_outcome_delivery` — SECURITY DEFINER, granted to `public`, no caller check

It marks goods handed over **and closes the warehouse entry**, and asked nothing about who was calling. **SECURITY DEFINER means RLS does not apply inside it**, so any account — `public` includes `anon` — could release any consignment in any yard. Its own comment claimed "same shape as disposal_toggle_delivery_status"; that sibling checks, this one never did.

Fixed with the sibling's exact guard and granted to `authenticated`. **Verified live in a rolled-back transaction**: wrong-yard officer → `not authorized`; Central Disposal → allowed.

Otherwise RBAC is sound: 19 SECURITY DEFINER writers, every non-exempt one re-verifying the caller. Screen-level hiding (16 screens) is cosmetic and the DB re-checks independently.

### ⚠️ Three more checker bugs — migrations redefine functions

The audit reported 5 false failures because it read **every** definition of a function instead of the **last**. `04_auth.sql` still holds the original `sign_up`; migration `52_` replaces it. Files apply in name order, so **last definition wins** — the live DB agreed with 52 while the checker was quoting 04. Same trap hit the RBAC scan and the "weak length rule" check.

Also: `update\s+\w` matched the word "update" inside `password_updated_at`, flagging two read-only `select` functions as unguarded writers — a function declared `stable`/`immutable` **cannot** write, so check that first. And anchoring "stale password rule" on the word "pass" within 200 characters matched `parts.length < 3`.

**Verify a clean audit by breaking something on purpose** — flipping `kDevSkipOtp = true` and planting a weak rule both got caught.


## The audit trail could be rewritten by the people it audits (2026-09-07)

Fourth security pass — tamper-proof logging and backup readiness.

### ⚠️ `audit_logs` had `FOR ALL`, so officers could edit their own trail

`audit_logs` sat in the **generic list of yard-scoped data tables** in `02_schema.sql`, so it received the same policy as `packages`:

```sql
create policy yard_all on public.audit_logs
  for all using (yard = auth_user_yard()) with check (...);
```

**`for all` includes UPDATE and DELETE.** Any officer could edit or delete the audit rows for their own yard — including the rows recording what they had just done. A trail whose subject can rewrite it is not evidence.

Now: only `audit_insert` and `audit_select` policies exist (no policy for a command = denied), plus `force row level security`, plus revoked grants, plus triggers.

⚠️ **The triggers are the only layer that actually holds today**, because the app connects as superuser `postgres`, which bypasses RLS *and* grants. The policies are defence in depth for when the app moves to `yard_app`.

### ⚠️ Three holes found only by ATTACKING it, not by reading config

1. **TRUNCATE fires no row triggers and is not a DELETE.** With the UPDATE/DELETE row triggers in place, `truncate audit_logs` **succeeded** as superuser — one statement, whole table gone. Needs a separate `before truncate ... for each statement` trigger.
2. **Impersonation.** The `audit_insert` policy says "only as yourself", but a superuser ignores policies: acting as a signed-in officer, an insert naming **another user's id was accepted**. The rule had to be restated in the insert trigger.
3. **Logging a failed login broke logging IN.** `audit_logs.user_id` is an FK to **`profiles`**, not `auth.users`. An auth user with no profile row violated it, and since the insert runs *inside* `record_failed_login`, the violation propagated out and **failed the whole sign-in attempt**. The FK column is now left null when no profile exists; `entity_id` (plain text, no key) keeps the real id.

**Read the attempt, never the configuration.** `pg_policies` and `information_schema` both say nothing useful about a superuser.

### Two event classes were never reaching the log

- **Failed logins: literally zero rows.** `record_failed_login` incremented a counter and locked the account but wrote nothing — a brute-force attempt left no trace beyond a counter that clears on the next success. Now logs every attempt with count + client IP, the lockout at attempt 5, and **attempts against non-existent e-mails** (address-guessing is exactly what a trail should show).
- **Role changes.** Changed by plain `UPDATE`s on `profiles` from several screens — no single call site to instrument. An `AFTER UPDATE` **trigger** catches role/is_active/yard/directorate with before/after values, **including edits made directly in pgAdmin**, which is the case that matters most. Records `auth.uid()` — *who did it*, not who it was done to; a null there means a direct DB edit, itself worth seeing.

Every row now carries `client_addr` (from `inet_client_addr()`), `app_name`, `db_user`, stamped by a trigger so it can be neither forged nor forgotten.

Retention (`purge_old_audit_logs`, 365 days) is the **one** sanctioned deletion, via a txn-local `app.audit_purge` flag the trigger recognises — and **it logs its own run**, so a gap has a matching entry instead of looking like tampering.

### Backups: restore actually tested, not just documented

`tool/backup_database.ps1` — `pg_dump -Fc`, then **`pg_restore --list` over every file it writes** (catches a truncated archive, the failure that stays invisible until it matters) and asserts `audit_logs` is in it. Retention deletes **last**, after the new dump verifies.

⚠️ **`pg_dump` is NOT on PATH here** — PostgreSQL 18.6 was unpacked to `C:\pgsql-extract\pgsql\bin`, not installed. A scheduled task fails with "not recognized as the name of a cmdlet" and nobody reads the failed run. The script resolves the binaries itself.

⚠️ **No `--verbose`, no `2>&1`.** pg_dump writes progress to stderr, and PowerShell 5.1 wraps a native command's redirected stderr in ErrorRecords — a **completely successful dump looked like a failure**. Judge by `$LASTEXITCODE`.

**Restore drill actually run**: restored into a scratch DB → 579 audit rows, 176 packages, 11 profiles — **and the append-only protections came back with it** (triggers, policies and FORCE RLS are all in the dump; `DELETE` on the restored copy was refused). Scratch DB dropped afterwards.

⚠️ **`archive_mode = off` — PITR is not available**, so up to 24h is recoverable only to the last nightly dump. `wal_level` is already `replica`; only archiving is missing. Enabling it needs a **restart**, not a reload, and a failing `archive_command` silently fills `pg_wal` until the disk is full — the audit checks `pg_stat_archiver.failed_count`.

**Verified the audit by breaking it**: dropping the delete and truncate triggers turned 0 failures into 5.

---

## Scaling to 100+ concurrent clients (2026-09-09)

The app is a desktop client that talks **straight to PostgreSQL** — no middle tier. That one fact drives every finding below: there is no shared pool, so every PC holds its own, and the server's limits are divided between all of them.

### ⚠️ The ceiling was 11 users, and nothing in the app said so

`max_connections = 100` (stock) and the app opened **9 sockets per PC** (pool of 8 + the LISTEN connection). So:

```
(100 - 3 reserved) / 9  =  10 clients
```

The **12th user** is refused with `53300: too many connections for role` — which reads like a server fault and is pure arithmetic. It appears nowhere in testing, because one developer on one machine uses 9 of 97.

Fixed from **both ends**, and both are required:

- `PG_POOL_SIZE` default **8 → 3** ([pg_connection.dart](lib/core/db/pg_connection.dart)). Verified live: the running app holds **2 idle sockets** (1 pooled + 1 listener), 4 at peak.
- `max_connections = 400` in [postgres/63_server_tuning.conf](postgres/63_server_tuning.conf) → `397/4 ≈ 99 clients` with headroom for pgAdmin and backups.

Pooled connections now also have a **bounded lifetime** (`maxConnectionAge`/`maxSessionUse`, 10 min). Without it an all-day client reaches its peak during the busy minute and never hands those sockets back. `maxQueryCount` is **not** used — the driver documents it as not yet implemented.

### The notification storm: one click cost ~100 queries

`03_realtime.sql` announced *"table X changed"* to every listener, and all 19 callbacks respond by refetching. So one officer saving one form woke all 100 PCs, each re-running its dashboard query in the same millisecond — and **most of that work was wasted**, since a PC showing GL1 has nothing to redraw when CED changes.

[postgres/64_realtime_yard_scoped.sql](postgres/64_realtime_yard_scoped.sql) puts the **yard in the payload**, and the client drops what it isn't showing.

⚠️ **A statement-level trigger has no `NEW`/`OLD` row.** These are `FOR EACH STATEMENT` on purpose (a 500-row insert should wake listeners once, not 500 times), so the yard is read from **transition tables** (`REFERENCING NEW TABLE AS new_rows`) and the *distinct* yards touched are collected — a statement spanning two yards correctly notifies both.

⚠️ **The `REFERENCING` clause is per-operation**: INSERT has no OLD, DELETE has no NEW. One combined trigger cannot declare both, so each table gets **three** narrow triggers (54 total), still one notification per statement.

⚠️ **A table with no `yard` column notifies `yard: null`, meaning "everyone".** Filtering is a pure optimisation layered on top of correct behaviour — a missed refresh shows stale seizure data, which is far worse than a redundant query. For the same reason `watchAllYards` **defaults to true** and the five cross-yard roles (`disposal`, `appeal`, `valuation`, `executive`, `ict`) never filter; only `officer`/`admin` do — and they are the bulk of the 100 clients.

**Verified by actually listening**: a 176-row update in one yard produced **one** `{"table":"packages","op":"UPDATE","yard":"GL1"}`, and a yard-less table correctly produced `"yard":null`.

Plus a **300ms per-channel debounce** — saving one form writes several tables in one transaction, each its own NOTIFY. Per *channel*, not global, so a busy table (`audit_logs`, written by every action) cannot delay an unrelated screen.

### Indexes: `yard` was filtered 23 times and indexed nowhere

The schema indexed its foreign keys well (19, 31) but not the two columns almost every screen narrows by. `packages` had **no index on `status` or `yard`** at all.

With 200 rows a sequential scan is sub-millisecond and the planner is right to prefer it — **the cost is multiplied by clients, not rows**. [postgres/63_scale_indexes.sql](postgres/63_scale_indexes.sql) adds 19, shaped `(yard, created_at DESC)` because nearly every query is *"this yard, newest first, one page"* — that shape makes the `ORDER BY` and `LIMIT` free, where two single-column indexes would still sort every matching row.

`CREATE INDEX CONCURRENTLY`, so it runs on the live server without locking writers — which is also why the file must **not** be wrapped in a transaction.

**Verified with `EXPLAIN ANALYZE`**, not assumed: `packages_yard_created_idx` and `audit_logs_entity_idx` are chosen by the planner. Also `ANALYZE`d at the end — a new index is invisible to the planner until statistics refresh, which otherwise looks like "the indexes did nothing".

⚠️ `random_page_cost` was still **4.0** (a spinning-disk assumption). On an SSD that is the most common reason a server *ignores* a perfectly good index — it would have wasted the work above. Now 1.1.

### Parsing off the UI thread

Dart is single-threaded: UI, animation and every `fromJson` share one isolate. `PackageModel.fromJson` is the heaviest parse in the app because it is **nested** — each package also parses its items, its warehouse entries, and each entry's warehouse and officer. `reports_screen.dart` calls `getAllPackages()` **21 times** with no pagination.

[lib/core/parse_isolate.dart](lib/core/parse_isolate.dart) moves it to `compute()` **past a 150-row threshold** — below that, spawning an isolate costs more than the parse it saves, so small per-dialog reads correctly stay inline.

⚠️ Entry points must be **top-level**, and what crosses the boundary is **copied** — which is why these take raw decoded rows (cheap to copy) and not a `Connection` or `PgQuery`, neither of which can be sent to an isolate at all.

### Already fine — checked, not assumed

- **Pagination exists**: `getPackagesPaged`, `getPerishableRowsPaged` etc. page in SQL.
- **`DataTable` does not virtualize**, but **23 of 27** tables page at 20 rows via `TablePager`, so only 20 rows are ever built. The ICT Activity Logs tab is **server**-paged at 25 (`offset`/`limit`) with its own pager.

Full suite green: **1518 tests**, plus 13 new in [test/scale_100_clients_test.dart](test/scale_100_clients_test.dart) covering the connection arithmetic, the yard filter in both directions, and sign-out restoring the safe default.

## Rates & taxes moved to ICT: nobody sets the figure they are billed (2026-09-10)

The daily **storage rate** lived in the yard's Admin Panel and the **sale
taxes** in Central Disposal's own Taxes tab — each in the portal it was
charged against. Both are now one ICT page,
[lib/screens/ict/system_rates_tab.dart](lib/screens/ict/system_rates_tab.dart),
reached from the rail as **Rates & Taxes** (index 3; Activity Logs moved to 4).

The reason is not tidiness. These are **statutory figures that must be the same
everywhere**, and a rate one office can change under another's feet is not a
rate. Both source pages are gone completely: the tab, the `TabView` child, the
controller length and `taxes_tab.dart` itself, with `taxesProvider` relocated to
[lib/core/providers.dart](lib/core/providers.dart).

⚠️ `DefaultTabController` asserts the tab list and the child list match, so
dropping a tab without its child is a **runtime crash, not a compile error**.
The enum in Central Disposal *is* the controller length, so `DisposalTab.taxes`
had to go with it.

### The audit gap the move exposed

`postgres/65_storage_rate_author.sql` adds `storage_rates.set_by` and a
`set_storage_rate(p_rate numeric)` SECURITY DEFINER that refuses a non-positive
rate and any role outside `('ict','admin')`. The verify block proves **both**
guards fire. Measured against the live DB afterwards: exactly **one** signature,
no overload — `create or replace` matches on the argument list, which is how
migration 60 once ended up with four functions where it wanted two. The single
existing rate row stays `(unattributed)`; it predates the column and there is no
honest value to backfill.

Setting a rate writes an audit row, and ICT's Activity Logs sits one tab over,
so the dialog now also invalidates `ictAllOfficeLogsProvider`. This is the same
bug the yard portal had before the move — invalidating a provider nothing
renders any more refreshes nothing, and the change stays invisible until you
navigate away and back. The test that guarded it followed the page rather than
being deleted.

### Proving the tables, not assuming them

[test/ict_system_rates_test.dart](test/ict_system_rates_test.dart) renders the
tab, because `DataTable2` fails at **runtime** in two ways the compiler cannot
see: cells that do not match columns, and
`totalFixedWidth < totalColAvailableWidth`. The Sale Taxes table carries 360px
of fixed columns against one flexible column, so it is the one at risk.

⚠️ The narrow-width test was **checked for teeth**: forced to 420px it fails on
exactly that assert, and passes at 1100px. So no `minWidth` was added — it was
demonstrated to be unnecessary, not assumed to be.

Full suite green: **1520 tests**, `flutter analyze` clean of errors, release
build succeeds.

---

## Unsold perishables reached no page at all (migration 017)

⚠️ **`exhausted_unsold` can never contain a perishable, by design — and the
yard's Unsold page read only that view.** The two unsold routes are
deliberately different: normal goods arrive after **4+ failed tenders and a
committee re-valuation**, a perishable after **ONE failed Special Tender
Sale** (it is rotting; it cannot wait for the long route). The view's two
gates — `tender_count > 3` **and** a `tender_committees` row — are therefore
conditions a perishable cannot satisfy. In this database that hid **9
packages from the yard, two of which the Top Management Directorate had
already ruled on** (`destroy`, `convert`): the rulings were recorded and no
yard page could show them.

[migrations/017_unsold_includes_perishables.sql](migrations/017_unsold_includes_perishables.sql)
adds **`unsold_all_routes`**, a `union all` of `exhausted_unsold` and
`unsold_perishables` in the first view's column shape (the committee columns
are NULL on the perishable side — accurate, not missing: there was no
committee). ⚠️ Fixed with a union rather than by **loosening the gates**,
which would let a normal package through *before* its committee has valued
it — the very thing those gates exist to prevent.

⚠️ **Three views, three questions.** Top Management's two decision tabs keep
reading one route each (there the distinction *is* the tab); the yard's pages
pass `includeAllRoutes: true` and get both. `verify` in the migration asserts
the row counts add up, that **no package arrives by both routes** (it would be
paged and counted twice) and that `security_invoker` survives — without it
every per-yard policy underneath is bypassed.

⚠️ **Guarded on both sources existing.** `postgres/23` and `/32` are applied
by hand and folded into neither `02_schema.sql` nor each other, so on a fresh
database the view is skipped rather than failing the one file that stands a
new server up. Verified by replaying `01_auth_and_session.sql` + `02_schema.sql`
into an empty database with **stderr actually captured**: 0 errors, guard held.

### The duplicate row: I added a second route beside the open one (045 → 046)

⚠️ **Before adding a route into a page, check which view the PAGE reads.**
Converted Goods showed *Liquid Milk Cartons* **twice**, and marking one
Delivered marked both — they were two rows for **one `proposal_id`**, and
delivery is recorded against the **proposal**, not the row.

Migration 045 added a perishable branch to `exhausted_unsold`, reasoning that
a perishable can never satisfy its `tender_count > 3`. **That reasoning was
correct and the conclusion was still wrong:** the four Final Outcome pages
never read `exhausted_unsold`. `getExhaustedUnsoldPaged(includeAllRoutes:
true)` reads **`unsold_all_routes`** — and its `unsold_perishables` arm had
carried those rulings since 017 (the section directly above). So:

```
exhausted_unsold    convert → 2   (1 normal + 1 perishable, added by 045)
unsold_perishables  convert → 1   (the same perishable)
unsold_all_routes   convert → 3   ← what the officer saw
```

[migrations/046_undo_045_the_perishable_route_already_existed.sql](migrations/046_undo_045_the_perishable_route_already_existed.sql)
removes it. 045 is deleted from the tree, and `044`'s stranding check now
asks **`unsold_all_routes`** rather than `exhausted_unsold` — checking the
narrower view alone is precisely what made 045 look necessary.

⚠️ **Do not rebuild a wrapped view by regex over `pg_get_viewdef`.** My first
046 recovered the pre-045 body with `from \((.*)\) base`. 045's own branch
also ended in `) b2`, so the **greedy** match ran past the real closing paren.
The result still parsed, still had **18 columns**, passed **both**
verifications — and returned **zero rows**, emptying `exhausted_unsold`,
`committee_pool`, `unsold_all_routes` and `unsold_retender_pool` together. A
column count is not proof; **046 now also asserts the view is non-empty.**
The definition lives in the source files, so 046 is a guard + marker only and
is applied **after** `postgres/23` → `migrations/016` (23 drops the view,
which discards 016's `is_perishable` wrap — the same ordering trap as before).

⚠️ **Rebuilding `exhausted_unsold` means rebuilding four views.**
`committee_pool`, `unsold_all_routes` and `unsold_retender_pool` all depend on
it, so the drop fails without them. Order:
`23` → `016` → `031` → `postgres/39` → `017`.

⚠️ **`Customs_SR_DB` is nearly empty; the real data is in
`Customs_SR_DB_backup_20260914_1543`** (318 forfeited packages vs 6). A
migration verified only against the live DB proves almost nothing — every
count above came from the backup.


### Perishables are marked, not hidden
`is_perishable` (migration 016) drives both a **filter chip** and a **row
tint** on the Sold/Destroyed/Re-exported/Released tables *and* now the
Unsold + four Final Outcome pages. Both narrow **in SQL**: these pages are
server-paged, so a Dart-side filter would cut rows out of a page the pager had
already counted. The chip has **two states** — off means "all goods", never
`false`, which would hide every perishable. `PerishableFilterChip` lives in
[lib/widgets/perishable_row.dart](lib/widgets/perishable_row.dart); two copies
of one control drift.

### A settled perishable tender still reads as perishable
⚠️ The leaf was keyed to `urgentPerishable`, which goes false the moment a sale
settles **or** before bidding opens — so **decided and appealing** perishable
sales lost their only distinguishing mark, exactly where there are most cards
to scan (4 of 5 special sales here are fully decided). Split into what the
goods **ARE** (`isPerishableSale` → leaf icon, amber tint, tag, at every
stage) versus whether they need **acting on now** (`urgentPerishable` → amber
wash + 1.5px border). A settled perishable's wash greys **towards amber**
rather than to neutral, so "finished" and "perishable" are both still legible.

⚠️ The grey belongs to the **surround and the border**, not the table's fill:
header (0.07 white) < data (0.02 white) < surround. At a 0.45 muted border the
table read heavier than the card holding it — the opposite of framing.

### A filter is only offered where it can act
⚠️ The Perishable chip was put on every disposition page, and Destroyed has
**no** perishables — so left switched on the page read **"0 Destroyed"**,
which looks like the yard destroyed nothing rather than like a filter matched
nothing. `dispositionHasPerishablesProvider` / `unsoldHasPerishablesProvider`
(a `count`, so it costs no rows) now gate it per page, each Final Outcome page
asking about **its own** population — Converted has one, Auction has none.
⚠️ Asked of the DATA, never hardcoded to "Sold only": a perishable **can** be
destroyed (one is ruled `destroy` right now, simply not yet carried out), and
a hardcoded rule would hide the chip exactly when it became useful.
⚠️ A widget test that mounts one of these screens must override the provider —
an un-stubbed real query leaves a pending reconnect timer at teardown.

### Two tints that meant different things looked identical
⚠️ Forfeited Goods washes an **expired appeal window** in `dangerRed` at 4%;
the disposal tables wash a **perishable** in `warningAmber` at 6%. A red and
an orange both diluted to a few percent over white are the *same pale rose*,
so goods whose appeal had run out read as perishable. The perishable tint
keeps the colour (it marks a KIND, and sits beside ordinary rows to compare
against); expiry became a **3px left edge bar** instead — nothing else on
these pages marks a row from its edge.

⚠️ Settled-card washes are between two failures: invisible at 0.07, and at
0.30 the card read as *disabled* with its contents murky. Settled grey sits at
**0.09**, a settled perishable at **0.07 amber over 0.07 grey** — "this is a
record now", not "this is switched off".

### The 5-minute idle lock stopped appearing
⚠️ **Two correct features collided.** Locking signs the user out; signing out
rebuilds the whole `ProviderScope` to drop the previous session's cached rows
(`core/session_reset.dart`). `idleLockedProvider` was a plain `StateProvider`
— it lives *inside* that container — so one frame after the lock went up the
rebuild reset it to `false` and the lock screen vanished. The app looked like
it had simply stopped locking. **The lock's own state was stored in the thing
the lock throws away.**

The same bug, twice: `_IdleLockOverlayState._signingOut` is also inside the
scope, so it came back `false` with the lock still raised and `_onLocked` ran
again — a second sign-out, a second rebuild, a loop.

Fixes: the flag moved to a process-global `ValueNotifier` (`idleLockedFlag`)
that `idleLockedProvider` mirrors via a `StateNotifier`, so it survives the
rebuild and the new container reads the lock that is still up; `_signingOut`
became `static`. ⚠️ A global that outlives everything can **stick**, so the
overlay clears it wherever a profile exists — a profile only exists after a
successful sign-in, which is the one point where "still locked" cannot be
true. ⚠️ It also outlives a TEST: `idle_lock_test.dart` needs a file-level
`setUp`/`tearDown` reset, or a test that locks leaves the next one locked.

⚠️ The end-to-end test was **checked for teeth** — reverted to the old
in-container `StateProvider` it fails on exactly that assertion, so it holds
the fix rather than describing it.

### The lock never appeared at all — it cancelled itself
⚠️ **A bug I introduced while fixing the previous one.** The "a profile
exists, so we cannot be locked" safety net lived in the overlay's `build()`.
Locking is two steps — the flag goes true, *then* the sign-out runs — and
between them the profile is **still set**. So the very next build saw
`locked == true` alongside a profile and cleared the flag, cancelling the lock
it had just raised. The officer saw **no lock screen**: the session was
silently signed out and the router dropped them on the portal chooser. That is
the "10 minutes and it goes to the home page" symptom, and it is why fixing
the flag's lifetime alone did not help.

⚠️ **Found only by mounting the real overlay.** Every earlier test drove
`IdleLockController` directly and passed throughout — the controller was never
wrong. A trace of the real widget showed `t=315s locked=false profile=null`:
the lock fired, wiped its own evidence, and left nothing on screen.
`idle_lock_reaches_the_screen_test.dart` now mounts `IdleLockOverlay` and
asserts the **seal and "Locked after" text are actually rendered**; both tests
were confirmed to fail against the old code.

The stale-global worry was real but belonged at **launch**, not in `build()` —
`main()` now sets `idleLockedFlag = false` once, where "nobody is signed in"
is unambiguous.

### The lock came back to the portal chooser, not the portal
⚠️ `_onLocked` read `routerProvider` and navigated **after** `signOut()` — but
sign-out bumps the session epoch, which replaces the ProviderScope, so that
read reached into a container being torn down. The officer was left on the
dashboard route; once the lock lifted, the redirect saw no session and sent
them to `/`, the front door with every portal on it. The router is now read
and the navigation issued **before** the sign-out, and `_unlock` re-states the
route rather than trusting what is underneath. `lastLockedPortal` lives
outside the scope for the same reason `idleLockedFlag` does — it is read after
the rebuild.

### "Expires in 0 days" still offered Skip
⚠️ `Duration.inDays` **truncates toward zero**, so 16 hours BEFORE expiry and
16 hours AFTER it both returned `0` — the two states the number exists to tell
apart. `isPasswordExpired` read `0 < 0` and stayed false, so an account a day
past its 90 days kept the "Skip for now" button. Verified against live data:
the Disposal DC account sits at **-0.676 days** and was skippable.
`isPasswordExpired` now compares the **instant** (`passwordExpiresAt`), and
`daysUntilPasswordExpiry` floors toward the past so -0.7 reads as -1.
`_skipPasswordChange` re-checks in all four directorate portals — hiding a
button is a hint, not a rule, and expiry can cross while the form sits open.

### The 90-day rule is now enforced by the DATABASE (migration 018)
⚠️ **Rejecting the sign-in is not the fix** — a password is changed from
*inside* a signed-in session, so refusing the sign-in would permanently lock
out exactly the people it is meant to prompt. Instead the sign-in **succeeds
into a state where only the password change works**.

`auth.uid()` is the root of the authorization model, so an expired session
makes it return NULL and every RLS policy denies it. ⚠️ **`auth.uid()` is not
the only root**: 13 policies ask `auth.role()` instead (`"Officers can view
all packages"` is just `auth.role() = 'authenticated'`). With only `uid()`
gated, a locked session **still read all 176 packages and 320 forfeited
packages** — found by testing, not by reading. `auth.role()` now returns
`'anon'` for an expired session too.

⚠️ The age is **not** looked up inside `auth.uid()` — it runs once per policy
per row, so a `profiles` lookup there would put a query on every row of every
screen. `auth.begin_session(id, role)` computes it once per connection into
`app.password_expired`; `auth.uid()` stays a session-variable read. The client
calls that function instead of `set_config`, so **it cannot decide its own
verdict**.

`auth.change_password` keeps working because it is SECURITY DEFINER and takes
the user id as an **argument** — it never calls `auth.uid()`. ⚠️ That is also
the hole it opens: a locked session could aim it at someone else's id, so it
is now wrapped to require `app.current_user_id = p_user_id` (the original body
is copied to `change_password_unchecked` by `pg_get_functiondef`, never
retyped). ⚠️ And the pool must be dropped after a change — `setCurrentUser`
cannot notice, the user id is unchanged, so idle connections keep
`password_expired = on` and would lock the officer out of the app they just
fixed.

⚠️ **A portal that can sign in must be able to change.** The yard and admin
screens had no password stage at all, and ICT's `_passwordStage` was never set
to true anywhere — its change form was unreachable. All three would have been
dead ends. `MandatoryPasswordChangeDialog` (not dismissible; backing out signs
out) now covers them, and a test asserts all **seven** portals both notice
expiry and offer a way out.

⚠️ **Four accounts are already past 90 days** — three yard officers and the
Disposal DC — and will be locked to password-change-only on next sign-in.
Verified end-to-end against the live database: locked = 0 rows everywhere,
change permitted, cross-user change refused (42501), full access restored
after; a healthy account (ICT, 78 days) is completely unaffected. The test
account was restored to its original hash and timestamp afterwards.

### 018 was too complete — it locked out the escape route (migration 019)
⚠️ **The app learns a password has expired by READING THE PROFILE**
(`isPasswordExpired` is computed from `password_updated_at`), and 018 blocked
exactly that. `finishOtpLogin` does
`from('profiles').select().eq('id', user.id).single()` — which returned **zero
rows**, so `.single()` threw and the login screen showed the generic *"Sign in
failed. Please try again."* The officer never reached the password-change
dialog, and the OTP they had just spent was gone. **Two dead ends, both of my
own making:**

1. `profiles_expired_self_read` now lets a locked session read **one row —
   its own**, and only while the expiry flag is on. Written against
   `auth.session_user_id()` (a new function reading `app.current_user_id`
   directly), because `auth.uid()` is precisely what is null here. Kept
   separate from `auth.uid()` on purpose: they answer *"who may act"* (nobody)
   versus *"whose session is this"* (still truthful). Verified as `yard_app`:
   1 own profile, **0** other profiles, **0** packages/warehouses/tenders.
2. A locked session **cannot write its heartbeat**, so `last_seen_at` goes
   null and `SessionSecurityPolicy.isExpired` treats null as long gone —
   signing the officer out on the next route redirect. `verifyUserSession`
   now skips the 30-minute idle rule while the password is expired. Nothing is
   lost: a locked session can already do nothing but change its own password.

Client-side `isPasswordExpired` also fixed: `Duration.inDays` **truncates
toward zero**, so 16 hours before and 16 hours after expiry both read `0` and
`0 < 0` stayed false — the Disposal DC account sat at **-0.676 days** and was
still offered "Skip for now". It now compares the **instant**.

### The form promised 8 characters and the validator demanded 12
⚠️ Four directorate login screens carried `helperText: 'Minimum 8
characters'` and ICT's field was labelled `New Password (min 8 chars)`, while
`PasswordPolicy.violation` rejects anything under **12** plus upper, lower,
digit, symbol and no common word. The form told the officer to do something
it would then refuse — the classic cost of a second, hand-written copy of a
rule.

`PasswordPolicy.rules` is now the single source: a list of
`(label, isMet)` pairs that generates the on-screen checklist, drives the
bar, and is asserted to agree with `violation()` on 17 sample passwords.
`allRulesMet()` and `isAcceptable()` can never diverge.

`lib/widgets/password_strength_field.dart` holds three widgets used by **all
17 password surfaces** (7 logins, 8 signups, 2 profile dialogs, forgot-password
and the mandatory dialog — a test enumerates them, because a new screen is
exactly where this gets forgotten):
- `PasswordRequirements` — the rules **above** the field, each ticking green
  as it is met, so the reader sees which one is outstanding rather than being
  told one at a time. Icon *and* colour change: a red/green pair alone is
  unreadable to the commonest colour blindness.
- `PasswordStrengthBar` — red, filling by *rules met*, green only when the
  form will actually accept it. ⚠️ Driven by the rule count, **not**
  `PasswordPolicy.strength` (a 0-4 opinion): filling a bar to the end and then
  rejecting the password is worse than showing no bar.
- `PasswordMatchBar` — fills only on an exact match, and says nothing at all
  about an untouched confirm box.

On the optional change surfaces (both profile dialogs) the checklist appears
only once typing starts — blank means "keep the current password", so unmet
rules on an untouched form would read as an error blocking an unrelated edit.

⚠️ A test greps `lib/` for the literal strings `Minimum 8 characters` and
`min 8 chars` outside comments, so the contradiction cannot come back.

⚠️ **The maximum is in the SAME rule as the minimum** — "Between 12 and 24
characters" — so going past the ceiling un-ticks the line that the minimum
ticked and the bar returns to red. A separate max rule would have let the bar
sit green while the form quietly rejected the password. Typing is deliberately
NOT capped with a field `maxLength` — that stops input with no explanation,
where the red bar says why.

⚠️ **24, not 128** (migration 020). The old ceiling was a limit on what the
ALGORITHM can hash — and it sat *above* even bcrypt's own 72-byte truncation,
so it could never fire: an officer would have had to enter 129 characters
correctly, twice. A limit nobody can reach is not a limit; it only made the
requirement line read as noise. 24 rather than 20 so a three-word passphrase
still fits. ⚠️ No account is affected — passwords are bcrypt hashes, so the
original length is unknowable and unchecked at sign-in; the rule applies only
when a NEW password is set. ⚠️ `PasswordPolicy.maxLength` and
`password_policy_violation` are the same rule written twice and must move
together; a test now pins the number AND compares the app's message
word-for-word against verdicts captured from the live database.

⚠️ **The checklist must not be inserted with a bare `if`.** On both profile
dialogs `if (...) ...[` added two children above the password field on the
first keystroke; the field lost focus and typing stopped until the officer
clicked back into the box. Fixed with a slot that is always in the tree whose
contents change. A widget test of this is useless — `tester.enterText`
focuses the field itself, so it passes against the broken code too — so the
guard is a source check on the shape that was changed.

### The officer-post vocabulary was renamed throughout
The old list (Officer / DC "Deputy Commissioner" / SDDC) did not match the
service. Now:

| Where | Posts |
|---|---|
| Yard Administration | **SDDC**, **DC** — Senior Deputy / Deputy Director of Customs |
| Yard Staff | **SC**, **DSC**, **ASC** — Superintendent of Customs and its deputy and assistant grades |
| Top Management | **DGC**, **ADGC**, **SDC**, **DC** |
| Disposal / Appeal / Valuation | **DC**, **SDDC** only |
| ICT | DC, SDDC **plus System Administrator** — the one directorate with a third post, because somebody has to provision the accounts |

⚠️ **A yard holds no plain DC — the post is DDC.** The key is still `dc`
(three live accounts store it in `profiles.job_role`), but the label and short
form read **DDC (Deputy Director of Customs)**. A plain DC belongs to the
directorates. The `SDDC / DDC` pair also replaced `DC / SDDC` across ~24
user-facing strings in the admin portal, ICT console, home screen and package
dialog; the remaining `DC / SDDC` mentions are directorate comments and are
correct as they stand.

### The password-expiry step is a STAGE on every portal, not a modal
⚠️ Three portals (yard, admin, ICT) opened `MandatoryPasswordChangeDialog`
while the four directorate portals drew the step inside their sign-in panel —
so the same moment in the same flow looked like a different product depending
on which door the officer came through. A modal also reads as an interruption
to something else, when it **is** the sign-in and there is nothing behind it
to return to.

`lib/widgets/password_expired_stage.dart` now serves the yard and admin
screens, and ICT uses its own `_passwordStage` (which already drew the form —
it had simply never been switched on). The stage **replaces** the credentials
form rather than covering it: those credentials have already been accepted,
and leaving them visible invites the officer to try them again. The dialog is
deleted.

### 🔴 Abandoning the expiry step let you in WITHOUT a password
⚠️ **The worst bug of this whole sequence.** The password-expiry step runs
*inside* a live session — `signInWithPassword` has already succeeded by the
time the officer is asked for a new password, and that is precisely what makes
the change possible (migration 018). So pressing the back arrow left a real
session behind: `supabase.auth.currentUser` set, `currentProfileProvider`
populated. The router then saw "logged in" on a public page and **delivered
the dashboard with no password ever entered**, bypassing the 90-day rule
entirely. Observed: a Central Disposal account backed out of its expiry screen
and landed in a **yard** dashboard with no profile shown.

Two layers, because the back arrow was only one exit:
1. `core/abandon_sign_in.dart` — every one of the seven portals now ends the
   session *before* navigating away. Order matters: navigating first lets the
   redirect run against a session that is still live. Cheap on an untouched
   form (it checks for a session first), and it clears the local profile even
   when the sign-out throws.
2. **The router** refuses an expired password on any route — a public page
   drops the stale session rather than letting it authorise the *next*
   navigation. Placed there, not in `verifyUserSession`, which must keep
   tolerating an expired password or the change form becomes unreachable.

Four live accounts sit on this path today (Disposal DC + three yard officers).

### Back goes BACK
⚠️ All 16 `AuthBackButton`s navigated to a hard-coded route — the portal
chooser, or a sign-in page — so an officer who reached a screen from somewhere
else was thrown out to the front door instead of to the page they had just
left. The arrow now pops history (`context.canPop()` → `context.pop()`) and
falls back to a named route only when there is nothing to pop (a fresh launch,
a deep link, or a `go()` that replaced the stack).

⚠️ The seven LOGIN screens keep an `onPressed` — not to pick a destination but
because leaving a half-finished sign-in must `abandonSignIn` first. Popping
alone would leave the expired session alive, which is the hole above.

⚠️ **A stage is not a route.** The OTP and password-expiry steps are
`setState` stages of ONE screen, so `canPop()` is false there and the arrow
fell straight through to the portal chooser. From a stage, back now means
**back to the credentials form**; only from the form itself does it leave the
screen — and it signs out either way, because the expiry stage runs inside a
live session.

### The Sign In link sat above the form
The signup screens put "Already have an account? Sign In" right under the
subtitle, while the sign-in screens put "Create Account" **below** the button
with a divider. The pair is one choice seen from two sides, so it belongs in
the same place on both; above the fields it read as a warning before the
officer had done anything. Moved, and it now disappears once the OTP stage
begins, exactly as the sign-in version does.

### The dropdown menu opened outside the field's border
⚠️ The menu was anchored to the widget's render box — which is the `InkWell`
around an `InputDecorator`, and **the decorator includes the helper line under
the box**. So `size.height` carried that line and the menu opened below it,
visibly detached from the border. `_fieldBoxHeight()` walks to the nearest
`InputDecorator` and measures its own box, falling back to the full height for
the chip variant that has no decorator at all.

### The Position dropdown did not match the fields under it
`StyledDropdownFormField` defaults to `isDense` with 12px vertical padding
while a plain `TextFormField` on the same form takes Material's roomier
default — so it sat visibly shorter than every box below it. The five
directorate signups now pass `isDense: false` and 16px.

⚠️ Its hover wash also covered the **helper text**, so the gap below the field
appeared to shrink as the cursor arrived: the `InkWell` wraps the whole
`InputDecorator`, and the decorator includes the helper line *under* the box.
An InkWell cannot be clipped to part of its child, and the field does not need
the wash — it already has a hover cursor and a focus border, exactly like the
fields beside it. ⚠️ **The fix is moving the HELPER LINE, not the ink.** Three attempts, two
wrong:
1. transparent `hoverColor`/`focusColor` — the tap ripple still washed the
   helper line;
2. all four ink colours transparent — the grey went, and so did the click
   animation, which was never what was asked;
3. InkWell inside the decorator's `child` — the ripple shrank to the value
   text alone, missing the icon, arrow and padding.

The ripple must cover the whole box, and **only the decorator knows that
shape** — but the decorator also draws the helper line beneath it. So the
helper text is taken off the `InputDecoration` (`helperText: null`) and
rendered as a sibling below; the decorator is then exactly the box, and the
InkWell around it ripples across exactly the box. ⚠️ `errorText` had to move
with it, or the message would draw twice — `error: SizedBox.shrink()` keeps
the red border without the text.

Verified by widget test, not by eye: **ink = decorator = 51px, ink width =
field width = 800**, while the whole widget is **74px** — so the helper line
sits outside the ink. A tap over the prefix icon still opens the menu, and the
helper text still renders.

⚠️ The file's other two InkWells are left alone — the chip variant wraps only
a Container (no helper line) and the menu-item one is inside the popup, where
a splash is exactly right.

(The "Sign In" link on every signup screen was already present and correctly
routed — `auth/signup_screen.dart` is the only one without it, and it is dead
code, routed from nowhere.)

### Yard-staff labels follow the posts
The chooser said **SC / DSC / ASC** while the sign-in behind it still said
"Officer Sign In" and "Officer Portal". Both now name the grades; the signup
screen reads **Yard Staff Sign Up**.

⚠️ **The KEYS did not change, only the labels.** `profiles.job_role` holds
`dc`/`officer` and directorate accounts are keyed by username (`DG`, `ADG`,
`VDC`). Renaming a key would orphan the live account carrying it — so `DG`
still keys the row that now renders "DGC (Director General of Customs)".

⚠️ **`officer` survives as a legacy key.** It is still in `kPostTitles` and
`kPostRoles` so the three live accounts holding it keep a title, but it is
absent from `kAssignablePostKeys`, so ICT cannot hand it out any more. The Add
dialog offers only assignable posts; **Edit and the role filter still walk the
full map**, or an account on a legacy post would show a dropdown with no
matching value and be silently re-posted on save.

No migration needed: `profiles` constrains only `role` (admin/officer/…), and
every new post maps onto an existing one via `kPostRoles`.

Also corrected: "Executive Sign Up" → **Top Management Sign Up**, and the
Appeal signup subtitle which claimed "one for AD and one for ADD" while its
picker offered DC/SDDC.

Full suite: **1726 passing**, 2 skipped, 20 pre-existing failures in six files
(unchanged baseline). `flutter analyze` clean of errors; clean schema replay
(0 errors, stderr captured); release build succeeds.

---

## Deploying over the internet (static IP + port forwarding)

Much of this was already built — `PG_SSL`, `PG_SSL_VERIFY`, `PG_REQUIRE_TLS`,
`transportWarning`, `enforceTransportPolicy`, timeouts and a 2-retry
`_withNetworkRetry` used by 228 call sites. Three genuine gaps were closed.

### A CA certificate, or verification is unusable
⚠️ An office server behind a static IP has a **self-signed** certificate —
nobody issues a public one for `203.0.113.10`. `SslMode.verifyFull` then
checks the chain against Windows' trust store, which has never heard of it, so
every connection fails; the usual "fix" is to turn verification back off,
re-opening the man-in-the-middle hole the setting exists to close.

`PG_SSL_ROOT_CERT` names the CA, `SecurityContext.setTrustedCertificates`
loads it, and it is threaded into **both** `ConnectionSettings` and
`PoolSettings` — the app runs on a pool, so a context on the single-connection
settings alone would leave every pooled connection unverified. Built **once**
and cached: the pool opens a fresh connection whenever it grows or retires one.
A relative path resolves beside the executable, so `PG_SSL_ROOT_CERT=ca.crt`
works on an installed copy. ⚠️ A path that does not resolve is now a stated
`transportWarning`, not a silent fall-back to the OS store — otherwise the
error names the TLS handshake rather than the file that is wrong.

### PG_HOST survives what people actually paste
A branch office is configured by someone pasting into Notepad. `_normaliseHost`
strips a scheme, a `user:pass@`, a `/database`, a `?query` and a trailing
`:5432`, and **brackets a bare IPv6 literal** — ⚠️ counting the colons first,
because stripping at the first one would leave a fragment that resolves to
nothing. `PG_HOST=` (set but blank) falls back to `localhost` instead of
failing to resolve the empty string.

### The officer is told when the link drops
⚠️ Over the internet a dropped link looks exactly like an empty table: the
query fails, the page renders nothing, and a branch officer concludes the yard
has no packages. `ConnectionHealth` + `OfflineBanner` say so instead.

Reported from inside `_withNetworkRetry` — the one place that knows whether a
call reached the server, and the only one all 228 callers pass through.
⚠️ **Only transport failures raise it**: a permission denial is the database
*answering*, so the link is fine and blaming the network would send an officer
to check their router over a bug in the app. The banner sits **outside** the
idle lock, so a PC that drops its link while unattended still says so.

### ⚠️ The server is not ready — the client work does nothing yet
Checked on the live server: **`ssl = off`** and `pg_hba.conf` is **`trust`**
(no password at all). Harmless while loopback-only; forward that port and it is
the whole database, public. `postgres/67_internet_deployment.md` has the
ordered steps — certificate, `ssl = on`, then `hostssl` + `scram-sha-256`
(⚠️ `hostssl`, not `host`: `host` accepts a plaintext client as happily as a
TLS one). Also: forward to the branches' own addresses, never connect as
`postgres` (a superuser bypasses every RLS policy separating the yards), and
remember TLS protects the traffic, not the port.

Full suite: **1743 passing**, 2 skipped, 20 pre-existing failures (unchanged).
Release build connects to the local database exactly as before — zero
regression.

---

## The auth brand panel, redesigned

The dark half of all 15 sign-in / sign-up / password-expiry screens.

- **A drifting orb field** — three soft discs of accent light over the panel's
  near-black, on a 40s loop. ⚠️ This is the movement the panel actually has:
  the gradient alone was a six-stop ramp between two near-blacks, a change too
  small to see, which was the complaint. The eye needs something with a SHAPE
  before it registers motion.
  - ⚠️ **The loop closes, it does not reverse.** A reversing controller sends
    the orbs back along the path they just took, which reads as a rewind. They
    move on `sin`/`cos` of the value, so at t=1 every orb is where it was at
    t=0 and there is no seam.
  - ⚠️ **Periods 1 / 0.61 / 1.37 — deliberately not multiples.** On matching
    periods the three return to the same arrangement every cycle and the panel
    visibly repeats.
  - **Painted, not stacked**: a `RadialGradient` shader per orb, inside a
    `RepaintBoundary`. Three `Container`s with box-shadows would each allocate
    a layer and composite every frame, and a blur that size is an expensive
    filter to run on half the window.
  - The gradient beneath is **pulled back towards the deep colour** now that
    the orbs carry the light — two bright layers over each other muddied both,
    and the orbs had nothing dark to read against.
- ⚠️ **`_behindCrest` read from the WRONG PLACE, and it showed.** It returned
  a colour based on `primaryNavy`, which was right while every panel's middle
  was navy — but each portal now supplies its own near-black, so on the purple
  panel the middle is `#0A0F2C` while this handed the crest `#1A1764`. The
  ship and plane were painted a navy matching nothing behind them and appeared
  as two solid patches: exactly the failure the knockout exists to prevent,
  caused by its one input being read from the wrong source. Now based on
  `widget.deepColor`. ⚠️ And the gradient's stop [2] is `behind` **unmixed** —
  a blend of it would no longer be the colour the knockout is painted with.
- ⚠️ **The orbs are kept OFF the centre** for the same reason: a disc of light
  drifting behind the crest changes the real colour there frame by frame, and
  no single knockout value could match it.
- ⚠️ **Eight stops on a squared falloff, not three on a straight line.** Three
  stops made the alpha fall in two straight segments, and on near-black the eye
  picks the join out as a RING — the banding that read as stripes. A display
  has 256 levels per channel; a linear ramp spends them evenly, so the wide
  dim outer half gets far too few and each covers enough pixels to be seen as
  an edge. `(1-x)^2` concentrates the change near the centre, which is both
  how light actually falls off and where the banding was worst.
- **Crest 200 → 240**, halo 250 → 300.
- ⚠️ **Gold needed its own strength, twice over.** Gold (#D4A017) has ~2.4x
  the relative luminance of the next brightest accent and 5x the dimmest, so
  at one shared value its orbs read as lamps while purple's read as a tint —
  and the banding, being a function of how much light is ramped, showed on
  gold alone. `_brightnessTrim` scales the orb alpha by luminance (measured:
  gold **0.55**, purple **1.00**), and `_accentFloor` holds the gradient
  corner back further (gold **0.58**, the dim accents unchanged at 0.34) —
  the corner and the orbs are two sources of the same colour on one panel.
- ⚠️ **The accent filled the whole panel, and three things caused it.** At
  r = 0.5..0.62 of the panel an orb centred at (0.18, 0.16) still reaches well
  past the middle, so three of them covered everything and the accent stopped
  being light in the corners — it became the panel's colour, with the crest
  sitting on gold. Fixed together: orbs cut to ~0.3 and pushed into the
  corners; the gradient's accent confined to the last third (those two stops
  were at 0.22/0.46, now 0.08/0.24); and a **pool of the deep colour painted
  over the middle, last**. Keeping the orbs out was not enough on its own —
  they are blurred by 18px and fade over hundreds more, so their light still
  reached the centre, and the ship and plane are painted with ONE expected
  colour that cannot track a drifting tint.
- ⚠️ **A real blur, because eight stops was not enough.** The softened falloff
  removed the hard rings, but a gradient still quantises to 256 levels per
  channel and on gold the remaining steps drifted across the panel as faint
  contour lines — "waves", in the report. An 18σ blur smears each step into
  its neighbours, which removes them rather than making them finer. **One**
  `saveLayer` for all three orbs: the filter is the expensive part and it is
  the same filter.
- **A halo behind the crest**, on its own 14s controller against the
  gradient's 9s. ⚠️ Two movements on ONE clock read as a single pulse — the
  panel breathes in and out as one object, which is exactly what pulls the eye
  off the form. Different periods drift in and out of phase and never repeat a
  pattern anyone can follow.
- ⚠️ **The halo is UNDER the crest, and that is not a layout preference.** The
  ship and plane are painted with the background colour to fake transparency
  (see `kCrestKnockoutHex`); anything drawn on top would tint the disc and
  those two shapes by different amounts and they would stop reading as holes —
  the one thing the widget exists to protect.
- ⚠️ **It brightens, it does not grow.** A halo that changes size reads as
  something approaching; one that changes only opacity reads as light.
- **A hairline between the subtitle and the portal badge** — the service's name
  and the door being used are two different statements, previously stacked with
  nothing between them.

All the existing colour work is untouched: luminance-scaled accent depth, the
contrast floor that turns Yard Access's branding white, the six evenly-spaced
gradient stops, and the per-frame knockout repaint.

⚠️ **Two of my new tests were built on a false premise** and were rewritten:
`rootBundle` serves no project assets under `flutter test`, so the crest never
renders and `find.byType(SvgPicture)` finds nothing. A widget test of the
halo's z-order would have passed against either order — worse than no test —
so that one is a source check with the reason stated.

⚠️ `brand_panel_gradient_test.dart` counted the gradient's stops over a fixed
700-character window, which the explanatory comments inside the list have
since outgrown — it reported three stops for a list that still has six. It now
measures to the closing bracket.

Full suite: **1763 passing**, 2 skipped, 20 pre-existing failures (unchanged).

---

## "Remove Supabase" — there was none to remove

⚠️ **The app already used pure PostgreSQL.** It talks to the server through
the `postgres` Dart package (`lib/core/db/`); `supabase_flutter` sat in
pubspec.yaml but was **imported nowhere** — 28 transitive packages of dead
weight, now gone with no code change needed.

What looked like Supabase was naming:

- **`auth.uid()` / `auth.role()` / `auth.users`** are this project's own
  functions in a schema it creates and owns, like `public`. ⚠️ Kept under
  those names **on purpose**: all 132 RLS policies are written against them,
  and rewriting 132 access-control rules by hand is 132 chances to widen
  access silently — a wrong policy does not fail, it shows one yard another
  yard's goods.
- The only extensions are **`uuid-ossp`** and **`pgcrypto`**, both shipped
  with standard PostgreSQL.
- `supabase` survives as the *variable name* of the database handle at ~198
  call sites. A mechanical rename of that size is a poor trade against one
  silent mistake in it.

Renamed for honesty: `01_supabase_compat.sql` → `01_auth_and_session.sql`,
`lib/core/supabase_client.dart` → `db_client.dart`, and the `supabase/`
directory (128 operational SQL scripts + the schema source the build script
reads) → `db/`.

### Applied to 10.10.71.15
Database was empty (only `pg_stat_statements`). After applying: **32 tables,
6 views, 132 RLS policies, 6 auth functions**, and the four roles with only
`yard_app` able to log in. Session functions verified: signed out reads as
`anon` with a null uid.

⚠️ **One real bug found by deploying.** `migrations/010`'s "no view may bypass
the caller's policies" check scanned *every* view in `public`, including the
two `pg_stat_statements` views the extension owns — which cannot be altered
and hold no application data. On a server with that extension the check threw
and took the whole schema build down. Now excludes extension-owned views
(`pg_depend.deptype = 'e'`).

⚠️ **Six non-fatal errors remain on re-run** (`cannot change name of input
parameter`, `already member of publication`, a constraint-backed index). Each
was verified as an "already correct" complaint — the function, constraint and
23 publication tables are all present — but the file is **not cleanly
idempotent**, which is worth fixing before it is handed to someone who assumes
a clean re-run means a clean state.

⚠️ **The server went unreachable** after the schema was applied (`Destination
host unreachable` from ping). The apply completed and was verified while it
was up; the app cannot currently connect because the machine is off the
network.

### ⚠️ Applying 01 and 02 is NOT a working server
`postgres/` holds **68 numbered files**, and 02_schema.sql is only the tables
and policies. Applying just those two left the server with `auth.uid()` but
**no `auth.sign_in`, `sign_up`, `change_password`, `update_user`,
`record_failed_login` or `clear_failed_login`** — every function the app needs
to log anybody in. Found by testing sign-in against the deployed server rather
than by trusting the object counts, which looked healthy (32 tables, 132
policies) the whole time.

After applying 03..65 in order: **25 views** (was 6) and **133 policies**.

⚠️ **`04_auth.sql` re-creates `auth.change_password` UNWRAPPED**, undoing the
caller-owns-the-account guard from `migrations/018` — so on a fresh install an
expired session could change somebody *else's* password. 018 has to be
re-applied after 04. Noted in postgres/README.md.

The 11 errors from that pass were checked one by one: nine are **data
assertions** ("expected 228 rows, got 11") that cannot hold on an empty
database, and the two that read like behavioural failures were verified
directly — the perishable-bid trigger and all three `audit_logs`
append-only triggers are present and correct. `audit_logs`'s third policy is
RESTRICTIVE, which *narrows* access; the check miscounts it as permissive.

### yard_app was half-built
The app refused to start with *"Database access must use the non-superuser
yard_app account"* — correctly: `PG_USER=postgres` was in the .env, and a
superuser **bypasses every RLS policy**, so GL1 would see GL2's goods.
`yard_app` existed but was **not a member of `authenticated`**, so every
policy written against that role would have denied everything. Grants and
membership applied; it is now `nosuperuser`, `nobypassrls`, and a member.

**Left for the operator** (`postgres/68_finish_server_setup.sql`): yard_app's
password, and the first ICT account — `profiles` is empty, so nothing can sign
in, including the portal that provisions everyone else. The bootstrap block
was tested end to end on the local database (account created, `auth.sign_in`
returned a row, rows removed afterwards) and its username clash is caught with
a message that names the reason, because `on conflict (id)` does not catch
`profiles_username_lower_idx`.

⚠️ Server-side: `ssl = on` and `scram-sha-256` are already set, so
`PG_SSL=true` is right. But `pg_hba.conf` ends with **`host`**, not
`hostssl`, on `0.0.0.0/0` — a client with `PG_SSL=false` is still accepted, so
the encryption is optional in practice.

### Four tests were reading the live `.env`
`client_security_test`, `network_transport_security_test` and
`remote_deployment_security_test` asserted `PgConfig.isLoopbackHost` and
`usingDefaultPassword` — so they passed only while the developer's `.env` said
localhost. Pointing it at a real deployment reported a **configuration change
as a security regression**. They now ask the *rule* about given values
(`debugIsLoopback`), not the machine's current config.

Full suite: **1763 passing**, 2 skipped, 20 pre-existing failures (unchanged).

---

## The ICT sign-up error was the bootstrap, not a bug

⚠️ **Creating the FIRST account through the app is impossible by design.**
`profiles` has two INSERT policies — `yard_profiles_insert` allows only your
own row (`id = auth.uid()`), and `profiles_ict_write` requires you to already
*be* ICT. And `auth.sign_up` deliberately does **not** adopt the new session
(so ICT stays signed in while provisioning others), which means `auth.uid()`
is NULL during the profile write. Reproduced directly as `yard_app`:
`new row violates row-level security policy for table "profiles"`.

The app maps `42501` to *"This account is not permitted to create that
profile"* — accurate, but it reads like a portal mix-up rather than "there is
no ICT account yet".

The second error, *"No verification code was sent"*, is a consequence: OTP
codes live in memory and are **consumed on use**, so the failed first attempt
spent the code shown on screen.

⚠️ **A trigger already creates the profile row.** `on_auth_user_created →
handle_new_user` inserts into `profiles` as soon as the auth user exists, so
the app's own write is an UPDATE, not an INSERT. Verified that the app's
upsert shape succeeds when signed in as ICT.

Resolved: the operator created the ICT account directly (pgAdmin), and
`yard_app`'s password was set. Verified on 10.10.71.15 — `yard_app` connects,
`auth_user_is_ict()` returns **true** for that account, and the full
`sign_up` + profile upsert path works from it. Server left holding exactly one
profile; every probe account removed.

---

## 🔴 One e-mail could TAKE OVER an existing account

⚠️ **Found in production use, and it is privilege escalation through a
sign-up form.** An ICT account was created with one e-mail; a Central Disposal
account was then created with the SAME e-mail and appeared to succeed. It had
not created anything — `auth.sign_up` correctly refused the duplicate, the app
caught `user_already_exists`, **signed in as the existing account**, and
upserted the new role over it. One e-mail, one id: the ICT account *became* a
Disposal account and ICT ceased to exist. Confirmed on the server — a single
`auth.users` row, created 15:15 and updated 15:32.

Anyone knowing an officer's address and password could re-point their account
at whichever portal they chose, and the officer would find themselves locked
out of their own directorate.

⚠️ The branch itself is legitimate — an account whose `auth.users` row was
created but whose profile write then failed is repaired by signing in and
re-writing the profile. It is only valid **when the role being written is the
role already there**. It now reads the existing role first, refuses a
different one with a message naming the reason, and signs out before throwing
so a refused takeover does not leave a live session behind.

The two admin-driven paths (ICT creating an officer, ICT creating a
directorate account) already refused outright; only the directorate
self-signup had the hole.

Recovery: the account was restored to `role='ict'` with its username and job
role; `auth_user_is_ict()` returns true again and the password is untouched.

### Three more tests were reading the live `.env`
`app_env_test` pinned `PG_USER=postgres`, `PG_SSL=false` and
`postgres@localhost:5432` as literals, so pointing the `.env` at the real
server reported a **configuration change as a test failure**. They now compare
against the file itself, or assert the shape of the string. With these fixed
the long-standing failure count drops from **20 to 18** — two of that baseline
were this same coupling.

Full suite: **1769 passing**, 2 skipped, 18 pre-existing failures.

### Hovering a portal tile greyed it out instead of colouring it
The home page's portal cards and the Yard Access tiles both washed out on
hover: the white went dull and the team colour came through as a muddy
smear rather than the portal's own colour.

⚠️ **The cause was a combination, not one value.** A hovered card filled
itself with a RadialGradient of **translucent** white (0.55 / 0.32) and sat
that over a **`BackdropFilter`** blurring the page behind it. So the card's
own fill was see-through onto a blurred background: the white lost its
brightness, and `accent.withOpacity(0.28)` over that read as grey. Neither
half is wrong alone — a translucent white over a *solid* ground is fine, and
a backdrop blur under an *opaque* fill is merely wasted — which is why this
survived review as "liquid glass" styling.

The fix, in both files: **no BackdropFilter**, and an **opaque** fill tinted
towards the accent with `Color.lerp(Colors.white, accent, 0.18)` — tinting
white keeps the hue *and* the brightness, where layering a transparent
accent could only ever darken. The icon circle and the "Create Account"
fill had the same translucent-white bug and are opaque now too. Removing the
filter also drops a `saveLayer` per hovered card.

The same code had been copied into both screens, so
[portal_hover_stays_bright_test.dart](test/portal_hover_stays_bright_test.dart)
asserts on **both** — at source level, since the defect is a combination of
two widgets that no non-golden widget test can observe. ⚠️ It matches
`BackdropFilter(`, the constructor call, not the bare word: the comments left
in both files name the filter to explain why it went, and the first version
of the test failed on its own explanation.

### …and hovering also made the page jump
Same two screens, reported right after the colour fix: hovering a portal
card nudged the **logo and the heading above the row** up and down, and on
the Yard Access tiles the title/subtitle jittered.

⚠️ **A `Border` paints INSIDE the box.** Both cards grew theirs on hover
(`width: _hovered ? 1.6 : 1`), so the content area shrank by 0.6px on every
side, the card's own contents reflowed, and everything laid out above them
moved with it. The border width is now **constant at 1.6** and only its
COLOUR changes.

⚠️ Two things that look like the same bug and are NOT, both deliberately
kept: the hover **`BoxShadow`** (`spreadRadius`) paints *outside* the box,
and the icon's **`AnimatedScale(1.08)`** is a transform that keeps its
layout size. Neither can move a sibling — removing them would cost the
animation for nothing. The rule the test encodes is narrower than "nothing
changes on hover": **colour may change, laid-out SIZE may not.**

### Yard portals never warned about the 90-day password limit
The four directorate portals had always entered their password stage on
`isPasswordExpired || isPasswordExpiringSoon`, warning for the last 7 days
with a day count and a "Skip for now". Both yard portals
([login_screen.dart](lib/screens/login/login_screen.dart), SC/DSC/ASC, and
[admin_login_screen.dart](lib/screens/admin/admin_login_screen.dart),
SDDC/DDC) gated on `isPasswordExpired` **alone** — so a yard officer's first
notice of the rotation was the morning it locked them out, and migration 018
makes an expired session read *nothing at all*.

Rather than copy the directorates' ~150-line inline `_buildPasswordStage`
into two more files, the warning half was added to the shared
[password_expired_stage.dart](lib/widgets/password_expired_stage.dart):
`expired` (**defaults to true** — a caller that forgets the flag gets the
strict behaviour, never a skippable expiry), `daysLeft`, `onSkip`.

⚠️ **Skip is drawn only while the password still works.** Once expired,
migration 018 has already shut the session out of every record, so a skip
would land the officer in an empty app that looks broken. ⚠️ `onSignOut`
reads `isPasswordExpired` **before** the `setState` that clears the profile
it depends on.

### Dormant accounts are disabled after 90 days
[021](migrations/021_dormant_accounts_are_disabled.sql). An account unused
for 90 days (same period as the password rotation) is switched off
automatically. **On first application this disabled 5 real accounts** —
Onela Randuni, Anushanga Kaushan, and the Valuation / Disposal / Appeal
directorate accounts, all last seen March–June 2026.

- ⚠️ **Reuses `is_active`**, not a second flag: every sign-in path already
  refuses an inactive profile and ICT already has the toggle, so
  reactivation worked on day one and there is one answer to "can this
  account sign in", not two that can disagree.
- ⚠️ **`coalesce(last_seen_at, created_at)`** — `last_seen_at` is null for a
  provisioned-but-never-used account, and reading null as "not dormant"
  would have exempted exactly the accounts the rule is for.
- ⚠️ **The sweep lives inside `auth.sign_in`, before the password check.**
  In the Dart client it would bind only people using the app; after the
  check it would grant one more sign-in. It also needs no scheduler —
  pg_cron is not installed, and a rule depending on an absent extension
  silently never runs. **`postgres/04_auth.sql` re-creates `sign_in` without
  it** — same hazard already recorded for `change_password`/018.
- ⚠️ **`reactivate_account` resets `last_seen_at`.** Without that the woken
  account is still 90 days stale and the next sweep disables it again —
  which is why `toggleUserStatus` now calls the RPC instead of writing the
  flag.
- `deactivated_reason` ('dormant' vs 'manual') drives a **DORMANT** amber
  chip distinct from **INACTIVE** red: waking a dormant account is routine,
  re-enabling a deliberate deactivation undoes somebody's decision.
- ⚠️ `copyWithOnline` must carry `deactivatedReason`, or every presence
  update would reset a dormant account to reading as manual.

`_PasswordAge` moved from `directorate_access_tab.dart` into
[account_cells.dart](lib/widgets/account_cells.dart) as **`PasswordAgeCell`**
and is now in both account tables — the Staff Register gained the Password
column ICT previously only had for directorates.

### Changing an expired password landed the officer on the HOME page
Reported on both yard portals, and present in all seven.

⚠️ **The profile in `currentProfileProvider` was read BEFORE the change**, so
its `password_updated_at` was still the old one and `isPasswordExpired`
stayed true. Walking that profile into the app meant the router's expiry
guard ([router.dart](lib/core/router.dart)) refused the destination and
redirected to `/` — the officer set a new password and arrived at the portal
picker, as if nothing had happened.

⚠️ The five directorate portals **re-read** the profile
(`getCurrentProfile()`) right after the change, which is why only the yard
pair showed the bug; ICT used `_pendingProfile` with no re-read at all and
had it in the same form as the yards.

The fix, everywhere, is what the user asked for and is better than a
re-read: **end the session and return to that portal's own sign-in form**, so
the officer signs in with the new password the ordinary way. It also proves
the new password works while the form that can correct it is still on
screen. Seven screens plus the shared
[password_expired_stage.dart](lib/widgets/password_expired_stage.dart).

⚠️ [password_change_returns_to_sign_in_test.dart](test/password_change_returns_to_sign_in_test.dart)
reads the **shared stage** for the two yard portals and the screen file for
the other five — the yard pair never calls `changePassword` themselves, so
asserting against their own source looked like a failure when the fix was
present.

### `SECURITY: PG_PASSWORD is unset` is not a parsing bug
Worth not re-investigating: the `.env` has a leading space on every key
(` PG_HOST=…`) and **dotenv parses those fine** — verified directly against
the package. The warning comes from `usingDefaultPassword`
([pg_connection.dart](lib/core/db/pg_connection.dart)), which fires because
the configured `PG_PASSWORD` genuinely *is* `postgres`, the compiled-in
default. Working as designed.

### ⚠️ Migration 021 read the WRONG COLUMN and disabled live accounts
[022](migrations/022_dormancy_reads_the_right_clock.sql) corrects it. This is
the most important note in this section.

`profiles.last_seen_at` is a **presence heartbeat, not a record of last
use**. `signOut()` and `setUserOffline()` both set it to **NULL on purpose**
([services.dart](lib/services/services.dart)) — the online list is judged by
a fresh heartbeat, so a lingering value would keep somebody showing as
"online" for ~90s after they left. Nulling it is correct for what that
column is for.

So 021's `coalesce(last_seen_at, created_at)` meant **any account whose
holder signed out tidily** fell back to `created_at` and was disabled the
moment the account was over 90 days old. Verified live: 6 of 11 accounts had
a null heartbeat despite signing in that day, and the user's own SDDC account
read as dormant minutes after they used it.

**`auth.users.last_sign_in_at` is the right clock** — `auth.sign_in` writes
it and nothing clears it. 022 switches the check, the sweep and
`reactivate_account` (which reset the *unread* column, so waking an account
would not have survived the next sweep), and re-enables every account 021
disabled whose real clock says it is not dormant — leaving `manual`
deactivations alone, because those were somebody's decision.

### Password reuse is blocked, not just the current password
[023](migrations/023_password_history_blocks_reuse.sql). `change_password`
already refused the *current* password, but alternating between two defeated
the rotation entirely. `auth.password_history` keeps the last
`password_history_depth()` (5) bcrypt hashes per account.

- ⚠️ **bcrypt salts per row**, so the candidate cannot be hashed once and
  looked up — each stored hash must be `crypt()`ed with its own salt in
  turn. A plain equality test would silently pass everything.
- ⚠️ The outgoing hash is inserted **before** `auth.users` is updated, or the
  password just replaced could be reused immediately.
- ⚠️ **023 overwrote migration 018's wrapper**, dropping the "you may only
  change your own password" guard — `018 must be re-applied after 023`, which
  re-wraps the new body as `change_password_unchecked`. Verified both guards
  are live and layered.

### Database refusals reached the UI wearing the driver's clothes
The sign-in screen showed `Severity.error 22023: New password must be
different…`. A `raise exception` is how the schema talks to a **person**, and
the postgres driver's `toString()` wraps it in a severity enum and SQLSTATE.
`describeDatabaseError` in [pg_query.dart](lib/core/db/pg_query.dart) strips
that, applied once in `PgClient.rpc` so every caller benefits. ⚠️ An
**unrecognised** error is passed through unchanged — inventing a friendly
message for a failure we do not recognise hides the detail that explains it.

### ⚠️ The ProviderScope reset throws the router away — that is why "go to the
### sign-in page" kept landing on HOME
The single most confusing bug of this run, and the navigation was never the
cause. `signOut()` calls `clearCachedSessionData()`, which bumps
`sessionEpoch` and rebuilds the whole **ProviderScope**
([session_reset.dart](lib/core/session_reset.dart)) — a deliberate security
measure, because ~100 non-autoDispose providers would otherwise show one
officer's rows to the next. Rebuilding the scope builds a **new GoRouter**,
and a new router starts at its `initialLocation`, which was the literal `'/'`.
So a portal's own `context.go('/login')` was discarded a frame later and the
officer arrived at the portal picker.

Fix: **`pendingLandingRoute`** + `takeLandingRoute()`. The router reads it
once as its `initialLocation` and it clears itself, so an ordinary sign-out
still goes home. ⚠️ It must be set **before** `signOut()` — that call
*schedules* the rebuild. All seven portals name their own sign-in route; the
two yard portals pass it to the shared stage as `signInRoute`.

### One-time codes: three separate faults
- ⚠️ **The e-mail promised 5 minutes, the screen expired at 2.** `_ttl` was
  `Duration(minutes: 5)` and the e-mail text derived from it, but every
  countdown was a literal `120` copied into **twelve** files. Now
  `GmailOtpService.codeLifetime` is the one source and all of them read it.
- ⚠️ **A rejected password destroyed the code.** `verifyCode` consumed on
  success, but `finishPasswordReset` verified *then* saved — so a password
  refused by the database (too short, used before) spent the code anyway. The
  next press said "No verification code was sent". `verifyCode(..., consume:
  false)` + `consumeCode()` after the reset actually succeeds.
- ⚠️ **`_error!.contains('code')` was too loose**, matching "No verification
  **code** was sent" and password messages containing the word, so a rejected
  PASSWORD bounced the officer to the OTP screen. Now matches the specific
  code complaints.

### ⚠️ Do not `dart format` whole directories
This cost two rounds of false regressions. Many tests in this suite assert on
**source text**; reflowing a file they read breaks the match while the code
behaves identically. A one-character edit that pushes a line past 80 chars
makes the formatter rewrap it — and formatting a directory rewraps files you
never touched. Format only the exact files you edited, and when a "regression"
appears in a file you did not functionally change, compare
**whitespace-stripped token hashes** against HEAD before believing it:
`git show HEAD:<f> | tr -d '[:space:]' | md5sum` vs the same on the working
copy. `git diff -w` is NOT sufficient — it ignores whitespace within a line
but still reports tokens moved between lines.
