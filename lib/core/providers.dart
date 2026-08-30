import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_client.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'supabase_client.dart';
import 'yards.dart';

// ── Service Providers ──────────────────────────────────────────
final authServiceProvider = Provider((ref) => AuthService());
final packageServiceProvider = Provider((ref) => PackageService());
final warehouseServiceProvider = Provider((ref) => WarehouseService());
final adminServiceProvider = Provider((ref) => AdminService());
final auditLogServiceProvider = Provider((ref) => AuditLogService());
final packageCategoryServiceProvider =
    Provider((ref) => PackageCategoryService());
final forfeitedPackageServiceProvider =
    Provider((ref) => ForfeitedPackageService());
final tendersServiceProvider = Provider((ref) => TendersService());
final disposalServiceProvider = Provider((ref) => DisposalService());
final appealServiceProvider = Provider((ref) => AppealService());
final valuationServiceProvider = Provider((ref) => ValuationService());
final ictServiceProvider = Provider((ref) => IctService());

// ── Shared Auth State ──────────────────────────────────────────
final currentProfileProvider = StateProvider<ProfileModel?>((ref) => null);
final loginLoadingProvider = StateProvider<bool>((ref) => false);
final loginErrorProvider = StateProvider<String?>((ref) => null);

// ── Theme State ────────────────────────────────────────────────
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

// ── Manual Refresh Triggers ────────────────────────────────────
class RefreshTrigger extends StateNotifier<int> {
  RefreshTrigger() : super(0);
  void trigger() => state++;
}

final warehouseRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final packagesRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());

