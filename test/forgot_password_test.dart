import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/forgot_password_panel.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _harness() => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          // Rendered inline, the way the sign-in panel shows it -- there is no
          // dialog to push any more.
          body: SingleChildScrollView(
            child: ForgotPasswordPanel(
              accent: const Color(0xFF3949AB),
              onClose: (_) {},
            ),
          ),
        ),
      ),
    );

void main() {
  group('both yard portals offer the reset', () {
    const portals = {
      'officer': 'lib/screens/login/login_screen.dart',
      'dc/sddc': 'lib/screens/admin/admin_login_screen.dart',
    };

    for (final p in portals.entries) {
      test('${p.key} has a Forgot password link that shows the panel', () {
        final src = _read(p.value);
        expect(src, contains("Text('Forgot password?'"));
        expect(src, contains('ForgotPasswordPanel('));
        expect(src, contains('_openForgotPassword'));
      });

      test('${p.key} pre-fills what was already typed', () {
        // So the officer does not type their username a second time.
        final src = _read(p.value);
        expect(src, contains('initialIdentifier: _emailCtrl.text.trim()'));
      });

      test('${p.key} tells them to sign in again afterwards', () {
        final src = _read(p.value);
        expect(src, contains('Sign in with your new password'));
      });
    }
  });

  group('the panel walks the three steps', () {
    testWidgets('it starts by asking who the account is', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('Reset your password'), findsOneWidget);
      expect(find.text('Username or Email'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('an empty identifier is refused before anything is sent',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(find.text('Username or email required'), findsOneWidget);
      // Still on step one.
      expect(find.text('Reset your password'), findsOneWidget);
    });

    // ⚠️ It hands control BACK rather than popping a route -- the panel is
    // part of the page, so there is nothing to pop. The login screen decides
    // what to show next.
    testWidgets('going back reports that nothing changed', (tester) async {
      final closed = <bool>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ForgotPasswordPanel(
              accent: const Color(0xFF3949AB),
              onClose: closed.add,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(closed, [false]);
    });
  });

  group('what the dialog will and will not say', () {
    final src = _read('lib/widgets/forgot_password_panel.dart');

    test('it never reports whether the account exists', () {
      // Saying "no such account" would let anyone test which usernames and
      // addresses are real.
      expect(src, contains('If that account exists'));
      expect(src, isNot(contains('No such account')));
      expect(src, isNot(contains('not found')));
    });

    test('it advances to the code step either way', () {
      // The identifier resolving to nothing is not reported; the code simply
      // never arrives.
      final fn = src.substring(src.indexOf('Future<void> _sendCode('));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains('_step = _Step.verify;'));
      expect(body, isNot(contains('if (email == null) return;')));
    });

    test('a wrong code is told apart from a failure to save', () {
      expect(src, contains('That code is not correct'));
      expect(src, contains('That code has expired'));
      expect(src, contains('already been used'));
    });

    test('a bad code keeps the typed password and only asks for the code again',
        () {
      final fn = src.substring(src.indexOf('Future<void> _save('));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains("if (_error!.contains('code')) _step = _Step.verify;"));
    });

    test('the confirm field has to match', () {
      expect(src, contains('The passwords do not match'));
    });

    test('the minimum length matches what the database enforces', () {
      // auth.change_password raises below 6, so checking here reports it on
      // the field instead of as a save failure.
      expect(src, contains('At least 6 characters'));
      final sql = _read('postgres/05_password_reset.sql');
      final auth = _read('postgres/04_auth.sql');
      expect(auth, contains('length(p_password) < 6'));
      expect(sql, contains('perform auth.change_password(v_id, p_password);'),
          reason: 'the reset must reuse the one setter, not re-hash itself');
    });
  });

  group('the reset cannot reach an account that could not sign in', () {
    final sql = _read('postgres/05_password_reset.sql');

    test('it resolves through the same resolver sign-in uses', () {
      expect(sql, contains('public.email_for_login('));
    });

    test('a deactivated account is not resettable into life', () {
      expect(sql, contains('and  p.is_active'));
    });

    test('both functions are SECURITY DEFINER, since auth.uid() is null', () {
      expect('security definer'.allMatches(sql).length, greaterThanOrEqualTo(2));
    });

    test('the file verifies itself against the database', () {
      // Run as part of applying it; these are the claims it checks.
      for (final claim in [
        'VERIFY FAILED: username did not resolve',
        'VERIFY FAILED: an unknown identifier resolved',
        'VERIFY FAILED: the new password does not sign in',
        'VERIFY FAILED: the old password still signs in',
        'VERIFY FAILED: a deactivated account resolved',
      ]) {
        expect(sql, contains(claim));
      }
    });
  });

  group('the service keeps the two steps honest', () {
    final svc = _read('lib/services/services.dart');

    test('the code is checked before the password is written', () {
      // Sliced to the NEXT method: this signature spans lines, so the first
      // closing brace belongs to its parameter list, not its body.
      final fn = svc.substring(svc.indexOf('Future<void> finishPasswordReset('));
      final body =
          fn.substring(0, fn.indexOf('/// Change the currently signed-in'));
      final verify = body.indexOf('verifyCode');
      final write = body.indexOf('reset_password_for_identifier');
      expect(verify, greaterThan(-1));
      expect(write, greaterThan(-1));
      expect(verify, lessThan(write),
          reason: 'a password must never be set on an unverified code');
    });

    test('the code goes to the address the ACCOUNT is registered to', () {
      // Never one the caller supplied.
      final fn = svc.substring(svc.indexOf('Future<String?> startPasswordReset('));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains("rpc('reset_email_for_identifier'"));
      // ⚠️ The recipient is what matters here, not the rest of the call --
      // the e-mail now also carries a purpose, and pinning the whole argument
      // list would make this fail on wording changes it is not guarding.
      expect(body, contains('sendCode(email'));
      expect(body, contains('purpose: OtpPurpose.passwordReset'),
          reason: 'a reset must not send a sign-in e-mail');
    });
  });
}
