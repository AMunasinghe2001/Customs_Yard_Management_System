import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/services/otp_service.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// The ICT sign-up reported three symptoms that were one fault:
///
///   * pressing "Verify OTP & Create Account" showed "This account is not
///     permitted to create that profile";
///   * pressing it again showed "No verification code was sent";
///   * and the account was in the database regardless.
void main() {
  final services = _read('lib/services/services.dart');
  final migration =
      _read('migrations/035_sign_up_writes_the_profile_atomically.sql');
  final migration036 =
      _read('migrations/036_ict_may_still_provision_yard_accounts.sql');

  group('the one-time code survives a failed sign-up', () {
    test('a failure leaves the code usable for the retry', () {
      // ⚠️ This is the second error the officer saw. The code was spent by
      // verifyCode BEFORE the account work, so when that work failed the
      // retry had nothing left to check and reported the code missing —
      // hiding the real complaint behind a false one.
      const email = 'retry@example.invalid';
      final code = GmailOtpService.instance.debugSeedCode(email);

      // What the service now does: check without spending.
      GmailOtpService.instance.verifyCode(email, code, consume: false);

      // The operation "fails" here — the code must still be good.
      expect(() => GmailOtpService.instance.verifyCode(email, code),
          returnsNormally,
          reason: 'the retry was left with no code to verify');
    });

    test('a success spends it, so it cannot be replayed', () {
      const email = 'spent@example.invalid';
      final code = GmailOtpService.instance.debugSeedCode(email);

      GmailOtpService.instance.verifyCode(email, code, consume: false);
      GmailOtpService.instance.consumeCode(email);

      expect(() => GmailOtpService.instance.verifyCode(email, code),
          throwsA(isA<Exception>()),
          reason: 'a used code must not work twice');
    });

    test('EVERY account-creating path verifies without consuming', () {
      // ⚠️ The first fix covered only the portal sign-up. ICT's two staff
      // screens had the same fault and still showed "No verification code was
      // sent" on the second press — reported from Create Yard Staff Account.
      final upfront = RegExp(r'verifyCode\(email\.trim\(\), otp\);')
          .allMatches(services)
          .length;
      expect(upfront, 0,
          reason: '\$upfront call site(s) still spend the code before the '
              'work that can fail');

      expect(
          RegExp(r'verifyCode\(email\.trim\(\), otp,\s*consume: false\)')
              .allMatches(services)
              .length,
          greaterThanOrEqualTo(3),
          reason: 'the three account-creating paths must all retain the code');
      expect(
          RegExp(r'GmailOtpService\.instance\.consumeCode')
              .allMatches(services)
              .length,
          greaterThanOrEqualTo(4),
          reason: 'each path must spend the code once it has succeeded');
    });
  });

  group('the account and its profile are written together', () {
    test('the client no longer writes the profile itself', () {
      // ⚠️ The upsert that used to sit after signUp is what RLS refused:
      // `yard_profiles_insert` requires id = auth.uid(), and a person signing
      // up is not signed in. Re-adding a client-side profile write restores
      // the bug, so this asserts it is gone rather than merely changed.
      final signupBody = services.substring(
        services.indexOf('Future<void> verifySignupOtp('),
        services.indexOf('Future<void> createOfficer('),
      );
      expect(signupBody.contains("from('profiles').upsert"), isFalse,
          reason: 'the client writes the profile again — RLS will refuse it');
    });

    test('sign_up fills the profile inside the transaction', () {
      expect(migration, contains('update public.profiles'));
      expect(migration, contains('security definer'));
    });

    test('it UPDATES rather than inserts, because a trigger already inserted',
        () {
      // ⚠️ The first draft of the migration inserted here and failed its own
      // verification with a duplicate key on profiles_pkey: the trigger
      // `on_auth_user_created` had already made the row.
      expect(migration, contains('on_auth_user_created'));
      expect(migration, contains('profiles_pkey'));
    });

    test('a missing trigger fails loudly instead of returning a dead account',
        () {
      expect(migration, contains('if not found then'));
    });
  });

  group('ICT can still provision yard accounts', () {
    test('the yard roles are gated on WHO is calling, not on the role alone',
        () {
      // ⚠️ 035 refused 'admin'/'officer' outright, which also broke ICT's own
      // Create Yard Staff Account screen — it goes through the same function.
      // The question is not which role, but whether an ICT user is signed in.
      expect(migration036, contains('public.auth_user_is_ict()'));
      expect(migration036,
          contains('may only be created by the ICT Directorate'));
    });

    test('a yard account must name its yard', () {
      // Without it every yard-scoped RLS policy has nothing to match on.
      expect(migration036, contains('a yard account needs an assigned yard'));
    });

    test('the migration proves both sides', () {
      expect(migration036, contains('PASS: a stranger cannot create a yard'));
      expect(migration036, contains('PASS: ICT can provision a yard account'));
    });

    test('the client does not re-write the profile after creating it', () {
      // It used to upsert here inside `catch (_) {}`, so a profile that never
      // took its username was still reported to ICT as created.
      final start = services.indexOf('Future<Map<String, dynamic>> '
          'verifyAndCreateUser(');
      final end = services.indexOf('/// Toggle Active / Inactive status');
      // ⚠️ Assert the window is real before asserting about its contents. A
      // -1 from indexOf silently makes substring throw, and a window that
      // matched the wrong thing would let this test pass while seeing none of
      // the code it claims to check.
      expect(start, greaterThan(0), reason: 'verifyAndCreateUser not found');
      expect(end, greaterThan(start), reason: 'end anchor not after start');
      final yardBody = services.substring(start, end);
      expect(yardBody.length, greaterThan(1000),
          reason: 'the window is too small to be the whole method');
      expect(yardBody.contains("from('profiles').upsert"), isFalse,
          reason: 'the redundant profile upsert is back');

      // ⚠️ Narrowly: a swallowed PROFILE WRITE. The two `catch (_) {}` that
      // remain in this method restore the ICT admin's session, where failing
      // really should not abort the creation — an earlier version of this
      // test banned every empty catch and failed on those, which would have
      // pushed me to "fix" code that was right.
      expect(
          RegExp(r"from\('profiles'\)[\s\S]{0,400}?\}\s*catch\s*\(_\)\s*\{\}")
              .hasMatch(yardBody),
          isFalse,
          reason: 'a profile write is being swallowed, so a broken account '
              'would be reported to ICT as created');

      // And the replacement is actually there.
      expect(yardBody.contains('its profile is missing'), isTrue,
          reason: 'nothing checks that the profile really was written');
    });
  });

  group('a sign-up form cannot mint a yard account', () {
    test('only the directorate roles are accepted', () {
      // 'admin' is SDDC/DDC — full control of a yard. Anyone who can reach
      // the sign-up form could otherwise create one for any yard.
      expect(migration,
          contains("v_role not in ('ict','valuation','appeal','disposal','executive')"));
      expect(migration, contains("errcode = '42501'"));
    });

    test('the migration proves the refusal leaves no orphan', () {
      expect(migration, contains('a refused sign-up left an orphan'));
      expect(migration, contains('a profile was left with no account behind it'));
    });

    test('the verification checks the fields that were being lost', () {
      // ⚠️ Asserting only that a profile row exists would have PASSED before
      // the fix, because the trigger already made one — while the officer
      // still had no username to sign in with.
      expect(migration, contains('the username never reached the profile'));
    });
  });
}
