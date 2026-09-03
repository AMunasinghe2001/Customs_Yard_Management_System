// The Valuation Directorate's perishable tab, and Central Disposal's tab order.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// Whole balanced `Foo(...)` entries from a Dart list body.
List<String> _blocks(String src) {
  final out = <String>[];
  var depth = 0;
  final cur = StringBuffer();
  for (final ch in src.split('')) {
    cur.write(ch);
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) {
        final t = cur.toString().replaceAll(RegExp(r'^[\s,]+'), '').trim();
        if (t.isNotEmpty) out.add(t);
        cur.clear();
      }
    }
  }
  return out;
}

void main() {
  final val = _read('lib/screens/valuation/valuation_dashboard_screen.dart');
  final disposal = _read('lib/screens/disposal/disposal_dashboard_screen.dart');

  group('Valuation has a perishable tab of its own', () {
    // ⚠️ Its own tab, not a filter on the first one. An officer could not
    // otherwise tell them apart, and a perishable is on a completely
    // different clock: no warehouse, no appeal window, one Special Tender
    // Sale and then the DG decides. Valuing one as though it had months is
    // the mistake this prevents.
    test('the tab exists', () {
      expect(val, contains("Text('Perishable Goods')"));
      expect(val, contains('_PendingValuationTab(perishableOnly: true)'));
    });

    // ⚠️ It splits the SAME list rather than fetching a different one, so the
    // two tabs can never disagree: whatever the directorate holds appears on
    // exactly one of them.
    test('both tabs come from one provider', () {
      expect(val, contains('isPerishable(r) == perishableOnly'));
      expect('valuationRequestsProvider'.allMatches(val).length,
          greaterThanOrEqualTo(1));
    });

    // ⚠️ EVERY item, not any: perishables arrive as their own request, so a
    // mixed one is not a perishable batch.
    test('a request is perishable only when every item is', () {
      expect(val,
          contains("r.items.every((i) => i.forfeited?.source == 'perishable')"));
    });

    // ⚠️ A short controller still PAINTS every tab, but clicks resolve
    // against the shorter one, so tapping does nothing while swiping works.
    test('the controller length matches the tabs and the views', () {
      final len = int.parse(
          RegExp(r'TabController\(length: (\d+)').firstMatch(val)!.group(1)!);
      final stripStart = val.indexOf('tabs: const [');
      final strip = val.substring(
          val.indexOf('[', stripStart) + 1, val.indexOf('// ── Tab views'));
      // Count the tab LABELS -- formatting-independent, unlike matching on
      // "Tab(" followed by a newline.
      expect(RegExp("Text\\('[^']+'\\)").allMatches(strip).length, len);
    });
  });

  group('a perishable never re-enters the tender pool', () {
    final services = _read('lib/services/services.dart');

    // ⚠️ Goods that spoil get NO second round: one failed Special Tender Sale
    // and they go straight to Top Management. Offering them again would be
    // offering goods that will not last the wait -- and it would hide them
    // from the DG, the only one who can act on them.
    test('the unsold pool excludes them by default', () {
      expect(services, contains('bool includePerishable = false'));
      expect(services,
          contains("if (!includePerishable && f.source == 'perishable') continue;"));
    });

    test("the DG's own list is the one place that asks for them", () {
      final fn = services.substring(
          services.indexOf('Future<List<ReTenderSaleInfo>> getUnsoldPerishables'));
      // The method body ends at the first newline-plus-closing-brace.
      final endMark = String.fromCharCode(10) + '  }';
      final body = fn.substring(0, fn.indexOf(endMark));
      expect(body, contains('includePerishable: true'));
      expect(body, contains("i.forfeited.source == 'perishable'"));
    });

    // Both Unsold Tenders tabs — Central Disposal's and Valuation's — read the
    // same provider, so neither can show one.
    test('both Unsold Tenders tabs read the same provider', () {
      expect(disposal, contains('unsoldTenderSalesProvider'));
      expect(val, contains('unsoldTenderSalesProvider'));
    });
  });

  group('Central Disposal reads in the same order as the yard rail', () {
    // The work in hand first, then how goods left, then the outcomes for what
    // nothing would take, then the reference tabs. Central Disposal has no
    // register or storage stage of its own, so it starts at the work.
    const expected = [
      'Disposal Requests', 'Tender Sales', 'Unsold Tenders', 'Committees',
      'Perishable',
      'Sold Goods', 'Unsold Goods', 'Destroyed Goods',
      'Government Use', 'Remanded', 'Auction', 'Converted', 'Removed',
      'Taxes', 'Expenses', 'Reports',
    ];

    final stripStart = disposal.indexOf('tabs: const [');
    final strip = disposal.substring(disposal.indexOf('[', stripStart) + 1,
        disposal.indexOf('child: TabBarView'));
    final labels = RegExp(r"Text\('([^']+)'\)")
        .allMatches(strip)
        .map((m) => m.group(1)!)
        .toList();

    test('the tabs are in that order', () {
      expect(labels, expected);
    });

    // ⚠️ The real risk in a reorder: a tab pointing at another tab's view.
    test('every tab still points at its own view', () {
      final vStart = disposal.indexOf('child: TabBarView(children: [');
      final views = _blocks(disposal.substring(
          disposal.indexOf('[', vStart) + 1,
          disposal.indexOf('\n              ]),', vStart)));
      expect(views.length, labels.length,
          reason: 'a tab or a view was added without the other');

      // The five outcome tabs share one widget and are told apart only by
      // their filter, so those must line up with their labels.
      final filters = RegExp(r"proposalFilter: '(\w+)'")
          .allMatches(views.join('\n'))
          .map((m) => m.group(1)!)
          .toList();
      expect(filters, [
        'government_use', 'remand', 'auction', 'convert', 'remove_from_premises',
      ]);
    });

    test('no tab was lost or gained in the reorder', () {
      expect(labels.toSet().length, labels.length, reason: 'a duplicate label');
      expect(labels.length, 16);
    });
  });
}
