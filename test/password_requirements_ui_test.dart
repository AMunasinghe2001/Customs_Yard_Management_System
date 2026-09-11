import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/security_policy.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/password_strength_field.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

void main() {
  group('the rules shown are the rules enforced', () {
    test('the checklist and the validator never disagree', () {
      // ⚠️ The whole point. Four login screens said "Minimum 8 characters"
      // while violation() rejected anything under 12, so the form told the
      // officer to do something it would then refuse.
      const samples = [
        '',
        'short',
        '123456789',
        'password1234',
        'Passw0rd!',
        'qwertyuiop12',
        'Abcdefgh1234',
        'Abcdefgh123!',
        'ALLUPPER1234!',
        'alllower1234!',
        'NoNumbers!!!!',
        'NoSymbol12345',
        'Customs12345!',
        'Redwood#Harbor47',
        'aB3!aB3!aB3!',
        'aB3!aB3!aB3',
        'letmein12345A!',
      ];
      for (final s in samples) {
        expect(PasswordPolicy.allRulesMet(s), PasswordPolicy.isAcceptable(s),
            reason: 'disagreed on "$s"');
      }
    });

    test('past the ceiling the bar goes back to red', () {
      // ⚠️ Both ends live in ONE rule, so exceeding the maximum un-ticks the
      // same line that the minimum ticked — the bar cannot sit green while
      // the form quietly rejects the password.
      const ok = 'Redwood#Harbor47';
      expect(PasswordPolicy.allRulesMet(ok), isTrue);

      final exact = ok
          .padRight(PasswordPolicy.maxLength, 'x')
          .substring(0, PasswordPolicy.maxLength);
      expect(exact.length, PasswordPolicy.maxLength);
      expect(PasswordPolicy.allRulesMet(exact), isTrue,
          reason: 'the boundary itself is still acceptable');

      final over = '${exact}x';
      expect(PasswordPolicy.allRulesMet(over), isFalse);
      expect(PasswordPolicy.isAcceptable(over), isFalse);
      expect(PasswordPolicy.violation(over), contains('at most'));
    });

    test('the app and the database agree on both ends', () {
      // password_policy_violation in PostgreSQL enforces 12..128. If these
      // drift the form promises what the server refuses — which is the bug
      // the "Minimum 8 characters" hint already was.
      expect(PasswordPolicy.minLength, 12);
      // ⚠️ 24, not bcrypt's 72 and not the 128 this was. Those are limits on
      // what the algorithm can hash, not on what a person can type twice at
      // a shared desk — the old ceiling sat above even bcrypt's and could
      // never fire. Migration 020 moves the database to the same number.
      expect(PasswordPolicy.maxLength, 24);
    });

    test('the app and the database return the SAME message', () {
      // ⚠️ Verdicts captured from password_policy_violation() on the live
      // database. Two copies of one rule is the whole failure mode here —
      // the wording has to match as well as the pass/fail, because the app
      // shows its own message and the server's reaches the user too.
      const expected = {
        'Redwood#Harbor47': 'OK',
        'Redwood#Harbor47x12345aA': 'OK',
        'Redwood#Harbor47x12345aAb': 'Password must be at most 24 characters.',
        'Short1!': 'Password must be at least 12 characters.',
        'alllowercase123!': 'Password must contain an uppercase letter.',
        'NoSymbolHere1234': 'Password must contain a special character.',
        'Password1234!': 'Password contains a commonly used word.',
      };
      expected.forEach((pass, want) {
        expect(PasswordPolicy.violation(pass) ?? 'OK', want,
            reason: 'disagreed with the database on "$pass"');
      });
    });

    test('the message names the ONE thing that is missing', () {
      final cases = {
        'short': 'at least 12',
        'alllowercase1!': 'uppercase',
        'ALLUPPERCASE1!': 'lowercase',
        'NoNumbersHere!!': 'number',
        'NoSymbolHere123': 'special',
        'Password1234!': 'commonly used',
      };
      cases.forEach((pass, expected) {
        final v = PasswordPolicy.violation(pass);
        expect(v, isNotNull, reason: '"$pass" should be rejected');
        expect(v!.toLowerCase(), contains(expected.toLowerCase()));
      });
    });

    test('no screen hand-writes a length that contradicts the policy', () {
      // The hint that started this. A grep, because the failure mode is
      // someone typing a number into a label instead of reading the policy.
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final line in f.readAsStringSync().split('\n')) {
          if (line.trimLeft().startsWith('//')) continue;
          expect(line.contains('Minimum 8 characters'), isFalse,
              reason: '${f.path} still promises 8 characters');
          expect(line.contains('min 8 chars'), isFalse,
              reason: '${f.path} still promises 8 characters');
        }
      }
    });
  });

  group('the bars say what they mean', () {
    testWidgets('the strength bar is hidden until something is typed',
        (tester) async {
      await tester.pumpWidget(_wrap(const PasswordStrengthBar(password: '')));
      // A red bar before the first keystroke reads as an error the user has
      // not had a chance to make yet.
      expect(find.textContaining('requirements met'), findsNothing);
    });

    testWidgets('it counts the rules met, and turns green only at the end',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const PasswordStrengthBar(password: 'abc')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('requirements met'), findsOneWidget);
      expect(find.text('Password meets every requirement'), findsNothing);

      await tester.pumpWidget(
          _wrap(const PasswordStrengthBar(password: 'Redwood#Harbor47')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Password meets every requirement'), findsOneWidget);
    });

    testWidgets('the match bar says nothing about an empty confirm field',
        (tester) async {
      await tester.pumpWidget(_wrap(
          const PasswordMatchBar(password: 'Redwood#Harbor47', confirm: '')));
      // "Does not match" on an untouched box is true and useless.
      expect(find.textContaining('match'), findsNothing);
    });

    testWidgets('and fills only on an exact match', (tester) async {
      await tester.pumpWidget(_wrap(const PasswordMatchBar(
          password: 'Redwood#Harbor47', confirm: 'Redwood#Harbor4')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Passwords do not match'), findsOneWidget);

      await tester.pumpWidget(_wrap(const PasswordMatchBar(
          password: 'Redwood#Harbor47', confirm: 'Redwood#Harbor47')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Passwords match'), findsOneWidget);
    });

    testWidgets('every rule is listed, and ticks as it is met', (tester) async {
      await tester.pumpWidget(_wrap(const PasswordRequirements(password: '')));
      for (final rule in PasswordPolicy.rules) {
        expect(find.text(rule.label), findsOneWidget,
            reason: 'the reader must see every rule, not one at a time');
      }
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.pumpWidget(
          _wrap(const PasswordRequirements(password: 'Redwood#Harbor47')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.check_circle_rounded),
          findsNWidgets(PasswordPolicy.rules.length));
    });
  });

  group('every password surface shows them', () {
    test('all 17 entry points are wired', () {
      // ⚠️ Enumerated, because a portal that validates silently and one that
      // guides the officer are not the same product -- and a new screen is
      // exactly where this gets forgotten.
      const surfaces = [
        'lib/screens/admin/admin_signup_screen.dart',
        'lib/screens/appeal/appeal_login_screen.dart',
        'lib/screens/appeal/appeal_signup_screen.dart',
        'lib/screens/auth/signup_screen.dart',
        'lib/screens/disposal/disposal_login_screen.dart',
        'lib/screens/disposal/disposal_signup_screen.dart',
        'lib/screens/executive/executive_login_screen.dart',
        'lib/screens/executive/executive_signup_screen.dart',
        'lib/screens/ict/ict_login_screen.dart',
        'lib/screens/ict/ict_signup_screen.dart',
        'lib/screens/login/officer_signup_screen.dart',
        'lib/screens/profile/edit_profile_screen.dart',
        'lib/screens/valuation/valuation_login_screen.dart',
        'lib/screens/valuation/valuation_signup_screen.dart',
        'lib/widgets/disposal_profile_dialog.dart',
        'lib/widgets/forgot_password_panel.dart',
        'lib/widgets/mandatory_password_change_dialog.dart',
      ];
      for (final path in surfaces) {
        final src = File(path).readAsStringSync();
        expect(src.contains('PasswordRequirements('), isTrue,
            reason: '$path does not show the rules');
        expect(src.contains('PasswordStrengthBar('), isTrue,
            reason: '$path does not show the strength bar');
        expect(src.contains('PasswordMatchBar('), isTrue,
            reason: '$path does not show the match bar');
      }
    });
  });
}
