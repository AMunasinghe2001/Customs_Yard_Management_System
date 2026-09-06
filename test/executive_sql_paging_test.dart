// The four Top Management tabs each rendered a whole list.
//
// Unsold Goods and Unsold Perishables loaded EVERY tender sale in every yard,
// with its items, forfeited rows, packages, package items and warehouse
// entries, then narrowed in Dart to the handful that had run out of road.
// Committees did the same and had no pager at all. Tender Sales loaded the
// heaviest query in the app and then showed all 82 sales -- including the 77
// whose items were every one decided, which is finished work.
//
// Measured against the live database: one page from each view is 4-5ms;
// getTenderSales() alone is 73ms.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final unsold = File('lib/screens/executive/unsold_decision_tab.dart')
      .readAsStringSync();
  final committees = File('lib/screens/executive/tender_committee_tab.dart')
      .readAsStringSync();
  final sales = File('lib/screens/executive/tender_sales_view_tab.dart')
      .readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  /// Just the code -- comment lines dropped.
  ///
  /// ⚠️ The comments NAME the whole-list providers to explain why they are
  /// gone, and a plain substring search reads that as still using them.
  String code(String src) => src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') &&
          !l.trimLeft().startsWith('///'))
      .join('\n');


  group('each tab asks the database for one page', () {
    test('Unsold Goods and Perishables share one paged provider', () {
      expect(unsold, contains('exhaustedUnsoldPageProvider(query)'));
      final c = code(unsold);
      expect(c.contains('ref.watch(exhaustedUnsoldProvider'), isFalse,
          reason: 'the whole-list provider is back');
      expect(c.contains('ref.watch(unsoldPerishablesProvider'), isFalse);
    });

    test('the two lists are told apart by the VIEW, not by Dart', () {
      // ⚠️ They reach Top Management by different routes -- one failed Special
      // Tender Sale versus five failed chances and a committee -- and the
      // views encode that. Everything after it is identical, so they share the
      // method rather than drifting apart in two copies.
      expect(services, contains('bool perishable = false,'));
      expect(services,
          contains("final view = perishable ? 'unsold_perishables' : 'exhausted_unsold';"));
      expect(services.contains("from('exhausted_unsold').select('forfeited_package_id')"),
          isFalse,
          reason: 'the view name is hard-coded again');
    });

    test('perishable is part of the query key', () {
      // ⚠️ In == AND hashCode, or the two tabs share a cached page and one
      // shows the other's list.
      const a = ExhaustedUnsoldQuery();
      const b = ExhaustedUnsoldQuery(perishable: true);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('Committees pages too, and now has a pager at all', () {
      expect(committees, contains('committeesPageProvider(query)'));
      expect(code(committees).contains('ref.watch(committeeEligibleProvider'),
          isFalse);
      expect(committees, contains('TablePager('));
      expect(committees, contains('final _committeePageProvider'));
    });

    test('Tender Sales pages, and drops finished sales', () {
      expect(sales, contains('tenderSalesPageProvider(query)'));
      expect(sales.contains('ref.watch(tenderSalesProvider)'), isFalse,
          reason: 'the heaviest query in the app is back on this tab');
      // ⚠️ The same worklist rule Central Disposal applies. 82 sales exist;
      // 5 have anything left to decide.
      expect(flat(sales), contains('onlyPending: true'));
    });

    test('every pager counts the DATABASE, not the page', () {
      // `rows.length` is one page, so a pager reading it says "20 of 20".
      // ⚠️ Comments stripped first, and a wider window: two of these
      // pagers carry an explanation between the call and its arguments.
      for (final entry in {
        'unsold': unsold,
        'committees': committees,
        'sales': sales,
      }.entries) {
        final f = flat(code(entry.value));
        final i = f.indexOf('TablePager(');
        expect(i, greaterThan(-1), reason: '${entry.key} has no pager');
        expect(f.substring(i, i + 60), contains('total: total'),
            reason: '${entry.key} counts its page, not the database');
      }
    });
  });

  group('Committees: the two portals want different halves', () {
    test('the service can serve either', () {
      expect(services, contains('bool appointedOnly = true,'));
      expect(services,
          contains("if (appointedOnly) q = q.eq('has_committee', true);"));
    });

    test('Top Management sees packages with NO committee yet', () {
      // ⚠️ It is the page that APPOINTS them -- narrowing to committees that
      // exist would make the one thing the page is for impossible.
      expect(flat(committees), contains('appointedOnly: false'));
    });

    test('Central Disposal keeps the default', () {
      // It cannot appoint one, so a package still waiting is nothing it can
      // act on.
      final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync();
      expect(dash.contains('appointedOnly'), isFalse);
    });

    test('the flag is part of the key', () {
      const watching = UnsoldRetenderQuery();
      const appointing = UnsoldRetenderQuery(appointedOnly: false);
      expect(watching == appointing, isFalse);
      expect(watching.hashCode == appointing.hashCode, isFalse);
    });
  });

  group('a perishable reaches the DG only once an officer says so', () {
    final v = File('postgres/37_unsold_perishables_marked.sql').readAsStringSync();

    test('membership is the MARK, not a clock', () {
      // ⚠️ postgres/32 selected "the sale ended and it did not sell", which
      // was the rule at the time. That rule is gone: Central Disposal marks
      // each item by hand, and the view was left behind.
      expect(v, contains('bool_or(ti.unsold)                 as marked_unsold'));
      expect(v, contains('and a.marked_unsold'));
      expect(v.contains('any_round_ended'), isFalse,
          reason: 'the clock is back in the view');
    });

    test('the migration proves nothing undecided reaches the DG', () {
      // The case that prompted it: CED/GL1/SR/17/2026 sits in SP05 with
      // sold=false AND unsold=false -- nobody has decided -- yet the DG was
      // being asked to rule on it.
      expect(v, contains('reached the DG without being marked'));
    });

    test('sold perishables still cannot appear', () {
      expect(v, contains('contains % SOLD package(s)'));
      expect(v, contains('not a.ever_sold'));
    });
  });

  group('the whole-list providers are gone from these tabs', () {
    test('nothing on the four tabs watches one', () {
      for (final entry in {
        'unsold_decision_tab.dart': unsold,
        'tender_committee_tab.dart': committees,
        'tender_sales_view_tab.dart': sales,
      }.entries) {
        for (final whole in [
          'exhaustedUnsoldProvider',
          'unsoldPerishablesProvider',
          'committeeEligibleProvider',
          'tenderSalesProvider',
        ]) {
          expect(code(entry.value).contains('ref.watch($whole'), isFalse,
              reason: '${entry.key} still watches $whole');
        }
      }
    });

    test('kDispositionPageSize is the page size everywhere', () {
      // Not a per-file _pageSize that can drift from the service's.
      expect(unsold.contains('static const int _pageSize'), isFalse);
      expect(providers, contains('kDispositionPageSize'));
    });
  });
}
