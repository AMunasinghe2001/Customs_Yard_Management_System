// A taken e-mail must be refused when the button is pressed, not after the
// officer has waited for a mail, opened it and typed six digits.
//
// ⚠️ The account is only created in `verifySignupOtp`, so `user_already_exists`
// used to surface at the very moment the officer expects to be finished.
// Reported directly: say it before the code is sent.
//
// ⚠️ It is also a small disclosure and quota problem: without the check, a
// stranger can confirm an address is registered by making the app mail a real
// code to it, and every doomed attempt spends an OTP.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/services/services.dart').readAsStringSync();
  final i = src.indexOf('Future<void> requestSignupOtp(');
  // The signature is multi-line, so the FIRST `\n  }` closes
  // the parameter list, not the method. Start after `}) async {`.
  final open = src.indexOf('}) async {', i);
  final body = src.substring(open, src.indexOf('\n  }', open));

  group('a taken e-mail is refused before the OTP is sent', () {
    test('requestSignupOtp checks first', () {
      expect(i, greaterThan(-1), reason: 'requestSignupOtp not found');
      expect(body, contains('_emailIsRegistered'));
    });

    test('the check comes BEFORE sendCode, not after', () {
      // ⚠️ The ordering is the whole point. After sendCode it would still
      // throw, and the officer would still have received a pointless mail.
      final check = body.indexOf('_emailIsRegistered');
      final send = body.indexOf('sendCode');
      expect(check, greaterThan(-1));
      expect(send, greaterThan(-1));
      expect(check, lessThan(send),
          reason: 'the duplicate check must run before the mail goes out');
    });

    test('it throws the code the sign-up screens already handle', () {
      expect(body, contains("code: 'user_already_exists'"));
    });

    test('the lookup reads sr_auth.users, not profiles', () {
      // ⚠️ sr_auth.users is where the unique constraint lives. Checking
      // `profiles` would miss an account whose profile row failed to write,
      // and the sign-up would then still die on a duplicate key at the end.
      final fn = src.substring(src.indexOf('_emailIsRegistered(String email)'));
      expect(fn.substring(0, 400), contains('sr_auth.users'));
    });

    test('a failed lookup does NOT block the sign-up', () {
      // ⚠️ Deliberate: a signed-out client may not be able to read that
      // table on every deployment. Refusing a legitimate sign-up because
      // the CHECK errored is worse than letting it reach the existing
      // duplicate guard at the end.
      final fn = src.substring(src.indexOf('_emailIsRegistered(String email)'));
      final upTo = fn.substring(0, 700);
      expect(upTo, contains('catch'));
      expect(upTo, contains('return false'));
    });
  });
}
