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

  /// Whitespace collapsed, so a call that wraps across lines still matches.
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  // Each report's block, sliced between its own case label and the next.
  String block(String label, String next) => reports.substring(
      reports.indexOf("case '$label':"), reports.indexOf("case '$next':"));

  group('All Tenders — every tender, by the goods that went into it', () {
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

    test('it lists the GOODS, with the tender they went into', () {
      expect(b, contains("headline = '\${rows.length} goods';"));
      for (final col in [
        "'Tender No'",
        "'Sale Date'",
        "'SR Number'",
        "'Goods Name'",
        "'Qty'",
        "'Latest Valuation (LKR)'",
        "'Sold Price (LKR)'",
      ]) {
        expect(b, contains(col), reason: '$col is missing from All Tenders');
      }
    });

    test('a sold item shows its price; an unsold one says so', () {
      // "No price" and "sold for nothing" are different facts.
      expect(b, contains("it.sold ? money.format(it.soldPrice) : '—'"));
      expect(b, contains("it.sold ? 'Sold' : 'Unsold'"));
    });

    test('open tenders are not withheld', () {
      // Unlike the sale sheet, this is the historical register.
      expect(b, isNot(contains('sale.saleEnded &&')));
    });

    test('the yard filter matches per item, not per sale', () {
      // A sale can mix items from a multi-directorate yard, so the
      // sale-level yard code cannot tell them apart.
      //
      // ⚠️ PER ITEM is the rule; how an item's yard is matched is not.
      // This pinned `i.yard == _yardArg` and failed when the match grew to
      // read the SR number's own yard segment as well -- a strictly better
      // match, and the rule this test guards had not changed.
      expect(b, contains('sale.items.any((i) => '));
      expect(b, contains('i.yard'));
      // And the row loop skips an item from another yard, by the same match.
      // Whitespace collapsed: the call wraps across lines, and a wrapped
      // call is exactly what a single-line pattern misses.
      expect(flat(b),
          contains('_matchesSelectedYard( it.yard, it.forfeited?.srNumber)'));
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

    test('it carries exactly the columns the DG needs at the sale', () {
      for (final col in [
        "'Tender No'",
        "'SR Number'",
        "'Goods Name'",
        "'Goods Description'",
        "'Qty'",
        "'Yard / Warehouse'",
        "'Latest Valuation (LKR)'",
      ]) {
        expect(b, contains(col), reason: '$col is missing from the sale sheet');
      }
    });

    test('it mirrors the Tender Sales PAGE, not the closed-tender history', () {
      // Same rule that page applies: UNDECIDED items remaining. That is
      // what makes the report empty exactly when the page is empty.
      //
      // ⚠️ Not sold is not the same as undecided -- an item marked unsold
      // has left the page too. This test pinned `!i.sold` alone, which was
      // the page's rule before marking arrived; it now reads both.
      final live = b.substring(b.indexOf("case 'tender_day'"));
      expect(live.substring(0, 900), contains('!i.sold'));
      expect(live.substring(0, 900), contains('!i.unsold'));
      // ⚠️ And no window. The report used to hide a sale once a
      // working-day deadline passed, which hid work that was still
      // outstanding -- the sale had unmarked items and nobody could see them.
      expect(b.contains('unsoldDeadline'), isFalse,
          reason: 'the report is hiding sales that still need a decision');
    });

    test('an item already decided has left the sale, so it is skipped', () {
      // ⚠️ Sold OR unsold: both are decisions, and a decided item is off
      // this sheet. The check used to name only `it.sold`.
      final sheet = b.substring(b.indexOf("case 'tender_day'"));
      expect(sheet, contains('it.sold || it.unsold) continue;'));
    });

    test('the location comes from the newest warehouse entry', () {
      // So the goods can actually be pulled for the sale.
      expect(b, contains('b.admittedAt.compareTo(a.admittedAt)'));
      expect(b, contains('w.warehouseName'));
    });

    test('the card stays on the page even with nothing to report', () {
      // The rows come and go; the card does not.
      final idx = reports.indexOf("title: 'Tender Sale Sheet'");
      final card = reports.substring(idx, idx + 900);
      expect(card, isNot(contains('rows.isEmpty')));
      expect(card, contains('to carry into the sale'));
    });
  });

  group('the read-only status names where the sale has got to', () {
    final disposal = _read('lib/screens/disposal/disposal_dashboard_screen.dart');

    test('a watched item reports the tender STAGE, not "Pending"', () {
      // "Pending" read as an action the VIEWER owed, and said nothing about
      // which of four situations the sale was in. See the stage tests in
      // register_swap_and_portal_polish_test.dart.
      final ro = disposal.substring(disposal.indexOf('if (widget.readOnly) {'));
      final block = ro.substring(0, 1400);
      expect(block, contains('widget.sale.stage'));
      expect(block, isNot(contains("'Pending'")));
    });
  });

  group('the Top Management tender page uses its own accent', () {
    final tab = _read('lib/screens/executive/tender_sales_view_tab.dart');

    test('teal, like the rest of the portal — not a second blue', () {
      expect(tab, contains('AppTheme.executiveTeal'));
      expect(tab, isNot(contains('context.colors.customsBlue')));
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
