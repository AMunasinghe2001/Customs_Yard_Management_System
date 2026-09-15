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

      // ⚠️ The section name comes from the CONSOLE header now, not from
      // the tab -- a module that reprints its own title twenty pixels
      // under the header is what the redesign got rid of. The tab names
      // the table it holds instead.
      expect(find.text('Directorate Accounts'), findsOneWidget);
      expect(find.text('Central Disposal Directorate'), findsOneWidget);
      expect(find.text('Appeal Directorate'), findsOneWidget);
      // ⚠️ The USERNAME is deliberately not on this page. It is half of a
      // working credential for an account a whole directorate signs in
      // with, and the page is read on an office monitor. The column now
      // carries what ICT is actually here to judge: how close the password
      // is to its 90-day rotation.
      expect(find.text('disposal.dc'), findsNothing);
      // The column renders for every account. Asserted by its icon rather
      // than its words: the words are a countdown against today's date, so a
      // text match would pass or fail depending on when the suite is run.
      expect(find.byIcon(Icons.lock_clock_rounded), findsNWidgets(4));
      // ⚠️ Three, not four. The inactive account shows Reactivate in that
      // cell instead — it cannot be sent credentials that would not sign in.
      expect(find.text('Reset access'), findsNWidgets(3));
      expect(find.text('Reactivate'), findsOneWidget);
    });

    testWidgets('a deactivated account cannot be reissued', (tester) async {
      // Its credentials would not sign in, so sending them helps nobody.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // ⚠️ This counted DISABLED buttons, assuming "cannot be reissued" had
      // to mean a greyed-out "Reset access". It does not: an inactive account
      // now offers Reactivate in that cell instead, which is a live button —
      // so the count went to zero and the test failed while the rule it
      // protects was intact.
      //
      // What matters is that no INACTIVE account offers Reset access. Stated
      // that way it survives the cell gaining other actions.
      expect(find.text('Reactivate'), findsOneWidget,
          reason: 'the inactive account has no way back');
      // One row is inactive, so one fewer Reset access than there are rows.
      // Four accounts in the fixture, one of them inactive.
      expect(find.text('Reset access'), findsNWidgets(3),
          reason: 'a deactivated account must not be offered its credentials');
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
      // ⚠️ Asserted on the recipient, not the full argument list: the call now
      // also says this is a REISSUE rather than a welcome, and the address on
      // record is the part this test exists to protect.
      expect(body, contains('sendCredentials(email, fullName, username, password'));
      expect(body, contains('isReissue: true'),
          reason: 'a reset must not arrive as a welcome to a new account');
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
      expect(body, contains("rpc(\n      'reset_directorate_credentials'"));
    });
  });

  group('the tab is wired into the ICT dashboard', () {
    final dash = _read('lib/screens/ict/ict_dashboard_screen.dart');

    test('the controller has room for it', () {
      // ⚠️ A slot per rail entry, or the view throws. Counted from the
      // rail rather than written out: the number changes whenever ICT gains
      // a section, and a literal here is a test that has to be edited
      // instead of one that checks the rule.
      final items = dash.substring(dash.indexOf('static const _items = ['));
      final n = '_IctRailItem('
          .allMatches(items.substring(0, items.indexOf('];')))
          .length;
      expect(dash, contains('TabController('));
      expect(dash, contains('length: $n,'),
          reason: 'the controller must have one slot per rail entry');
      // The label now names a rail entry, not a Tab.
      //
      // ⚠️ Matched whitespace-insensitively. `dart format` re-wraps this
      // constructor whenever the lines around it change length, so an exact
      // single-line pattern fails for a purely cosmetic reason and says
      // nothing about whether the rail entry is actually there.
      expect(
          RegExp(r"_IctRailItem\(\s*'Directorate Access'")
              .hasMatch(dash.replaceAll(RegExp(r'\s+'), ' ')),
          isTrue,
          reason: 'the Directorate Access rail entry is missing');
      expect(dash, contains('DirectorateAccessTab(accent: accent)'));
    });

    test('the rail and the view stay the same length', () {
      // ⚠️ ICT's tab strip became a left RAIL (_IctSideRail), so the four
      // entries live in its own list now. The count still has to match the
      // controller and the view: a short controller paints every entry but
      // resolves clicks against the shorter list, so tapping does nothing.
      final railStart = dash.indexOf('static const _items = [');
      final rail = dash.substring(railStart, dash.indexOf('];', railStart));
      final railCount = '_IctRailItem('.allMatches(rail).length;
      expect(railCount, greaterThanOrEqualTo(4));
      // The four bodies the TabBarView holds. Counted by NAME rather than by
      // slicing the children list: its first child is a large inline widget,
      // so the first "]," closes an inner list, not the TabBarView's.
      final views = dash.substring(dash.indexOf('// ── Body Content'));
      for (final tab in const [
        'YardDirectorateTab(',
        'DirectorateAccessTab(',
        'SystemRatesTab(',
        'ActivityLogsTab(',
      ]) {
        expect(views, contains(tab));
      }
      // ⚠️ All three counts, against each other. A controller shorter than
      // the rail paints every entry but resolves clicks against the shorter
      // list, so a tap on the last one does nothing at all.
      expect(dash, contains('length: $railCount,'));
      // The first module is a large inline widget, so the modules are
      // counted by their index argument rather than by slicing children.
      for (var i = 1; i < railCount; i++) {
        expect(views, contains('index: $i,'),
            reason: 'rail entry $i has no module in the view');
      }
    });
  });
}
