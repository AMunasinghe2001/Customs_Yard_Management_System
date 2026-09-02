import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

TenderSaleModel _sale({
  DateTime? date,
  String? startTime,
  String? endTime,
}) =>
    TenderSaleModel(
      id: 's1',
      saleNumber: 'CDU/TS/2026/8',
      saleDate: date,
      saleTime: startTime,
      saleEndTime: endTime,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  final reports = _read('lib/screens/reports/reports_screen.dart');

  // Each report's block, sliced between its own case label and the next.
  String block(String label, String next) => reports.substring(
      reports.indexOf("case '$label':"), reports.indexOf("case '$next':"));

  group('All Tenders — the register of tenders', () {
    final b = block('all_tenders', 'tender_day');

    test('every portal gets the card', () {
      // No executiveMode guard around it: the yard, Central Disposal and Top
      // Management all list tenders.
      final card = reports.substring(reports.indexOf("title: 'All Tenders'"));
      final upTo = card.substring(0, card.indexOf('),\n'));
      expect(upTo, isNot(contains('executiveMode')));
      expect(reports, contains("_stockRevenueReport('all_tenders', 'view')"));
      expect(reports, contains("_stockRevenueReport('all_tenders', 'excel')"));
    });

    test('one row per SALE, not per item', () {
      expect(b, contains("headline = '\${rows.length} tender sales';"));
      expect(b, contains("'Tender No'"));
      expect(b, contains("'Sold'"));
      expect(b, contains("'Unsold'"));
      expect(b, contains("'Proceeds (LKR)'"));
    });

    test('open and closed tenders both appear, labelled', () {
      // Unlike the sale sheet, this is a register: nothing is withheld.
      expect(b, contains("sale.saleEnded ? 'Closed' : 'Open'"));
      expect(b, isNot(contains('where((sale) => sale.saleEnded')));
    });

    test('the yard filter matches per item, not per sale', () {
      // A sale can mix items from a multi-directorate yard.
      expect(b, contains('sale.items.any((i) => i.yard == _yardArg)'));
    });

    test('proceeds count only what actually sold', () {
      expect(b, contains('items\n                .where((i) => i.sold)'));
    });
  });

  group('Tender Sale Sheet — Top Management only', () {
    final b = block('tender_day', 'destroyed');

    test('the card is executive-only', () {
      final idx = reports.indexOf("title: 'Tender Sale Sheet'");
      expect(idx, greaterThan(-1));
      // The guard sits immediately before the card.
      final before = reports.substring(idx - 400, idx);
      expect(before, contains('if (widget.executiveMode)'));
    });

    test('it lists goods with their valuation', () {
      expect(b, contains("'Valuation (LKR)'"));
      expect(b, contains("'Qty'"));
      expect(b, contains('money.format(unit * qty)'));
    });

    test('ONLY closed tenders contribute rows', () {
      // The valuation is the reserve price: it may not be shown while
      // bidding is open. This is what makes the report empty until a tender
      // closes, and fill again on the next one.
      expect(b, contains('sale.saleEnded &&'));
    });

    test('the card stays on the page even with nothing to report', () {
      // The user asked for exactly this: the div stays, the rows come and go.
      final idx = reports.indexOf("title: 'Tender Sale Sheet'");
      final card = reports.substring(idx, idx + 900);
      expect(card, isNot(contains('rows.isEmpty')));
      expect(card, contains('available once the tender closes'));
    });
  });

  group('saleEnded is the gate, and it means what the report needs', () {
    test('a sale still running has not ended', () {
      final s = _sale(
          date: DateTime.now(), startTime: '00:01', endTime: '23:59');
      expect(s.saleEnded, isFalse,
          reason: 'the reserve price would leak while bidding is open');
    });

    test('a sale whose end time has passed has ended', () {
      final s = _sale(
          date: DateTime.now().subtract(const Duration(days: 1)),
          startTime: '10:00',
          endTime: '11:00');
      expect(s.saleEnded, isTrue);
    });

    test('with no end time it falls back to the start moment', () {
      // Rows created before sale_end_time existed must still behave.
      final past = _sale(
          date: DateTime.now().subtract(const Duration(days: 1)),
          startTime: '10:00');
      expect(past.saleEnded, isTrue);

      final future = _sale(
          date: DateTime.now().add(const Duration(days: 1)),
          startTime: '10:00');
      expect(future.saleEnded, isFalse);
    });

    test('a sale with no date at all never counts as ended', () {
      expect(_sale().saleEnded, isFalse,
          reason: 'an undated sale must not leak its valuations');
    });
  });
}
