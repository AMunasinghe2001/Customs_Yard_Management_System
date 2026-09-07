// Two things that were quietly costing a whole-table fetch.
//
// 1. `lib/screens/dashboard/dashboard_screen.dart` — 728 lines, no route, no
//    import anywhere. It defined its OWN `recentPackagesProvider` and
//    `dashboardStatsProvider`, shadowing the real ones, and its copy still
//    called getAllPackages(). Harmless while nothing imported it; a silent
//    regression the moment anything did.
//
// 2. The real `recentPackagesProvider` fetched EVERY package in the yard —
//    176 rows at 405ms, each with its items and warehouse entries — to keep
//    the twenty touched today. 405ms -> 7ms.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final view =
      File('postgres/51_recent_activity_view.sql').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') &&
          !l.trimLeft().startsWith('///'))
      .join('\n'));

  group('the dead dashboard screen is gone', () {
    test('the file no longer exists', () {
      expect(File('lib/screens/dashboard/dashboard_screen.dart').existsSync(),
          isFalse);
    });

    test('nothing was importing it', () {
      // ⚠️ The check that made deleting it safe, kept so a future copy of the
      // file cannot quietly come back.
      for (final dir in ['lib', 'test']) {
        final hits = Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            // ⚠️ Skip THIS file: it names the path in order to check
            // for it, and would otherwise match itself.
            .where((f) => !f.path.endsWith('dead_screen_and_recent_test.dart'))
            .where((f) => f.readAsStringSync().contains(
                'dashboard/dashboard_screen.dart'))
            .toList();
        expect(hits, isEmpty, reason: '$dir still imports the dead screen');
      }
    });

    test('only one recentPackagesProvider is defined', () {
      // ⚠️ Two providers of the same name in different files do not clash —
      // the local one simply wins wherever it is in scope. That is what made
      // the duplicate dangerous rather than noisy.
      var defs = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        defs += RegExp(r'^final recentPackagesProvider',
                multiLine: true)
            .allMatches(f.readAsStringSync())
            .length;
      }
      expect(defs, 1);
    });
  });

  group('recent activity is twenty rows, chosen in SQL', () {
    test('the service reads the view and caps the page', () {
      expect(services, contains('getRecentActivity('));
      final fn = code(services.substring(services.indexOf('getRecentActivity(')));
      final body = fn.substring(0, 1200);
      expect(body, contains("from('recent_package_activity')"));
      expect(body, contains("order('touched_at', ascending: false)"));
      expect(body, contains('.limit(limit)'));
    });

    test('the provider stopped fetching every package', () {
      final fn = code(providers.substring(
          providers.indexOf('final recentPackagesProvider')));
      final body = fn.substring(0, 700);
      expect(body, contains('getRecentActivity()'));
      expect(body.contains('getAllPackages()'), isFalse,
          reason: 'the whole yard is back on the dashboard');
    });

    test('a warehouse entry counts as a touch', () {
      // ⚠️ Release, Re-export and Forfeit write ONLY to warehouse_entries and
      // never touch the package row, so its own timestamps cannot answer the
      // question. This is why the whole table was being read.
      expect(view, contains('from public.warehouse_entries we'));
      expect(view, contains('we.admitted_at at time zone'));
      expect(view, contains('we.returned_at at time zone'));
    });

    test('TODAY means today, not today or later', () {
      // ⚠️ The Dart tested `isAfter(startOfDay)` with no upper bound, so an
      // entry whose returned_at is next week counted as activity now — two
      // rows on the live data. A list headed "Recent Activity" reporting
      // something that has not happened yet is worse than a short list.
      expect(view, contains('TODAY means today'));
      // Equality, never a one-sided comparison, on all four timestamps.
      expect(RegExp(r"at time zone 'Asia/Colombo'\)::date\s*\n?\s*= ")
              .allMatches(view.replaceAll('\r\n', '\n'))
              .length,
          greaterThanOrEqualTo(4));
    });

    test('the day is pinned to Asia/Colombo and proven', () {
      // ⚠️ The app connects as UTC and psql inherits Asia/Colombo, so a date
      // that follows the session gives the two different days near midnight —
      // a yard's own work vanishing from its dashboard.
      expect(view, contains("at time zone 'Asia/Colombo'"));
      expect(view, contains("set local timezone to 'UTC'"));
      expect(view, contains('today depends on the reader'));
    });
  });
}
