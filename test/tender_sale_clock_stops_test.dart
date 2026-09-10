import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

TenderSaleItemModel _item({bool sold = false, bool unsold = false}) =>
    TenderSaleItemModel(
      id: '${sold}_${unsold}_${DateTime.now().microsecondsSinceEpoch}_${_n++}',
      tenderSaleId: 'sale-1',
      forfeitedPackageId: 'fp-${_n}',
      yard: 'GL1',
      sold: sold,
      unsold: unsold,
    );
int _n = 0;

TenderSaleModel _sale(List<TenderSaleItemModel> items) => TenderSaleModel(
      id: 'sale-1',
      saleNumber: 'TS/GL1/2026/068',
      items: items,
      createdAt: DateTime(2026, 9, 5),
    );

void main() {
  test('a sale where everything went UNSOLD is decided', () {
    // The case on screen: TS/GL1/2026/068, three items, all Unsold, and the
    // clock still climbing at "5d 15h since bidding started".
    final sale = _sale([
      _item(unsold: true),
      _item(unsold: true),
      _item(unsold: true),
    ]);
    expect(sale.totalCount, 3);
    expect(sale.soldCount, 0, reason: 'nothing sold — the old rule saw this as unfinished');
    expect(sale.decidedCount, 3);
    expect(sale.allDecided, isTrue);
  });

  test('one item still awaiting a decision keeps the sale open', () {
    // TS/GL1/2026/SP05: Unsold, Awaiting Decision, Sold.
    final sale = _sale([
      _item(unsold: true),
      _item(), // awaiting
      _item(sold: true),
    ]);
    expect(sale.decidedCount, 2);
    expect(sale.allDecided, isFalse,
        reason: 'the clock must keep running while one item is undecided');
  });

  test('a mix of sold and unsold is still finished', () {
    final sale = _sale([_item(sold: true), _item(unsold: true)]);
    expect(sale.allDecided, isTrue);
  });

  test('an empty sale is not "decided"', () {
    // Nothing to decide is not the same as everything decided; treating it as
    // finished would put a "Bidding closed" chip on a sale with no items.
    expect(_sale([]).allDecided, isFalse);
  });

  test('only the yard page stops the clock early', () {
    final src =
        File('lib/screens/disposal/disposal_dashboard_screen.dart').readAsStringSync();
    // Default off, so Central Disposal and Top Management keep the all-sold
    // rule they measure progress by.
    expect(src, contains('this.closeWhenAllDecided = false,'));
    expect(src, contains(
        'final settled = widget.closeWhenAllDecided ? widget.sale.allDecided : allSold;'));
    // The clock and the perishable urgency both follow it.
    expect(src, contains('if (!settled &&'));
    expect(src, contains('final urgentPerishable = !settled &&'));

    final yard = File('lib/screens/forfeited_packages/tender_disposal_screen.dart')
        .readAsStringSync();
    expect(yard, contains('closeWhenAllDecided: true,'));

    final exec = File('lib/screens/executive/tender_sales_view_tab.dart')
        .readAsStringSync();
    expect(exec, isNot(contains('closeWhenAllDecided')));
  });
}
