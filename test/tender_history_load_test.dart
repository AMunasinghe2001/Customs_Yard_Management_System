import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The Sold Goods popup's Tender History appeared noticeably later than the
  // rest of the dialog, but only in the YARD. The cause was not the widget: it
  // derived a package's rounds by filtering tenderSalesProvider, which fetches
  // EVERY tender sale joined down through items -> packages -> package_items ->
  // warehouse_entries (measured: 389 rows, ~122ms). Central Disposal's Tender
  // Sales tab had already cached that, so its popup was instant; the yard's
  // Sold Goods page never loads it, so every popup paid the cold fetch.
  //
  // Fixed by asking for one package's rounds (~11ms) and warming that while
  // the table is on screen.
  group('the popup does not pull every tender sale', () {
    final dialog =
        File('lib/widgets/package_details_dialog.dart').readAsStringSync();

    test('tender history reads the per-package rounds provider', () {
      expect(dialog, contains('tenderRoundsForPackageProvider(forfeited.id)'));
    });

    test('it no longer watches the whole-table provider', () {
      // A comment may still mention it; a ref.watch must not.
      expect(dialog, isNot(contains('ref.watch(tenderSalesProvider)')),
          reason: 'That fetch is what made this section load late.');
    });

    test('the service query stays scoped to one package', () {
      final services = File('lib/services/services.dart').readAsStringSync();
      final i = services.indexOf('getTenderRoundsForPackage');
      expect(i, greaterThan(-1));
      final body = services.substring(i, i + 900);
      expect(body, contains("eq('forfeited_package_id'"),
          reason: 'Without the filter this is the slow query again.');
      // Only the two columns the round numbering needs.
      expect(body, contains('tender_sales(id, created_at)'));
      expect(body, isNot(contains('warehouse_entries')));
    });
  });

  test('the Sold table warms the history while it is on screen', () {
    // So the data is ready on click rather than starting to load then.
    final screen =
        File('lib/screens/packages/disposition_category_screen.dart')
            .readAsStringSync();
    expect(screen, contains('ref.watch(tenderRoundsForPackageProvider(fp.id))'));
    expect(screen, contains('ref.watch(tenderBidsProvider(fp.id))'));
  });
}
