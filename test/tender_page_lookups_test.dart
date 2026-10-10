// Four cells on the Unsold Tenders table each fetched their OWN row's bids or
// re-valuations — `_UnsoldValuationCell`, `_LatestValuationCell`,
// `_ReTenderStatusCell` and `_BidsCell` all read
// `tenderRevaluationsProvider(fpId)` or `tenderBidsProvider(fpId)` from inside
// their build. Twenty rows meant twenty round trips per cell. And two more
// providers were read as LOOKUPS — one `[fpId]` per row — while fetching every
// committee and every ruling in the country to serve them.
//
// Measured at page size, warm:
//
//     per-row    512ms
//     page-wide  151ms   (and that figure includes the committees and the
//                         rulings, which the per-row number does not)
//
// The committees pool is eight rows today and the rulings ten — but both are
// fed by all twenty-eight yards, and a committee is appointed for every
// package that survives four tender rounds.
//
// ⚠️ Porting them found a real ordering bug; see the last group.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final scope = File('lib/widgets/tender_page_scope.dart').readAsStringSync();
  final disposal =
      File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync();
  final committeeTab =
      File('lib/screens/executive/tender_committee_tab.dart').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') &&
          !l.trimLeft().startsWith('///'))
      .join('\n'));

  group('the page fetches once, not once per row', () {
    test('all four lookups have a page-wide form', () {
      for (final fn in [
        'getTenderBidsForPackages(',
        'getTenderRevaluationsForPackages(',
        'getTenderCommitteesForPackages(',
        'getUnsoldProposalsForPackages(',
      ]) {
        expect(services, contains(fn));
      }
      // Each takes a LIST and filters on it.
      final bids = code(services.substring(
          services.indexOf('getTenderBidsForPackages(')));
      expect(bids.substring(0, 900),
          contains("inFilter('forfeited_package_id'"));
    });

    test('the providers are keyed by the page, stably', () {
      // ⚠️ A family key is compared by value, so an unstable one opens a
      // fresh query on every rebuild — trading one slow load for a permanent
      // one.
      expect(providers, contains('String packageKeyOf('));
      final fn = code(providers.substring(providers.indexOf('String packageKeyOf(')));
      expect(fn.substring(0, 300), contains('.toSet()'));
      expect(fn.substring(0, 300), contains('..sort()'));
      for (final p in [
        'pageBidsProvider',
        'pageRevaluationsProvider',
        'pageCommitteesProvider',
        'pageProposalsProvider',
      ]) {
        expect(providers, contains('final $p ='));
      }
    });

    test('one definition of the key, shared', () {
      // ⚠️ Two copies of "sorted, de-duplicated, pipe-joined" is two chances
      // for a key built in the widget to miss the cache filled by the
      // provider — and the symptom is a page that fetches twice and merely
      // looks slow.
      expect(scope, contains('static String keyFor(Iterable<String> ids) => packageKeyOf(ids);'));
    });

    test('the cells read the page query, with a fallback', () {
      final c = code(disposal);
      expect(c, contains('Map<String, TenderRevaluationModel> _revalsFor('));
      expect(c, contains('Map<String, List<double>> _bidsFor('));
      expect(c, contains('TenderCommitteeModel? _committeeFor('));
      // ⚠️ These cells are also built inside DIALOGS, which have no page
      // around them. A cell that simply showed nothing there would be a blank
      // where a valuation belongs — so an empty key falls back.
      final fn = code(disposal.substring(disposal.indexOf('_revalsFor(')));
      expect(fn.substring(0, 700), contains('key.isEmpty'));
      expect(fn.substring(0, 700), contains('tenderRevaluationsProvider(fpId)'));
    });

    test('the tables carry the scope', () {
      expect(code(disposal), contains('TenderPageScope('));
      expect(code(committeeTab), contains('TenderPageScope('));
      // ⚠️ The committee tab's BID cell used to read `pageBidsProvider`;
      // the Bids column has since been removed from that tab, so the
      // provider went with it. Its re-valuation cell still takes the
      // page-scoped path, which is the property this test is about --
      // one query per page, never one per row.
      expect(code(committeeTab), contains('pageRevaluationsProvider('));
      expect(code(committeeTab).contains('tenderBidsProvider('), isFalse,
          reason: 'a per-row bid fetch is back on the committee tab');
    });

    test('the whole-table watches are gone from the row paths', () {
      // The Unsold tab and the Committees tab both read
      // `tenderCommitteesProvider` — every committee in the country — purely
      // as a per-row lookup.
      final c = code(disposal);
      expect(c, contains('pageCommitteesProvider('));
      expect(c, contains('pageProposalsProvider('));
      expect(c.contains('watch(unsoldProposalsProvider)'), isFalse,
          reason: 'the whole rulings table is back on a row path');
    });
  });

  group('the bid order is defined', () {
    test('every query breaks the created_at tie on id', () {
      // ⚠️ A real bug the port uncovered. Bids entered together carry the
      // SAME created_at to the microsecond, and Postgres promises no order
      // between tied rows — so the same two amounts came back swapped from
      // one read to the next. The edit dialog seeds one text field per bid in
      // exactly this order, so an officer could reopen a round and find their
      // figures rearranged.
      for (final fn in [
        'getTenderBidsForPackages(',
        'getTenderRevaluationsForPackages(',
        'getTenderBidsByRound(',
        'getTenderRevaluationsByRound(',
      ]) {
        final body = code(services.substring(services.indexOf(fn)));
        expect(body.substring(0, 1400), contains("order('id', ascending: true)"),
            reason: '$fn has no tiebreak');
      }
    });

    test('the page-wide queries order by package first', () {
      // ⚠️ Ordering by created_at alone interleaves the packages, and a
      // package's own rows then arrive in a different order than the
      // per-package query gives.
      for (final fn in [
        'getTenderBidsForPackages(',
        'getTenderRevaluationsForPackages(',
      ]) {
        final body = code(services.substring(services.indexOf(fn)));
        expect(body.substring(0, 1400),
            contains("order('forfeited_package_id', ascending: true)"));
      }
    });
  });
}
