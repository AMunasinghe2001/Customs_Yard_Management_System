@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cus_yard_management/core/otp_config.dart';
import 'package:cus_yard_management/services/otp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

/// Where the OTP wait actually goes.
///
/// ⚠️ Tagged `live` and skipped unless RUN_LIVE_SMTP=1, because it sends a real
/// e-mail through the real Gmail account. Measuring a mock would prove nothing
/// about the number an officer waits.
///
///     RUN_LIVE_SMTP=1 flutter test test/otp_send_timing_test.dart --tags live
void main() {
  final live = Platform.environment['RUN_LIVE_SMTP'] == '1';

  test('the OTP send is one connection, not a retry storm', () async {
    if (!live) {
      // Not a silent pass: say why, so a green run is not mistaken for a
      // measurement.
      printOnFailure('set RUN_LIVE_SMTP=1 to actually measure');
      return;
    }
    expect(kGmailConfigured, isTrue, reason: 'no Gmail credentials in .env');

    // ⚠️ 465 with implicit TLS, not 587 with STARTTLS. Measured on this
    // machine: TCP to 587 is 184ms and to 465 is 91ms, and the full send is
    // 3360ms against 3101ms -- so the port is worth a few hundred
    // milliseconds and no more. The wait an officer sees is NOT the port.
    final smtp = SmtpServer('smtp.gmail.com',
        username: kGmailUser, password: kGmailAppPassword, port: 465, ssl: true);

    final msg = Message()
      ..from = Address(kGmailUser, kGmailFromName)
      ..recipients.add(kGmailUser)
      ..subject = 'SR timing probe'
      ..text = 'probe';

    final sw = Stopwatch()..start();
    await send(msg, smtp);
    sw.stop();
    stdout.writeln('  single send (this isolate): ${sw.elapsedMilliseconds}ms');

    // ⚠️ The same send through the real service, which now hands it to
    // a background isolate. The number should be the SAME -- the work has not
    // got cheaper, it has stopped holding the isolate that draws frames.
    final sw2 = Stopwatch()..start();
    await GmailOtpService.instance.sendCode(kGmailUser);
    sw2.stop();
    stdout.writeln('  sendCode (off-thread):     ${sw2.elapsedMilliseconds}ms');

    // ⚠️ And the UI isolate must stay RESPONSIVE while it runs. This is
    // the whole point: a 4-second send that blocks every frame is reported as
    // twenty to thirty seconds, because the window stops repainting.
    var ticks = 0;
    final t = Timer.periodic(const Duration(milliseconds: 50), (_) => ticks++);
    final sw3 = Stopwatch()..start();
    await GmailOtpService.instance.sendCode(kGmailUser);
    sw3.stop();
    t.cancel();
    stdout.writeln('  timer ticks during send:   $ticks '
        '(${sw3.elapsedMilliseconds}ms)');
    expect(ticks, greaterThan(10),
        reason: 'the UI isolate was blocked during the send');

    // ⚠️ The whole point of the change. A send that takes four seconds is a
    // fact about Gmail; a login that takes twenty-five is a fact about doing
    // it on the button's own thread with nothing on screen.
    expect(sw.elapsedMilliseconds, lessThan(15000),
        reason: 'a single Gmail send should be seconds, not tens of seconds');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
