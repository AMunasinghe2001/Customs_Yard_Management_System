// The yard's Tender Sale page watched `tenderSalesProvider` — the heaviest
// query in the app, every sale in the country with its items, forfeited rows,
// packages, package items and warehouse entries — then filtered it by yard,
// search, date range and year in Dart and paged the result with
// `pageSlice`. Client-side paging still loads everything; it only renders
// less. 154ms → 49ms for a page.
//
// Porting it uncovered a live bug in Top Management's copy of the same query:
// both of that tab's filters were throwing, because the service asked for
// columns the view did not have.
//
// Every filter was checked against the Dart it replaces, on the live
// database: 82 sales for GL1 either way, year 2026 → 44 both ways, August
// 2026 → 5 both ways.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final screen =
      File('lib/screens/forfeited_packages/tender_disposal_screen.dart')
          .readAsStringSync();
  final view =
      File('postgres/46_tender_summary_consignees.sql').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n'));

  group('the view has the columns the filters name', () {
    test('item_yards and consignees exist', () {
      // ⚠️ This is the bug the port found. Top Management's Tender Sales tab
      // pages against `tender_sale_summary`, and BOTH its filters threw:
      //
      //     column "item_yards" does not exist
      //     column "consignees" does not exist
      //
      // The service asked for `item_yards`; the view called it `yards`. And
      // nothing ever carried the consignee names the search claims to match.
      // Neither failure showed on the page — picking a yard or typing a
      // search simply errored the tab, while the unfiltered case kept working.
      expect(view, contains('as item_yards'));
      expect(view, contains('as consignees'));
      // The migration proves it by selecting on them, so a missing column
      // raises 42703 in the migration rather than in the app.
      expect(view, contains(r'do $verify$'));
      expect(view, contains("item_yards ilike '%|GL1|%'"));
      expect(view, contains('is not being'));
    });

    test('every list is pipe-wrapped', () {
      // ⚠️ So an `ilike '%|GL1|%'` matches a whole value and cannot run
      // across two neighbouring entries.
      expect(view, contains('are not pipe-wrapped'));
    });

    test('the two names for the yard list cannot drift', () {
      expect(view, contains('yards and item_yards disagreeing'));
    });

    test('has_pending still means UNDECIDED', () {
      // The rule postgres/35 established, re-asserted because this migration
      // rewrites the whole view.
      expect(view, contains('undecided_count > 0 as has_pending'));
      expect(view, contains('report has_pending against their own'));
    });
  });

  group('the page asks SQL for a page', () {
    test('the service filters on dates and year in SQL', () {
      final fn = code(services.substring(
          services.indexOf('getTenderSalesPaged({')));
      final body = fn.substring(0, 2600);
      expect(body, contains("gte('sale_date'"));
      expect(body, contains("lte('sale_date'"));
      // ⚠️ The year is a RANGE, not a string test: a sale with no date
      // matched no year before and must not start matching one now.
      expect(body, contains(r"'$year-01-01'"));
      expect(body.contains("ilike('sale_date'"), isFalse);
    });

    test('the year list comes from all sales, not the page', () {
      // ⚠️ A dropdown built from twenty rows offers only the years on screen,
      // and a year that is not listed reads as records that no longer exist.
      expect(services, contains('getTenderSaleYears()'));
      expect(providers, contains('tenderSaleYearsProvider'));
      final c = code(screen);
      expect(c, contains('tenderSaleYearsProvider'));
      expect(c.contains('.map((s) => s.saleDate!.year.toString())'), isFalse,
          reason: 'the years are being derived from the page again');
    });

    test('the key carries the dates, in == and hashCode', () {
      final cls = providers.substring(providers.indexOf('class TenderSaleQuery'),
          providers.indexOf('typedef TenderSalePage'));
      for (final field in [
        'page',
        'search',
        'yardFilter',
        'onlyPending',
        'dateStart',
        'dateEnd',
        'year',
      ]) {
        expect(cls.split('other.$field == $field').length - 1, 1,
            reason: '$field is missing from ==');
        expect(cls.substring(cls.indexOf('int get hashCode')), contains(field),
            reason: '$field is missing from hashCode');
      }
    });

    test('the screen watches the paged provider and filters nothing', () {
      final c = code(screen);
      expect(c, contains('tenderSalesPageProvider('));
      expect(c.contains('watch(tenderSalesProvider)'), isFalse,
          reason: 'the heaviest query in the app is back on this page');
      expect(c.contains('pageSlice('), isFalse,
          reason: 'client-side paging still loads everything');
      expect(c, contains('total: data.total'));
      expect(c, contains('pageSize: kDispositionPageSize'));
    });

    test('the yard is the SQL filter, not a Dart pass', () {
      final c = code(screen);
      expect(c, contains('yardFilter: myYard'));
      expect(c.contains('s.items.any((i) => i.effectiveYard == myYard)'), isFalse,
          reason: 'the yard is being matched over a fetched list again');
    });

    test('re-tenders are detected over ALL sales', () {
      // ⚠️ Derived from twenty rows a sale would be called new simply
      // because its predecessor sat on the page before.
      final c = code(screen);
      expect(c, contains('retenderSaleIdsProvider'));
      expect(c.contains('retenderTenderSaleIds(visible)'), isFalse);
    });

    test('the dead whole-table provider is gone', () {
      // ⚠️ `allForfeitedMapProvider` fetched EVERY forfeited package with
      // every package item, and nothing watched it — kept alive by the file
      // rather than by any reader.
      expect(screen.contains('final allForfeitedMapProvider'), isFalse);
    });
  });
}
