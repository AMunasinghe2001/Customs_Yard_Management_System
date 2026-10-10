// The ICT "Create Yard Staff Account" dialog must let the officer ask for a
// new code, the way every sign-up screen already does.
//
// ⚠️ The code went out exactly once. Pressing Back and Send OTP again
// did re-send it, but NOTHING on screen changed -- no countdown, no
// confirmation that a second mail had gone -- and Gmail threads the two
// identical subjects together, so the new code hid under the old one. An
// officer whose first mail went astray had no way to tell a slow mail from
// a dead button.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File('lib/screens/ict/ict_dashboard_screen.dart').readAsStringSync();
  final i = src.indexOf('void _showAddStaffDialog()');
  final dialog = src.substring(i, src.indexOf('void _showSuccessCredentialsDialog', i));

  group('the ICT staff dialog can resend its OTP', () {
    test('the dialog exists and was found', () {
      expect(i, greaterThan(-1));
      expect(dialog, contains('Send OTP'));
    });

    test('sendOtp takes an isResend flag', () {
      expect(dialog, contains('sendOtp({bool isResend = false})'));
      expect(dialog, contains('sendOtp(isResend: true)'));
    });

    test('there is a Resend control', () {
      expect(dialog, contains('Resend code'));
    });

    test('a countdown tells the officer the code is still alive', () {
      // ⚠️ The point of the countdown: without it, a missing mail and a
      // broken button look identical.
      expect(dialog, contains('Code expires in'));
      expect(dialog, contains('Code expired'));
      expect(dialog, contains('startCountdown()'));
    });

    test('the window comes from the service, not a copied literal', () {
      // ⚠️ A hard-coded 120 once made the screen expire at two minutes
      // while the e-mail promised five. One source of truth.
      expect(dialog, contains('GmailOtpService.codeLifetime.inSeconds'));
    });

    test('resending is capped and then locked', () {
      expect(dialog, contains('maxResends = 2'));
      expect(dialog, contains('Duration(hours: 2)'));
      expect(dialog, contains('Resend limit reached'));
    });

    test('a resend does NOT re-run the form validation', () {
      // The fields are disabled once the code is out, so there is nothing
      // to correct -- re-validating would only produce noise.
      expect(dialog, contains('if (isResend && !canResend()) return;'));
      expect(dialog, contains('if (!isResend &&'));
    });

    test('Back stops the clock but KEEPS the resend count', () {
      // ⚠️ Otherwise Back is an unlimited mail button.
      final back = dialog.substring(dialog.indexOf("child: const Text('Back')") - 900,
          dialog.indexOf("child: const Text('Back')"));
      expect(back, contains('countdownTimer?.cancel()'));
      expect(back, contains('secondsLeft = 0'));
      expect(back, isNot(contains('resendCount = 0')));
    });

    test('both timers are cancelled when the dialog closes', () {
      // ⚠️ A periodic Timer calling setDialogState on a disposed element
      // throws; the 2-hour lock timer would pin the whole closure in memory.
      final tail = dialog.substring(dialog.indexOf('.whenComplete('));
      expect(tail, contains('countdownTimer?.cancel()'));
      expect(tail, contains('lockTimer?.cancel()'));
    });

    test('the resend says the previous code is dead', () {
      // sendCode overwrites the stored code, so the old one really does
      // stop working -- the officer has to be told, or they will keep
      // typing the first one.
      //
      // Matched as ONE short fragment on ONE source line: a message split
      // across two adjacent string literals breaks this test the next time
      // `dart format` re-wraps it, with no behaviour change at all.
      expect(dialog, contains('Use the latest one.'));
    });
  });
}
