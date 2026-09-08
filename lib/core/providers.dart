import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_client.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'supabase_client.dart';
import 'yards.dart';
import 'directorates.dart';

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
final directorateServiceProvider = Provider((ref) => DirectorateService());

// ── Directorates & yards (ICT-maintained reference data) ───────────────────
//  The lists used to be `const` in the code; they now come from the database
//  so ICT can add a yard without a rebuild. Each falls back to the seed list
//  in yards.dart / directorates.dart when the query fails, so a dropped LAN
//  link degrades to the built-in list instead of an empty picker.

/// Bumped after any ICT edit so every open picker re-reads the lists.
final directorateConfigRefreshProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());

final directoratesProvider =
    FutureProvider<List<DirectorateModel>>((ref) async {
  ref.watch(directorateConfigRefreshProvider);
  try {
    final rows =
        await ref.read(directorateServiceProvider).getDirectorates();
    if (rows.isNotEmpty) return rows;
  } catch (_) {
    // fall through to the seed
  }
  return [
    for (final d in kDirectorates)
      DirectorateModel(code: d.code, name: d.name, srPrefix: d.srPrefix)
  ];
});

final yardsProvider = FutureProvider<List<YardModel>>((ref) async {
  ref.watch(directorateConfigRefreshProvider);
  try {
    final rows = await ref.read(directorateServiceProvider).getYards();
    if (rows.isNotEmpty) return rows;
  } catch (_) {
    // fall through to the seed
  }
  return [
    for (final y in kYards)
      YardModel(code: y.code, name: y.name, srPrefix: y.srPrefix)
  ];
});

/// `{yardCode: [directorateCode, ...]}` — a yard may sit under several.
final yardDirectoratesProvider =
    FutureProvider<Map<String, List<String>>>((ref) async {
  ref.watch(directorateConfigRefreshProvider);
  try {
    final map =
        await ref.read(directorateServiceProvider).getYardDirectorates();
    if (map.isNotEmpty) return map;
  } catch (_) {
    // fall through to the seed
  }
  return kYardDirectorates;
});

/// The yards under one directorate — the registration yard picker's source.
/// Returns every yard when [directorateCode] is null, so the picker is usable
/// before a directorate has been chosen.
/// One entry a yard filter dropdown can offer.
///
/// [filterYard] is what a package/forfeited-package row's OWN `yard` field is
/// compared against — always the bare yard code, e.g. "NNR". [directorate] is
/// set only when this entry represents ONE of several directorates a yard sits
/// under (e.g. "CED/NNR" vs "PSD/NNR"); a row must then ALSO match that
/// directorate's SR-number prefix, which the picking code below applies.
class YardFilterOption {
  final String value; // unique dropdown key, e.g. "NNR" or "NNR|CED"
  final String label; // "Grey Line 1" or "CED/NNR"
  final String filterYard;
  final String? directorate;
  const YardFilterOption(
      {required this.value,
      required this.label,
      required this.filterYard,
      this.directorate});
}

/// The full set of yard-filter dropdown entries, built from ICT's live
/// yards/directorates data.
///
/// EVERY yard is labelled `<DIRECTORATE>/<YARD CODE>` — the same shape as the
/// SR numbers it produces, and as the ICT portal's own "Example SR" column, so
/// "CED/GL1" in the picker reads exactly like the `CED/GL1/SR/25/2026` on the
/// goods. A yard under SEVERAL directorates (NNR is CED and PSD; Katunayaka,
/// Rathmalana and Mattala are B/A and ACD) becomes ONE ENTRY PER DIRECTORATE,
/// because "NNR" alone cannot tell a CED package from a PSD one filed at the
/// same physical yard. A yard with NO directorate keeps its bare code, matching
/// the unprefixed `CVT/SR/01/2026` such a yard still mints.
///
/// ⚠️ The VALUE is only split (`"<yard>|<dir>"`) for a MULTI-directorate yard.
/// A single-directorate yard keeps the bare code even though its label is
/// prefixed: filtering it by yard alone is already exact, and it also keeps
/// matching the legacy unprefixed SR numbers (`GL1/SR/62/2026`) that pre-date
/// directorates — a `"GL1|CED"` value would silently drop those rows.
///
/// Adding or removing a yard/link in the ICT portal changes this list with no
/// rebuild — see [directorateConfigRefreshProvider].
final yardFilterOptionsProvider =
    FutureProvider<List<YardFilterOption>>((ref) async {
  final yards = await ref.watch(yardsProvider.future);
  final directorates = await ref.watch(directoratesProvider.future);
  final yardDirs = await ref.watch(yardDirectoratesProvider.future);
  final byCode = {for (final d in directorates) d.code: d};
  String prefixOf(String dirCode) => byCode[dirCode]?.srPrefix ?? dirCode;

  final out = <YardFilterOption>[];
  for (final y in yards) {
    if (!y.isActive) continue;
    final dirCodes = yardDirs[y.code] ?? const <String>[];
    if (dirCodes.isEmpty) {
      // No directorate yet — its SR numbers carry no prefix either.
      out.add(YardFilterOption(
          value: y.code, label: y.code, filterYard: y.code));
      continue;
    }
    if (dirCodes.length == 1) {
      out.add(YardFilterOption(
          value: y.code,
          label: '${prefixOf(dirCodes.first)}/${y.code}',
          filterYard: y.code,
          directorate: dirCodes.first));
      continue;
    }
    for (final dc in dirCodes) {
      out.add(YardFilterOption(
          value: '${y.code}|$dc',
          label: '${prefixOf(dc)}/${y.code}',
          filterYard: y.code,
          directorate: dc));
    }
  }
  return out;
});

/// `{srPrefix: code}` for every live directorate — feeds
/// [directorateOfSrNumber] so a filter split by directorate (see
/// [yardFilterOptionsProvider]) recognises one ICT added at run time.
final directorateSrPrefixMapProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final directorates = await ref.watch(directoratesProvider.future);
  return {for (final d in directorates) d.srPrefix: d.code};
});

/// Does one row (its `yard` + `srNumber`) match a yard-filter selection?
///
/// [filterValue] is a [YardFilterOption.value] — either a bare yard code
/// ("NNR", from a single-directorate yard or "All Yards" callers passing
/// null) or `"<yard>|<directorate>"` (from a split multi-directorate entry
/// like "CED/NNR"). [prefixToCode] should come from
/// [directorateSrPrefixMapProvider] so a directorate ICT just added is
/// recognised; omit it to fall back to the seed list.
bool matchesYardFilter(String? filterValue, String? rowYard, String rowSrNumber,
    {Map<String, String>? prefixToCode}) {
  if (filterValue == null) return true; // "All Yards"
  final bar = filterValue.indexOf('|');
  if (bar < 0) return rowYard == filterValue;
  final yard = filterValue.substring(0, bar);
  final dir = filterValue.substring(bar + 1);
  if (rowYard != yard) return false;
  return directorateOfSrNumber(rowSrNumber, prefixToCode: prefixToCode) == dir;
}

final yardsForDirectorateProvider =
    FutureProvider.family<List<YardModel>, String?>((ref, directorateCode) async {
  final yards = await ref.watch(yardsProvider.future);
  if (directorateCode == null || directorateCode.isEmpty) return yards;
  final map = await ref.watch(yardDirectoratesProvider.future);
  final allowed = <String>{
    for (final e in map.entries)
      if (e.value.contains(directorateCode)) e.key
  };
  return yards.where((y) => allowed.contains(y.code)).toList();
});

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

