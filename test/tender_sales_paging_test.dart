// Tender Sales is the heaviest query in the app.
//
// getTenderSales fetches every sale with its items, their forfeited rows,
// those rows' packages, and every package item and warehouse entry underneath
// -- and Central Disposal shows all twenty-eight yards through it.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';

void main() {
  final view =
      File('postgres/26_tender_sale_summary_view.sql').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final screen = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();

  group('the view settles what SQL can settle', () {
    test('one row per sale, with its counts', () {
      expect(view, contains('as item_count'));
      expect(view, contains('as sold_count'));
      expect(view, contains('as has_pending'));
      expect(view, contains('sale(s) have counts that disagree with their items'));
    });

    test('the yard match is on any ITEM, not the sale', () {
      // ⚠️ A sale can mix items from a multi-directorate yard -- NNR items
      // filed under CED beside ones filed under PSD -- so the sale-level yard
      // code cannot tell them apart.
      expect(view, contains('as item_yards'));
      expect(view, contains("string_agg(distinct ti.yard, '|')"));
    });

    test('the searchable columns are TEXT, not arrays', () {
      // ⚠️ ilike cannot serve an array, and the Dart driver hands array
      // columns back as UndecodedBytes -- the row would arrive unreadable.
      expect(view, contains("'|' || coalesce(string_agg"));
      // And pipe-wrapped, so a filter cannot match across two neighbours.
      expect(view, contains("|| '|'"));
      expect(view, contains('sale(s) have items but no SR numbers to search'));
    });

    test('a re-tender needs an EARLIER sale sharing its goods', () {
      expect(view, contains('as is_retender'));
      expect(view, contains('earlier.created_at < ts.created_at'));
      expect(view,
          contains('sale(s) claim to be re-tenders with nothing before them'));
    });

    test('it matches on the ITEM, falling back to the forfeited id', () {
      // Two DIFFERENT items of one SR in two sales are not a re-tender.
      expect(view, contains('fpa.item_id'));
      expect(view, contains('a.forfeited_package_id::text'));
    });
  });

  group('the sell window stays in Dart, deliberately', () {
    test('the view does not try to decide it', () {
      // ⚠️ `workingDeadline` rolls past weekends AND Sri Lankan public
      // holidays fetched from an API at runtime. There is no holiday table
      // here, so a SQL version would disagree with the app on exactly the days
      // that matter.
      expect(view, isNot(contains('unsold_deadline')));
      expect(view, contains('does NOT decide'));
    });

    test('the screen applies it to the page it received', () {
      expect(screen, contains('final windowClosed = s.unsoldDeadline != null'));
    });
  });

  group('the query', () {
    final method = services.substring(services.indexOf('getTenderSalesPaged'));

    test('one filter closure serves the rows and the count', () {
      expect(method, contains('PgQuery narrow(PgQuery q)'));
      expect(method, contains('.range(offset, offset + limit - 1)'));
      expect(method,
          contains("narrow(supabase.from('tender_sale_summary')).count()"));
    });

    test('the heavy fetch runs for one page of ids only', () {
      // ⚠️ This is the whole point: the join tree that made the old query
      // expensive now runs against twenty sales, not all of them.
      expect(method, contains(".inFilter('id', ids)"));
      expect(method, contains('tender_sale_items(*, forfeited_packages(*'));
    });

    test('an empty page asks for nothing', () {
      expect(method, contains('if (ids.isEmpty)'));
    });

    test("the view's order is kept, not re-sorted in Dart", () {
      expect(method, contains('for (final id in ids) if (byId[id] != null)'));
    });
  });

  group('re-tender ids come from their own query', () {
    test('over ALL sales, not the page', () {
      // ⚠️ Derived from one page, a sale would be marked new simply because
      // its predecessor sat on the page before.
      expect(services, contains('Future<Set<String>> getRetenderSaleIds()'));
      expect(services, contains("eq('is_retender', true)"));
      expect(screen, contains('retenderSaleIdsProvider'));
    });
  });

  group('the query key', () {
    test('two identical queries are the same key', () {
      const a = TenderSaleQuery(page: 1, search: 'TS/GL1');
      const b = TenderSaleQuery(page: 1, search: 'TS/GL1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every filter takes part in it', () {
      const base = TenderSaleQuery();
      expect(base, isNot(const TenderSaleQuery(page: 1)));
      expect(base, isNot(const TenderSaleQuery(search: 'x')));
      expect(base, isNot(const TenderSaleQuery(yardFilter: 'GL1')));
      expect(base, isNot(const TenderSaleQuery(onlyPending: true)));
    });
  });

  group('the tab reads it', () {
    test('the paged provider, with a pager and the server total', () {
      expect(screen, contains('tenderSalesPageProvider(query)'));
      expect(screen, contains('total: result.total,'));
      expect(screen, contains('pageSize: kDispositionPageSize,'));
    });

    test('it hides sales with nothing left to act on, in SQL', () {
      expect(screen, contains('onlyPending: true,'));
    });

    test('a filter change starts at the top', () {
      // ⚠️ A narrowed result otherwise strands the reader on a page that no
      // longer exists.
      expect(screen, contains('_tenderSalePage = 0'));
    });
  });

  group('Disposal Requests pages the same way', () {
    final drView =
        File('postgres/27_disposal_request_summary_view.sql').readAsStringSync();
    final method =
        services.substring(services.indexOf('getDisposalRequestsPaged'));

    test('a request with nothing live is not listed at all', () {
      // ⚠️ This is the rule that forced the old code to fetch everything: a
      // request is visible only through its items, so it had to load them all
      // to discover which requests to throw away.
      expect(drView, contains('agg.live_count > 0'));
      expect(drView, contains('request(s) are listed with no live items'));
    });

    test('both gates are kept, exactly as the app had them', () {
      // The request must be forwarded by the Valuation Directorate...
      expect(drView, contains("dr.valuation_status = 'forwarded'"));
      // ...and the ITEM's own flag must be set: a request can be forwarded
      // with only some of its items released.
      expect(drView, contains('where dri.forwarded'));
      expect(drView, contains('request(s) are not forwarded but are listed'));
    });

    test('all three consumed sources are excluded', () {
      // A tender's id array, a tender sale's items, a destruction's items.
      expect(drView, contains('unnest(t.forfeited_package_ids)'));
      expect(drView, contains('from public.tender_sale_items ti'));
      expect(drView, contains('from public.destruction_items di'));
      expect(drView,
          contains('request(s) count goods that have already moved on'));
    });

    test('the searchable columns are text, pipe-wrapped', () {
      expect(drView, contains("'|' || coalesce(string_agg"));
      expect(drView, contains('request(s) have no SR numbers to search'));
    });

    test('the heavy fetch runs for one page of ids', () {
      expect(method, contains(".inFilter('id', ids)"));
      expect(method, contains('.range(offset, offset + limit - 1)'));
      expect(method,
          contains("narrow(supabase.from('disposal_request_summary')).count()"));
    });

    test('the page still drops consumed items from the rows it got', () {
      // ⚠️ The view decides which REQUESTS survive; the item list on each card
      // still has to exclude the consumed ones or a card would show goods that
      // have already moved on.
      expect(method, contains('!consumed.contains(i.forfeitedPackageId)'));
    });

    test('the tab reads it, with a pager and the server total', () {
      expect(screen, contains('disposalRequestsPageProvider(query)'));
      expect(screen, contains('DisposalRequestQuery('));
    });
  });
}
