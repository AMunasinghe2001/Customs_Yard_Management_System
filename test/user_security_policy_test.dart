import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/dev_config.dart';
import 'package:cus_yard_management/core/security_policy.dart';
import 'package:cus_yard_management/models/models.dart';

/// User-level security: second factor, password strength and rotation, and
/// the rule that the client is never the only thing enforcing a role.
void main() {
  group('OTP / second factor', () {
    test('the OTP bypass is off, and off by construction', () {
      // Tests run in debug, where the bypass COULD be on — it is off because
      // no --dart-define asked for it. That is the point: skipping OTP is a
      // deliberate per-build act, not a state the repo can be left in.
      expect(kDevSkipOtp, isFalse);
      expect(kOtpEnforced, isTrue);
    });

    test('a release build can never skip OTP', () {
      // ⚠️ The property that matters, and the one a debug test cannot execute:
      // kDevSkipOtp is ANDed with !kReleaseMode, so even a build whose define
      // says "skip" still demands the emailed code once released. Read from
      // the source, because the release branch is unreachable from here.
      final src = File('lib/core/dev_config.dart').readAsStringSync();
      expect(src, contains('kReleaseMode'),
          reason: 'the bypass must be tied to the build mode');
      expect(
          RegExp(r'kDevSkipOtp\s*=\s*[^;]*!\s*kReleaseMode').hasMatch(src),
          isTrue,
          reason: 'kDevSkipOtp must be ANDed with !kReleaseMode');
      // And it must never be a bare `= true`.
      expect(RegExp(r'kDevSkipOtp\s*=\s*true\s*;').hasMatch(src), isFalse);
    });

    test('every privileged portal runs the emailed-code flow', () {
      const portals = [
        'lib/screens/disposal/disposal_login_screen.dart',
        'lib/screens/valuation/valuation_login_screen.dart',
        'lib/screens/appeal/appeal_login_screen.dart',
        'lib/screens/executive/executive_login_screen.dart',
        'lib/screens/ict/ict_login_screen.dart',
      ];
      for (final p in portals) {
        final s = File(p).readAsStringSync();
        expect(s.contains('startOtpLogin') || s.contains('finishOtpLogin'),
            isTrue,
            reason: '$p has no OTP flow');
      }
    });
  });

  group('PasswordPolicy', () {
    test('rejects each way a password can be weak', () {
      // One failure reported at a time, so the message names something the
      // user can act on.
      expect(PasswordPolicy.violation('Short1!aA'),
          contains('at least 12 characters'));
      expect(PasswordPolicy.violation('alllowercase123!'),
          contains('uppercase'));
      expect(PasswordPolicy.violation('ALLUPPERCASE123!'),
          contains('lowercase'));
      expect(PasswordPolicy.violation('NoDigitsHere!!!'), contains('number'));
      expect(PasswordPolicy.violation('NoSpecials12345'),
          contains('special character'));
      expect(PasswordPolicy.violation('Password1234!'),
          contains('commonly used'));
      expect(PasswordPolicy.violation(null), contains('at least 12'));
      expect(PasswordPolicy.violation(''), contains('at least 12'));
    });

    test('accepts a strong password', () {
      for (final good in [
        'Tr0ub4dor&Kestrel',
        'Yard-Manage7!Colombo',
        r'9$Harbour_Lantern',
      ]) {
        expect(PasswordPolicy.violation(good), isNull,
            reason: 'rejected $good');
        expect(PasswordPolicy.isAcceptable(good), isTrue);
      }
    });

    test('refuses a password longer than bcrypt actually hashes', () {
      // bcrypt stops at 72 bytes. Accepting 500 characters would let someone
      // believe the tail is protecting them when it is discarded.
      final long = 'A1!${'a' * 200}';
      expect(PasswordPolicy.violation(long), contains('at most'));
    });

    test('validate() is usable directly as a form validator', () {
      expect(PasswordPolicy.validate('weak'), isNotNull);
      expect(PasswordPolicy.validate('Tr0ub4dor&Kestrel'), isNull);
    });

    test('the client rule is not laxer than the SQL rule', () {
      // ⚠️ Two copies of a rule drift. The SQL is the control; this pins the
      // mirror to it, so a relaxed client cannot quietly disagree.
      final sql =
          File('postgres/52_user_security_policies.sql').readAsStringSync();
      final m = RegExp(r'length\(p_password\)\s*<\s*(\d+)').firstMatch(sql);
      expect(m, isNotNull, reason: 'no length rule found in the migration');
      expect(PasswordPolicy.minLength,
          greaterThanOrEqualTo(int.parse(m!.group(1)!)));

      // Each rule the SQL enforces has a counterpart here.
      for (final needle in ['[A-Z]', '[a-z]', '[0-9]', '[^A-Za-z0-9]']) {
        expect(sql, contains(needle));
      }
      for (final word in PasswordPolicy.commonWords) {
        expect(sql, contains(word),
            reason: 'SQL does not block the common word "$word"');
      }
    });
  });

  group('password rotation', () {
    ProfileModel profileWithPasswordAge(int days) => ProfileModel(
          id: 'p1',
          fullName: 'Officer',
          role: 'officer',
          isActive: true,
          createdAt: DateTime.now().subtract(Duration(days: days + 10)),
          passwordUpdatedAt: DateTime.now().subtract(Duration(days: days)),
        );

    test('a fresh password is neither expired nor expiring', () {
      final p = profileWithPasswordAge(0);
      expect(p.isPasswordExpired, isFalse);
      expect(p.isPasswordExpiringSoon, isFalse);
    });

    test('warns inside the final week', () {
      final p = profileWithPasswordAge(85);
      expect(p.isPasswordExpired, isFalse);
      expect(p.isPasswordExpiringSoon, isTrue);
    });

    test('expires after 90 days', () {
      final p = profileWithPasswordAge(95);
      expect(p.isPasswordExpired, isTrue);
      // Expired is not "expiring soon" — the two are exclusive, so a screen
      // cannot show both a warning and a block.
      expect(p.isPasswordExpiringSoon, isFalse);
    });

    test('the client and the server agree on the same window', () {
      // ⚠️ 90 days and a 7-day warning means the SQL must warn from day 83.
      // A mismatch shows as the app nagging on a different day than the
      // server, which reads as a bug rather than a policy.
      expect(PasswordRotationPolicy.maxAgeDays,
          equals(ProfileModel.passwordMaxAgeDays));
      expect(PasswordRotationPolicy.warnWithinDays,
          equals(ProfileModel.passwordWarnDays));

      final sql =
          File('postgres/52_user_security_policies.sql').readAsStringSync();
      expect(sql, contains("interval '90 days'"));
      final warnFrom = PasswordRotationPolicy.maxAgeDays -
          PasswordRotationPolicy.warnWithinDays;
      expect(sql, contains("interval '$warnFrom days'"),
          reason: 'the SQL warning window must start at day $warnFrom');
    });
  });

  group('RBAC is enforced server-side', () {
    test('the delivery RPC checks its caller', () {
      // ⚠️ This function is SECURITY DEFINER, so RLS does NOT apply inside it,
      // and it both hands goods over and closes the warehouse entry. Before
      // the fix it asked nothing about the caller and was granted to `public`.
      final sql =
          File('postgres/52_user_security_policies.sql').readAsStringSync();
      expect(sql, contains('disposal_toggle_outcome_delivery'));
      expect(sql, contains('auth_user_is_disposal()'),
          reason: 'the RPC must verify the role server-side');
      expect(sql, contains('not authorized'));
      expect(sql, contains('revoke execute'),
          reason: 'it must no longer be executable by public/anon');
    });

    test('privileged writes are granted to authenticated, not public', () {
      final sql =
          File('postgres/52_user_security_policies.sql').readAsStringSync();
      expect(
          RegExp(r'grant execute on function\s+'
                  r'public\.disposal_toggle_outcome_delivery[^;]*to authenticated')
              .hasMatch(sql),
          isTrue);
    });

    test('the server, not the screen, decides password strength', () {
      // Hiding a button is cosmetic; these are the functions that actually
      // refuse. Both entry points must consult the policy.
      final sql =
          File('postgres/52_user_security_policies.sql').readAsStringSync();
      for (final fn in ['sr_auth.sign_up', 'sr_auth.change_password']) {
        final i = sql.indexOf('create or replace function $fn');
        expect(i, greaterThan(-1), reason: '$fn not redefined');
        final body = sql.substring(i, sql.indexOf(r'$fn$;', i));
        expect(body, contains('password_policy_violation'),
            reason: '$fn does not enforce the policy');
      }
    });
  });
}