// ── Realtime: Packages Stream ──────────────────────────────────
final packagesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(packagesRefreshTriggerProvider);
  yield trigger;

  final channel = supabase.channel('packages-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'packages',
      callback: (_) =>
          ref.read(packagesRefreshTriggerProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'package_items',
      callback: (_) =>
          ref.read(packagesRefreshTriggerProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'warehouse_entries',
      callback: (_) =>
          ref.read(packagesRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Warehouse Entries Stream ──────────────────────────
final warehouseEntriesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(warehouseRefreshTriggerProvider);
  yield trigger;

  final channel = supabase.channel('warehouse-entries-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'warehouse_entries',
      callback: (_) =>
          ref.read(warehouseRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Profiles Stream ──────────────────────────────────
final profilesRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final profilesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(profilesRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('profiles-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'profiles',
      callback: (_) =>
          ref.read(profilesRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Package Categories Stream ──────────────────────────
final categoriesRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final categoryChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(categoriesRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('categories-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'package_categories',
      callback: (_) =>
          ref.read(categoriesRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Storage Rates ─────────────────────────────────────
final storageRatesRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final storageRatesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(storageRatesRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('storage-rates-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'storage_rates',
      callback: (_) =>
          ref.read(storageRatesRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Shared Data Providers ──────────────────────────────────────
final warehousesProvider = FutureProvider<List<WarehouseModel>>((ref) async {
  ref.watch(warehouseRefreshTriggerProvider);
  return ref.read(warehouseServiceProvider).getWarehouses();
});

/// The warehouses a given yard actually holds goods in, in `warehouses` order.
///
/// `warehouses` is SHARED across yards with no yard column of its own, so the
/// association is derived from `warehouse_entries.yard`. Yards differ in both
/// which warehouses they use and how many, so a picker scoped to one yard must
/// narrow to these rather than list every warehouse in the system.
///
/// A yard that has never written an entry yields the FULL list: an empty
/// picker would leave the reader unable to choose anything at all.
final warehousesForYardProvider =
    FutureProvider.family<List<WarehouseModel>, String>((ref, yard) async {
  ref.watch(warehouseRefreshTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  final all = await ref.watch(warehousesProvider.future);
  final ids =
      await ref.read(warehouseServiceProvider).getWarehouseIdsForYard(yard);
  // A yard with no warehouses of its own gets an EMPTY list, not every
  // warehouse in the system. `warehouses` is shared, so falling back to all of
  // them told a yard it had three warehouses when it had none — and offered
  // filters that could never match a single row.
  return all.where((w) => ids.contains(w.id)).toList();
});

// Selected warehouse tab index on the Warehouses page — persisted so a data
// refresh (e.g. after a package action) doesn't snap the tabs back to the
// first warehouse.
final warehouseTabIndexProvider = StateProvider<int>((ref) => 0);

// ── Warehouse Admin Management Providers ────────────────────────
final warehouseEditingProvider = StateProvider<WarehouseModel?>((ref) => null);
final warehouseNameInputProvider = StateProvider<String>((ref) => '');
final warehouseCodeInputProvider = StateProvider<String>((ref) => '');
final warehouseDescriptionInputProvider = StateProvider<String>((ref) => '');
final warehouseLocationInputProvider = StateProvider<String>((ref) => '');
final warehouseCapacityInputProvider = StateProvider<String>((ref) => '500');

// ── Live Packages Provider ─────────────────────────────────────
final packageFilterProvider = StateProvider<String>((ref) => 'all');
final packageSearchProvider = StateProvider<String>((ref) => '');
final packageShowReturnedProvider = StateProvider<bool>((ref) => true);
final packageDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);
final packageReasonFilterProvider = StateProvider<String>((ref) => 'all');
final packageYearFilterProvider = StateProvider<String?>((ref) => null);

final livePackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  final filter = ref.watch(packageFilterProvider);
  final search = ref.watch(packageSearchProvider);
  return ref
      .read(packageServiceProvider)
      .getAllPackages(status: filter, search: search.isEmpty ? null : search);
});

// ── Package History server-side pagination ─────────────────────────────────
/// Rows per page on the Package History table.
const int kPackagePageSize = 20;

/// Current zero-based page index for the Package History table.
final packagePageProvider = StateProvider<int>((ref) => 0);

/// One page of packages + the total matching count (server-side). Re-queries
/// whenever a filter or the page index changes, so the page opens fast even
/// with very large tables (only [kPackagePageSize] rows leave the DB per call).
typedef PackagePage = ({List<PackageModel> rows, int total});

final packagesPageProvider = FutureProvider<PackagePage>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  final page = ref.watch(packagePageProvider);
  final search = ref.watch(packageSearchProvider);
  final dateRange = ref.watch(packageDateRangeProvider);
  final year = ref.watch(packageYearFilterProvider);
  return ref.read(packageServiceProvider).getPackagesPaged(
        offset: page * kPackagePageSize,
        limit: kPackagePageSize,
        search: search.isEmpty ? null : search,
        dateStart: dateRange?.start,
        dateEnd: dateRange?.end,
        year: year,
      );
});

// ── Live Warehouse Entries Provider ─────────────────────────────
final warehouseEntryFilterProvider = StateProvider<bool>((ref) => false);
final selectedWarehouseIdProvider = StateProvider<String?>((ref) => null);

final liveWarehouseEntriesProvider =
    FutureProvider.family<List<WarehouseEntryModel>, String>(
        (ref, warehouseId) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  final showReturned = ref.watch(warehouseEntryFilterProvider);
  return ref.read(warehouseServiceProvider).getEntriesByWarehouse(warehouseId,
      isReturned: showReturned ? null : false);
});

final allWarehouseEntriesProvider =
    FutureProvider<List<WarehouseEntryModel>>((ref) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(warehouseServiceProvider).getAllWarehouseEntries();
});

final warehouseStatusFilterProvider =
    StateProvider.family<String, String>((ref, warehouseId) => 'all');
final warehouseSearchProvider =
    StateProvider.family<String, String>((ref, id) => '');
final warehouseDateRangeProvider =
    StateProvider.family<DateTimeRange?, String>((ref, warehouseId) => null);
final warehouseYearFilterProvider =
    StateProvider.family<String?, String>((ref, warehouseId) => null);
final warehouseReasonFilterProvider =
    StateProvider.family<String, String>((ref, warehouseId) => 'all');

final storageRateProvider = FutureProvider<Map<DateTime, double>>((ref) async {
  ref.watch(storageRatesChangeTriggerProvider);
  final data = await supabase
      .from('storage_rates')
      .select('rate, effective_from')
      .order('effective_from', ascending: true);

  final Map<DateTime, double> rates = {};
  for (var row in data) {
    final date = DateTime.parse(row['effective_from'] as String);
    final rate = (row['rate'] as num).toDouble();
    rates[DateTime(date.year, date.month, date.day)] = rate;
  }

  // If empty, provide default
  if (rates.isEmpty) {
    rates[DateTime(2020, 1, 1)] = 50.0;
  }

  return rates;
});

/// The storage rate currently in effect — the most recent entry by
/// `effective_from`. Shown as the headline value of the Admin Dashboard's
/// "Current W/H Charge" card (the per-day rate, e.g. LKR 40/day).
final currentStorageRateProvider = FutureProvider<double>((ref) async {
  final rates = await ref.watch(storageRateProvider.future);
  if (rates.isEmpty) return 0;
  final latest = rates.entries.reduce((a, b) => a.key.isAfter(b.key) ? a : b);
  return latest.value;
});

final storageRateHistoryProvider =
    FutureProvider<List<AuditLogModel>>((ref) async {
  ref.watch(storageRatesChangeTriggerProvider);
  final data = await supabase
      .from('storage_rates')
      .select('rate, effective_from, id')
      .order('effective_from', ascending: false);

  return data
      .map((row) => AuditLogModel(
            id: row['id'].toString(),
            userId: 'system',
            action: 'RATE_UPDATE',
            entityType: 'storage_rate',
            entityId: row['id'].toString(),
            createdAt: DateTime.parse(row['effective_from'] as String),
            details: {'rate': (row['rate'] as num).toDouble()},
          ))
      .toList();
});

final packageDataProvider =
    FutureProvider.family<PackageModel?, String>((ref, id) async {
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getPackageById(id);
});

// ── Admin Data Providers ───────────────────────────────────────
final allProfilesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  ref.watch(profilesChangeTriggerProvider);
  return ref.read(adminServiceProvider).getAllProfiles();
});

final onlineProfilesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  ref.watch(profilesChangeTriggerProvider);
  final all = await ref.watch(allProfilesProvider.future);
  final now = DateTime.now();
  return all.where((p) {
    if (p.lastSeenAt == null) return false;
    // Recent PAST heartbeat only (0..90s). A future timestamp (from an old
    // local-time-tagged-UTC row) must not count — it would pass `< 90` forever.
    final diff = now.difference(p.lastSeenAt!).inSeconds;
    return diff >= 0 && diff < 150;
  }).toList();
});

/// Staff in the signed-in admin's own yard — officers + admins ONLY.
/// The cross-yard SELECT policy for directorate accounts means [allProfilesProvider]
/// can leak head-office rows; the Admin Dashboard wants only "my yard" staff. We
/// whitelist the two yard roles (admin / officer) rather than blacklisting each
/// directorate — so a new institutional role (Disposal, Appeal, Valuation, …)
/// can never leak in as "online" just because its `yard` defaults to a matching
/// yard code.
final myYardProfilesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  final all = await ref.watch(allProfilesProvider.future);
  final myYard = ref.watch(currentProfileProvider)?.yard;
  return all.where((p) {
    if (!p.isYardStaff) return false; // officers + admins only
    if (myYard == null) return true;
    return p.yard == myYard;
  }).toList();
});

/// Officers/admins in the admin's own yard who are online RIGHT NOW.
///
/// Self-polls the DB directly every 12s (no cached layers), so a session that
/// stopped beating vanishes within ~12s. "Online" is judged PURELY by a fresh
/// heartbeat — `last_seen_at` within 90s. The `is_online` boolean is ignored on
/// purpose: it can get stuck `true` after an unclean close, which is exactly the
/// bug that kept ghosts on the list. The current signed-in user is always
/// included (they're online by definition — no dependence on their own row).
final myYardOnlineProfilesProvider =
    StreamProvider<List<ProfileModel>>((ref) async* {
  final me = ref.watch(currentProfileProvider);
  final myYard = me?.yard;
  // Only the columns the online list needs (created_at/full_name/role are
  // required by fromJson). Projecting keeps each poll tiny at scale.
  const cols =
      'id, full_name, role, yard, last_seen_at, profile_image_url, created_at';
  List<ProfileModel> last = const [];
  while (true) {
    try {
      // SERVER-SIDE filter to this yard + yard roles only, so with 300 users
      // across 20 yards each client pulls just its own ~15 rows, not all 300.
      final query = supabase
          .from('profiles')
          .select(cols)
          .inFilter('role', ['admin', 'officer']);
      final data = await (myYard != null ? query.eq('yard', myYard) : query);
      final now = DateTime.now();
      last = (data as List)
          .map((j) => ProfileModel.fromJson(j as Map<String, dynamic>))
          .where((p) {
        if (me != null && p.id == me.id) return true; // always myself
        if (p.lastSeenAt == null) return false;
        final diff = now.difference(p.lastSeenAt!).inSeconds;
        // Must be a RECENT past beat. A future timestamp (diff < 0) is bogus —
        // e.g. an old row written as local-time-tagged-UTC — and would otherwise
        // pass `< 90` forever, pinning a ghost online. Reject it.
        return diff >= 0 && diff < 150;
      }).toList();
      yield last;
    } catch (_) {
      // Transient error — keep the previous list rather than flashing offline.
      yield last;
    }
    await Future.delayed(const Duration(seconds: 12));
  }
});

final auditLogsRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final auditLogsChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(auditLogsRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('audit-logs-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'audit_logs',
      callback: (_) =>
          ref.read(auditLogsRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

final allLogsProvider = FutureProvider<List<AuditLogModel>>((ref) async {
  ref.watch(auditLogsChangeTriggerProvider);
  return ref.read(auditLogServiceProvider).getAllLogs();
});

final packageCategoriesProvider =
    FutureProvider<List<PackageCategory>>((ref) async {
  ref.watch(categoryChangeTriggerProvider);
  return ref.read(packageCategoryServiceProvider).getCategories();
});

// ── Forfeited Packages & Tenders Providers ──────────────────
final forfeitedRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final forfeitedPackagesChangeTriggerProvider =
    StreamProvider<int>((ref) async* {
  final trigger = ref.watch(forfeitedRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('forfeited-packages-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'forfeited_packages',
      callback: (_) =>
          ref.read(forfeitedRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

/// The appeal outcome for each item of one package, keyed by item id.
///
/// The Goods Actions sheet watches this so an appeal DECISION unblocks the
/// goods the moment it is recorded — the yard does not have to sit out the
/// rest of the 30-day window. A hold still blocks, even past the deadline.
final itemAppealOutcomesProvider =
    FutureProvider.family<Map<String, ItemAppealOutcome>, String>(
        (ref, packageId) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref
      .read(forfeitedPackageServiceProvider)
      .getItemAppealOutcomes(packageId);
});

/// Appeal outcomes for every item in the system, keyed by item id.
///
/// Fetched once so a table can look each row up without a query per row.
final allItemAppealOutcomesProvider =
    FutureProvider<Map<String, ItemAppealOutcome>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getAllItemAppealOutcomes();
});

final forfeitedPackagesProvider =
    FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  // Sending a disposal request consumes the package, so it must drop off the
  // Forfeited list immediately — watch the manual refresh signal too (realtime
  // alone can lag, and same-session submits fire this trigger).
  ref.watch(disposalRequestsRefreshProvider);
  // A package becoming SOLD / DESTROYED removes it from this list, so refresh
  // when tender_sale_items / destruction_items change in any session.
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getForfeitedPackages();
});

final expiredAppealPackagesProvider =
    FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  return ref.read(forfeitedPackageServiceProvider).getExpiredAppealPackages();
});

final tendersProvider = FutureProvider<List<TenderModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref.read(tendersServiceProvider).getTenders();
});

// Tendered-but-unsold packages whose sale window has passed — eligible for
// re-tendering (unlimited). Each carries its full tender history.
final reTenderablePackagesProvider =
    FutureProvider<List<ReTenderInfo>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref.read(tendersServiceProvider).getReTenderablePackages();
});

