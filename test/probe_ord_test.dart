import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

void main() {
  test('does created_at order match sale_date order?', () async {
    final c = await Connection.open(
      Endpoint(host: 'localhost', port: 5432, database: 'Customs_SR_DB',
          username: 'postgres', password: 'postgres'),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    final r = await c.execute('''
      select pi.item_name, ts.sale_number,
             ts.created_at::text, ts.sale_date::text,
             tr.valuation_cost
      from forfeited_packages fp
      join tender_sale_items tsi on tsi.forfeited_package_id = fp.id
      join tender_sales ts on ts.id = tsi.tender_sale_id
      left join package_items pi on pi.id = fp.item_id
      left join tender_revaluations tr
        on tr.tender_sale_id = ts.id and tr.forfeited_package_id = fp.id
      where pi.item_name in ('Costume jewellery','Power tools')
      order by pi.item_name, ts.created_at
    ''');
    print('item | sale | created_at | sale_date | reval');
    for (final row in r) {
      print(row.map((e) => e ?? '-').join(' | '));
    }
    await c.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