// ── Disposition pages: server-side ─────────────────────────────────────────
/// Rows per page on the disposition tables.
///
/// Deliberately equal to `kClientPageSize` in the widgets layer -- the pager
/// under the table has to agree with the query above it or the page numbers
/// mean nothing. It is redeclared rather than imported because the core layer
/// does not depend on widgets.
const int kDispositionPageSize = 20;

/// What one disposition page is asking for.
///
/// ⚠️ A value type with `==` and `hashCode`, because it is a provider FAMILY
/// key: two identical queries must be the SAME key or every rebuild opens a
/// fresh request and the page flickers through loading forever.
@immutable
class DispositionQuery {
  /// 'SOLD' | 'DESTROYED' | 'RE-EXPORTED' | 'OTHER'.
  final String finalTag;
  final int page;
  final String? search;
  final String? yard;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  /// Delivered / Pending on Sold and Destroyed. Null is "All" — which is a
  /// third answer, not the absence of one.
  final bool? delivered;

  /// The Reason dropdown on Released Goods.
  final String? holdReason;

  /// Destroyed Goods' Pending / Destroyed filter — the one page with a middle
  /// state. Null is "All".
  final bool? isDestroyed;

  const DispositionQuery({
    required this.finalTag,
    this.page = 0,
    this.search,
    this.yard,
    this.dateStart,
    this.dateEnd,
    this.year,
    this.delivered,
    this.holdReason,
    this.isDestroyed,
  });

  @override
  bool operator ==(Object other) =>
      other is DispositionQuery &&
      other.finalTag == finalTag &&
      other.page == page &&
      other.search == search &&
      other.yard == yard &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year &&
      other.delivered == delivered &&
      other.holdReason == holdReason &&
      other.isDestroyed == isDestroyed;

  @override
  int get hashCode => Object.hash(
      finalTag, page, search, yard, dateStart, dateEnd, year, delivered,
      holdReason, isDestroyed);
}

/// One page of a disposition table, filtered and paged in SQL.
///
/// Watches the same change triggers the old client-side path did, so an
/// officer recording a disposition still sees the table update -- the work
/// moved to the database, the liveness did not.
final dispositionPageProvider =
    FutureProvider.family<DispositionPage, DispositionQuery>((ref, q) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(packageServiceProvider).getDispositionRowsPaged(
        finalTag: q.finalTag,
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yard: q.yard,
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
        delivered: q.delivered,
        holdReason: q.holdReason,
        isDestroyed: q.isDestroyed,
      );
});

/// One page of disposition rows WITH the packages behind them.
///
/// The rows come from the view; the packages are then fetched for that page
/// alone. ⚠️ Two round trips, both bounded by the page size -- the details
/// popup and the per-sale cells need the whole package, and the old path got
/// it by holding every package in the yard in memory.
typedef DispositionPageWithPackages = ({
  List<DispositionRow> rows,
  Map<String, PackageModel> packages,
  int total,
});

final dispositionPageWithPackagesProvider = FutureProvider.family<
    DispositionPageWithPackages, DispositionQuery>((ref, q) async {
  final page = await ref.watch(dispositionPageProvider(q).future);
  final packages = await ref
      .read(packageServiceProvider)
      .getPackagesByIds([for (final r in page.rows) r.packageId]);
  return (rows: page.rows, packages: packages, total: page.total);
});

/// What one page of a Held Goods table is asking for.
@immutable
class HeldGoodsQuery {
  /// 'DETAINED' | 'ABANDONED' | 'OTHER'.
  final String kind;
  final int page;
  final String? search;

  /// The SR number's own yard segment, not the package's yard column.
  final String? yardSrPrefix;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  /// The Post Status Activity filter; 'all' and null both mean no filter.
  final String? activity;

  const HeldGoodsQuery({
    required this.kind,
    this.page = 0,
    this.search,
    this.yardSrPrefix,
    this.dateStart,
    this.dateEnd,
    this.year,
    this.activity,
  });

  @override
  bool operator ==(Object other) =>
      other is HeldGoodsQuery &&
      other.kind == kind &&
      other.page == page &&
      other.search == search &&
      other.yardSrPrefix == yardSrPrefix &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(
      kind, page, search, yardSrPrefix, dateStart, dateEnd, year, activity);
}

/// One page of a Held Goods table, with the packages behind it.
typedef HeldGoodsPage = ({
  List<({String rowKey, String packageId, String itemId})> keys,
  Map<String, PackageModel> packages,
  int total,
});

final heldGoodsPageProvider =
    FutureProvider.family<HeldGoodsPage, HeldGoodsQuery>((ref, q) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  final page = await ref.read(packageServiceProvider).getHeldGoodsPaged(
        kind: q.kind,
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardSrPrefix: q.yardSrPrefix,
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
        activity: q.activity,
      );
  final packages =
      await ref.read(packageServiceProvider).getPackagesByIds(page.packageIds);
  return (
    keys: [
      for (var i = 0; i < page.rowKeys.length; i++)
        (
          rowKey: page.rowKeys[i],
          packageId: page.packageIds[i],
          itemId: page.itemIds[i],
        )
    ],
    packages: packages,
    total: page.total,
  );
});

/// The header counts a Held Goods page shows — Total / In Appeal / Actionable.
///
/// ⚠️ Its own query. Derived from one page they would contradict the header
/// they sit in, and derived from the whole list they would undo the paging.
typedef HeldGoodsCounts = ({int total, int inAppeal, int actionable});

final heldGoodsCountsProvider =
    FutureProvider.family<HeldGoodsCounts, String>((ref, kind) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  return ref.read(packageServiceProvider).getHeldGoodsCounts(kind);
});

/// The SR numbers on a Held Goods page, for its year filter.
final heldGoodsYearsProvider =
    FutureProvider.family<List<String>, String>((ref, kind) async {
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getHeldGoodsYears(kind);
});

/// What one page of Old Entries is asking for.
@immutable
class OldEntryQuery {
  final int page;
  final String? search;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  const OldEntryQuery({
    this.page = 0,
    this.search,
    this.dateStart,
    this.dateEnd,
    this.year,
  });

  @override
  bool operator ==(Object other) =>
      other is OldEntryQuery &&
      other.page == page &&
      other.search == search &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year;

  @override
  int get hashCode => Object.hash(page, search, dateStart, dateEnd, year);
}

/// One page of Old Entries — packages carrying a legacy SR number.
final oldEntriesPageProvider =
    FutureProvider.family<PackagePage, OldEntryQuery>((ref, q) async {
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getOldEntriesPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
      );
});

/// The years Old Entries offers — from all four places a year can appear, not
/// from the twenty rows currently on screen.
final oldEntryYearsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getOldEntryYears();
});

/// What one page of Perishable Goods is asking for.
@immutable
class PerishableQuery {
  final int page;
  final String? search;

  /// The yard SEGMENT of the SR number, not the package's yard column — the
  /// latter can be the filing directorate rather than the yard holding the
  /// goods.
  final String? yardSrPrefix;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  /// The Post Status Activity filter; 'all' and null both mean no filter.
  final String? activity;