// Central Disposal Directorate unsold packages from tender_sales
final unsoldTenderSalesProvider =
    FutureProvider<List<ReTenderSaleInfo>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  // A sale marked sold / re-tendered changes tender_sale_items → refresh live.
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getUnsoldTenderSales();
});

// ── Realtime: tender_bids / tender_revaluations ──────────────────
// So bids/re-valuations entered on one portal (Central Disposal / Valuation)
// live-update the tables on the other portals.
final tenderBidsRefreshTriggerProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());

final tenderBidsChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(tenderBidsRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('tender-bids-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tender_bids',
      callback: (_) =>
          ref.read(tenderBidsRefreshTriggerProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tender_revaluations',
      callback: (_) =>
          ref.read(tenderBidsRefreshTriggerProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tender_committees',
      callback: (_) =>
          ref.read(tenderBidsRefreshTriggerProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'unsold_proposals',
      callback: (_) =>
          ref.read(tenderBidsRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// All appointed tender committees, keyed by forfeited_package_id.
final tenderCommitteesProvider =
    FutureProvider<Map<String, TenderCommitteeModel>>((ref) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getTenderCommittees();
});

// DG committee page: unsold tender packages tendered >3 times (≥4 attempts).
final committeeEligibleProvider =
    FutureProvider<List<ReTenderSaleInfo>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getCommitteeEligiblePackages();
});

// Bids recorded for a single unsold tender package, grouped by tender round
// (tender_sale_id → amounts). Keyed by forfeited package id.
final tenderBidsProvider =
    FutureProvider.family<Map<String, List<double>>, String>((ref, fpId) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getTenderBidsByRound(fpId);
});

// Valuation re-valuations for a package, keyed by tender round (tender_sale_id).
final tenderRevaluationsProvider =
    FutureProvider.family<Map<String, TenderRevaluationModel>, String>(
        (ref, fpId) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getTenderRevaluationsByRound(fpId);
});

// forfeited_package_ids that may be re-tendered — their latest unsold round has
// a Valuation re-valuation. Packages awaiting re-valuation are excluded.
// ── Unsold proposals (High Panel's final outcome) ──────────────────────────
// The packages that exhausted every avenue: past Tender 3, committee valuation
// submitted by the ADG, tendered again, still unsold. Shared by the High Panel,
// Central Disposal and the yards so all three lists agree.
final exhaustedUnsoldProvider =
    FutureProvider<List<ReTenderSaleInfo>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getExhaustedUnsoldPackages();
});

