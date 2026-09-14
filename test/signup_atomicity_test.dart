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

    test('the sign-up path verifies without consuming', () {
      expect(services, contains('verifyCode(email.trim(), otp, consume: false)'),
          reason: 'verifySignupOtp is spending the code up front again');
      expect(services, contains('GmailOtpService.instance.consumeCode'),
          reason: 'nothing spends the code on success');
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