  /// The Final Outcome filter: a proposal, kOutcomeSold, kOutcomeAwaiting,
  /// or null for all.
  final String? outcome;

  const PerishableQuery({
    this.page = 0,
    this.search,
    this.yardSrPrefix,
    this.dateStart,
    this.dateEnd,
    this.year,
    this.activity,
    this.outcome,
  });

  @override
  bool operator ==(Object other) =>
      other is PerishableQuery &&
      other.page == page &&
      other.search == search &&
      other.yardSrPrefix == yardSrPrefix &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year &&
      other.activity == activity &&
      other.outcome == outcome;

  @override
  // ⚠️ outcome is in BOTH == and hashCode, or the family key stays equal
  // across a filter change and the provider never refetches.
  int get hashCode => Object.hash(
      page, search, yardSrPrefix, dateStart, dateEnd, year, activity, outcome);
}

/// One page of Perishable Goods, with the packages behind it.
///
/// ⚠️ The rows name a package and an item; the page needs the whole package
/// for the details popup and the Send Disposal Request flow, so those are
/// fetched for the page's ids alone.
typedef PerishablePage = ({
  List<({String packageId, String itemId})> keys,
  Map<String, PackageModel> packages,

  /// ⚠️ Item ids that SOLD at tender, with the price. A perishable that
  /// sells never reaches the DG -- selling IS its final outcome -- so the page
  /// cannot read the outcome from unsold_proposals alone.
  Map<String, double> soldPriceByItem,
  Map<String, bool> sentByItem,
  Map<String, bool> markedUnsoldByItem,
  int total,
});

final perishablePageProvider =
    FutureProvider.family<PerishablePage, PerishableQuery>((ref, q) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  final page = await ref.read(packageServiceProvider).getPerishableRowsPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardSrPrefix: q.yardSrPrefix,
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
        activity: q.activity,
        outcome: q.outcome,
      );
  final packages = await ref
      .read(packageServiceProvider)
      .getPackagesByIds(page.packageIds);
  return (
    keys: [
      for (var i = 0; i < page.itemIds.length; i++)
        (packageId: page.packageIds[i], itemId: page.itemIds[i])
    ],
    packages: packages,
    soldPriceByItem: page.soldPriceByItem,
    sentByItem: page.sentByItem,
    markedUnsoldByItem: page.markedUnsoldByItem,
    total: page.total,
  );
});

/// Every SR number on Perishable Goods, for its year filter.
final perishableYearsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getPerishableYears();
});

/// Every SR number on one disposition page, for its year filter.
///
/// Keyed by the page's tag. The table pages on the server now, so the loaded
/// rows are one page -- not enough to know which years exist.
final dispositionYearSourceProvider =
    FutureProvider.family<List<String>, String>((ref, finalTag) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getDispositionYears(finalTag);
});

/// Every SR number in Goods History, for its year filter.
///
/// Goods History pages on the server, so the loaded rows are only ever one
/// page -- not enough to know which years exist. This asks for the numbers
/// alone (one small column) so `srYears()` can build the same list every other
/// page builds.
final packageYearSourceProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getPackageYears();
});

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
    final date = parseDbDateRequired(row['effective_from']);
    final rate = parseDbNum(row['rate']) ?? 0;
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

  // Typed explicitly: `data` is dynamic, so a bare .map().toList() infers
  // List<dynamic> and throws on return.
  return [
    for (final row in (data as List))
      AuditLogModel(
        id: row['id'].toString(),
        userId: 'system',
        action: 'RATE_UPDATE',
        entityType: 'storage_rate',
        entityId: row['id'].toString(),
        createdAt: parseDbDateRequired(row['effective_from']),
        details: {'rate': parseDbNum(row['rate']) ?? 0},
      )
  ];
});

final packageDataProvider =
    FutureProvider.family<PackageModel?, String>((ref, id) async {
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getPackageById(id);
});

/// What one page of a warehouse tab is asking for.
///
/// ⚠️ The warehouse id belongs in the key with everything else. The tabs
/// are one widget per facility; a key without it would serve whichever
/// facility asked first, and an officer would be looking at another
/// warehouse's contents under this one's name.
@immutable
class WarehouseQuery {
  final String warehouseId;
  final int page;
  final String status;
  final String reason;
  final String? search;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  const WarehouseQuery({
    required this.warehouseId,
    this.page = 0,
    this.status = 'all',
    this.reason = 'all',
    this.search,
    this.dateStart,
    this.dateEnd,
    this.year,
  });

  @override
  bool operator ==(Object other) =>
      other is WarehouseQuery &&
      other.warehouseId == warehouseId &&
      other.page == page &&
      other.status == status &&
      other.reason == reason &&
      other.search == search &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year;

  @override
  int get hashCode => Object.hash(
      warehouseId, page, status, reason, search, dateStart, dateEnd, year);
}

/// One page of a warehouse's live contents: the entry ids, and how many the
/// filter matches.
typedef WarehousePage = ({List<WarehouseEntryModel> rows, int total});

final warehousePageProvider =
    FutureProvider.family<WarehousePage, WarehouseQuery>((ref, q) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  return ref.read(warehouseServiceProvider).getWarehouseRowsPaged(
        warehouseId: q.warehouseId,
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        status: q.status,
        reason: q.reason,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
      );
});

/// What one facility holds, by item status -- the header's four figures.
///
/// ⚠️ In SQL. The header counted them by reading a package per entry,
/// inside two nested loops, so a facility of 75 entries fired the same
/// per-package fetch four times over.
final warehouseStatusCountsProvider = FutureProvider.family<
    ({int total, int detain, int forfeit, int abandoned}), String>(
        (ref, warehouseId) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  return ref
      .read(warehouseServiceProvider)
      .getWarehouseStatusCounts(warehouseId);
});

/// The reasons, statuses and years one warehouse actually holds.
///
/// ⚠️ Over the whole facility, not the page: an option missing from a
/// dropdown reads as goods that are not there.
final warehouseFilterOptionsProvider = FutureProvider.family<
    ({List<String> reasons, List<String> statuses, List<String> years}),
    String>((ref, warehouseId) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  return ref
      .read(warehouseServiceProvider)
      .getWarehouseFilterOptions(warehouseId);
});