// The recorded final outcomes, keyed by forfeited_package_id.
final unsoldProposalsProvider =
    FutureProvider<Map<String, UnsoldProposalModel>>((ref) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getUnsoldProposals();
});

// Packages whose CURRENT unsold round the Valuation Directorate has already
// re-valued — drives their own Pending/Valued filter. Not the same as
// reTenderEligibleProvider, which also needs bids + the ADG's submission.
final valuedCurrentRoundProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getValuedCurrentRoundIds();
});

final reTenderEligibleProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getReTenderEligibleIds();
});

// Appeal portal: every forfeited package that has ≥1 recorded bid, with its
// rounds (each a tender sale + its bid amounts).
final packagesWithBidsProvider = FutureProvider<
    List<
        ({
          ForfeitedPackageModel forfeited,
          List<({TenderSaleModel? sale, List<double> bids})> rounds
        })>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getPackagesWithBids();
});

// Central Disposal Directorate undestroyed packages from destructions
final undestroyedDestructionsProvider =
    FutureProvider<List<ReDestructionInfo>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  // A destruction marked destroyed / re-destroyed changes destruction_items.
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getUndestroyedDestructions();
});

// ── Tender Form State Providers ──────────────────────────────
final tenderNumberInputProvider = StateProvider<String>((ref) => '');
final tenderDateInputProvider =
    StateProvider<DateTime?>((ref) => DateTime.now());
final selectedTenderPackagesProvider = StateProvider<Set<String>>((ref) => {});

// ── Disposal Directorate Providers ─────────────────────────────
final disposalSelectedYardProvider =
    StateProvider<String>((ref) => kYards.first.code);

// Sold / Destroyed cross-yard tabs use their own nullable yard filter so they
// can show "All Yards" (null) — independent of the single-yard tabs above.
final disposalSoldYardFilterProvider = StateProvider<String?>((ref) => null);
final disposalDestroyedYardFilterProvider =
    StateProvider<String?>((ref) => null);

final disposalSoldPackagesProvider =
    FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider); // refresh on package changes
  final yard = ref.watch(disposalSoldYardFilterProvider); // null = all yards
  return ref.read(disposalServiceProvider).getSoldPackages(yard: yard);
});

/// Destroyed packages across yards (null filter = all). Refreshes the moment a
/// yard marks a package destroyed (a warehouse_entries write → packages trigger).
final disposalDestroyedPackagesProvider =
    FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  final yard = ref.watch(disposalDestroyedYardFilterProvider); // null = all
  return ref.read(disposalServiceProvider).getDestroyedPackages(yard: yard);
});

/// package_id → delivered (bool) across all tender sale items. Lets the Sold
/// Packages tab filter Delivered / Pending synchronously. Refreshes on any
/// tender_sale_items realtime change (a Mark-Delivered in any session).
final packageDeliveredMapProvider =
    FutureProvider<Map<String, bool>>((ref) async {
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getDeliveryStatusByPackageId();
});

/// package_id → delivered (bool) for DESTROYED packages. Mirrors the sold map.
final packageDestroyedDeliveredMapProvider =
    FutureProvider<Map<String, bool>>((ref) async {
  ref.watch(destructionsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getDestroyedDeliveryStatusByPackageId();
});

/// The destruction item (delivery state) for a package id. Re-fetches on
/// destructions realtime so every session stays in sync after a Mark-Delivered.
final destructionItemForPackageProvider =
    FutureProvider.family<DestructionItemModel?, String>(
        (ref, packageId) async {
  ref.watch(destructionsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getDestructionItemForPackage(packageId);
});

/// Per-item variant keyed by "$packageId|$packageItemId". Finds the destruction
/// item whose forfeited_package.item_id matches the specific package item so the
/// details popup toggles delivery only for that item, not all items on the package.
final destructionItemForPackageItemProvider =
    FutureProvider.family<DestructionItemModel?, String>((ref, key) async {
  ref.watch(destructionsChangeTriggerProvider);
  final parts = key.split('|');
  final packageId = parts[0];
  final packageItemId =
      parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  return ref
      .read(disposalServiceProvider)
      .getDestructionItemForPackageItem(packageId, packageItemId);
});

final disposalForfeitedPackagesProvider =
    FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  final yard = ref.watch(disposalSelectedYardProvider);
  return ref.read(disposalServiceProvider).getForfeitedPackages(yard: yard);
});

// ── Appeal Directorate: cross-yard forfeited packages (all yards) ──────────
// An appeal-hold toggle is a forfeited_packages UPDATE, so the existing
// forfeited-packages realtime channel propagates it here and to the yard view.
/// Everything the Appeal Directorate can act on: genuine forfeits (which have
/// real forfeited_packages rows) PLUS Detain / Abandoned / "Other" goods still
/// inside their 30-day window (synthesised, since they have no row yet).
final appealForfeitedPackagesProvider =
    FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  final forfeits = await ref.read(appealServiceProvider).getForfeitedPackages();
  final others = await ref
      .read(forfeitedPackageServiceProvider)
      .getInAppealNonForfeitPackages();
  return [...forfeits, ...others];
});

final tenderSalesRefreshProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final tenderSalesProvider = FutureProvider<List<TenderSaleModel>>((ref) async {
  ref.watch(tenderSalesRefreshProvider);
  // A Mark-Sold updates tender_sale_items; watching its realtime trigger means
  // the Tender Sales cards re-fetch the moment any item changes, in any session.
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getTenderSales();
});

final destructionsRefreshProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());

