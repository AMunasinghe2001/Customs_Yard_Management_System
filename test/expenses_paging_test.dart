// Disposal Expenses: the last Central Disposal tab fetching the whole yard.
//
// It read srFinancialsProvider, which calls getAllPackages() AND
// getTenderSales() and rolls the whole yard up in Dart -- per item, per tax
// name. That was measured and deliberately left alone once, on ONE yard; this
// tab shows twenty-eight.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';

void main() {
  final view =
      File('postgres/30_sr_expense_summary_view.sql').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final tab =
      File('lib/screens/disposal/expenses_tab.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();

  group('the view answers only what this tab needs', () {
    test('it lists an SR only when there is money to account for', () {
      // An SR with neither a deposit nor a cost would be a blank row.
      expect(view, contains('where coalesce(p.destroying_deposit, 0) > 0'));
      expect(view, contains('SR(s) are listed with nothing to account for'));
    });

    test('an expense counts whether it names an item or only the SR', () {
      // ⚠️ 16 rows key to a package item and 55 to the SR alone in this
      // database. Matching one way would silently drop most of the money.
      expect(view, contains('group by fe.sr_number'));
      expect(view, contains('expense row(s) belong to no listed SR'));
    });

    test('a zero deposit is real, never invented', () {
      // ⚠️ A mistake this codebase has already made once: a plausible-looking
      // figure seeded from a hash, indistinguishable from a true LKR 0.
      expect(view, contains('coalesce(p.destroying_deposit, 0)'));
      expect(view, contains('never invented'));
    });

    test('a refund and a deficit cannot both be positive', () {
      // Either the deposit covered the spend or it did not.
      expect(view, contains('SR(s) claim a refund AND a deficit'));
    });

    test('the parts add up to the total spent', () {
      expect(view, contains('SR(s) have a spend that disagrees with its parts'));
    });
  });

  group('the date fallback survived the move', () {
    test('it falls back to the YEAR IN THE SR NUMBER', () {
      // ⚠️ A legacy SR can carry no usable date at all. The app matched it on
      // its number's year rather than dropping it from every date filter, and
      // losing that would hide those SRs whenever a range was set.
      expect(view, contains(r"substring(p.sr_number from '(20[0-9]{2})')"));
      expect(view, contains('THE YEAR IN THE SR NUMBER'));
    });

    test('no row may be dateless', () {
      expect(view,
          contains('SR(s) have no date, so a range filter would hide them'));
    });

    test('the Dart version is gone, and says where it went', () {
      expect(tab, isNot(contains('bool _matchesDateRange(')));
      expect(tab, contains('moved into `sr_expense_summary`'));
    });
  });

  group('the totals are summed across the FILTER, not the page', () {
    test('they have their own query', () {
      // ⚠️ The strip used to add up the rows on screen. That was right while
      // the table held every row and became wrong the moment it held twenty:
      // it would report one page's money as the directorate's total.
      expect(services, contains('Future<Map<String, double>> getExpenseTotals'));
      expect(providers, contains('`totals` is a separate query on purpose'));
    });

    test('the strip takes the sums rather than the rows', () {
      // ⚠️ Scoped to the STRIP. `_ExpensesTable` still takes rows and should:
      // it renders the page, which is exactly a list of rows.
      final stripStart = tab.indexOf('class _TotalsStrip');
      final strip = tab.substring(
          stripStart, tab.indexOf('class ', stripStart + 10));
      expect(strip, contains('final Map<String, double> totals;'));
      expect(strip, isNot(contains('final List<SrFinancials> rows;')));
      expect(tab, contains('_TotalsStrip(totals: result.totals)'));
    });

    test('they are computed even when the page is empty', () {
      // A filter that matches money but no page-1 rows must still report it.
      final prov = providers.substring(providers.indexOf('expensePageProvider'));
      expect(prov.indexOf('getExpenseTotals'),
          lessThan(prov.indexOf('if (ids.packageIds.isEmpty)')));
    });
  });

  group('the ledger is built for one page', () {
    test('buildSrFinancials was extracted so a page can use it', () {
      // ⚠️ A function, not a view: the table and its dialog read the per-item
      // `goods` list, and reproducing that in SQL would be a second definition
      // of the same figures.
      expect(providers, contains('List<SrFinancials> buildSrFinancials({'));
      expect(providers, contains('the EXPENSES tab can build'));
    });

    test('the whole-ledger provider still uses it', () {
      // The Financials tab genuinely sums everything, so it must not have
      // been broken by the extraction.
      expect(providers, contains('return buildSrFinancials('));
      expect(providers, contains('final srFinancialsProvider'));
    });

    test('the page fetches only its own packages', () {
      expect(providers, contains('packageSvc.getPackagesByIds(ids.packageIds)'));
    });

    test('the view decides which SRs, and in what order', () {
      final m = services.substring(services.indexOf('getExpenseSrPageIds'));
      expect(m, contains(".order('activity_date', ascending: false)"));
      expect(m, contains('.range(offset, offset + limit - 1)'));
      expect(m, contains("supabase.from('sr_expense_summary')"));
    });
  });

  group('the query key', () {
    test('two identical queries are the same key', () {
      const a = ExpenseQuery(page: 1, search: 'CED');
      const b = ExpenseQuery(page: 1, search: 'CED');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every filter takes part in it', () {
      const base = ExpenseQuery();
      expect(base, isNot(const ExpenseQuery(page: 1)));
      expect(base, isNot(const ExpenseQuery(search: 'x')));
      expect(base, isNot(const ExpenseQuery(yardFilter: 'GL1')));
      expect(base, isNot(ExpenseQuery(dateStart: DateTime(2026, 1, 1))));
    });
  });

  group('the tab reads it', () {
    test('the paged provider, and the server count', () {
      expect(tab, contains('expensePageProvider(query)'));
      expect(tab, contains("value: '\$total',"));
      expect(tab, contains('total: total,'));
      expect(tab, isNot(contains('ref.watch(srFinancialsProvider)')));
    });

    test('the yard filter keeps its SR-prefix fallback', () {
      // ⚠️ A row with no yard of its own must not be hidden from a yard it
      // plainly belongs to.
      final m = services.substring(services.indexOf('getExpenseSrPageIds'));
      expect(m, contains(r"sr_number.ilike.%/$yardFilter/%"));
    });
  });
}
