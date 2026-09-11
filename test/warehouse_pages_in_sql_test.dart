// The Warehouses page loaded a whole facility's entries — each with its
// warehouse, its package and both officers' profiles — filtered them in Dart
// on six conditions, and paged the result with `pageSlice`. Client-side paging
// still loads everything; it only renders less.
//
// One of those filters needed the PACKAGE ITEM behind each entry, so it read
// `packageDataProvider(e.packageId)` per row — a getPackageById per entry,
// each pulling the package with its items, its warehouse entries, those
// entries' warehouses and the returning officer's profile. The row builder
// read it again, and the header counted its four figures by reading it twice
// more inside nested loops.
//
// Measured on Warehouse 01 (75 entries, 52 packages), warm:
//
//     old  83ms entries + 249ms per-row packages + 49ms outcomes = 381ms
//     new  102ms all in
//
// Checked entry-for-entry against the Dart on all four facilities, and the
// four header figures agree exactly: 38/25/56/34 held, and every status count.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final screen = File('lib/screens/warehouses/warehouses_screen.dart')
      .readAsStringSync();
  final view = File('postgres/48_warehouse_rows_view.sql').readAsStringSync();
  final outcomesView =
      File('postgres/47_item_appeal_outcomes_view.sql').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n'));

  group('the table pages in SQL', () {
    test('the service pages and counts against the view', () {
      expect(services, contains('getWarehouseRowsPaged'));
      final fn = code(services.substring(
          services.indexOf('getWarehouseRowsPaged({')));
      final body = fn.substring(0, 3200);
      expect(body, contains("from('warehouse_rows')"));
      expect(body, contains('.range(offset, offset + limit - 1)'));
      expect(body, contains('.count()'));
      // The page's entries, not the facility's.
      expect(body, contains(".inFilter('id', ids)"));
    });

    test('all seven filters are SQL predicates', () {
      final fn = code(services.substring(
          services.indexOf('getWarehouseRowsPaged({')));
      final body = fn.substring(0, 3200);
      // ⚠️ The 'confiscated' chip reads the PACKAGE status, not the item's:
      // that chip has always asked a different question from the others.
      expect(body, contains("eq('is_package_confiscated', true)"));
      // ⚠️ ilike, not eq. The SR form has written this column both ways —
      // "Other" and "other" — and an exact match returned half the goods.
      expect(body, contains("ilike('item_status', status)"));
      // The appeal filter is SQL too: the pager takes its total from the
      // server, so narrowing the page after it arrives would mis-count.
      expect(body, contains("eq('appeal_state', appeal)"));
      expect(body, contains("eq('hold_reason', reason)"));
      expect(body, contains('sr_number.ilike'));
      expect(body, contains("gte('admitted_at'"));
      // ⚠️ EITHER year: an SR filed in one year can be admitted in the next,
      // and an officer looking for either should find it.
      expect(body, contains(r"or('sr_year.eq.$year,admitted_year.eq.$year')"));
    });

    test('the screen filters nothing and pages on the server count', () {
      final c = code(screen);
      expect(c, contains('warehousePageProvider('));
      expect(c.contains('pageSlice('), isFalse,
          reason: 'client-side paging still loads everything');
      expect(c.contains('final filteredList ='), isFalse,
          reason: 'the six-condition walk is back');
      expect(c, contains('total: page?.total ?? 0'));
      expect(c, contains('pageSize: kDispositionPageSize'));
    });

    test('the packages come as ONE query for the page', () {
      // ⚠️ Paging a table does not page what its CELLS fetch — the mistake
      // the Destroyed Goods tab was fixed for, in a second place.
      final c = code(screen);
      expect(c, contains('warehousePackagesProvider(query)'));

      // ⚠️ Not in the ROW BUILDER. `packageDataProvider` is still right for a
      // dialog the officer opens — that is one package on demand — so the
      // check is on the table body, between the DataTable2 and the pager.
      final table = c.substring(c.indexOf('rows: pageRows'));
      expect(table.substring(0, 2000).contains('watch(packageDataProvider('),
          isFalse,
          reason: 'a getPackageById per row is back');
      // And the provider follows the PAGE, not the facility.
      final prov = code(providers.substring(
          providers.indexOf('final warehousePackagesProvider')));
      expect(prov.substring(0, 700), contains('warehousePageProvider(q).future'));
    });

    test('the header counts in SQL', () {
      // ⚠️ Four figures folded from a fetch of every live entry, each fold
      // reading a package per entry — so 75 entries fired the same per-package
      // fetch four times over.
      expect(services, contains('getWarehouseStatusCounts('));
      expect(providers, contains('warehouseStatusCountsProvider'));
      final c = code(screen);
      expect(c, contains('warehouseStatusCountsProvider('));
      expect(c.contains('int statusCount(String target)'), isFalse);
    });

    test('the year dropdown offers both years the filter matches', () {
      // ⚠️ It listed only the SR numbers' years while the filter matches the
      // SR year OR the admission year — so a year an officer could genuinely
      // filter by was missing from the dropdown that offers it.
      final c = code(screen);
      expect(c, contains('warehouseFilterOptionsProvider('));
      expect(c.contains("srYears(list.map((e) => e.srNumber ?? ''))"), isFalse);
      expect(services, contains('getWarehouseFilterOptions('));
    });

    test('the query key carries the warehouse, in == and hashCode', () {
      // ⚠️ The tabs are one widget per facility. Without the id in the key,
      // whichever facility asked first would be served to all of them.
      final cls = providers.substring(providers.indexOf('class WarehouseQuery'),
          providers.indexOf('typedef WarehousePage'));
      for (final field in [
        'warehouseId',
        'page',
        'status',
        'reason',
        'search',
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
  });

  group('the view holds what the screen showed', () {
    test('returned entries and departed goods are both excluded', () {
      // ⚠️ The entry is still open because nobody closed it, but the goods
      // are gone — listing them sends an officer to find something that is
      // not there.
      expect(view, contains('not coalesce(we.is_returned, false)'));
      expect(view, contains("'released', 'returned', 'sold', 're-export', 're-exported',"));
      expect(view, contains(r'do $verify$'));
      expect(view, contains('are still listed as held'));
    });

    test('the Forfiet typo is folded, not merely lowercased', () {
      // A typo that reached the data would otherwise split one filter choice
      // into two.
      expect(view, contains("= 'forfiet' then 'Forfeit'"));
      expect(view, contains('still carry the Forfiet spelling'));
    });

    test('both year values are carried', () {
      expect(view, contains('as admitted_year'));
      expect(view, contains('as sr_year'));
    });
  });

  group('the appeal outcomes stopped reading every column', () {
    test('they come from their own view', () {
      // ⚠️ Not `appeal_rows`: that is the Appeal PORTAL's feed and is
      // `source = 'forfeit'` only, while a ruling can exist against detained,
      // abandoned and other goods too — 65 of them on the live data, which
      // would have vanished from the four screens reading this.
      final fn = code(services.substring(
          services.indexOf('getAllItemAppealOutcomes()')));
      expect(fn.substring(0, 1600), contains("from('item_appeal_outcomes')"));
      expect(fn.substring(0, 1600).contains("from('forfeited_packages').select('*')"),
          isFalse);
    });

    test('the multi-item guard finally fires', () {
      // ⚠️ `appealDecisionForItem` needs the package's ITEM COUNT to know
      // whether a package-level decision may stand in for a missing per-item
      // one — and `select('*')` embeds no package, so `packageDetails` was
      // always null and the guard could never fire. A decision on one item
      // therefore reported every sibling decided.
      expect(outcomesView, contains('coalesce(ic.n, 0) > 1'));
      expect(outcomesView, contains('inherit a package-level decision across'));
    });

    test('a ruling wins over silence when rows disagree', () {
      // Several forfeited rows can name the same item; dropping the wrong
      // copy would tell a yard the goods are free to move when the
      // directorate has frozen them.
      expect(outcomesView, contains('distinct on (r.item_id)'));
      expect(outcomesView, contains('item(s) appear twice'));
    });

    test('rulings against every source are kept', () {
      expect(outcomesView, contains('the view is '));
      expect(outcomesView, contains('narrowed to one kind of goods'));
    });
  });
}