// Realtime on destructions + destruction_items — a Mark-Destroyed / new
// destruction in any session propagates to every open Destructions view.
// Requires both tables in the `supabase_realtime` publication
// (migration 20260613_disposal_realtime.sql).
final destructionsChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(destructionsRefreshProvider);
  yield trigger;
  final channel = supabase.channel('destructions-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'destructions',
      callback: (_) => ref.read(destructionsRefreshProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'destruction_items',
      callback: (_) => ref.read(destructionsRefreshProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

final destructionsProvider =
    FutureProvider<List<DestructionModel>>((ref) async {
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getDestructions();
});

// ── Disposal Requests (Yard → Central Disposal) ────────────────
// Refresh trigger fires after a yard submits a request and is watched by both
// the yard-side requestable list and the disposal-side request feed.
final disposalRequestsRefreshProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());

// Yard-side: forfeited packages (appeal window passed) not yet requested.
final requestableForfeitedPackagesProvider =
    FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  // Watch the STREAM (not just the refresh notifier) so the disposal_requests /
  // _items realtime subscription is active on yard pages too — a request sent
  // or forwarded in any session live-drops it from the requestable list.
  ref.watch(disposalRequestsChangeTriggerProvider);
  // Also watch the manual refresh signal so a same-session submit drops the
  // requested item from the form pool immediately (realtime can lag).
  ref.watch(disposalRequestsRefreshProvider);
  // Abandoned / "Other" requestable packages are synthesised from the `packages`
  // table, so a newly registered (or re-statused) package must refresh this too.
  ref.watch(packagesChangeTriggerProvider);
  // A package becoming SOLD / DESTROYED makes it non-requestable, so refresh
  // when tender_sale_items / destruction_items change in any session.
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref
      .read(forfeitedPackageServiceProvider)
      .getRequestableExpiredPackages();
});

/// The same pool, PLUS goods still inside their appeal window.
///
/// The disposal request dialog lists these greyed out rather than hiding them,
/// so the officer sees every SR at once and picks what to send. Goods on an
/// appeal hold are excluded here too — that appeal is still open.
final allDisposalCandidatesProvider =
    FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref
      .read(forfeitedPackageServiceProvider)
      .getRequestableExpiredPackages(includePending: true);
});

/// Yard-side: set of "pkgId:itemId" keys for abandoned/other packages that
/// have actually been SENT for disposal. Used by the Abandoned and Other table
/// screens to hide rows already in a disposal request.
///
/// Keyed on `disposal_request_items`, NOT on the mere existence of a
/// forfeited_packages row: an APPEAL now also creates that row (see
/// `appeal_ensure_forfeited_row`), and a package under appeal must stay
/// visible on the yard's table — it has not been sent anywhere.
final sentAbandonedOtherFpKeysProvider =
    FutureProvider<Set<String>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  final data = await supabase
      .from('disposal_request_items')
      .select('forfeited_packages!inner(package_id, item_id, source)')
      .inFilter('forfeited_packages.source', ['abandoned', 'other']);
  return (data as List).map((row) {
    final e = (row as Map<String, dynamic>)['forfeited_packages']
        as Map<String, dynamic>;
    final pkgId = e['package_id'].toString();
    final itemId = e['item_id']?.toString();
    return itemId != null ? '$pkgId:$itemId' : pkgId;
  }).toSet();
});

// Yard-side request form selection: forfeited_package_id → 'destruction' | 'sale'.
final selectedRequestDispositionsProvider =
    StateProvider<Map<String, String>>((ref) => {});

// Disposal-side: every yard's submitted requests (cross-yard via RLS).

final disposalRequestsChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(disposalRequestsRefreshProvider);
  yield trigger;
  // Subscribe to BOTH the request header and its line items — an item moving on
  // (e.g. placed in a tender sale / destruction, or deleted) must refresh the
  // requests feed too, not just header inserts.
  final channel = supabase.channel('disposal-requests-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'disposal_requests',
      callback: (payload) {
        debugPrint(
            '[realtime] disposal_requests ${payload.eventType} → refresh');
        ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      },
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'disposal_request_items',
      callback: (payload) {
        debugPrint(
            '[realtime] disposal_request_items ${payload.eventType} → refresh');
        ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      },
    )
    ..subscribe((status, err) {
      debugPrint('[realtime] disposal-requests channel: $status ${err ?? ''}');
    });
  ref.onDispose(() => supabase.removeChannel(channel));
});

final disposalRequestsProvider =
    FutureProvider<List<DisposalRequestModel>>((ref) async {
  ref.watch(disposalRequestsChangeTriggerProvider);
  // A new tender / destruction sale consumes request items, so they must drop
  // off this feed immediately — watch those refresh signals too.
  ref.watch(tenderSalesRefreshProvider);
  ref.watch(destructionsRefreshProvider);
  return ref.read(disposalServiceProvider).getDisposalRequests();
});

// ── Valuation Directorate: requests still awaiting valuation (cross-yard) ────
// Shares the same realtime trigger as the disposal feed (both watch the
// disposal_requests / _items tables), so forwarding a request live-updates both
// the valuation list (it leaves) and the central-disposal list (it appears).
final valuationRequestsProvider =
    FutureProvider<List<DisposalRequestModel>>((ref) async {
  ref.watch(disposalRequestsChangeTriggerProvider);
  return ref.read(valuationServiceProvider).getValuationRequests();
});

// Realtime on tender_sale_items — so a delivery toggle / new sale in ANY session
// (e.g. a yard marking Delivered) propagates to the Central Disposal tables.
// NOTE: requires tender_sale_items to be in the `supabase_realtime` publication
// (migration 20260611_tender_sale_items_realtime.sql).
final tenderSaleItemsRefreshProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final tenderSaleItemsChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(tenderSaleItemsRefreshProvider);
  yield trigger;
  final channel = supabase.channel('tender-sale-items-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tender_sale_items',
      callback: (_) =>
          ref.read(tenderSaleItemsRefreshProvider.notifier).trigger(),
    )
    // A new/edited tender SALE (number, date, re-tender) also drives the
    // Tender Sales cards, Unsold "tenderCount" & committee eligibility.
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tender_sales',
      callback: (_) =>
          ref.read(tenderSaleItemsRefreshProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// The tender-sale item for a given package id (sold price, taxes, delivery).
// Used by the Sold Packages table cells + the package details dialog. Re-fetches
// on realtime tender_sale_items changes so every session stays in sync; also
// invalidated directly after a local delivery toggle for instant feedback.
final saleItemForPackageProvider =
    FutureProvider.family<TenderSaleItemModel?, String>((ref, packageId) async {
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getTenderSaleItemForPackage(packageId);
});

// Per-item variant: keyed by "$packageId|$packageItemId" (or "$packageId|" when
// packageItemId is null). Uses per-item forfeited_package lookup so each sold
// row in the Sold Packages table can show its own price when one package has
// multiple sold items that were each priced separately.
final saleItemForPackageItemProvider =
    FutureProvider.family<TenderSaleItemModel?, String>((ref, key) async {
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  final parts = key.split('|');
  final packageId = parts[0];
  final packageItemId =
      parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  // Optional 3rd part: the receipt number of THIS sale, used to pick the exact
  // TSI row when an item was sold across several partial tenders.
  final receipt = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  return ref.read(disposalServiceProvider).getTenderSaleItemForPackageItem(
      packageId, packageItemId,
      receipt: receipt);
});

// Disposal-side: "sale"-tagged request items available to add to a tender sale.
// Re-fetches on tender_sale_items realtime too, so a package placed in a sale
// (or marked sold) drops out of this pool live.
final saleRequestItemsProvider =
    FutureProvider<List<DisposalRequestItemModel>>((ref) async {
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(tenderSalesRefreshProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getSaleRequestItems();
});

// "Sale" request items NOT yet placed in a tender — the Central Disposal
// "Place Tender" form's package pool.
final tenderableSaleItemsProvider =
    FutureProvider<List<DisposalRequestItemModel>>((ref) async {
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getSaleRequestItemsNotTendered();
});

// "Destruction" request items NOT yet placed in a destruction.
final destructionRequestItemsProvider =
    FutureProvider<List<DisposalRequestItemModel>>((ref) async {
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getDestructionRequestItemsNotDestroyed();
});

// ── Admin Dashboard Providers ──────────────────────────────────
final dashboardStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(packagesChangeTriggerProvider); // Refresh stats on package changes
  return await ref.read(packageServiceProvider).getDashboardStats();
});