/// The packages behind ONE PAGE of a warehouse's entries, keyed by id.
///
/// ⚠️ One query for the page, not one per row -- and for the PAGE, not the
/// facility.
///
/// The warehouse table read `packageDataProvider(e.packageId)` from inside its
/// row filter AND from inside its row builder: a getPackageById per entry,
/// each pulling the package with its items, its warehouse entries, those
/// entries' warehouses and the returning officer's profile. Measured on
/// Warehouse 01: 52 packages, 249ms as separate calls against 46ms as one.
///
/// It is the same mistake the Destroyed Goods tab was fixed for: paging a
/// table does not page what its CELLS fetch.
final warehousePackagesProvider =
    FutureProvider.family<Map<String, PackageModel>, WarehouseQuery>(
        (ref, q) async {
  ref.watch(packagesChangeTriggerProvider);
  final page = await ref.watch(warehousePageProvider(q).future);
  final ids = page.rows.map((e) => e.packageId).toSet().toList();
  if (ids.isEmpty) return const {};
  return ref.read(packageServiceProvider).getPackagesByIds(ids);
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

/// One page of the Admin screen's activity log.
///
/// ⚠️ The screen fetched a YEAR of rows and paged them in Dart --
/// retention keeps twelve months, so that fetch grows all year and is largest
/// exactly when an admin most wants to look something up. 166 rows, 344ms,
/// against 45ms for a page.
final yardLogsPageProvider = FutureProvider.family<
    ({List<AuditLogModel> rows, int total}), int>((ref, page) async {
  ref.watch(auditLogsChangeTriggerProvider);
  return ref.read(auditLogServiceProvider).getYardLogsPaged(
        offset: page * kDispositionPageSize,
        limit: kDispositionPageSize,
      );
});

final allLogsProvider = FutureProvider<List<AuditLogModel>>((ref) async {
  ref.watch(auditLogsChangeTriggerProvider);
  return ref.read(auditLogServiceProvider).getAllLogs();
});

/// The date window the ICT Activity Logs tab is showing, or null for "all".
///
/// Held as state rather than filtered client-side so the window is pushed into
/// SQL — the log is the one table that grows without bound between purges.
final ictLogRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Every log across every yard and directorate, for the ICT Directorate.
///
/// Re-fetches when the date window changes. Cross-office by design: ICT
/// provisions all these accounts, so unlike [allLogsProvider] this is scoped
/// to no yard and drops nobody's role.
/// What page of the log, narrowed how.
///
/// ⚠️ Every field is part of the provider's identity, so changing a filter or
/// turning a page is a NEW query rather than a re-filter of rows already held.
/// That is the point: the screen keeps one page, not the table.
class IctLogQuery {
  final String? yard;
  final String? role;
  final String? entityType;
  final String search;
  final int page;
  final int pageSize;

  const IctLogQuery({
    this.yard,
    this.role,
    this.entityType,
    this.search = '',
    this.page = 0,
    this.pageSize = 25,
  });

  @override
  bool operator ==(Object other) =>
      other is IctLogQuery &&
      other.yard == yard &&
      other.role == role &&
      other.entityType == entityType &&
      other.search == search &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode =>
      Object.hash(yard, role, entityType, search, page, pageSize);
}

final ictLogQueryProvider =
    StateProvider<IctLogQuery>((ref) => const IctLogQuery());

final ictAllOfficeLogsProvider = FutureProvider<AuditLogPage>((ref) async {
  ref.watch(auditLogsChangeTriggerProvider);
  final range = ref.watch(ictLogRangeProvider);
  final q = ref.watch(ictLogQueryProvider);
  return ref.read(auditLogServiceProvider).getAllLogsAcrossOffices(
        from: range?.start,
        // The picker hands back a date, so the end day is inclusive only if
        // we reach the end OF that day.
        to: range == null
            ? null
            : DateTime(range.end.year, range.end.month, range.end.day, 23, 59,
                59),
        yard: q.yard,
        role: q.role,
        entityType: q.entityType,
        search: q.search,
        offset: q.page * q.pageSize,
        limit: q.pageSize,
      );
});

/// The years the Activity Logs date pickers offer.
///
/// Its own query for the same reason the entity list is: the screen holds one
/// page, so a list built from the rows on screen would name the years that
/// happened to be on that page.
final ictLogYearsProvider = FutureProvider<List<int>>((ref) async {
  ref.watch(auditLogsChangeTriggerProvider);
  return ref.read(auditLogServiceProvider).auditLogYears();
});

/// The entity types the Activity filter offers.
///
/// Its own query: the screen holds one page now, so a list built from the
/// rows on screen would offer whatever happened to be on that page.
final ictLogEntityTypesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(auditLogsChangeTriggerProvider);
  return ref.read(auditLogServiceProvider).auditEntityTypes();
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

/// The forfeited row for each item of one package, keyed by item id.
///
/// ⚠️ Unfiltered on purpose -- see `getForfeitedByItemForPackage`. The SR popup
/// uses this to show each item's OWN tender history, so it must still find the
/// items that have already been sold or destroyed, which every other forfeited
/// provider deliberately drops.
final forfeitedByItemProvider =
    FutureProvider.family<Map<String, ForfeitedPackageModel>, String>(
        (ref, packageId) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref
      .read(forfeitedPackageServiceProvider)
      .getForfeitedByItemForPackage(packageId);
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

/// What one page of the Forfeited table is asking for.
@immutable
class ForfeitQuery {
  final int page;
  final String? search;
  final String? yardFilter;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;
  final String activity;

  const ForfeitQuery({
    this.page = 0,
    this.search,
    this.yardFilter,
    this.dateStart,
    this.dateEnd,
    this.year,
    this.activity = 'all',
  });

  @override
  bool operator ==(Object other) =>
      other is ForfeitQuery &&
      other.page == page &&
      other.search == search &&
      other.yardFilter == yardFilter &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(
      page, search, yardFilter, dateStart, dateEnd, year, activity);
}

typedef ForfeitPage = ({
  List<ForfeitRowData> rows,
  int total,
  /// The forfeited records behind THIS page, for the appeal column and the
  /// details popup.
  Map<String, ForfeitedPackageModel> packages,
});

/// One page of the yard's Forfeited table.
///
/// ⚠️ 122 lines of Dart moved into `forfeit_rows` (postgres/49). The screen
/// built its rows by walking every forfeited package with its items and
/// warehouse entries, and had no pager at all -- 48 rows rendered at once, and
/// growing with the yard.
final forfeitPageProvider =
    FutureProvider.family<ForfeitPage, ForfeitQuery>((ref, q) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getForfeitRowsPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
        activity: q.activity,
      );
});

/// The Forfeited header's two figures, counted over the whole table.
final forfeitCountsProvider =
    FutureProvider<({int total, int actionable})>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getForfeitCounts();
});

/// The SR years the Forfeited table's year filter offers.
///
/// ⚠️ Over the whole table, not the page.
final forfeitRowYearsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getForfeitRowYears();
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
// The tender rounds ONE package sat in, oldest first. The Tender History used
// to derive this from tenderSalesProvider (every sale, with items, packages and
// warehouses attached) — free on Central Disposal, where the Tender Sales tab
// has already cached it, but a cold ~120ms fetch on the yard's Sold Goods page,
// which is why that popup's history appeared late.
final tenderRoundsForPackageProvider = FutureProvider.family<
    List<
        ({
          String id,
          DateTime createdAt,
          bool hasRun,
          bool sold,
          double? soldPrice
        })>,
    String>((ref, fpId) async {
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getTenderRoundsForPackage(fpId);
});

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
// ── Unsold proposals (Top Management Directorate's final outcome) ──────────────────────────
// The packages that exhausted every avenue: past Tender 3, committee valuation
// submitted by the ADG, tendered again, still unsold. Shared by the Top Management Directorate,
// Central Disposal and the yards so all three lists agree.
/// Perishables that failed their one Special Tender Sale, awaiting Top
/// Management's decision. Separate from [exhaustedUnsoldProvider] because the
/// route there is entirely different -- no committee, no second chance.
final unsoldPerishablesProvider =
    FutureProvider<List<ReTenderSaleInfo>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getUnsoldPerishables();
});

final exhaustedUnsoldProvider =
    FutureProvider<List<ReTenderSaleInfo>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getExhaustedUnsoldPackages();
});

