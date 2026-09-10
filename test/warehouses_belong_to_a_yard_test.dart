import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration =
      File('migrations/008_warehouses_belong_to_a_yard.sql').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final models = File('lib/models/models.dart').readAsStringSync();

  test('warehouses carry the yard they stand in', () {
    expect(migration, contains('add column if not exists yard text'));
    expect(migration, contains('warehouses_yard_idx'));
    expect(models, contains('final String? yard;'));
    expect(models, contains("yard: json['yard'] as String?"));
  });

  test('a yard reads only its own warehouses and zones', () {
    // The old policies handed every authenticated user every warehouse.
    expect(migration, contains('drop policy if exists "All can view warehouses"'));
    expect(migration, contains('warehouses_yard_select'));
    expect(migration, contains('yard = public.auth_user_yard()'));
    // Zones have no yard of their own; they inherit through the warehouse.
    expect(migration, contains('warehouse_zones_yard_select'));
    expect(migration,
        contains('public.warehouse_yard(warehouse_id) = public.auth_user_yard()'));
  });

  test('the zone parent lookup cannot recurse', () {
    // Reading a zone checks its warehouse. Doing that inline would re-enter
    // the warehouses policies, so it goes through SECURITY DEFINER.
    expect(migration, contains('create or replace function public.warehouse_yard'));
    expect(migration, contains('security definer'));
    // No POLICY may read profiles inline (42P17). The verification block in
    // the migration mentions the phrase, so check the policy bodies only.
    final policyBodies = RegExp(r'create policy[\s\S]*?;')
        .allMatches(migration)
        .map((m) => m.group(0)!)
        .join(' ');
    expect(policyBodies, isNot(contains('profiles')));
    expect(policyBodies, contains('auth_user_yard()'));
  });

  test('an admin manages warehouses in their own yard only', () {
    expect(migration,
        contains('drop policy if exists "Admins can manage warehouses"'));
    expect(migration, contains('warehouses_yard_write'));
    // A new warehouse is stamped with the creator's yard, never left global.
    expect(services, contains("'yard': AppSession.currentYard,"));
  });

  test('the backfill refuses to guess a shared warehouse', () {
    // Picking one yard for a warehouse two yards had used would hand a yard
    // another yard's goods.
    expect(migration, contains('having count(distinct yard) = 1'));
    expect(migration, contains('and w.yard is null'));
  });

  test('yard warehouses come from the column, not from stored goods', () {
    // Deriving it from warehouse_entries could never place a NEW warehouse:
    // it appeared only once goods were in it, and goods cannot be put into a
    // warehouse the picker does not offer.
    expect(providers, contains('all.where((w) => w.yard == yard)'));
    expect(providers, isNot(contains('getWarehouseIdsForYard')));
    expect(services, isNot(contains('getWarehouseIdsForYard')));
  });

  test('the view that bypassed the policies runs as the caller', () {
    expect(migration,
        contains('alter view public.warehouse_contents set (security_invoker = true)'));
  });

  test('an empty warehouse is named, not "Unknown"', () {
    // Names used to come only from the occupancy view, which is filtered to
    // stored goods — so every empty warehouse was listed as "Unknown".
    expect(services, contains('for (final w in await getWarehouses())'));
  });
}