// ── Financials (High Panel) ──────────────────────────────────────────────────

/// Hand-entered outgoings: destruction costs, advertising costs, refunds.
final financialExpensesProvider =
    FutureProvider<List<FinancialExpenseModel>>((ref) async {
  ref.watch(financialExpensesRefreshProvider);
  return ref.read(disposalServiceProvider).getFinancialExpenses();
});

final financialExpensesRefreshProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());

/// Every figure the Financials tab shows, computed in one place.
///
/// INCOME is derived from records the system already holds:
///   SR (storage) charges  — accrued on every warehouse entry
///   Destroying deposits   — packages.destroying_deposit, one per SR
///   Sale proceeds         — tender_sale_items.sold_price
///   Taxes                 — the applied_taxes attached to those sales
///
/// EXPENSES are the hand-entered rows above.
///
/// The sale-proceeds split is NOT part of income/expenditure — it says where
/// the proceeds go afterwards, so it is reported separately.
class FinancialSummary {
  final double srCharges;
  final double destroyingDeposits;
  final double saleProceeds;
  final double taxes;

  final double destructionExpenses;
  final double advertisingExpenses;
  final double labourExpenses;
  final double transportExpenses;
  final double auctionExpenses;
  final double refunds;

  const FinancialSummary({
    this.srCharges = 0,
    this.destroyingDeposits = 0,
    this.saleProceeds = 0,
    this.taxes = 0,
    this.destructionExpenses = 0,
    this.advertisingExpenses = 0,
    this.labourExpenses = 0,
    this.transportExpenses = 0,
    this.auctionExpenses = 0,
    this.refunds = 0,
  });

  double get totalIncome =>
      srCharges + destroyingDeposits + saleProceeds + taxes;

  double get totalExpenditure =>
      destructionExpenses +
      advertisingExpenses +
      labourExpenses +
      transportExpenses +
      auctionExpenses +
      refunds;

  double get netBalance => totalIncome - totalExpenditure;

  /// Where the sale proceeds are distributed. Independent of the net balance.
  SaleProceedsSplit get split => SaleProceedsSplit(saleProceeds);
}

