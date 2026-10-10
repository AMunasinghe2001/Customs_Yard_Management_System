// The Appeal Directorate's two tabs each fetched EVERY forfeited package in
// the country — through packages, their items and their warehouse entries,
// ~245ms — then expanded, filtered and paged the result in Dart with
// `pageSlice(rows, page, kClientPageSize)`. Client-side paging still loads
// everything; it only renders less.
//
// Five rules decided what the directorate sees and every one ran in Dart.
// `appeal_rows` (postgres/45) carries all five, and the port was checked
// row-for-row against the model on the live database: 136 rows either way, 20
// active, 9 decided, chips 20 / 17 / 3, and the same goods name on all 29 rows
// a page-by-page sweep could reach.
//
//     old  245ms for the whole feed
//     new   90ms for a page
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final screen = File('lib/screens/appeal/appeal_dashboard_screen.dart')
      .readAsStringSync();
  final view = File('postgres/45_appeal_rows_view.sql').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n'));

  group('the tabs ask SQL for a page', () {
    test('the service pages and counts against the view', () {
      expect(services, contains('getAppealRowsPaged'));
      final fn = code(services.substring(services.indexOf('getAppealRowsPaged'),
          services.indexOf('Future<List<ForfeitedPackageModel>> _appealRowsForIds')));
      expect(fn, contains("from('appeal_rows')"));
      expect(fn, contains('.range(offset, offset + limit - 1)'));
      expect(fn, contains('.count()'));
      // The tab IS the filter.
      expect(fn, contains("eq('has_decision', true)"));
      expect(fn, contains("eq('is_active', true)"));
    });

    test('the active tab leads with the soonest deadline', () {
      // ⚠️ The most urgent appeals must lead instead of being paged out of
      // sight. Sorting a PAGE would only order twenty rows within themselves,
      // which is the very thing that sort existed to prevent — so the order is
      // in SQL, before the page is cut.
      final fn = code(services.substring(services.indexOf('getAppealRowsPaged')));
      expect(fn.substring(0, 3000), contains("'appeal_deadline'"));
      // And the decided tab reads newest-ruling-first: a record is read that
      // way, and a closed appeal has no urgency left.
      expect(fn.substring(0, 3000), contains("'appeal_decided_at'"));
    });

    test('the stat chips count the ACTIVE set on either tab', () {
      // ⚠️ Their own narrowing. The page filter answers to `decided`, so
      // reusing it would have counted rulings on the Decided tab and labelled
      // them Active.
      final fn = code(services.substring(services.indexOf('getAppealRowsPaged')));
      final body = fn.substring(0, 3400);
      expect(body, contains('PgQuery narrowActive('));
      expect(body, contains("eq('in_appeal_window', true)"));
      expect(body, contains("eq('is_held', true)"));
    });

    test('the row is re-pointed at the item the view chose', () {
      // ⚠️ forfeited_packages stores no item_name, so a row fetched straight
      // from it carries a null one — and the screen's fallback then shows the
      // package's FIRST item, which is the wrong goods on any multi-item
      // package.
      final fn = code(services.substring(
          services.indexOf('_appealRowsForIds(')));
      expect(fn.substring(0, 2200), contains('itemName: item?.itemName'));
      expect(fn.substring(0, 2200), contains('itemId: itemId'));
    });

    test('the query key carries the tab, in == and hashCode', () {
      // ⚠️ Without `decided` the Decided tab would serve whatever Active had
      // cached, and an officer would read closed appeals as open ones.
      final cls = providers.substring(providers.indexOf('class AppealQuery'),
          providers.indexOf('typedef AppealPage'));
      for (final field in ['page', 'decided', 'search', 'yardFilter']) {
        expect(cls.split('other.$field == $field').length - 1, 1,
            reason: '$field is missing from ==');
        expect(cls.substring(cls.indexOf('int get hashCode')), contains(field),
            reason: '$field is missing from hashCode');
      }
    });

    test('the screen stopped fetching the whole feed', () {
      final c = code(screen);
      expect(c, contains('appealPageProvider('));
      expect(c.contains('watch(appealForfeitedPackagesProvider)'), isFalse,
          reason: 'every forfeited package in the country, again');
      expect(c.contains('pageSlice('), isFalse,
          reason: 'client-side paging still loads everything');
      expect(c, contains('total: data.total'));
      expect(c, contains('pageSize: kDispositionPageSize'));
    });
  });

  group('the view carries the five rules', () {
    test('only genuine forfeits, expanded per item', () {
      expect(view, contains("fp.source = 'forfeit'"));
      // Rule 3: the same test the yard's Forfeited table applies.
      expect(view, contains("'forfeit', 'forfeited', 'forfiet', 'confiscated'"));
      expect(view, contains("like '[FORFEIT%'"));
      expect(view, contains("like '[CONFISCAT%'"));
    });

    test('a finalised package has nothing left to appeal', () {
      expect(view, contains("like '[FINAL:%'"));
      expect(view,
          contains("('sold', 'destroyed', 're-exported', 'released')"));
    });

    test('a package-level decision never bleeds across siblings', () {
      // ⚠️ Deciding one item — or a stale package-level value left by the old
      // flow — would otherwise mark every sibling decided, and the directorate
      // would never see them again.
      expect(view, contains('package_item_count > 1'));
      expect(view, contains(r'do $verify$'));
      expect(view, contains('inherit a package-level decision across'));
    });

    test('a hold outranks the deadline', () {
      // An expired package on hold is still the directorate's work; dropping
      // it would strand the appeal.
      expect(view, contains('not r.is_expired or r.is_held'));
      expect(view, contains('fell off the active tab'));
    });

    test('one row per (package, item), most appeal state winning', () {
      // ⚠️ A package can carry several forfeited rows and each expands into
      // the same items — three of them over three items rendered nine times.
      // The copy holding a decision or a hold must be the one that survives.
      expect(view, contains('distinct on (r.package_id'));
      expect(view, contains('duplicate row key(s)'));
    });

    test('active and decided never overlap', () {
      expect(view, contains('are both active and decided'));
    });
  });
}
