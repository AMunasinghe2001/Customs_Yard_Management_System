import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/ict/activity_logs_tab.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

AuditLogModel _log({
  required String action,
  String? user,
  String? role,
  String? yard,
  String entityType = 'package',
  DateTime? at,
  Map<String, dynamic>? details,
}) =>
    AuditLogModel(
      id: action,
      userId: 'u1',
      action: action,
      entityType: entityType,
      entityId: 'e1',
      details: details,
      createdAt: at ?? DateTime(2026, 9, 1, 10),
      yard: yard,
      userFullName: user,
      userRole: role,
    );

final _logs = [
  _log(action: 'Signed In', user: 'Ajantha Deepal', role: 'officer', yard: 'GL1', entityType: 'auth'),
  _log(action: 'Placed appeal hold', user: 'Appeal Officer', role: 'appeal', yard: 'GL2', entityType: 'forfeited_package'),
  _log(action: 'Created tender sale', user: 'Disposal DC', role: 'disposal', yard: 'GL1', entityType: 'tender_sale'),
  _log(action: 'Deactivated directorate BA', user: 'ICT Chief', role: 'ict', yard: 'GL1', entityType: 'directorate_config'),
];

Widget _harness({List<AuditLogModel>? logs}) => ProviderScope(
      overrides: [
        ictAllOfficeLogsProvider
            .overrideWith((ref) => Future.value(logs ?? _logs)),
        yardFilterOptionsProvider
            .overrideWith((ref) => Future.value(const <YardFilterOption>[])),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ActivityLogsTab(accent: const Color(0xFF9B1C3C)),
        ),
      ),
    );

void main() {
  final tab = _read('lib/screens/ict/activity_logs_tab.dart');
  final dash = _read('lib/screens/ict/ict_dashboard_screen.dart');

  group('the tab is wired into the ICT dashboard', () {
    test('the controller has room for it', () {
      expect(dash, contains('TabController(length: 4, vsync: this)'),
          reason: 'every tab needs a slot, or the view throws');
      // The label now names a rail entry, not a Tab.
      expect(dash, contains("_IctRailItem('Activity Logs'"));
      expect(dash, contains('ActivityLogsTab(accent: accent)'));
    });

    test('the rail and the view stay the same length', () {
      // ⚠️ ICT's tab strip became a left RAIL (_IctSideRail), so the four
      // entries live in its own list now. The count still has to match the
      // controller and the view: a short controller paints every entry but
      // resolves clicks against the shorter list, so tapping does nothing.
      final railStart = dash.indexOf('static const _items = [');
      final rail = dash.substring(railStart, dash.indexOf('];', railStart));
      expect('_IctRailItem('.allMatches(rail).length, 4);
      // The four bodies the TabBarView holds. Counted by NAME rather than by
      // slicing the children list: its first child is a large inline widget,
      // so the first "]," closes an inner list, not the TabBarView's.
      final views = dash.substring(dash.indexOf('// ── Body Content'));
      for (final tab in const [
        'YardDirectorateTab(',
        'DirectorateAccessTab(',
        'ActivityLogsTab(',
      ]) {
        expect(views, contains(tab));
      }
      expect(dash, contains('TabController(length: 4'));
    });
  });

  group('it reads the whole log, not one yard', () {
    final services = _read('lib/services/services.dart');

    test('the cross-office query is scoped to no yard and drops no role', () {
      final fn = services.substring(
          services.indexOf('Future<List<AuditLogModel>> getAllLogsAcrossOffices'));
      final body = fn.substring(0, fn.indexOf('Future<void> recordLog'));
      expect(body, isNot(contains("eq('yard'")),
          reason: 'ICT oversees every yard');
      expect(body, isNot(contains('inFilter')),
          reason: 'ICT oversees every directorate too');
    });

    test('the date window is pushed into SQL, not filtered client-side', () {
      final fn = services.substring(
          services.indexOf('Future<List<AuditLogModel>> getAllLogsAcrossOffices'));
      final body = fn.substring(0, fn.indexOf('Future<void> recordLog'));
      expect(body, contains("gte('created_at'"));
      expect(body, contains("lte('created_at'"));
    });

    test('the yard admin view is untouched and still narrow', () {
      final fn = services
          .substring(services.indexOf('Future<List<AuditLogModel>> getAllLogs()'));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains("eq('yard', AppSession.currentYard)"));
      expect(body, contains("inFilter('profiles.role', ['admin', 'officer'])"));
    });
  });

  group('the model carries what the filters need', () {
    test('role and yard survive the parse', () {
      final m = AuditLogModel.fromJson({
        'id': 'l1',
        'user_id': 'u1',
        'action': 'Signed In',
        'entity_type': 'auth',
        'entity_id': 'e1',
        'created_at': '2026-09-01T10:00:00Z',
        'yard': 'GL2',
        'profiles': {'full_name': 'A Officer', 'role': 'appeal'},
      });
      expect(m.userRole, 'appeal',
          reason: 'the role was dropped, so ICT could not filter by office');
      expect(m.yard, 'GL2');
      expect(m.userFullName, 'A Officer');
    });

    test('a row with no joined profile still parses', () {
      final m = AuditLogModel.fromJson({
        'id': 'l1',
        'user_id': 'u1',
        'action': 'Signed In',
        'entity_type': 'auth',
        'entity_id': 'e1',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(m.userRole, isNull);
      expect(m.yard, isNull);
    });
  });

  group('every period the officer can ask for', () {
    test('all five are offered', () {
      expect(LogPeriod.values.map((p) => p.label), [
        'All Time',
        'Single Day',
        'Date Range',
        'By Month',
        'By Year',
      ]);
    });

    test('the month window covers a short February', () {
      // Built as the 0th day of the NEXT month, so 2024-02 ends on the 29th.
      expect(tab, contains('DateTime(m.year, m.month + 1, 0)'));
      expect(DateTime(2024, 3, 0).day, 29);
      expect(DateTime(2026, 3, 0).day, 28);
    });

    test('the end of the window includes the whole last day', () {
      final providers = _read('lib/core/providers.dart');
      expect(providers, contains('23, 59, 59'),
          reason: 'a date-only bound would drop that day\'s own activity');
    });
  });

  group('it renders', () {
    testWidgets('the log table, one row per action', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // ⚠️ The section name comes from the CONSOLE header now; the tab
      // names the table it holds.
      expect(find.text('Audit Trail'), findsOneWidget);
      expect(find.text('Ajantha Deepal'), findsOneWidget);
      expect(find.text('Placed appeal hold'), findsOneWidget);
      // Each office's role reads as its own pill -- uppercase, because
      // every pill in the console is drawn by IctStatusPill.
      expect(find.text('OFFICER'), findsWidgets);
      expect(find.text('APPEAL'), findsWidgets);
      expect(find.text('ICT'), findsWidgets);
    });

    testWidgets('an empty log says so instead of showing a bare table',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(logs: const []));
      await tester.pumpAndSettle();

      expect(find.text('No activity for these filters'), findsOneWidget);
    });

    testWidgets('the count chip reports what is shown', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('4 actions'), findsOneWidget);
    });
  });
}
