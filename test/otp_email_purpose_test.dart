// Every one of these e-mails used to be the same message.
//
// "Your SL Customs verification code" arrived whether you were signing in,
// creating an account, or resetting a password -- with no hint of what the
// code unlocked. That matters most for a code the reader did NOT request:
// "someone tried to sign in" and "someone is creating an account with your
// address" call for different action.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/services/otp_service.dart';

void main() {
  final otp = File('lib/services/otp_service.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();

  group('a code says what it is for', () {
    test('there is a purpose for each flow the app has', () {
      expect(OtpPurpose.values, hasLength(4));
      expect(OtpPurpose.values, contains(OtpPurpose.signIn));
      expect(OtpPurpose.values, contains(OtpPurpose.createAccount));
      expect(OtpPurpose.values, contains(OtpPurpose.passwordReset));
      expect(OtpPurpose.values, contains(OtpPurpose.officerAccount));
    });

    test('each has its own subject line', () {
      // ⚠️ The subject is the only part read in a crowded inbox, so it is
      // where the purpose has to land first.
      for (final subject in [
        "'Your SL Customs sign-in code'",
        "'Confirm your SL Customs account'",
        "'Reset your SL Customs password'",
        "'Confirm your SL Customs officer account'",
      ]) {
        expect(otp, contains(subject), reason: 'missing subject $subject');
      }
    });

    test('each says what to do if the reader did NOT ask for it', () {
      // ⚠️ And says something DIFFERENT: an unexpected sign-in code means
      // someone has your password; an unexpected account code means someone
      // typed your address by mistake.
      expect(otp, contains('someone else may have your password'));
      expect(otp, contains('someone has used your address by'));
      // ⚠️ Matched as single fragments. The source wraps these strings, so an
      // assertion that included the wrapping would fail on a reformat without
      // the wording having changed at all.
      expect(otp,
          contains('current password still works and nothing has changed.'));
      expect(otp, contains('nothing is created until the code is entered.'));
    });

    test('the old one-size subject is gone', () {
      expect(otp, isNot(contains("'Your SL Customs verification code'")));
    });
  });

  group('every caller passes the purpose its flow serves', () {
    test('a password reset says so', () {
      expect(services, contains('purpose: OtpPurpose.passwordReset'));
    });

    test('a sign-in says so', () {
      expect(services, contains('purpose: OtpPurpose.signIn'));
    });

    test('creating an account says so', () {
      expect(services, contains('purpose: OtpPurpose.createAccount'));
    });

    test('an officer account says so — twice, for both entry points', () {
      expect('purpose: OtpPurpose.officerAccount'.allMatches(services).length,
          2);
    });

    test('no call is left on the default by accident', () {
      // ⚠️ signIn is the default, so a caller that forgot to say would send a
      // sign-in e-mail for a password reset. Every call site names one.
      final calls = 'sendCode('.allMatches(services).length;
      final purposes = 'purpose: OtpPurpose.'.allMatches(services).length;
      expect(purposes, calls,
          reason: '$calls sendCode call(s) but $purposes purpose(s)');
    });
  });

  group('credentials: a welcome and a reissue are different letters', () {
    test('the subject changes', () {
      expect(otp, contains('Welcome to SL Customs — your account is ready'));
      expect(otp,
          contains('Your SL Customs sign-in details have been reissued'));
    });

    test('a reissue warns that the old password has stopped working', () {
      // ⚠️ This one arrives unannounced. A welcome is expected; a password
      // that has just been changed for you is not.
      expect(otp, contains('The previous password no longer works'));
      expect(otp, contains('someone else has reset your account'));
    });

    test('a welcome says to delete the e-mail once the password is changed', () {
      // ⚠️ It carries a working credential — it should not sit in an inbox.
      expect(otp, contains('it carries a working credential'));
    });

    test('the reissue path is the one that sets isReissue', () {
      // The two officer-creation paths are genuine welcomes and keep the
      // default.
      expect('isReissue: true'.allMatches(services).length, 1);
      final reset =
          services.substring(services.indexOf('resetDirectorateCredentials'));
      expect(reset.substring(0, 2000), contains('isReissue: true'));
    });
  });

  group('they read as one system', () {
    test('every message goes through the same frame', () {
      expect(otp, contains('static String _shell({'));
      expect('_shell('.allMatches(otp).length, 3); // definition + 2 uses
    });

    test('the frame names the sender and says not to reply', () {
      expect(otp, contains('Sri Lanka Customs'));
      expect(otp, contains('SR Management System'));
      expect(otp, contains('Please do not reply'));
    });

    test('a greeting appears only when there is a name for it', () {
      // Otherwise the e-mail opens with a bare "Hello ,".
      expect(otp, contains("recipientName.trim().isNotEmpty)"));
    });
  });
}
