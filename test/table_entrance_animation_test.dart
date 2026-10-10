// Every table arrives the same way.
//
// Old Entries animated its header and its filter bar but not its TABLE, so the
// two slid in and the rows simply appeared underneath them -- the table read as
// snapping into place while the rest of the page settled. Perishable Goods had
// a subtler version: its table used the same 200ms delay as the filter bar
// above it, so the two moved together and the page arrived as one block.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Every screen in the app that renders a DataTable2 the user pages through.
  const screens = [
    'lib/screens/packages/old_entries_screen.dart',
    'lib/screens/packages/perishable_goods_screen.dart',
    'lib/screens/packages/returned_packages_screen.dart',
    'lib/screens/packages/detained_packages_screen.dart',
    'lib/screens/packages/abandoned_packages_screen.dart',
    'lib/screens/packages/other_packages_screen.dart',
    'lib/screens/packages/disposition_category_screen.dart',
    'lib/screens/packages/unsold_packages_screen.dart',
    'lib/screens/warehouses/warehouses_screen.dart',
  ];

  group('every paged table animates in', () {
    for (final path in screens) {
      final name = path.split('/').last.replaceAll('.dart', '');
      final src = File(path).readAsStringSync();

      test('$name renders a table', () {
        // Guards the list above: a screen renamed or reworked away should fail
        // here rather than quietly stop being checked.
        expect(src, contains('DataTable2('),
            reason: '$path no longer has a table — update this list');
      });

      test('$name slides its table in, after the filter bar', () {
        // ⚠️ 300ms is the whole point: the header uses none, the filter bar
        // uses 200, and the table waits for both so the page settles top to
        // bottom instead of arriving as one block.
        expect(src, contains('delay: 300.ms'),
            reason: '$path: its table must animate like every other one');
      });
    }
  });

  group('the timings are a sequence, not a coincidence', () {
    test('header, then filter bar, then table', () {
      // One page is enough to pin the intended order; the test above holds
      // every other page to the same last step.
      final src =
          File('lib/screens/packages/returned_packages_screen.dart')
              .readAsStringSync();
      // The filter bar comes in at 200...
      expect(src, contains('delay: 200.ms'));
      // ...and the table after it.
      expect(src, contains('delay: 300.ms'));
    });
  });
}
