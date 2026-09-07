// The last four unpaged pages: the yard's Forfeited table, its Destruction
// page, and the Admin activity log. (Officers & Admins was left alone —
// 11 profiles at 51ms, where a pager is chrome, not a saving.)
//
// Measured against the live database, warm:
//
//     Forfeited      163ms whole table  ->  74ms a page   (and NO pager at all
//                                                          before: 48 rows
//                                                          rendered at once)
//     Destruction     56ms              ->  54ms          (39 rows; the win is
//                                                          the shape, not the
//                                                          clock)
//     Admin logs     344ms a YEAR       ->  45ms a page   (166 rows -> 20)
//
// The Forfeited port is the big one: 122 lines of row-building Dart moved into
// `forfeit_rows`, checked row-for-row against that code before it was deleted
// — 48 rows either way.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final forfeitScreen =
      File('lib/screens/forfeited_packages/forfeited_packages_screen.dart')
          .readAsStringSync();
  final destScreen =
      File('lib/screens/forfeited_packages/destruction_disposal_screen.dart')
          .readAsStringSync();
  final adminScreen =
      File('lib/screens/admin/admin_screen.dart').readAsStringSync();
  final forfeitView =
      File('postgres/49_forfeit_rows_view.sql').readAsStringSync();
  final destView =
      File('postgres/50_destruction_summary_view.sql').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n'));

  group('the Forfeited table pages in SQL', () {
    test('the 122-line row builder is gone', () {
      final c = code(forfeitScreen);
      expect(c.contains('List<_ForfeitRow> _buildForfeitRows('), isFalse);
      expect(c.contains('class _ForfeitRow {'), isFalse);
      // And its three helpers with it.
      expect(c.contains('bool _isForfeitStatus('), isFalse);
      expect(c.contains('bool _isForfeitEntry('), isFalse);
      expect(c.contains('bool _itemHasFinalDisposition('), isFalse);
    });

    test('the screen reads a page and pages on the server count', () {
      final c = code(forfeitScreen);
      expect(c, contains('forfeitPageProvider('));
      expect(c.contains('watch(forfeitedPackagesProvider)'), isFalse,
          reason: 'the whole forfeited table is back');
      // ⚠️ A pager this screen never had: every forfeited row in the yard
      // rendered at once, and the count grows with the yard.
      expect(c, contains('TablePager('));
      expect(c, contains('total: data.total'));
    });

    test('the header counts the rows the TABLE renders', () {
      // ⚠️ Not the raw record count, which includes records that produce no
      // forfeit row at all.
      expect(services, contains('getForfeitCounts()'));
      expect(providers, contains('forfeitCountsProvider'));
      expect(code(forfeitScreen), contains('forfeitCountsProvider'));
    });

    test('the search keeps its token match', () {
      // ⚠️ A partial SR like "GL1/13" must still find "GL1/SR/13/2026", so
      // every "/"- or space-separated piece has to match.
      final fn = code(services.substring(
          services.indexOf('getForfeitRowsPaged({')));
      expect(fn.substring(0, 2600), contains(r"split(RegExp(r'[\s/]+'))"));
    });

    test('the year list comes from the whole table', () {
      expect(services, contains('getForfeitRowYears()'));
      final c = code(forfeitScreen);
      expect(c, contains('forfeitRowYearsProvider'));
      expect(c.contains('.map((p) => p.srNumber)'), isFalse,
          reason: 'the years are being derived from the page again');
    });

    test('the view keeps the three row shapes apart', () {
      // ⚠️ They are genuinely different rows: an event names a quantity and
      // an officer, an item row names neither, and a summary row stands for a
      // record with no item detail at all.
      expect(forfeitView, contains('1 as row_kind'));
      expect(forfeitView, contains('2 as row_kind'));
      expect(forfeitView, contains('3 as row_kind'));
      expect(forfeitView, contains(r'do $verify$'));
      expect(forfeitView,
          contains('have both an event row and a fallback row'));
      expect(forfeitView, contains('duplicate a detailed row'));
    });

    test('the appeal-lifecycle exception survives the final cut', () {
      // ⚠️ A held item, still live, on hold or inside its window or already
      // ruled on, stays visible even with a stale `[FINAL:…]` entry. Dropping
      // it would hide goods the yard still has to act on.
      expect(forfeitView, contains('in_appeal_lifecycle'));
      expect(forfeitView, contains('has_final and not in_appeal_lifecycle'));
    });

    test('the three ways a record leaves the table are all there', () {
      // Tendered, sold/destroyed, and requested — a separate layer in the
      // service, not in the row builder.
      expect(forfeitView, contains('tendered as ('));
      expect(forfeitView, contains('gone as ('));
      expect(forfeitView, contains('requested_item as ('));
      // ⚠️ Requests are keyed on the ORIGINATING (package, item): a request
      // stores a row that may be a synthetic per-item one.
      expect(forfeitView, contains('select distinct fp.package_id, fp.item_id'));
    });

    test("'other' is terminal, with or without a note", () {
      expect(forfeitView, contains("not like 'other:%'"));
      expect(forfeitView, contains('are still on the forfeited table'));
    });
  });

  group('the Destruction page pages in SQL', () {
    test('the service pages against its own summary view', () {
      expect(services, contains('getDestructionsPaged'));
      final fn = code(services.substring(
          services.indexOf('getDestructionsPaged({')));
      final body = fn.substring(0, 2600);
      expect(body, contains("from('destruction_summary')"));
      expect(body, contains('.range(offset, offset + limit - 1)'));
      expect(body, contains('.count()'));
      expect(body, contains('.inFilter(\'id\', ids)'));
    });

    test('the yard match follows effectiveYard', () {
      // ⚠️ Older rows leave destruction_items.yard empty, so the forfeited
      // row's yard stands in — the screen's own rule.
      expect(destView,
          contains("coalesce(nullif(trim(di2.yard), ''), fp.yard, '')"));
      expect(destView, contains('as item_yards'));
    });

    test('the screen filters nothing and pages on the server count', () {
      final c = code(destScreen);
      expect(c, contains('destructionsPageProvider('));
      expect(c.contains('watch(destructionsProvider)'), isFalse);
      expect(c.contains('pageSlice('), isFalse);
      expect(c, contains('total: data.total'));
      expect(c, contains('pageSize: kDispositionPageSize'));
    });

    test('re-destructions and years come from ALL destructions', () {
      // ⚠️ From one page a destruction looks new because its predecessor sat
      // on the page before, and a year not listed reads as records gone.
      expect(services, contains('getRedestructionIds()'));
      expect(services, contains('getDestructionYears()'));
      final c = code(destScreen);
      expect(c, contains('redestructionIdsProvider'));
      expect(c, contains('destructionYearsProvider'));
      expect(c.contains('retenderDestructionIds(visible)'), isFalse);
    });

    test('the year filter is a RANGE, not a string test', () {
      // A destruction with no date matched no year before and must not start
      // matching one now.
      final fn = code(services.substring(
          services.indexOf('getDestructionsPaged({')));
      expect(fn.substring(0, 2600), contains(r"'$year-01-01'"));
    });
  });

  group('the Admin activity log pages in SQL', () {
    test('the service pages and counts with one narrowing', () {
      expect(services, contains('getYardLogsPaged('));
      final fn = code(services.substring(
          services.indexOf('getYardLogsPaged({')));
      final body = fn.substring(0, 1800);
      // ⚠️ This yard, and only its OWN staff: directorate accounts are
      // head-office and must not appear even when they share a yard code.
      expect(body, contains("eq('yard', AppSession.currentYard)"));
      expect(body, contains("inFilter('profiles.role', ['admin', 'officer'])"));
      expect(body, contains('.range(offset, offset + limit - 1)'));
      expect(body, contains('.count()'));
      // Retention: twelve months, so the fetch grows all year.
      expect(body, contains('Duration(days: 365)'));
    });

    test('the screen reads the page, not the year', () {
      final c = code(adminScreen);
      expect(c, contains('yardLogsPageProvider('));
      expect(c.contains('watch(allLogsProvider)'), isFalse,
          reason: 'a year of log rows is back on the screen');
      expect(c, contains('total: data.total'));
    });

    test('a rate change still refreshes the log the screen reads', () {
      // ⚠️ Invalidating allLogsProvider alone refreshed a fetch nothing
      // renders any more, so the change would not appear until the admin
      // navigated away and back.
      final c = code(adminScreen);
      expect(c, contains('invalidate(yardLogsPageProvider)'));
    });
  });
}