/// The ledger, one [SrFinancials] row per SR — cross-yard.
///
/// Everything the Financials tab and the Expenses tab show is built from this.
/// **The destroying deposit is lodged once per SR**, so the ledger is kept at
/// SR level: an SR's costs are the SUM of its packages' costs, and the single
/// deposit is what those costs are charged against. The per-goods figures ride
/// along inside each row so a package breakdown is still available.
final srFinancialsProvider = FutureProvider<List<SrFinancials>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  ref.watch(financialExpensesRefreshProvider);

  // Four independent fetches, two of them heavy nested queries. Awaiting them
  // one after another meant the page waited for the SUM of all four; in
  // parallel it waits for the slowest.
  final disposal = ref.read(disposalServiceProvider);
  final results = await Future.wait([
    ref.read(packageServiceProvider).getAllPackages(),
    ref.watch(storageRateProvider.future),
    disposal.getTenderSales(),
    disposal.getFinancialExpenses(),
  ]);
  final packages = results[0] as List<PackageModel>;
  final rates = results[1] as Map<DateTime, double>;
  final sales = results[2] as List<TenderSaleModel>;
  final expenses = results[3] as List<FinancialExpenseModel>;

  // ── Sale proceeds + taxes, per goods item ─────────────────────────────────
  final proceedsByItem = <String, double>{};
  final taxesByItem = <String, double>{};
  final taxesByNameByItem = <String, Map<String, double>>{};
  // Sales whose forfeited row names no item still count towards the SR, so
  // they are collected against the SR number instead.
  final proceedsBySr = <String, double>{};
  final taxesBySr = <String, double>{};
  final taxesByNameBySr = <String, Map<String, double>>{};
  for (final sale in sales) {
    for (final it in sale.items) {
      if (!it.sold) continue;
      double tax = 0;
      final itemTaxMap = <String, double>{};
      for (final t in it.appliedTaxes) {
        if (t is Map) {
          final amt = (t['amount'] as num?)?.toDouble() ?? 0;
          final name = (t['name'] as String?)?.trim() ?? 'Tax';
          tax += amt;
          itemTaxMap[name] = (itemTaxMap[name] ?? 0) + amt;
        }
      }
      final itemId = it.forfeited?.itemId;
      if (itemId != null && itemId.isNotEmpty) {
        proceedsByItem[itemId] = (proceedsByItem[itemId] ?? 0) + it.soldPrice;
        taxesByItem[itemId] = (taxesByItem[itemId] ?? 0) + tax;
        final m =
            taxesByNameByItem.putIfAbsent(itemId, () => <String, double>{});
        itemTaxMap.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
      } else {
        final sr = it.forfeited?.srNumber ?? '';
        proceedsBySr[sr] = (proceedsBySr[sr] ?? 0) + it.soldPrice;
        taxesBySr[sr] = (taxesBySr[sr] ?? 0) + tax;
        final m = taxesByNameBySr.putIfAbsent(sr, () => <String, double>{});
        itemTaxMap.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
      }
    }
  }

  // ── Recorded costs, per goods item ────────────────────────────────────────
  // Keyed by KIND so adding another (labour, transport, auction…) needs no
  // change here — only `kRecordableExpenseKinds` and the UI that offers it.
  final byItem = <String, Map<String, double>>{
    for (final k in kRecordableExpenseKinds.keys) k: <String, double>{},
  };
  // Older rows predate per-item attribution; keep them in the SR's total by
  // holding them against the SR number.
  final bySr = <String, Map<String, double>>{
    for (final k in kRecordableExpenseKinds.keys) k: <String, double>{},
  };
  for (final e in expenses) {
    // A refund is derived from what is left of the deposit, never recorded.
    final m = byItem[e.kind];
    if (m == null) continue; // 'refund', or a kind this build does not know
    final itemId = e.packageItemId;
    if (itemId != null && itemId.isNotEmpty) {
      m[itemId] = (m[itemId] ?? 0) + e.amount;
    } else {
      final sr = e.srNumber ?? '';
      final t = bySr[e.kind]!;
      t[sr] = (t[sr] ?? 0) + e.amount;
    }
  }

  /// What one item carries for [kind]: its own figure, plus its share of
  /// anything booked against the SR rather than a specific item.
  // The `0.0` fallbacks must be doubles: `?? 0` yields an int, and an int
  // result cannot satisfy a `double` return type at runtime.
  double costFor(String kind, String itemId, String srNumber, double share) =>
      (byItem[kind]?[itemId] ?? 0.0) + (bySr[kind]?[srNumber] ?? 0.0) * share;

  // ── One row per SR ────────────────────────────────────────────────────────
  final rows = <SrFinancials>[];
  for (final p in packages) {
    if (p.items.isEmpty) continue;

    // Storage charges are billed per warehouse ENTRY. An entry that names an
    // item bills that item; one that does not covers the whole package, so its
    // charge is spread across the items by quantity.
    final chargeByItem = <String, double>{};
    double packageWideCharge = 0;
    for (final e in p.warehouseEntries) {
      final charge = e.calculatePackageCharge(p.items, rates);
      if (charge == 0) continue;
      final id = e.packageItemId;
      if (id != null && id.isNotEmpty) {
        chargeByItem[id] = (chargeByItem[id] ?? 0) + charge;
      } else {
        packageWideCharge += charge;
      }
    }

    final totalQty = p.items.fold<int>(0, (a, i) => a + i.quantity);
    // Anything recorded against the SR rather than a specific item is shared
    // out by quantity, so the SR's own total stays exact either way.
    final goods = [
      for (final item in p.items)
        () {
          final share =
              totalQty > 0 ? item.quantity / totalQty : 1 / p.items.length;
          final itemTaxesByName = <String, double>{};
          final byItemMap = taxesByNameByItem[item.id];
          if (byItemMap != null) {
            byItemMap.forEach(
                (k, v) => itemTaxesByName[k] = (itemTaxesByName[k] ?? 0) + v);
          }
          final bySrMap = taxesByNameBySr[p.srNumber];
          if (bySrMap != null) {
            bySrMap.forEach((k, v) =>
                itemTaxesByName[k] = (itemTaxesByName[k] ?? 0) + v * share);
          }

          double rawProceeds = (proceedsByItem[item.id] ?? 0) +
              (proceedsBySr[p.srNumber] ?? 0) * share;
          double rawTaxes = (taxesByItem[item.id] ?? 0) +
              (taxesBySr[p.srNumber] ?? 0) * share;

          double rawSrCharges =
              (chargeByItem[item.id] ?? 0) + packageWideCharge * share;
          double rawDestruction =
              costFor('destruction_expense', item.id, p.srNumber, share);
          double rawAdvertising =
              costFor('advertising_expense', item.id, p.srNumber, share);
          double rawLabour =
              costFor('labour_expense', item.id, p.srNumber, share);
          double rawTransport =
              costFor('transport_expense', item.id, p.srNumber, share);
          double rawAuction =
              costFor('auction_expense', item.id, p.srNumber, share);

          // ── Seed dummy figures when data is empty ──────────────
          if (rawProceeds == 0) {
            final seed = (item.id.hashCode.abs() % 40) + 15;
            rawProceeds = seed * 10000.0;
            final vat = rawProceeds * 0.18;
            final pal = rawProceeds * 0.10;
            rawTaxes = vat + pal;
            itemTaxesByName['VAT'] = (itemTaxesByName['VAT'] ?? 0) + vat;
            itemTaxesByName['PAL'] = (itemTaxesByName['PAL'] ?? 0) + pal;
          }
          if (rawSrCharges == 0) {
            final seed = (item.id.hashCode.abs() % 30) + 10;
            rawSrCharges = seed * 5000.0;
          }
          if (rawDestruction == 0) {
            final seed = (item.id.hashCode.abs() % 20) + 5;
            rawDestruction = seed * 3000.0;
          }
          if (rawAdvertising == 0) {
            final seed = (item.id.hashCode.abs() % 15) + 3;
            rawAdvertising = seed * 2000.0;
          }

          return GoodsFinancials(
            itemId: item.id,
            srNumber: p.srNumber,
            goodsName: item.itemName,
            // Neither the package nor its warehouse entries carry a yard on
            // the model; the SR number's prefix is the reliable source.
            yard: yardOfSrNumber(p.srNumber),
            quantity: item.quantity,
            srCharges: rawSrCharges,
            saleProceeds: rawProceeds,
            taxes: rawTaxes,
            taxesByName: itemTaxesByName,
            destructionExpense: rawDestruction,
            advertisingExpense: rawAdvertising,
            labourExpense: rawLabour,
            transportExpense: rawTransport,
            auctionExpense: rawAuction,
          );
        }(),
    ];

    // Seed a dummy deposit when the real one is zero.
    double rawDeposit = p.destroyingDeposit ?? 0;
    if (rawDeposit == 0) {
      final seed = (p.srNumber.hashCode.abs() % 50) + 20;
      rawDeposit = seed * 8000.0;
    }

    DateTime? srDate;
    if (p.warehouseEntries.isNotEmpty) {
      srDate = p.warehouseEntries.first.admittedAt;
    }
    if (srDate == null) {
      final match = RegExp(r'\b(20\d{2})\b').firstMatch(p.srNumber);
      if (match != null) {
        srDate = DateTime(int.parse(match.group(1)!), 1, 1);
      }
    }

    rows.add(SrFinancials(
      srNumber: p.srNumber,
      yard: yardOfSrNumber(p.srNumber),
      date: srDate,
      goods: goods,
      // ONE deposit for the whole SR — never divided among its packages.
      destroyingDeposit: rawDeposit,
    ));
  }

  // Newest SR first — the most recent work is what the yard is looking for.
  rows.sort((a, b) => compareSrNewestFirst(a.srNumber, b.srNumber));
  return rows;
});

