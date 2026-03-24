import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'supabase_client.dart';

// ── Service Providers ──────────────────────────────────────────
final authServiceProvider = Provider((ref) => AuthService());
final packageServiceProvider = Provider((ref) => PackageService());
final warehouseServiceProvider = Provider((ref) => WarehouseService());
final customsRulesServiceProvider = Provider((ref) => CustomsRulesService());
final adminServiceProvider = Provider((ref) => AdminService());
final auditLogServiceProvider = Provider((ref) => AuditLogService());
final packageCategoryServiceProvider = Provider((ref) => PackageCategoryService());
final holdReasonServiceProvider = Provider((ref) => HoldReasonService());

// ── Shared Auth State ──────────────────────────────────────────
final currentProfileProvider = StateProvider<ProfileModel?>((ref) => null);
final loginLoadingProvider = StateProvider<bool>((ref) => false);
final loginErrorProvider = StateProvider<String?>((ref) => null);

// ── Theme State ────────────────────────────────────────────────
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

// ── Realtime: Packages Stream ──────────────────────────────────
final packagesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  yield tick;
  final channel = supabase.channel('packages-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'packages',
      callback: (_) {
        tick++;
        ref.invalidateSelf();
      },
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'package_items',
      callback: (_) {
        tick++;
        ref.invalidateSelf();
      },
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Warehouse Entries Stream ──────────────────────────
final warehouseEntriesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  yield tick;
  final channel = supabase.channel('warehouse-entries-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'warehouse_entries',
      callback: (_) {
        tick++;
        ref.invalidateSelf();
      },
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Profiles Stream ──────────────────────────────────
final profilesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  yield tick;
  final channel = supabase.channel('profiles-realtime')
    ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: (_) {
          tick++;
          ref.invalidateSelf();
        })
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Realtime: Package Categories Stream ──────────────────────────
final categoryChangeTriggerProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  yield tick;
  final channel = supabase.channel('categories-realtime')
    ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'package_categories',
        callback: (_) {
          tick++;
          ref.invalidateSelf();
        })
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

// ── Shared Data Providers ──────────────────────────────────────
final warehousesProvider = FutureProvider<List<WarehouseModel>>((ref) async {
  return ref.read(warehouseServiceProvider).getWarehouses();
});

// ── Live Packages Provider ─────────────────────────────────────
final packageFilterProvider = StateProvider<String>((ref) => 'all');
final packageSearchProvider = StateProvider<String>((ref) => '');
final packageShowReturnedProvider = StateProvider<bool>((ref) => true);
final packageDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);
final packageReasonFilterProvider = StateProvider<String>((ref) => 'all');

final livePackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  ref.watch(packagesChangeTriggerProvider);
  final filter = ref.watch(packageFilterProvider);
  final search = ref.watch(packageSearchProvider);
  return ref.read(packageServiceProvider).getAllPackages(
      status: filter, search: search.isEmpty ? null : search);
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
  return ref.read(warehouseServiceProvider).getAllWarehouseEntries();
});

final warehouseStatusFilterProvider = StateProvider.family<String, String>((ref, warehouseId) => 'all');
final warehouseSearchProvider = StateProvider.family<String, String>((ref, id) => '');
final warehouseDateRangeProvider = StateProvider.family<DateTimeRange?, String>((ref, warehouseId) => null);
final warehouseReasonFilterProvider = StateProvider.family<String, String>((ref, warehouseId) => 'all');

final storageRateProvider = FutureProvider<double>((ref) async {
  return ref.watch(customsRulesServiceProvider).getStorageRate();
});

final storageRateHistoryProvider = FutureProvider<List<AuditLogModel>>((ref) async {
  return ref.read(customsRulesServiceProvider).getStorageRateHistory();
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

final allRulesProvider = FutureProvider<List<CustomsRule>>((ref) async {
  return ref.read(customsRulesServiceProvider).getAllRules();
});

final auditLogsChangeTriggerProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  yield tick;
  final channel = supabase.channel('audit-logs-realtime')
    ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'audit_logs',
        callback: (_) {
          tick++;
          ref.invalidateSelf();
        })
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
