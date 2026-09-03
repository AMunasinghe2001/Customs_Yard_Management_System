import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/ict/directorate_access_tab.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

ProfileModel _acct(String role, String name,
        {String? username, bool active = true}) =>
    ProfileModel(
      id: role,
      fullName: name,
      username: username,
      role: role,
      isActive: active,
      createdAt: DateTime(2026, 1, 1),
    );

final _accounts = [
  _acct('disposal', 'Disposal Directorate (DC)', username: 'disposal.dc'),
  _acct('appeal', 'Appeal Directorate (AD)', username: 'appeal.ad'),
  _acct('executive', 'Executive Office (DG)', username: 'exec.dg'),
  _acct('ict', 'ICT Directorate', username: 'ict.admin', active: false),
];

Widget _harness({List<ProfileModel>? accounts}) => ProviderScope(
      overrides: [
        directorateAccountsProvider
            .overrideWith((ref) => Future.value(accounts ?? _accounts)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: DirectorateAccessTab(accent: Color(0xFF9B1C3C)),
        ),
      ),
    );

void main() {
  group('which accounts belong on this page', () {
    test('the five directorate roles, and no yard role', () {
      // Yard staff reset their own password from the login page; only an
      // institutional account needs ICT to reissue.
      expect(kDirectorateRoles,
          ['disposal', 'appeal', 'valuation', 'executive', 'ict']);
      expect(kDirectorateRoles, isNot(contains('officer')));
      expect(kDirectorateRoles, isNot(contains('admin')));
    });

    test('every one has a portal name to show', () {
      for (final r in kDirectorateRoles) {
        expect(kDirectorateRoleNames[r], isNotNull,
            reason: '$r would render as a bare role code');
      }
    });

    test('the list matches the accounts that never expire', () {
      // Same accounts, same reason -- they belong to a post, not a person.
      for (final role in kDirectorateRoles) {
        final p = ProfileModel(
            id: 'x',
            fullName: 'A',
            role: role,
            isActive: true,
            createdAt: DateTime.now().subtract(const Duration(days: 400)));
        expect(p.isExpired, isFalse, reason: '$role should never auto-expire');
        expect(p.daysUntilExpiry, isNull);
      }
    });

    test('the query asks for exactly those roles', () {
      final svc = _read('lib/services/services.dart');
      final fn = svc.substring(
          svc.indexOf('Future<List<ProfileModel>> getDirectorateAccounts()'));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains("inFilter('role', kDirectorateRoles)"));
    });
  });

  group('the page renders', () {
    testWidgets('one row per directorate account', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('Directorate Access'), findsOneWidget);
      expect(find.text('Central Disposal Directorate'), findsOneWidget);
      expect(find.text('Appeal Directorate'), findsOneWidget);
      expect(find.text('disposal.dc'), findsOneWidget);
      expect(find.text('Reset access'), findsNWidgets(4));
    });

    testWidgets('a deactivated account cannot be reissued', (tester) async {
      // Its credentials would not sign in, so sending them helps nobody.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .toList();
      final disabled = buttons.where((b) => b.onPressed == null).length;
      expect(disabled, 1, reason: 'only the inactive ICT account is disabled');
    });

    testWidgets('an empty list says so instead of showing a bare table',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(accounts: const []));
      await tester.pumpAndSettle();
      expect(find.text('No directorate accounts'), findsOneWidget);
    });

    testWidgets('the confirmation warns that the old details stop working',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset access').first);
      await tester.pumpAndSettle();

      expect(find.text('Reissue sign-in details'), findsOneWidget);
      expect(find.textContaining('stop working at once'), findsOneWidget);
      // Nothing has happened yet.
      expect(find.text('Send new details'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('what the reset does, and does not, reveal', () {
    final src = _read('lib/screens/ict/directorate_access_tab.dart');
    final svc = _read('lib/services/services.dart');

    test('the password is never shown on screen', () {
      // It belongs in the mailbox, not on an office monitor.
      expect(src, contains('The new username is'));
      expect(src, isNot(contains('new password is')));
    });

    test('the audit log records the username but not the password', () {
      final fn = svc.substring(
          svc.indexOf('Future<String> resetDirectorateCredentials('));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains("'username': username"));
      expect(body, isNot(contains("'password': password")));
    });

    test('the credentials go to the address the ACCOUNT is registered to', () {
      final fn = svc.substring(
          svc.indexOf('Future<String> resetDirectorateCredentials('));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains("from('auth.users').select('email')"));
      expect(body, contains('sendCredentials(email, fullName, username, password)'));
    });

    test('both halves are generated, not chosen', () {
      final fn = svc.substring(
          svc.indexOf('Future<String> resetDirectorateCredentials('));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains('_uniqueUsername(fullName)'));
      expect(body, contains('_randomOfficerPassword()'));
    });

    test('it reuses the one password setter rather than hashing its own', () {
      final fn = svc.substring(
          svc.indexOf('Future<String> resetDirectorateCredentials('));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains("rpc(\n        'reset_password_for_identifier'"));
    });
  });

  group('the tab is wired into the ICT dashboard', () {
    final dash = _read('lib/screens/ict/ict_dashboard_screen.dart');

    test('the controller has room for it', () {
      expect(dash, contains('TabController(length: 4, vsync: this)'),
          reason: 'a fourth tab needs a fourth slot, or the view throws');
      // The label now names a rail entry, not a Tab.
      expect(dash, contains("_IctRailItem('Directorate Access'"));
      expect(dash, contains('DirectorateAccessTab(accent: accent)'));
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
}