/// What one page of Unsold Goods is asking for.
///
/// ⚠️ A value type, like [DispositionQuery] and for the same reason: a family
/// key without value equality opens a fresh request on every rebuild.
@immutable
class ExhaustedUnsoldQuery {
  final int page;
  final String? search;
  final String? yard;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  /// The Decided / Awaiting filter. Null is "All" — a third answer.
  /// The page's Final Outcome filter: one of kUnsoldProposals,
  /// kOutcomeAwaiting, or null for all.
  ///
  /// ⚠️ Replaces a decided/awaiting flag. "Decided" lumped all six outcomes
  /// together, which is not a question an officer asks -- they want the ones
  /// going to auction, or back out of the country.
  final String? outcome;

  /// One of the four Final Outcome pages; null is Unsold Goods itself.
  final String? proposal;

  /// The All / Pending / Delivered filter. Null is "All".
  final bool? delivered;

  /// Serve the Unsold PERISHABLES list instead.
  ///
  /// ⚠️ Part of the key, so the two tabs cannot share a cached page. They
  /// are different lists reached by different routes -- one failed Special
  /// Tender Sale versus five failed chances and a committee.
  final bool perishable;

  const ExhaustedUnsoldQuery({
    this.page = 0,
    this.search,
    this.yard,
    this.dateStart,
    this.dateEnd,
    this.year,
    this.outcome,
    this.proposal,
    this.delivered,
    this.perishable = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ExhaustedUnsoldQuery &&
      other.page == page &&
      other.search == search &&
      other.yard == yard &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year &&
      other.outcome == outcome &&
      other.proposal == proposal &&
      other.delivered == delivered &&
      other.perishable == perishable;

  @override
  int get hashCode => Object.hash(page, search, yard, dateStart, dateEnd, year,
      outcome, proposal, delivered, perishable);
}

/// One page of Unsold Goods, chosen and filtered by the database.
typedef ExhaustedUnsoldPage = ({List<ReTenderSaleInfo> rows, int total});

final exhaustedUnsoldPageProvider = FutureProvider.family<ExhaustedUnsoldPage,
    ExhaustedUnsoldQuery>((ref, q) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getExhaustedUnsoldPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yard: q.yard,
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
        outcome: q.outcome,
        proposal: q.proposal,
        delivered: q.delivered,
        perishable: q.perishable,
      );
});

/// What one page of the re-tender pool is asking for.
@immutable
class UnsoldRetenderQuery {
  final int page;
  final String? search;
  final String? yardFilter;

  /// Committees only: narrow to packages that HAVE a committee.
  ///
  /// ⚠️ Central Disposal watches appointed committees; Top Management
  /// APPOINTS them, so its tab must show the packages with none yet -- or the
  /// one thing that page is for would be impossible.
  final bool appointedOnly;

  /// Valuation only: hide packages past the fourth round.
  ///
  /// ⚠️ Past four a package belongs to Top Management -- a committee
  /// prices it -- so the Valuation Directorate has no work left on it, and a
  /// row it cannot act on is worse than no row.
  final bool valuationRoundsOnly;

  /// Pending (false) / already valued (true) / both (null).
  final bool? valued;

  const UnsoldRetenderQuery(
      {this.page = 0,
      this.search,
      this.yardFilter,
      this.appointedOnly = true,
      this.valuationRoundsOnly = false,
      this.valued});

  @override
  bool operator ==(Object other) =>
      other is UnsoldRetenderQuery &&
      other.page == page &&
      other.search == search &&
      other.yardFilter == yardFilter &&
      other.appointedOnly == appointedOnly &&
      other.valuationRoundsOnly == valuationRoundsOnly &&
      other.valued == valued;

  @override
  // ⚠️ In BOTH, or the two tabs share a cached page and one shows the
  // other portal's list.
  int get hashCode => Object.hash(
      page, search, yardFilter, appointedOnly, valuationRoundsOnly, valued);
}

/// One page of the re-tender pool, chosen in SQL.
/// One page of the re-tender pool, and which of its rows are already priced.
typedef RetenderPage = ({
  List<ReTenderSaleInfo> rows,
  /// ⚠️ Read off the SAME rows the page came from. This used to be
  /// `valuedCurrentRoundProvider`, which called getUnsoldTenderSales() -- the
  /// heaviest query in the app -- a SECOND time to learn one boolean per row.
  Set<String> valued,
  int total,
});

final unsoldRetenderPageProvider =
    FutureProvider.family<RetenderPage, UnsoldRetenderQuery>((ref, q) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getUnsoldRetenderPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
        valuationRoundsOnly: q.valuationRoundsOnly,
        valued: q.valued,
      );
});

/// "N of M awaiting valuation", over the whole filter rather than the page.
final unsoldRetenderCountsProvider =
    FutureProvider.family<({int pending, int total}), UnsoldRetenderQuery>(
        (ref, q) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getUnsoldRetenderCounts(
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
        valuationRoundsOnly: q.valuationRoundsOnly,
      );
});

/// One page of the Committees tab — the re-tender pool narrowed to packages
/// on their fourth round that have a committee appointed.
final committeesPageProvider = FutureProvider.family<ExhaustedUnsoldPage,
    UnsoldRetenderQuery>((ref, q) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getCommitteesPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
        // Central Disposal watches appointed committees; Top Management
        // appoints them and must see the packages with none yet.
        appointedOnly: q.appointedOnly,
      );
});

/// Every SR number on Unsold Goods, for its year filter — one small column,
/// because a page of twenty cannot know which years the table covers.
final exhaustedUnsoldYearsProvider =
    FutureProvider<List<String>>((ref) async {
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getExhaustedUnsoldYears();
});

// The recorded final outcomes, keyed by forfeited_package_id.
/// The DG's final outcomes keyed by package_item_id, for pages that list
/// items rather than forfeited packages (Perishable Goods).
final unsoldProposalsByItemProvider =
    FutureProvider<Map<String, UnsoldProposalModel>>((ref) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getUnsoldProposalsByItem();
});

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
/// What one page of an Appeal tab is asking for.
///
/// ⚠️ `decided` belongs in the key as much as the page number does. The two
/// tabs are one query with one flag flipped; a key without it would serve the
/// Decided tab whatever Active had cached, and an officer would be looking at
/// closed appeals believing they were open.
@immutable
class AppealQuery {
  final int page;
  final bool decided;
  final String? search;
  final String? yardFilter;

  const AppealQuery({
    this.page = 0,
    required this.decided,
    this.search,
    this.yardFilter,
  });

  @override
  bool operator ==(Object other) =>
      other is AppealQuery &&
      other.page == page &&
      other.decided == decided &&
      other.search == search &&
      other.yardFilter == yardFilter;

  @override
  int get hashCode => Object.hash(page, decided, search, yardFilter);
}

/// One page of an Appeal tab, with the counts its stat chips show.
typedef AppealPage = ({
  List<ForfeitedPackageModel> rows,
  int total,
  /// ⚠️ Counted over the whole ACTIVE set under the same filters, on either
  /// tab -- these chips describe the directorate's workload, not the page.
  int active,
  int inWindow,
  int held,
});

