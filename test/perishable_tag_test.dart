// The perishable label, and why it belongs in a header.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final valuation =
      _read('lib/screens/valuation/valuation_dashboard_screen.dart');
  final disposal = _read('lib/screens/disposal/disposal_dashboard_screen.dart');

  group('the label speaks for a whole batch', () {
    // ⚠️ Perishables arrive TOGETHER — their own request, their own sale.
    // They may only enter a Special Tender Sale, so they are never mixed with
    // normal goods, and a header label therefore describes everything under
    // it with nothing to contradict. Repeating it per row would say the same
    // thing many times.
    test('the tag is in the Valuation request header', () {
      expect(valuation, contains('PerishableTag(compact: true)'));
      expect(valuation, contains('isPerishableRequest'));
    });

    test('the tag is in the Disposal Requests header', () {
      expect(disposal, contains('PerishableTag(compact: true)'));
      expect(disposal, contains('isPerishableRequest'));
    });

    test('the tag is in the Tender Sale header', () {
      expect(disposal, contains("widget.sale.tenderType == 'special'"));
    });
  });

  group('what makes a batch perishable', () {
    // ⚠️ EVERY item, not any. A mixed set must not wear the tag: it would
    // tell the officer the normal goods beside it are on the perishable clock
    // too — no warehouse, no appeal window, one sale and then the DG decides.
    bool tagged(List<String> sources) =>
        sources.isNotEmpty && sources.every((s) => s == 'perishable');

    test('all perishable earns the tag', () {
      expect(tagged(const ['perishable', 'perishable']), isTrue);
    });

    test('one normal item among them loses it', () {
      expect(tagged(const ['perishable', 'forfeit']), isFalse);
    });

    test('an empty request is not tagged', () {
      expect(tagged(const []), isFalse);
    });

    test('the check is written that way in both screens', () {
      const check = "items.every((i) => i.forfeited?.source == 'perishable')";
      expect(valuation, contains(check));
      expect(disposal, contains(check));
    });
  });

  group('a special sale is proof by itself', () {
    // The gate is two-way: a perishable may ONLY enter a special sale, and a
    // special sale carries ONLY perishables. So the sale type alone says what
    // is in it — no need to inspect the items.
    bool saleIsPerishable(String tenderType) => tenderType == 'special';

    test('special carries perishables', () {
      expect(saleIsPerishable('special'), isTrue);
    });

    test('general does not', () {
      expect(saleIsPerishable('general'), isFalse);
    });
  });

  group("'perishable' is a real source now", () {
    // ⚠️ It used to be SYNTHETIC — built on the fly for goods with no
    // forfeited_packages row. The CHECK constraint allowed only forfeit /
    // abandoned / other / detain, so a perishable that genuinely reached a
    // sale had to be filed under 'forfeit', and then sat in the appeal list
    // wearing a Forfeit badge — indistinguishable from goods that really do
    // have 30 days to run. A perishable has no appeal window at all.
    test('the migration widens the constraint and re-files the rows', () {
      final sql = _read('postgres/07_perishable_source.sql');
      expect(sql, contains("'perishable'::text"));
      expect(sql, contains('forfeited_packages_source_check'));
      expect(sql, contains("set source = 'perishable'"));
      // It verifies its own claims against the live database.
      expect(sql, contains(r'do $verify$'));
      expect(sql, contains('raise exception'));
    });
  });
}
