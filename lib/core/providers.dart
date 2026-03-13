import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'supabase_client.dart';

// ── Shared Auth State ──────────────────────────────────────────
final currentProfileProvider = StateProvider<ProfileModel?>((ref) => null);
final loginLoadingProvider = StateProvider<bool>((ref) => false);
final loginErrorProvider = StateProvider<String?>((ref) => null);

// ── Theme State ────────────────────────────────────────────────
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

// ── Realtime: Packages Stream ──────────────────────────────────
// Lightweight stream that fires whenever the packages table changes.
// Consumers just watch this to know when to reload package data.
final packagesChangeTriggerProvider = StreamProvider<int>((ref) async* {
  int tick = 0;
  yield tick; // emit immediately so first-render works

  final channel = supabase.channel('packages-realtime')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'packages',
      callback: (_) {
        tick++;
        // invalidate dependent providers
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

// ── Shared Data Providers ──────────────────────────────────────
final warehousesProvider = FutureProvider<List<WarehouseModel>>((ref) async {
  return ref.read(warehouseServiceProvider).getWarehouses();
});

// ── Live Packages Provider (re-fetches on realtime trigger) ────
final packageFilterProvider = StateProvider<String>((ref) => 'all');
final packageSearchProvider = StateProvider<String>((ref) => '');

final livePackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  // Watch trigger so we re-run whenever table changes
  ref.watch(packagesChangeTriggerProvider);
  final filter = ref.watch(packageFilterProvider);
  final search = ref.watch(packageSearchProvider);
  return ref.read(packageServiceProvider).getAllPackages(
    status: filter, search: search.isEmpty ? null : search);
});

// ── Live Warehouse Entries Provider ─────────────────────────────
final warehouseEntryFilterProvider = StateProvider<bool>((ref) => false); // false = active only
final selectedWarehouseIdProvider = StateProvider<String?>((ref) => null);

final liveWarehouseEntriesProvider =
    FutureProvider.family<List<WarehouseEntryModel>, String>((ref, warehouseId) async {
  ref.watch(warehouseEntriesChangeTriggerProvider);
  ref.watch(packagesChangeTriggerProvider);
  final showReturned = ref.watch(warehouseEntryFilterProvider);
  return ref.read(warehouseServiceProvider).getEntriesByWarehouse(
    warehouseId, isReturned: showReturned ? null : false);
});