/// The Appeal Directorate's feed, a page at a time.
///
/// ⚠️ Both tabs used to watch [appealForfeitedPackagesProvider] -- every
/// forfeited package in the country with its package, items and warehouse
/// entries -- then filter it and page it with `pageSlice`. Client-side paging
/// still loads everything; it only renders less. `appeal_rows` (postgres/45)
/// carries all five membership rules.
final appealPageProvider =
    FutureProvider.family<AppealPage, AppealQuery>((ref, q) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  return ref.read(appealServiceProvider).getAppealRowsPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        decided: q.decided,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
      );
});

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

/// What one page of Tender Sales is asking for.
@immutable
class TenderSaleQuery {
  final int page;
  final String? search;
  final String? yardFilter;

  /// Hide sales with nothing left to act on. Central Disposal's own tab does;
  /// the read-only views show everything.
  final bool onlyPending;

  /// The yard page's own date filters.
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  const TenderSaleQuery({
    this.page = 0,
    this.search,
    this.yardFilter,
    this.onlyPending = false,
    this.dateStart,
    this.dateEnd,
    this.year,
  });

  @override
  bool operator ==(Object other) =>
      other is TenderSaleQuery &&
      other.page == page &&
      other.search == search &&
      other.yardFilter == yardFilter &&
      other.onlyPending == onlyPending &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year;

  @override
  int get hashCode => Object.hash(
      page, search, yardFilter, onlyPending, dateStart, dateEnd, year);
}

typedef TenderSalePage = ({List<TenderSaleModel> rows, int total});

/// One page of Tender Sales, chosen in SQL and then loaded in full.
final tenderSalesPageProvider =
    FutureProvider.family<TenderSalePage, TenderSaleQuery>((ref, q) async {
  ref.watch(tenderSalesRefreshProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getTenderSalesPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
        onlyPending: q.onlyPending,
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
      );
});

/// The years the Tender Sale page's year filter offers.
///
/// ⚠️ Over ALL sales, not the page. A dropdown built from one page offers
/// only the years on screen, and a year that is not listed reads as records
/// that no longer exist.
final tenderSaleYearsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(tenderSalesRefreshProvider);
  return ref.read(disposalServiceProvider).getTenderSaleYears();
});

/// The sales that RE-TENDER goods from an earlier one.
///
/// ⚠️ Its own query over ALL sales. Derived from one page, a sale would be
/// marked as new simply because its predecessor sat on the page before.
final retenderSaleIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(tenderSalesRefreshProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getRetenderSaleIds();
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

/// What one page of the yard's Destruction page is asking for.
@immutable
class DestructionQuery {
  final int page;
  final String? search;
  final String? yardFilter;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? year;

  const DestructionQuery({
    this.page = 0,
    this.search,
    this.yardFilter,
    this.dateStart,
    this.dateEnd,
    this.year,
  });

  @override
  bool operator ==(Object other) =>
      other is DestructionQuery &&
      other.page == page &&
      other.search == search &&
      other.yardFilter == yardFilter &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd &&
      other.year == year;

  @override
  int get hashCode =>
      Object.hash(page, search, yardFilter, dateStart, dateEnd, year);
}

typedef DestructionPage = ({List<DestructionModel> rows, int total});

/// One page of destructions, chosen in SQL and then loaded in full.
final destructionsPageProvider =
    FutureProvider.family<DestructionPage, DestructionQuery>((ref, q) async {
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getDestructionsPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
        dateStart: q.dateStart,
        dateEnd: q.dateEnd,
        year: q.year,
      );
});

/// The years the destruction year filter offers, over ALL destructions.
final destructionYearsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getDestructionYears();
});

/// The destructions that RE-DESTROY goods from an earlier one.
///
/// ⚠️ Its own query over ALL destructions. Derived from one page, a
/// destruction would be marked new simply because its predecessor sat on the
/// page before.
final redestructionIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(disposalServiceProvider).getRedestructionIds();
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

/// What one page of Disposal Requests is asking for.
@immutable
class DisposalRequestQuery {
  final int page;
  final String? search;
  final String? yardFilter;

  const DisposalRequestQuery({this.page = 0, this.search, this.yardFilter});

  @override
  bool operator ==(Object other) =>
      other is DisposalRequestQuery &&
      other.page == page &&
      other.search == search &&
      other.yardFilter == yardFilter;

  @override
  int get hashCode => Object.hash(page, search, yardFilter);
}

typedef DisposalRequestPage = ({List<DisposalRequestModel> rows, int total});

