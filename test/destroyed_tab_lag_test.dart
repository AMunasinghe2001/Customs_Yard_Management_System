// The Destroyed Goods tab lagged on load, and paging the tab had not fixed it.
//
// The table was paged, but each row's "Destruction Expenses" cell watched
// srFinancialsProvider -- getAllPackages() plus getTenderSales(), rolled up
// per item and per tax name -- to display ONE figure, then scanned that list
// linearly for its SR. Twenty rows meant twenty widgets waiting on the whole
// yard's ledger.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cell =
      File('lib/widgets/destruction_status_pill.dart').readAsStringSync();
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();
  final yardPage =
      File('lib/screens/packages/disposition_category_screen.dart')
          .readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();

  group('the expense cell no longer fetches the whole yard', () {
    test('it does not watch the ledger provider', () {
      // ⚠️ This is the lag. One cell, one whole-yard ledger.
      expect(cell, isNot(contains('ref.watch(srFinancialsProvider)')));
      expect(cell, contains('destructionSpendProvider'));
    });

    test('the replacement asks only for the page it needs', () {
      expect(services,
          contains('Future<Map<String, double>> getDestructionSpendBySr'));
      expect(services, contains(".inFilter('sr_number', srNumbers"));
      // From the summary view, which already sums the spend per SR.
      expect(services, contains("supabase.from('sr_expense_summary')"));
    });

    test('an empty page asks for nothing at all', () {
      final m = services.substring(services.indexOf('getDestructionSpendBySr'));
      expect(m, contains('if (srNumbers.isEmpty) return const {};'));
    });
  });

  group('one query per PAGE, not per row', () {
    test('the scope carries the page key', () {
      // ⚠️ An InheritedWidget rather than a constructor argument: the cells
      // are built deep inside a DataTable2 row builder, and threading the list
      // through each one would put the page's shape into every cell.
      expect(cell, contains('class DestructionExpenseScope extends InheritedWidget'));
      expect(cell, contains('DestructionExpenseScope.of(context)'));
    });

    test('the key is stable for a given page', () {
      // ⚠️ Sorted and de-duplicated: an unstable family key opens a fresh
      // query on every rebuild, which would trade one slow load for a
      // permanent one.
      expect(cell, contains('final list = set.toList()..sort();'));
      expect(cell, contains('.toSet()'));
    });

    test('both tables that show the column provide it', () {
      // Central Disposal's Destroyed tab...
      expect(dash, contains('DestructionExpenseScope('));
      expect(dash, contains('DestructionExpenseScope.keyFor('));
      // ...and the yard's own Destroyed page.
      expect(yardPage, contains('DestructionExpenseScope('));
      expect(yardPage, contains('DestructionExpenseScope.keyFor('));
    });

    test('the provider is keyed by the joined SR list', () {
      expect(providers, contains('final destructionSpendProvider'));
      expect(providers, contains("srKey.split('|')"));
    });
  });

  group('the dead per-row cells are gone', () {
    test('neither is left in the file', () {
      // ⚠️ Each watched destructionItemForPackageItemProvider, which is TWO
      // round trips per row -- the second with a deep nested join. Never
      // rendered, but forty queries a page if anyone wired them up.
      expect(dash, isNot(contains('class _DestructionValuationCell')));
      expect(dash, isNot(contains('class _DestructionPriceCell')));
      expect(dash, contains('were never rendered'));
    });
  });
}
