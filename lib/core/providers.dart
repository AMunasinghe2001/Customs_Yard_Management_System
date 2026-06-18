import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
final packageCategoryServiceProvider = Provider((ref) => PackageCategoryService());
final holdReasonServiceProvider = Provider((ref) => HoldReasonService());
final forfeitedPackageServiceProvider = Provider((ref) => ForfeitedPackageService());
final tendersServiceProvider = Provider((ref) => TendersService());
final disposalServiceProvider = Provider((ref) => DisposalService());
final appealServiceProvider = Provider((ref) => AppealService());
final valuationServiceProvider = Provider((ref) => ValuationService());

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

final warehouseRefreshTriggerProvider = StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final packagesRefreshTriggerProvider = StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());

// ── Realtime: Packages Stream ──────────────────────────────────
final packagesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(packagesRefreshTriggerProvider);
  yield trigger;
  
  final channel = supabase.channel('packages-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'packages',
      callback: (_) => ref.read(packagesRefreshTriggerProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'package_items',
      callback: (_) => ref.read(packagesRefreshTriggerProvider.notifier).trigger(),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'warehouse_entries',
      callback: (_) => ref.read(packagesRefreshTriggerProvider.notifier).trigger(),
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
      callback: (_) => ref.read(warehouseRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Profiles Stream ──────────────────────────────────
final profilesRefreshTriggerProvider = StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final profilesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(profilesRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('profiles-realtime')
    ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: (_) => ref.read(profilesRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Package Categories Stream ──────────────────────────
final categoriesRefreshTriggerProvider = StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final categoryChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(categoriesRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('categories-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'package_categories',
      callback: (_) => ref.read(categoriesRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Shared Data Providers ──────────────────────────────────────
final warehousesProvider = FutureProvider<List<WarehouseModel>>((ref) async {
  ref.watch(warehouseRefreshTriggerProvider);
  return ref.read(warehouseServiceProvider).getWarehouses();
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
  return ref.read(packageServiceProvider).getAllPackages(
      status: filter, search: search.isEmpty ? null : search);
});

// ── Package History server-side pagination ─────────────────────────────────
/// Rows per page on the Package History table.
const int kPackagePageSize = 50;

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
    FutureProvider.family<List<WarehouseEntryModel>, String>((ref, warehouseId) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  final showReturned = ref.watch(warehouseEntryFilterProvider);
  return ref.read(warehouseServiceProvider).getEntriesByWarehouse(
      warehouseId, isReturned: showReturned ? null : false);
});

final allWarehouseEntriesProvider = FutureProvider<List<WarehouseEntryModel>>((ref) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(warehouseServiceProvider).getAllWarehouseEntries();
});

final warehouseStatusFilterProvider = StateProvider.family<String, String>((ref, warehouseId) => 'all');
final warehouseSearchProvider = StateProvider.family<String, String>((ref, id) => '');
final warehouseDateRangeProvider = StateProvider.family<DateTimeRange?, String>((ref, warehouseId) => null);
final warehouseReasonFilterProvider = StateProvider.family<String, String>((ref, warehouseId) => 'all');

final storageRateProvider = FutureProvider<Map<DateTime, double>>((ref) async {
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

final storageRateHistoryProvider = FutureProvider<List<AuditLogModel>>((ref) async {
  final data = await supabase
      .from('storage_rates')
      .select('rate, effective_from, id')
      .order('effective_from', ascending: false);
  
  return data.map((row) => AuditLogModel(
    id: row['id'].toString(),
    userId: 'system',
    action: 'RATE_UPDATE',
    entityType: 'storage_rate',
    entityId: row['id'].toString(),
    createdAt: DateTime.parse(row['effective_from'] as String),
    details: {'rate': (row['rate'] as num).toDouble()},
  )).toList();
});

final packageDataProvider = FutureProvider.family<PackageModel?, String>((ref, id) async {
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
    if (!p.isOnline) return false;
    if (p.lastSeenAt == null) return false;
    return now.difference(p.lastSeenAt!).inMinutes < 5;
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

/// Online members (seen in the last 5 min) within the admin's own yard.
final myYardOnlineProfilesProvider =
    FutureProvider<List<ProfileModel>>((ref) async {
  final mine = await ref.watch(myYardProfilesProvider.future);
  final now = DateTime.now();
  return mine.where((p) {
    if (!p.isOnline) return false;
    if (p.lastSeenAt == null) return false;
    return now.difference(p.lastSeenAt!).inMinutes < 5;
  }).toList();
});

final auditLogsRefreshTriggerProvider = StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final auditLogsChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(auditLogsRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('audit-logs-realtime')
    ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'audit_logs',
        callback: (_) => ref.read(auditLogsRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

final allLogsProvider = FutureProvider<List<AuditLogModel>>((ref) async {
  ref.watch(auditLogsChangeTriggerProvider);
  return ref.read(auditLogServiceProvider).getAllLogs();
});

final packageCategoriesProvider = FutureProvider<List<PackageCategory>>((ref) async {
  ref.watch(categoryChangeTriggerProvider);
  return ref.read(packageCategoryServiceProvider).getCategories();
});

final holdReasonsProvider = FutureProvider<List<HoldReasonModel>>((ref) async {
  return ref.read(holdReasonServiceProvider).getReasons();
});

// ── Forfeited Packages & Tenders Providers ──────────────────
final forfeitedRefreshTriggerProvider = StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());
final forfeitedPackagesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  final trigger = ref.watch(forfeitedRefreshTriggerProvider);
  yield trigger;
  final channel = supabase.channel('forfeited-packages-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'forfeited_packages',
      callback: (_) => ref.read(forfeitedRefreshTriggerProvider.notifier).trigger(),
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

final forfeitedPackagesProvider = FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  // A package becoming SOLD / DESTROYED removes it from this list, so refresh
  // when tender_sale_items / destruction_items change in any session.
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getForfeitedPackages();
});

final expiredAppealPackagesProvider = FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
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
final tenderDateInputProvider = StateProvider<DateTime?>((ref) => DateTime.now());
final selectedTenderPackagesProvider = StateProvider<Set<String>>((ref) => {});

// ── Disposal Directorate Providers ─────────────────────────────
final disposalSelectedYardProvider =
    StateProvider<String>((ref) => kYards.first.code);

final disposalSoldPackagesProvider =
    FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider); // refresh on package changes
  final yard = ref.watch(disposalSelectedYardProvider);
  return ref.read(disposalServiceProvider).getSoldPackages(yard: yard);
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
final appealForfeitedPackagesProvider =
    FutureProvider<List<ForfeitedPackageModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref.read(appealServiceProvider).getForfeitedPackages();
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

final destructionsProvider = FutureProvider<List<DestructionModel>>((ref) async {
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
  // Abandoned / "Other" requestable packages are synthesised from the `packages`
  // table, so a newly registered (or re-statused) package must refresh this too.
  ref.watch(packagesChangeTriggerProvider);
  // A package becoming SOLD / DESTROYED makes it non-requestable, so refresh
  // when tender_sale_items / destruction_items change in any session.
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getRequestableExpiredPackages();
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
        debugPrint('[realtime] disposal_requests ${payload.eventType} → refresh');
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
  return ref.read(disposalServiceProvider).getTenderSaleItemForPackage(packageId);
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
  return ref.read(disposalServiceProvider).getDestructionRequestItemsNotDestroyed();
});

// ── Admin Dashboard Providers ──────────────────────────────────
final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(packagesChangeTriggerProvider); // Refresh stats on package changes
  return await ref.read(packageServiceProvider).getDashboardStats();
});

final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider); // Refresh list on package changes
  final today = DateTime.now();
  final startOfDay = DateTime(today.year, today.month, today.day);
  final all = await ref.read(packageServiceProvider).getAllPackages();
  final todayActivity = all.where((p) => 
    p.updatedAt.isAfter(startOfDay) || p.createdAt.isAfter(startOfDay)
  ).toList();
  
  todayActivity.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return todayActivity.take(20).toList();
});

final categoryZoneSummaryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(packagesChangeTriggerProvider); // Refresh inventory on package changes
  return ref.read(warehouseServiceProvider).getCategoryZoneCombinedSummary();
});

/// Per-warehouse capacity utilisation for the current admin's yard (used by the
/// Zone Capacity page). Refreshes whenever stock moves in/out of a warehouse.
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
