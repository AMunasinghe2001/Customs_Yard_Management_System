// The Financials page used to load the WHOLE ledger to show twenty rows.
//
// srFinancialsProvider fetched every package in every yard with its items and
// warehouse entries, every tender sale, and every expense row -- then the tab
// filtered them with `.where`, paged them with `.skip().take()`, and summed
// them with summariseSrs. 420 kB of JSON decoded on the UI isolate so a header
// strip could show ten numbers, which is what made the page take a second or
// two to open.
//
// It now reads `sr_financials` (postgres/41): the filter, the ordering, the
// page and the totals are all SQL. Measured against the live database, warm:
//
//     the old whole-ledger load   357-465ms
//     narrowed + serial            167-204ms
//     one page + SQL totals        102-135ms
//
// The view's own verify block asserts its ten figures against what the page
// was showing before it existed, and a live comparison confirmed the two agree
// to the cent: income 767,034,359.19, expenditure 4,736,392.00.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final tab =
      File('lib/screens/executive/financials_tab.dart').readAsStringSync();
  final view =
      File('postgres/41_sr_financials_view.sql').readAsStringSync();

  /// Whitespace collapsed: these calls wrap across lines, and a single-line
  /// pattern is exactly what let a wrapped call hide before.
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  /// Code with the comment lines dropped. A comment that NAMES the old
  /// approach, to record why it is gone, reads to a substring check as the old
  /// approach still being there.
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n'));

  group('the page asks SQL for a page, not Dart for the ledger', () {
    test('the service pages and counts against the view', () {
      expect(services, contains('getSrFinancialsPaged'));
      final fn = code(services.substring(
          services.indexOf('Future<({List<SrLedgerRow> rows, int total})>')));
      final body = fn.substring(0, 1800);

      expect(body, contains("from('sr_financials')"));
      // A page, and a count of what the filter matches beyond it.
      expect(body, contains('.range(offset, offset + limit - 1)'));
      expect(body, contains('.count()'));
    });

    test('the totals are their own query over the whole filter', () {
      // ⚠️ Not folded from the page. Summing twenty rows would report one
      // page of money as the directorate's total — the mistake the Expenses
      // tab had to be corrected for.
      expect(services, contains('Future<FinancialSummary> getSrFinancialTotals'));
      final fn = code(services.substring(
          services.indexOf('Future<FinancialSummary> getSrFinancialTotals')));
      final body = fn.substring(0, 1600);

      expect(body, contains("from('sr_financials')"));
      expect(body.contains('.range('), isFalse,
          reason: 'the totals must not be limited to a page');
      for (final column in [
        'sr_charges',
        'destroying_deposit',
        'sale_proceeds',
        'taxes',
        'destruction_expense',
        'advertising_expense',
        'labour_expense',
        'transport_expense',
        'auction_expense',
        'refund',
      ]) {
        expect(body, contains(column),
            reason: '$column is one of the ten figures the strip shows');
      }
    });

    test('one filter closure serves the rows, the count and the totals', () {
      // ⚠️ When they narrow separately they drift, and the strip then
      // reports money the table below it does not list.
      expect(services, contains('PgQuery _narrowFinancials('));
      final rows = code(services.substring(
          services.indexOf('Future<({List<SrLedgerRow> rows, int total})>')));
      expect(rows.substring(0, 1800).split('_narrowFinancials').length - 1,
          greaterThanOrEqualTo(2),
          reason: 'the rows and the count must share the filter');
      final totals = code(services.substring(
          services.indexOf('Future<FinancialSummary> getSrFinancialTotals')));
      expect(totals.substring(0, 1600), contains('_narrowFinancials'));
    });

    test('the search reaches the goods name, not just the SR', () {
      final fn = code(services.substring(
          services.indexOf('PgQuery _narrowFinancials(')));
      final body = fn.substring(0, 1200);
      for (final column in ['sr_number', 'consignee_name', 'goods_name']) {
        expect(body, contains('$column.ilike'));
      }
    });
  });

  group('the provider is a family, keyed by the whole filter', () {
    test('every field of the key is in == AND hashCode', () {
      // ⚠️ A family key that forgets a field never refetches when that field
      // changes: the page silently keeps the previous filter's rows.
      final cls = providers.substring(providers.indexOf('class FinancialsQuery'),
          providers.indexOf('typedef FinancialsPage'));
      for (final field in [
        'page',
        'search',
        'yardFilter',
        'dateStart',
        'dateEnd',
      ]) {
        expect(cls.split('other.$field == $field').length - 1, 1,
            reason: '$field is missing from ==');
        expect(cls.substring(cls.indexOf('int get hashCode')), contains(field),
            reason: '$field is missing from hashCode');
      }
    });

    test('the page and the totals both come from it', () {
      final fn = code(providers.substring(
          providers.indexOf('final financialsPageProvider'),
          providers.indexOf('final recentPackagesProvider')));
      expect(fn, contains('getSrFinancialsPaged('));
      expect(fn, contains('getSrFinancialTotals('));
      // ⚠️ Serial, for the reason srFinancialsProvider measures: both decode
      // on this isolate, so issuing them together only makes each wait longer.
      expect(fn.contains('Future.wait('), isFalse);
    });
  });

  group('the tab stopped loading the ledger', () {
    test('it watches the paged provider, not the whole-ledger one', () {
      final c = code(tab);
      expect(c, contains('financialsPageProvider('));
      expect(c.contains('watch(srFinancialsProvider)'), isFalse,
          reason: 'the tab is loading every package in every yard again');
    });

    test('nothing is filtered or summed in Dart any more', () {
      final c = code(tab);
      expect(c.contains('summariseSrs('), isFalse,
          reason: 'the totals come from SQL now');
      expect(c.contains('_matchesDateRange('), isFalse,
          reason: 'the date filter is a SQL predicate now');
    });

    test('the pager is clamped against the SERVER count', () {
      // ⚠️ `rows.length` is now the PAGE size, not the ledger's. Clamping
      // against it would pin the pager to page 1 and hide every later page.
      final fn = code(tab.substring(tab.indexOf('class _GoodsBreakdown ')));
      final body = fn.substring(0, 900);
      expect(body, contains('total == 0 ? 0 : (total - 1)'));
      expect(body.contains('(rows.length - 1) ~/'), isFalse);
    });
  });

  group('the view computes what the Dart computed', () {
    test('it asserts its figures against the running page', () {
      // A view that computes different money is a wrong view, however clean
      // its SQL reads — so the migration checks all ten against what the page
      // was showing, and refuses to apply otherwise.
      expect(view, contains(r'do $verify$'));
      for (final figure in [
        '369383700', // SR charges
        '3776645', // deposits
        '308692662', // sale proceeds
        '85181352', // taxes
        '423384', // destruction
        '189664', // advertising
        '338536', // labour
        '294632', // transport
        '341859', // auction
        '3148317', // refunds
      ]) {
        expect(view, contains(figure),
            reason: '$figure is one of the ten the page showed');
      }
    });

    test('dates are pinned to Asia/Colombo, not the reader', () {
      // ⚠️ `admitted_at::date` follows the SESSION's timezone. psql here
      // inherits Asia/Colombo and the app's driver connects as UTC, so the
      // same entry landed on a different day for each: the storage charge
      // read 88,100 higher through the app than through psql, from the same
      // view and the same database. Dart counts days in local time
      // (parseDbDate calls .toLocal()), so the view says so explicitly.
      expect(view, contains("at time zone 'Asia/Colombo'"));
      expect(view, contains("set local timezone to 'UTC'"),
          reason: 'the migration must prove the figures do not move under UTC');

      // No bare ::date on a timestamptz column would defeat the point.
      for (final bare in [
        'we.admitted_at::date',
        'we.returned_at::date',
        'now()::date',
      ]) {
        expect(view.contains(bare), isFalse,
            reason: '$bare follows the reader\'s timezone');
      }
    });

    test('the rate before the first recorded rate is still charged', () {
      // ⚠️ Goods admitted before the rate table was filled in are charged at
      // the model's own default of 50. Dropping that period would silently
      // zero them.
      final periods = view.substring(view.indexOf('rate_period as ('));
      expect(periods.substring(0, 1200), contains("date '1900-01-01'"));
      expect(periods.substring(0, 1200), contains('50::numeric'));
    });

    test('the tax breakdown is by NAME, from what was stored', () {
      // The table draws a column per tax and the names are data: a tax added
      // tomorrow must appear without a migration. And the amounts are the ones
      // written at the moment of sale — re-reading today's tax table would
      // restate past sales whenever a rate is switched on or off.
      expect(view, contains('jsonb_object_agg(tax_name, amount)'));
      expect(view, contains('applied_taxes'));
    });

    test('a refund is floored per SR, never per total', () {
      // An SR that overspent its deposit refunds nothing; summing a negative
      // would understate the directorate's refunds.
      expect(view, contains('greatest('));
      final refundBlock =
          view.substring(view.indexOf('as deposit_spent'));
      expect(refundBlock.substring(0, 600), contains('greatest('));
    });
  });
}
