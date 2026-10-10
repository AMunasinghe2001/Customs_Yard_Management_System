import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/services/otp_service.dart';

/// Two faults in the one-time code, both reported from the yard portals.
void main() {
  group('the code lives exactly as long as the e-mail promises', () {
    test('there is ONE lifetime, and the screens read it', () {
      // ⚠️ The e-mail said "expires in 5 minutes" (generated from the
      // service) while every on-screen countdown was a literal `120` copied
      // into twelve files. So the screen expired the code at two minutes and
      // the server went on accepting it for three more — the officer was
      // told a live code was dead.
      expect(GmailOtpService.codeLifetime, const Duration(minutes: 5));

      final hardcoded = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('_otpWindowSeconds = 120'))
          .map((f) => f.path)
          .toList();
      expect(hardcoded, isEmpty,
          reason: 'these screens still hardcode a 2-minute window: '
              '${hardcoded.join(", ")}');
    });
  });

  group('a rejected password does not destroy the code', () {
    // ⚠️ The reported sequence: reset the password, get an error, press the
    // button again — and be told "No verification code was sent", bounced to
    // the OTP screen to re-enter a code that had already been spent by the
    // ATTEMPT THAT FAILED.
    const email = 'otp.lifetime.test@example.invalid';

    test('verifyCode can check without spending', () {
      final svc = GmailOtpService.instance;
      final code = svc.debugSeedCode(email);

      // Checked twice without consuming: this is the failed-password case.
      svc.verifyCode(email, code, consume: false);
      svc.verifyCode(email, code, consume: false);

      // And it still works for the attempt that succeeds.
      svc.verifyCode(email, code, consume: false);
      svc.consumeCode(email);

      // Once spent, it is gone.
      expect(() => svc.verifyCode(email, code, consume: false),
          throwsA(isA<Exception>()));
    });

    test('the default still consumes', () {
      // Callers that verify as their LAST step rely on this.
      final svc = GmailOtpService.instance;
      final code = svc.debugSeedCode(email);
      svc.verifyCode(email, code);
      expect(() => svc.verifyCode(email, code), throwsA(isA<Exception>()));
    });
  });

  group('the reset only retreats for a problem with the CODE', () {
    final panel =
        File('lib/widgets/forgot_password_panel.dart').readAsStringSync();

    test('a rejected password does not bounce to the OTP step', () {
      // ⚠️ `_error.contains('code')` matched "No verification code was
      // sent" AND any password message containing the word, so a password
      // complaint threw the officer back to fix a code that was fine.
      expect(panel.contains("_error!.contains('code')"), isFalse,
          reason: 'the loose match is back; a password error will bounce the '
              'officer to the code screen');
      expect(panel, contains("about.contains('invalid code')"));
    });
  });
}