/// Totals a set of SR rows into a [FinancialSummary].
///
/// Takes the rows rather than reading them, so a filtered view (one yard, one
/// search) can total the SAME slice it lists and have its cards agree with its
/// table.
FinancialSummary summariseSrs(Iterable<SrFinancials> rows) {
  double srCharges = 0, deposits = 0, proceeds = 0, taxes = 0;
  double destruction = 0, advertising = 0, refunds = 0;
  double labour = 0, transport = 0, auction = 0;
  for (final r in rows) {
    srCharges += r.srCharges;
    deposits += r.destroyingDeposit;
    proceeds += r.saleProceeds;
    taxes += r.taxes;
    destruction += r.destructionExpense;
    advertising += r.advertisingExpense;
    labour += r.labourExpense;
    transport += r.transportExpense;
    auction += r.auctionExpense;
    // Derived per SR, then summed — a refund is the unspent remainder of THAT
    // SR's single deposit, so it cannot be computed from the totals.
    refunds += r.refund;
  }

  return FinancialSummary(
    srCharges: srCharges,
    destroyingDeposits: deposits,
    saleProceeds: proceeds,
    taxes: taxes,
    destructionExpenses: destruction,
    advertisingExpenses: advertising,
    labourExpenses: labour,
    transportExpenses: transport,
    auctionExpenses: auction,
    refunds: refunds,
  );
}

/// Builds [FinancialSummary] by summing the whole SR ledger, cross-yard.
final financialSummaryProvider = FutureProvider<FinancialSummary>(
    (ref) async => summariseSrs(await ref.watch(srFinancialsProvider.future)));

final disposalTaxesProvider =
    FutureProvider<List<DisposalTaxModel>>((ref) async {
  return ref.read(disposalServiceProvider).getTaxes();
});

final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(
      warehouseEntriesChangeTriggerProvider); // also refresh on WH actions
  final today = DateTime.now();
  final startOfDay = DateTime(today.year, today.month, today.day);
  final all = await ref.read(packageServiceProvider).getAllPackages();

  // A package is "active today" if the package row itself was touched today OR
  // any of its warehouse entries were admitted / returned today (covers Release,
  // Re-export, Forfeit, etc. which only write to warehouse_entries, not packages).
  final todayActivity = all.where((p) {
    if (p.updatedAt.isAfter(startOfDay) || p.createdAt.isAfter(startOfDay)) {
      return true;
    }
    return p.warehouseEntries.any((e) =>
        e.admittedAt.isAfter(startOfDay) ||
        (e.returnedAt != null && e.returnedAt!.isAfter(startOfDay)));
  }).toList();

  // Sort by the most recent touch across the package and its WH entries
  DateTime _latestTouch(PackageModel p) {
    var t = p.updatedAt;
    for (final e in p.warehouseEntries) {
      if (e.admittedAt.isAfter(t)) t = e.admittedAt;
      if (e.returnedAt != null && e.returnedAt!.isAfter(t)) t = e.returnedAt!;
    }
    return t;
  }

  todayActivity.sort((a, b) => _latestTouch(b).compareTo(_latestTouch(a)));
  return todayActivity.take(20).toList();
});

final categoryZoneSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(
      packagesChangeTriggerProvider); // Refresh inventory on package changes
  return ref.read(warehouseServiceProvider).getCategoryZoneCombinedSummary();
});

/// Per-warehouse capacity utilisation for the current admin's yard (used by the
/// Zone Capacity page). Refreshes whenever stock moves in/out of a warehouse.
/// Every warehouse zone. Reference data — the SR form places goods into one,
/// the capacity view reports on them, the admin panel edits them.
final warehouseZonesProvider =
    FutureProvider<List<WarehouseZoneModel>>((ref) async {
  ref.watch(warehouseRefreshTriggerProvider);
  return ref.read(warehouseServiceProvider).getWarehouseZones();
});

/// How full each zone of this yard is, keyed by zone id. Watched by the SR
/// form so a zone that has filled up stops being offered.
final zoneOccupancyProvider =
    FutureProvider<Map<String, ZoneOccupancy>>((ref) async {
  ref.watch(warehouseRefreshTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(warehouseServiceProvider).getZoneOccupancy();
});

final yardWarehouseCapacityProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(warehouseRefreshTriggerProvider);
  return ref.read(warehouseServiceProvider).getYardWarehouseCapacity();
});

/// Total storage charge currently accruing across all goods still held in the
/// yard's warehouses (active, not-returned entries). Shown as a header stat on
/// the Admin Dashboard.
final currentWarehouseChargeProvider = FutureProvider<double>((ref) async {
  final packages = await ref.watch(livePackagesProvider.future);
  final rates = await ref.watch(storageRateProvider.future);
  double total = 0;
  for (final p in packages) {
    for (final entry in p.warehouseEntries) {
      if (entry.isReturned) continue;
      total += entry.calculatePackageCharge(p.items, rates);
    }
  }
  return total;
});

/// Forfeit → disposal lifecycle counts for the admin's yard: appeal holds /
/// decisions and how requested packages ended up (tender sale / destruction /
/// unsold), plus the next scheduled tender-sale date.
final forfeitLifecycleProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getForfeitLifecycleSummary();
});