/// One page of Disposal Requests, chosen in SQL and then loaded in full.
final disposalRequestsPageProvider = FutureProvider.family<DisposalRequestPage,
    DisposalRequestQuery>((ref, q) async {
  ref.watch(disposalRequestsChangeTriggerProvider);
  // A new tender / destruction sale consumes request items, so they must drop
  // off this feed immediately — watch those refresh signals too.
  ref.watch(tenderSalesRefreshProvider);
  ref.watch(destructionsRefreshProvider);
  return ref.read(disposalServiceProvider).getDisposalRequestsPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
      );
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
/// What one page of a Valuation feed tab is asking for.
///
/// ⚠️ `perishable` is in the key as much as the page number is. The two
/// tabs are the same widget with one flag flipped, so a key that left it out
/// would serve the perishable tab whatever the ordinary tab had cached -- and
/// the officer would be costing goods on the wrong clock.
@immutable
class ValuationFeedQuery {
  final int page;
  final bool perishable;
  final String? search;
  final String? yardFilter;

  const ValuationFeedQuery({
    this.page = 0,
    required this.perishable,
    this.search,
    this.yardFilter,
  });

  @override
  bool operator ==(Object other) =>
      other is ValuationFeedQuery &&
      other.page == page &&
      other.perishable == perishable &&
      other.search == search &&
      other.yardFilter == yardFilter;

  @override
  int get hashCode => Object.hash(page, perishable, search, yardFilter);
}

/// One page of a Valuation feed tab, plus how many the filter matches.
typedef ValuationFeedPage = ({List<DisposalRequestModel> rows, int total});

/// The Valuation Directorate's feed, a page at a time.
///
/// ⚠️ This portal had NO paging -- not SQL, not even client-side. Every
/// request awaiting valuation was fetched through a six-level embed and
/// rendered at once. `valuation_rows` (postgres/42) carries both membership
/// rules, so the page and the count are SQL and the deep fetch runs for one
/// page of requests.
final valuationFeedPageProvider =
    FutureProvider.family<ValuationFeedPage, ValuationFeedQuery>((ref, q) async {
  ref.watch(disposalRequestsChangeTriggerProvider);
  return ref.read(valuationServiceProvider).getValuationFeedPaged(
        offset: q.page * kDispositionPageSize,
        limit: kDispositionPageSize,
        perishable: q.perishable,
        search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        yardFilter: q.yardFilter,
      );
});

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

// ── Financials (Top Management Directorate) ──────────────────────────────────────────────────

/// Hand-entered outgoings: destruction costs, advertising costs, refunds.
final financialExpensesProvider =
    FutureProvider<List<FinancialExpenseModel>>((ref) async {
  ref.watch(financialExpensesRefreshProvider);
  return ref.read(disposalServiceProvider).getFinancialExpenses();
});

final financialExpensesRefreshProvider =
    StateNotifierProvider<RefreshTrigger, int>((ref) => RefreshTrigger());


/// The ledger, one [SrFinancials] row per SR — cross-yard.
///
/// Everything the Financials tab and the Expenses tab show is built from this.
/// **The destroying deposit is lodged once per SR**, so the ledger is kept at
/// SR level: an SR's costs are the SUM of its packages' costs, and the single
/// deposit is what those costs are charged against. The per-goods figures ride
/// along inside each row so a package breakdown is still available.
/// The SR ledger for a given set of packages.
///
/// ⚠️ Extracted from `srFinancialsProvider` so the EXPENSES tab can build
/// the same rows for ONE PAGE of SRs. The provider below still passes every
/// package -- the Financials tab genuinely sums the whole ledger -- but a tab
/// that shows twenty rows should not have to.
///
/// The nested shape is why this is a function rather than a view: the table
/// and its detail dialog read the per-item `goods` list, and reproducing that
/// in SQL would be a second definition of the same figures.
List<SrFinancials> buildSrFinancials({
  required List<PackageModel> packages,
  required Map<DateTime, double> rates,
  required List<TenderSaleModel> sales,
  required List<FinancialExpenseModel> expenses,
}) {

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
          final amt = parseDbNum(t['amount']) ?? 0;
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

          // Zero is a real, meaningful answer here -- "nothing recorded yet"
          // -- and must reach the UI as zero. A fake-seeded placeholder used
          // to sit here instead, inventing a plausible-looking proceeds/tax/
          // destruction/advertising figure out of the item id's hash whenever
          // the true recorded value was zero. That made every screen reading
          // this provider (Financials tab, Expenses tab, and the Destroyed
          // Goods popup) show money nobody had actually recorded, with no way
          // to tell a real LKR 0 apart from an invented one.

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

    // A zero deposit is real: it means none was lodged, or none was recorded
    // on the SR form. It used to be replaced with an invented figure here.
    final double rawDeposit = p.destroyingDeposit ?? 0;

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
}

final srFinancialsProvider = FutureProvider<List<SrFinancials>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  ref.watch(financialExpensesRefreshProvider);

  // ⚠️ Four fetches, awaited ONE AFTER ANOTHER. Future.wait is slower here,
  // which is the opposite of what it looks like.
  //
  // Measured against the live database, three runs, warm:
  //
  //     one after another   167ms  186ms  204ms
  //     Future.wait         298ms  303ms  371ms
  //
  // The wait is not the network. Postgres answers the packages query in 15ms;
  // the rest is the driver turning rows into Dart objects, and that runs on
  // this isolate. Issued together, the four responses arrive together and then
  // queue behind each other to be decoded on the one thread -- so nothing
  // finishes sooner, every query's own latency grows, and the scheduling is
  // pure overhead. Alone: packages 146ms, sales 74ms, expenses 54ms, rates
  // 6ms; together those same rates took 167ms.
  //
  // Making these parallel again means measuring it again, not reasoning about
  // it: a test pins the serial shape.
  final disposal = ref.read(disposalServiceProvider);

  // ⚠️ The LEDGER's packages, not every package with every embed.
  // getAllPackages() also brings each entry's warehouse and the returning
  // officer's profile, plus the inspecting officer's -- 419 kB of JSON the
  // financial roll-up never reads, and 130-210ms of driver time to decode.
  final packages = await ref.read(packageServiceProvider).getPackagesForLedger();
  // ⚠️ The ledger's cut of the sales, stopping at the forfeited row.
  // getTenderSales() goes three levels further -- packages, their items and
  // their warehouse entries -- none of which buildSrFinancials reads.
  final sales = await disposal.getTenderSalesForLedger();
  final rates = await ref.watch(storageRateProvider.future);
  final expenses = await disposal.getFinancialExpenses();

  return buildSrFinancials(
    packages: packages,
    rates: rates,
    sales: sales,
    expenses: expenses,
  );
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
/// Destruction spend for a PAGE of SR numbers, keyed by SR.
///
/// ⚠️ Keyed by the joined list so a page is one query, not one per row. The
/// Destroyed Goods cell used to watch `srFinancialsProvider` — the whole yard
/// ledger — from inside each row, which is what made that tab lag.
/// A page's forfeited-package ids as one stable family key.
///
/// ⚠️ SORTED and de-duplicated. A family key is compared by value, so
/// an unstable one opens a fresh query on every rebuild -- trading one slow
/// load for a permanent one. This is the same key shape `destructionSpendProvider`
/// uses, and for the same reason.
String packageKeyOf(Iterable<String> ids) =>
    (ids.where((s) => s.trim().isNotEmpty).toSet().toList()..sort()).join('|');

List<String> _idsFromKey(String key) =>
    key.split('|').where((s) => s.trim().isNotEmpty).toList();

/// The bids for ONE PAGE of packages: package id -> round id -> amounts.
///
/// ⚠️ `tenderBidsProvider` is keyed by a single package and the tables
/// read it from inside their ROW BUILDERS -- twenty rows, twenty round trips.
/// Measured at page size: 57ms as separate calls against 22ms as one.
///
/// The mistake the Destroyed Goods tab and then the Warehouses page were both
/// fixed for: paging a table does not page what its CELLS fetch.
final pageBidsProvider =
    FutureProvider.family<Map<String, Map<String, List<double>>>, String>(
        (ref, key) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getTenderBidsForPackages(_idsFromKey(key));
});

/// The re-valuations for ONE PAGE of packages.
///
/// ⚠️ Measured at page size: 74ms as separate calls against 14ms as one.
final pageRevaluationsProvider = FutureProvider.family<
    Map<String, Map<String, TenderRevaluationModel>>, String>((ref, key) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getTenderRevaluationsForPackages(_idsFromKey(key));
});

/// The committees for ONE PAGE of packages.
///
/// ⚠️ The tables read this as a lookup -- one `[fpId]` per row -- but
/// fetched every committee in the country to serve it, from six places. Eight
/// rows today; the pool is fed by all twenty-eight yards, and a committee is
/// appointed for every package that survives four tender rounds.
final pageCommitteesProvider =
    FutureProvider.family<Map<String, TenderCommitteeModel>, String>(
        (ref, key) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getTenderCommitteesForPackages(_idsFromKey(key));
});

/// The DG's rulings for ONE PAGE of packages.
final pageProposalsProvider =
    FutureProvider.family<Map<String, UnsoldProposalModel>, String>(
        (ref, key) async {
  ref.watch(tenderBidsChangeTriggerProvider);
  return ref
      .read(disposalServiceProvider)
      .getUnsoldProposalsForPackages(_idsFromKey(key));
});

final destructionSpendProvider =
    FutureProvider.family<Map<String, double>, String>((ref, srKey) async {
  ref.watch(financialExpensesRefreshProvider);
  final srNumbers =
      srKey.split('|').where((s) => s.trim().isNotEmpty).toList();
  return ref.read(packageServiceProvider).getDestructionSpendBySr(srNumbers);
});

/// What one page of the Disposal Expenses tab is asking for.
@immutable
class ExpenseQuery {
  final int page;
  final String? search;
  final String? yardFilter;
  final DateTime? dateStart;
  final DateTime? dateEnd;

  const ExpenseQuery({
    this.page = 0,
    this.search,
    this.yardFilter,
    this.dateStart,
    this.dateEnd,
  });

