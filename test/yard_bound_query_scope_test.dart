import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final warehouseMigration =
      File('migrations/004_warehouse_query_yard_scope.sql').readAsStringSync();

  test('warehouse rows are narrowed by the signed-in yard in SQL', () {
    final start = services.indexOf('getWarehouseRowsPaged({');
    final end = services.indexOf('getWarehouseFilterOptions(', start);
    final body = services.substring(start, end);
    expect(body, contains("q = q.eq('yard', effectiveYard)"));
    expect(body, contains("query = query.eq('yard', AppSession.currentYard)"));
    expect(warehouseMigration, contains('p.yard'));
  });

  test('held-goods rows, totals and years use the signed-in yard in SQL', () {
    final start = services.indexOf('getHeldGoodsPaged({');
    final end = services.indexOf('getExpenseSummaryPaged(', start);
    final body = services.substring(start, end);
    expect(body, contains("q = q.eq('yard', effectiveYard)"));
    expect(body, contains("query = query.eq('yard', AppSession.currentYard)"));
  });
}
