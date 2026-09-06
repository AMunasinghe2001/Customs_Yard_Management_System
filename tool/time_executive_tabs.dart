import 'package:postgres/postgres.dart';

/// Times what each Top Management tab loads, so "it lags" can be measured
/// rather than guessed at.
///
/// ⚠️ Every one of these tabs fetches a WHOLE list and then pages it in Dart.
/// Central Disposal already pages the same data in SQL -- these numbers are
/// what that difference costs here.
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

  Future<int> time(String label, String sql) async {
    await conn.execute(sql); // warm-up, so nothing is charged for cold cache
    var best = 1 << 30;
    var rows = 0;
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      final r = await conn.execute(sql);
      sw.stop();
      rows = r.length;
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    print('${best.toString().padLeft(6)}ms ${rows.toString().padLeft(5)} rows'
        '   $label');
    return best;
  }

  print('\n── Financials: the whole ledger, to show ten totals ────────\n');

  final pkgs = await time('getAllPackages (all yards, 3 embeds)', '''
select p.*,
  (select coalesce(json_agg(to_jsonb(pi)), '[]') from package_items pi
     where pi.package_id = p.id) as package_items,
  (select coalesce(json_agg(jsonb_build_object(
     'we', to_jsonb(we),
     'warehouses', (select to_jsonb(w) from warehouses w where w.id = we.warehouse_id)
   )), '[]') from warehouse_entries we where we.package_id = p.id) as wes
from packages p order by p.created_at desc''');

  final sales = await time('getTenderSales (5 levels deep)', '''
select ts.*,
  (select coalesce(json_agg(jsonb_build_object(
      'it', to_jsonb(tsi),
      'fp', (select jsonb_build_object(
          'fp', to_jsonb(fp),
          'pkg', (select jsonb_build_object(
              'p', to_jsonb(p),
              'items', (select coalesce(json_agg(to_jsonb(pi)), '[]')
                 from package_items pi where pi.package_id = p.id),
              'wes', (select coalesce(json_agg(to_jsonb(we)), '[]')
                 from warehouse_entries we where we.package_id = p.id))
            from packages p where p.id = fp.package_id))
        from forfeited_packages fp where fp.id = tsi.forfeited_package_id)
    )), '[]')
   from tender_sale_items tsi where tsi.tender_sale_id = ts.id) as items
from tender_sales ts order by ts.created_at desc''');

  await time('financial_expenses', 'select * from financial_expenses');

  print('\n  Financials waits for the slowest of these: '
      '${pkgs > sales ? pkgs : sales}ms\n');

  print('── What the same totals cost as ONE aggregate query ───────\n');

  await time('sr_expense_summary rolled up', '''
select coalesce(sum(destruction_spend), 0)  as destruction,
       coalesce(sum(advertising_spend), 0)  as advertising,
       coalesce(sum(labour_spend), 0)       as labour,
       coalesce(sum(transport_spend), 0)    as transport,
       coalesce(sum(auction_spend), 0)      as auction
from sr_expense_summary''');

  print('\n── The other three tabs: whole lists, paged in Dart ───────\n');

  await time('Tender Sales tab -> the same getTenderSales', 'select 1');
  await time('Committees: eligible packages', '''
select count(*) from unsold_retender_pool
 where round_count = 4 and has_committee = true''');
  await time('Unsold Goods: exhausted_unsold', 'select * from exhausted_unsold');
  await time('Unsold Perishables: perishable_rows', '''
select * from perishable_rows''');

  print('\n── Row counts, so the numbers can be read in context ──────\n');
  for (final t in [
    'packages',
    'tender_sales',
    'tender_sale_items',
    'forfeited_packages',
    'financial_expenses',
  ]) {
    final r = await conn.execute('select count(*) from $t');
    print('  ${t.padRight(22)} ${r.first[0]}');
  }

  await conn.close();
}