  @override
  bool operator ==(Object other) =>
      other is ExpenseQuery &&
      other.page == page &&
      other.search == search &&
      other.yardFilter == yardFilter &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd;

  @override
  int get hashCode =>
      Object.hash(page, search, yardFilter, dateStart, dateEnd);
}

/// One page of the Disposal Expenses tab, with the totals across ALL of it.
///
/// ⚠️ `totals` is a separate query on purpose. The strip sums every filtered
/// SR, not the page — computing it from twenty rows would report a fraction of
/// the money and quietly understate what the directorate has spent.
typedef ExpensePage = ({
  List<SrFinancials> rows,
  Map<String, double> totals,
  int total,
});

final expensePageProvider =
    FutureProvider.family<ExpensePage, ExpenseQuery>((ref, q) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  ref.watch(financialExpensesRefreshProvider);

  final disposal = ref.read(disposalServiceProvider);
  // ⚠️ On PackageService, not DisposalService: the view is about SRs and the
  // packages behind them, which is that service's subject.
  final packageSvc = ref.read(packageServiceProvider);
  final ids = await packageSvc.getExpenseSrPageIds(
    offset: q.page * kDispositionPageSize,
    limit: kDispositionPageSize,
    search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
    yardFilter: q.yardFilter,
    dateStart: q.dateStart,
    dateEnd: q.dateEnd,
  );

  // The totals run whatever the page holds — including an empty one, where
  // they must still report the money the filter matches.
  final totals = await packageSvc.getExpenseTotals(
    search: (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
    yardFilter: q.yardFilter,
    dateStart: q.dateStart,
    dateEnd: q.dateEnd,
  );

  if (ids.packageIds.isEmpty) {
    return (rows: const <SrFinancials>[], totals: totals, total: ids.total);
  }

  // ⚠️ The heavy part, for THIS page's packages only. The nested goods list is
  // what the table and its dialog read, so it cannot come from the view.
  // ⚠️ One after another, for the reason [srFinancialsProvider] measures:
  // the four decode on this isolate, so issuing them together only makes each
  // one wait longer for the same total work.
  final byId = await packageSvc.getPackagesByIds(ids.packageIds);
  // ⚠️ The ledger's cut of the sales, stopping at the forfeited row.
  // getTenderSales() goes three levels further -- packages, their items and
  // their warehouse entries -- none of which buildSrFinancials reads.
  final sales = await disposal.getTenderSalesForLedger();
  final rates = await ref.watch(storageRateProvider.future);
  final expenses = await disposal.getFinancialExpenses();

  final rows = buildSrFinancials(
    packages: [for (final id in ids.packageIds) if (byId[id] != null) byId[id]!],
    rates: rates,
    sales: sales,
    expenses: expenses,
  );
  return (rows: rows, totals: totals, total: ids.total);
});

final financialSummaryProvider = FutureProvider<FinancialSummary>(
    (ref) async => summariseSrs(await ref.watch(srFinancialsProvider.future)));

final disposalTaxesProvider =
    FutureProvider<List<DisposalTaxModel>>((ref) async {
  return ref.read(disposalServiceProvider).getTaxes();
});

/// What one page of the Financials tab is asking for.
///
/// ⚠️ Every field appears in BOTH `==` and `hashCode`. A family key that
/// forgets one never refetches when that field changes -- the page silently
/// keeps showing the previous filter's rows.
@immutable
class FinancialsQuery {
  final int page;
  final String? search;
  final String? yardFilter;
  final DateTime? dateStart;
  final DateTime? dateEnd;

  const FinancialsQuery({
    required this.page,
    this.search,
    this.yardFilter,
    this.dateStart,
    this.dateEnd,
  });

  @override
  bool operator ==(Object other) =>
      other is FinancialsQuery &&
      other.page == page &&
      other.search == search &&
      other.yardFilter == yardFilter &&
      other.dateStart == dateStart &&
      other.dateEnd == dateEnd;

  @override
  int get hashCode =>
      Object.hash(page, search, yardFilter, dateStart, dateEnd);
}

/// One page of the Financials ledger, plus the totals over the whole filter.
typedef FinancialsPage = ({
  List<SrLedgerRow> rows,
  FinancialSummary totals,
  int total,
});

/// The Financials tab: a PAGE of rows and the totals for the whole filter.
///
/// ⚠️ The tab used to watch [srFinancialsProvider] -- every package in
/// every yard with its items and warehouse entries, every tender sale and
/// every expense row -- then filter and total them in Dart. 420 kB of JSON
/// decoded on the UI isolate so a header strip could show ten numbers, which
/// is what made the page take a second or two to open.
///
/// Both queries read `sr_financials` (postgres/41), which computes the same
/// ten figures per SR in SQL; the view's verify block asserts them against
/// what the page was showing before it existed.
final financialsPageProvider =
    FutureProvider.family<FinancialsPage, FinancialsQuery>((ref, q) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  ref.watch(financialExpensesRefreshProvider);

  final svc = ref.read(packageServiceProvider);
  final search = (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim();

  // ⚠️ One after another, for the reason [srFinancialsProvider] measures:
  // both decode on this isolate, so issuing them together only makes each wait
  // longer for the same total work.
  final page = await svc.getSrFinancialsPaged(
    offset: q.page * kDispositionPageSize,
    limit: kDispositionPageSize,
    search: search,
    yardFilter: q.yardFilter,
    dateStart: q.dateStart,
    dateEnd: q.dateEnd,
  );

  // ⚠️ The totals run over the WHOLE filter, including when the page is
  // empty: a filter that matches money but no rows on page 1 must still report
  // that money.
  final totals = await svc.getSrFinancialTotals(
    search: search,
    yardFilter: q.yardFilter,
    dateStart: q.dateStart,
    dateEnd: q.dateEnd,
  );

  return (rows: page.rows, totals: totals, total: page.total);
});

/// The packages this yard touched TODAY, newest first.
///
/// ⚠️ Twenty rows, chosen in SQL. This fetched EVERY package in the
/// yard with its items and warehouse entries -- 176 rows at 159ms -- filtered
/// them to today in Dart, sorted them, and took twenty.
///
/// The membership is subtler than the package row: a warehouse entry admitted
/// or returned today counts too, because Release, Re-export and Forfeit write
/// only to `warehouse_entries`. `recent_package_activity` (postgres/51)
/// carries that, and pins the date to Asia/Colombo so the answer does not
/// depend on the reader's timezone.
///
/// ⚠️ TODAY means today, not "today or later". The Dart tested
/// `isAfter(startOfDay)` with no upper bound, so an entry whose returned_at is
/// next week counted as activity now -- two rows on the live data. A list
/// headed "Recent Activity" reporting something that has not happened yet is
/// worse than a short list.
final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  return ref.read(packageServiceProvider).getRecentActivity();
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
/// What this yard is holding right now, and what is waiting on someone else.
///
/// ⚠️ These read the same views the nav rail's own pages read, so a
/// figure on the dashboard and the page it links to cannot disagree.
final yardHoldingCountsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getYardHoldingCounts();
});

final forfeitLifecycleProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(tenderSaleItemsChangeTriggerProvider);
  ref.watch(destructionsChangeTriggerProvider);
  return ref.read(forfeitedPackageServiceProvider).getForfeitLifecycleSummary();
});
