import 'dart:io';
import 'package:postgres/postgres.dart';

/// Times the queries the Destroyed Goods tab actually runs, so the lag can be
/// measured rather than guessed at.
///
/// ⚠️ Run against the real database. The tab issues these in sequence -- the
/// second cannot start until the first returns the package ids -- so the wall
/// time an officer waits is their SUM, not the slower of the two.
Future<void> main() async {
  final conn = await Connection.open(
    Endpoint(
        host: 'localhost',
        port: 5432,
        database: 'Customs_SR_DB',
        username: 'postgres',
        password: 'postgres'),
    settings: ConnectionSettings(
        sslMode: SslMode.disable, queryTimeout: const Duration(seconds: 120)),
  );

  Future<(int, int)> time(String label, String sql) async {
    // One warm-up, then three timed runs: the first touches cold cache and
    // would blame the query for the disk.
    await conn.execute(sql);
    var best = 1 << 30;
    var rows = 0;
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      final r = await conn.execute(sql);
      sw.stop();
      rows = r.length;
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    print('${best.toString().padLeft(6)}ms  ${rows.toString().padLeft(5)} rows'
        '   $label');
    return (best, rows);
  }

  print('\n── The two queries the tab runs, in order ──────────────────\n');

  // 1. The page of disposition rows.
  final page = await time(
      'disposition_rows page (20)',
      "select * from disposition_rows where final_tag = 'DESTROYED' "
          "order by happened_at desc nulls last limit 20 offset 0");

  // 2. The count for the pager.
  await time('disposition_rows count',
      "select count(*) from disposition_rows where final_tag = 'DESTROYED'");

  // 3. getPackagesByIds for that page -- the nested-embed one.
  final ids = await conn.execute(
      "select distinct package_id from disposition_rows "
      "where final_tag = 'DESTROYED' limit 20");
  final idList =
      ids.map((r) => "'${r[0]}'").join(',');

  await time(
      'getPackagesByIds (packages + 3 nested embeds)',
      '''
select p.*,
  (select coalesce(json_agg(to_jsonb(pi)), '[]') from package_items pi
     where pi.package_id = p.id) as package_items,
  (select coalesce(json_agg(to_jsonb(we)), '[]') from warehouse_entries we
     where we.package_id = p.id) as warehouse_entries,
  (select to_jsonb(pr) from profiles pr where pr.id = p.inspected_by) as profiles
from packages p where p.id in ($idList)''');

  print('\n── What each embed costs on its own ───────────────────────\n');

  await time(
      'packages row only (no embeds)', 'select * from packages where id in ($idList)');

  await time(
      '+ package_items',
      "select p.*, (select coalesce(json_agg(to_jsonb(pi)), '[]') "
          "from package_items pi where pi.package_id = p.id) as items "
          "from packages p where p.id in ($idList)");

  await time(
      '+ warehouse_entries with warehouses AND returned_profile',
      '''
select p.*,
  (select coalesce(json_agg(jsonb_build_object(
      'we', to_jsonb(we),
      'warehouses', (select to_jsonb(w) from warehouses w where w.id = we.warehouse_id),
      'returned_profile', (select to_jsonb(rp) from profiles rp where rp.id = we.returned_by)
   )), '[]')
   from warehouse_entries we where we.package_id = p.id) as wes
from packages p where p.id in ($idList)''');

  print('\n── Index check on the columns these filter by ─────────────\n');

  for (final t in [
    ('package_items', 'package_id'),
    ('warehouse_entries', 'package_id'),
    ('warehouse_entries', 'warehouse_id'),
  ]) {
    final r = await conn.execute("select indexname from pg_indexes "
        "where tablename = '${t.$1}' and indexdef like '%(${t.$2}%'");
    final names = r.map((x) => x[0]).join(', ');
    print('  ${t.$1}.${t.$2}: ${names.isEmpty ? "NO INDEX  <-- scans" : names}');
  }

  print('\n  page query alone: ${page.$1}ms');
  await conn.close();
}
