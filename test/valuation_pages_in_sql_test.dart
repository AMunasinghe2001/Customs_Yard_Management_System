// The Valuation portal had no paging at all — not SQL paging, not even a
// client-side pager. All three tabs rendered every row they fetched:
//
//   * Pending Valuation and Perishable Goods shared one query six levels deep
//     (requests -> items -> forfeited -> packages -> items, and separately ->
//     warehouse entries -> warehouses), then split it in Dart.
//
//   * Unsold Tenders watched getUnsoldTenderSales() — the heaviest query in
//     the app — and then getValuedCurrentRoundIds(), which called that SAME
//     query a second time to learn one boolean per row.
//
// Measured against the live database, warm:
//
//     old   feed 82ms + unsold 132ms + valued 131ms = 345ms
//     new   tab 1 19ms, tab 3 29ms
//
// Membership is identical either way: 6 ordinary, 2 perishable, 9 unsold of
// which 5 pending — and Pending + Valued partition the tab exactly.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final screen = File('lib/screens/valuation/valuation_dashboard_screen.dart')
      .readAsStringSync();
  final feedView =
      File('postgres/42_valuation_rows_view.sql').readAsStringSync();
  final poolView =
      File('postgres/44_retender_pool_marked_unsold.sql').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n'));

  group('the feed tabs page in SQL', () {
    test('the service asks the view for a page and a count', () {
      expect(services, contains('getValuationFeedPaged'));
      final fn = code(services.substring(
          services.indexOf('getValuationFeedPaged'),
          services.indexOf('Future<List<DisposalRequestModel>> '
              '_valuationRequestsByIds')));
      expect(fn, contains("from('valuation_rows')"));
      expect(fn, contains('.range(offset, offset + limit - 1)'));
      expect(fn, contains('.count()'));
      // The tab IS the filter, not a Dart pass afterwards.
      expect(fn, contains("eq('is_perishable', perishable)"));
    });

    test('the deep fetch runs for one page of requests', () {
      // ⚠️ The embed is still six levels — the per-item cost form needs the
      // package's items to name the goods, and its warehouse entries because
      // the quantity being valued is the FORFEITED quantity, read off the
      // entries a forfeit returned. What changed is how many requests it runs
      // for.
      final fn = code(services.substring(
          services.indexOf('_valuationRequestsByIds(')));
      expect(fn.substring(0, 900), contains('.inFilter(\'id\', ids)'));
    });

    test('one rule decides which items are pending, for both fetches', () {
      // ⚠️ Shared, or the paged feed and the whole-feed fetch could disagree
      // about which items an officer is being asked to cost.
      expect(services, contains('_pendingItemsOnly('));
      expect('_pendingItemsOnly('.allMatches(services).length,
          greaterThanOrEqualTo(3),
          reason: 'the definition plus both callers');
    });

    test('the query key carries the tab, not just the page', () {
      // ⚠️ The two tabs are the same widget with one flag flipped. A key
      // without `perishable` would serve one tab whatever the other cached —
      // and the officer would be costing goods on the wrong clock.
      final cls = providers.substring(providers.indexOf('class ValuationFeedQuery'),
          providers.indexOf('typedef ValuationFeedPage'));
      for (final field in ['page', 'perishable', 'search', 'yardFilter']) {
        expect(cls.split('other.$field == $field').length - 1, 1,
            reason: '$field is missing from ==');
        expect(cls.substring(cls.indexOf('int get hashCode')), contains(field),
            reason: '$field is missing from hashCode');
      }
    });

    test('the tab renders a page and pages against the server count', () {
      final c = code(screen);
      expect(c, contains('valuationFeedPageProvider('));
      expect(c.contains('watch(valuationRequestsProvider)'), isFalse,
          reason: 'the tab is fetching the whole feed again');
      // The pager, which this portal did not have at all.
      expect(c, contains('TablePager('));
      expect(c, contains('total: data.total'));
      // ⚠️ A page counter PER TAB. One shared counter would carry the
      // officer's position across to the other tab, which reads as the list
      // having jumped.
      expect(c, contains('_valFeedPageProvider(perishableOnly)'));
    });
  });

  group('the unsold tab stopped fetching the yard twice', () {
    test('it reads the pool view, not the whole-sales query', () {
      final c = code(screen);
      expect(c, contains('unsoldRetenderPageProvider('));
      expect(c.contains('watch(unsoldTenderSalesProvider)'), isFalse,
          reason: 'the heaviest query in the app is back on this tab');
      expect(c.contains('watch(valuedCurrentRoundProvider)'), isFalse,
          reason: 'that provider runs the same heavy query a SECOND time');
    });

    test('the valued flag rides on the rows it describes', () {
      // ⚠️ Read off the same rows the page came from, not fetched again.
      final fn = code(services.substring(
          services.indexOf('getUnsoldRetenderPaged({')));
      expect(fn.substring(0, 2600),
          contains("select('forfeited_package_id, valued')"));
    });

    test('every filter is a SQL predicate', () {
      final fn = code(services.substring(
          services.indexOf('getUnsoldRetenderPaged({')));
      final body = fn.substring(0, 2600);
      // The round limit that keeps Top Management's packages off this tab.
      expect(body, contains("lte('round_count', kMaxBidTenderRounds)"));
      // Pending / Valued.
      expect(body, contains("eq('valued', valued)"));
      // Search and yard.
      expect(body, contains('sr_number.ilike'));
      expect(body, contains('yard.eq'));

      // And nothing is filtered in Dart afterwards.
      final tab = code(screen.substring(screen.indexOf('class _UnsoldTendersValTab')));
      expect(tab.substring(0, 4000).contains('rows.where('), isFalse,
          reason: 'filtering a page in Dart leaves the pager counting rows '
              'the table no longer shows');
    });

    test('the "N of M" counts run over the filter, not the page', () {
      expect(services, contains('getUnsoldRetenderCounts('));
      final fn = code(services.substring(
          services.indexOf('getUnsoldRetenderCounts(')));
      final body = fn.substring(0, 1400);
      expect(body.contains('.range('), isFalse,
          reason: 'a count limited to a page is one page of work, not the '
              'directorate queue');
      expect(body, contains('.count()'));
      expect(code(screen), contains('unsoldRetenderCountsProvider('));
    });

    test('the key carries the two new fields, in == and hashCode', () {
      final cls = providers.substring(providers.indexOf('class UnsoldRetenderQuery'),
          providers.indexOf('int get hashCode', providers.indexOf('class UnsoldRetenderQuery')) + 200);
      for (final field in ['valuationRoundsOnly', 'valued']) {
        expect(cls, contains('other.$field == $field'),
            reason: '$field is missing from ==');
        expect(cls.substring(cls.indexOf('int get hashCode')), contains(field),
            reason: '$field is missing from hashCode');
      }
    });
  });

  group('the views carry the rules the Dart used to', () {
    test('a request is perishable when EVERY pending item is', () {
      expect(feedView, contains("bool_and(source = 'perishable')"));
      expect(feedView, contains('where not dri.forwarded'));
      // The migration proves the two tabs partition the feed.
      expect(feedView, contains(r'do $verify$'));
      expect(feedView, contains('the two tabs hold'));
    });

    test('the pool follows the MARK, never a clock', () {
      // ⚠️ This was the bug the port uncovered. The Dart entered a package
      // into the pool when an officer MARKED its latest round unsold; the
      // view admitted any package whatever had been recorded, and carried a
      // `round_moment_passed` column computed from `sale_moment < now()`.
      // getUnsoldTenderSales() found 9 packages, the view listed 15 — the six
      // extra were sales Central Disposal had still to record the outcome of.
      //
      // Marking rather than the calendar was asked for directly: a public
      // holiday used to move the deadline and the package moved with it, and
      // the sale had already gone from Central Disposal's tab so they could
      // not record what happened.
      expect(poolView, contains('l.latest_unsold'));
      expect(poolView, contains(r'do $verify$'));
      expect(poolView, contains('nobody '));

      // The column stays as information and decides nothing.
      expect(poolView, contains('round_moment_passed'));
      expect(poolView.contains('and l.sale_moment < now()'), isFalse,
          reason: 'the calendar is deciding an outcome again');
    });

    test('the four-round limit survived the rewrite', () {
      // ⚠️ Rewriting a whole view to add a column is exactly when a `where`
      // clause goes missing, so the migration re-asserts every rule /38
      // established.
      expect(poolView, contains('round_count <= 4'));
      expect(poolView, contains('can be re-tendered past four rounds'));
      expect(poolView, contains('sold package(s) are in the re-tender pool'));
      expect(poolView, contains('perishable(s) are in the re-tender pool'));
      expect(poolView, contains('exhausted package(s) are in the re-tender pool'));
    });

    test('valued means the NEXT round is priced, not this one', () {
      // ⚠️ A figure keyed TO a round is that round's own reserve, and every
      // held round has one — counting those marked every package valued and
      // hid the Set Value button.
      expect(poolView, contains('tr.tender_sale_id is null'));
    });
  });
}
