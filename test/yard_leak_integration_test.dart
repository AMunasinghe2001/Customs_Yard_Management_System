@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/db/pg_client.dart';
import 'package:cus_yard_management/core/db/pg_connection.dart';

/// Signs in as real users through the SAME stack the screens use, and checks
/// what each one can see. A psql session cannot catch a leak that lives in
/// the client (a stale pooled session, a Dart-side filter), so this drives
/// the real sign-in path and the real connection pool.
///
/// Run against a scratch copy:
///   flutter test test/yard_leak_integration_test.dart \
///     --dart-define=PG_DATABASE=yard_leak_test
void main() {
  Future<int> count(String rel, [String where = '']) async {
    final rows = await PgDatabase.instance
        .query('select count(*)::int as n from public.$rel $where');
    return rows.first['n'] as int;
  }

  Future<Map<String, int>> snapshot() async => {
        'packages': await count('packages'),
        'package_items': await count('package_items'),
        'warehouse_entries': await count('warehouse_entries'),
        'forfeited_packages': await count('forfeited_packages'),
        'warehouses': await count('warehouses'),
        'warehouse_zones': await count('warehouse_zones'),
        'held_goods_rows': await count('held_goods_rows'),
        'warehouse_rows': await count('warehouse_rows'),
        'perishable_rows': await count('perishable_rows'),
        'disposition_rows': await count('disposition_rows'),
        'forfeit_rows': await count('forfeit_rows'),
        'valuation_rows': await count('valuation_rows'),
        'appeal_rows': await count('appeal_rows'),
      };

  /// Rows that plainly belong to another yard, by SR-number prefix — the
  /// check a person would do by eye on the screenshots.
  Future<int> foreignRows(String myYard) async {
    final rows = await PgDatabase.instance.query(
      "select count(*)::int as n from public.disposition_rows "
      "where yard is not null and yard <> '$myYard'",
    );
    return rows.first['n'] as int;
  }

  Future<void> signIn(String email) async {
    await PgClient.instance.auth
        .signInWithPassword(email: email, password: 'TestPass123');
  }

  setUpAll(() async => PgClient.instance.initialize());

  test('a GL2 officer sees nothing belonging to GL1', () async {
    await signIn('onela@gmail.com');
    final seen = await snapshot();
    print('GL2 officer (Onela): $seen');

    // GL2 has no data of its own yet, so every count must be zero. Before the
    // restrictive boundary existed this returned all 176 GL1 packages.
    for (final e in seen.entries) {
      expect(e.value, 0, reason: '${e.key} leaked another yard to a GL2 officer');
    }
    expect(await foreignRows('GL2'), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a GL1 officer sees GL1, and only GL1', () async {
    await signIn('deepal@gmail.com');
    final seen = await snapshot();
    print('GL1 officer (Ajantha): $seen');

    // The pages that were reported blank must actually carry rows.
    expect(seen['held_goods_rows'], greaterThan(0));
    expect(seen['disposition_rows'], greaterThan(0));
    expect(seen['perishable_rows'], greaterThan(0));
    expect(seen['warehouses'], greaterThan(0));
    // Re-exported was the page showing 0 while GL1 had 19.
    expect(await count('disposition_rows', "where final_tag = 'RE-EXPORTED'"),
        greaterThan(0));
    // And nothing from any other yard.
    expect(await foreignRows('GL1'), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a yard admin is bound to their yard too', () async {
    await signIn('anushangamunasinghe@gmail.com');
    final seen = await snapshot();
    print('GL1 admin (Anushanga): $seen');
    expect(seen['held_goods_rows'], greaterThan(0));
    // Admin is yard staff: no cross-yard bypass (migration 002's rule).
    expect(await foreignRows('GL1'), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('switching users does not leave the previous yard visible', () async {
    // The pooled session is per-connection. If sign-in did not reset every
    // pooled connection, the next user would inherit the previous one's rows.
    await signIn('deepal@gmail.com');
    expect(await count('packages'), greaterThan(0));

    await signIn('onela@gmail.com');
    expect(await count('packages'), 0,
        reason: 'GL2 inherited GL1 rows from the pooled session');

    await signIn('deepal@gmail.com');
    expect(await count('packages'), greaterThan(0),
        reason: 'GL1 lost its own rows after switching back');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
