import 'dart:isolate';
import 'dart:math';

import 'package:mailer/smtp_server.dart';

import 'package:mailer/mailer.dart';

import '../core/otp_config.dart';
import 'package:flutter/foundation.dart';

class _OtpEntry {
  final String code;
  final DateTime expiresAt;
  int attempts;
  _OtpEntry(this.code, this.expiresAt, this.attempts);
}

/// Self-issued OTP delivered over **Gmail SMTP** — no Supabase involvement, so
/// it is not limited by Supabase's free-tier email quota (~2/hour). Codes are
/// generated, e-mailed and verified in-memory within this app instance (the
/// same instance both sends and verifies during a login / sign-up), so no
/// backend or database is needed for the code itself.
///
/// Configure the sender in [kGmailUser] / [kGmailAppPassword] (otp_config.dart).
/// What a one-time code is FOR. The e-mail says so — see
/// [GmailOtpService._copy].
enum OtpPurpose { signIn, createAccount, passwordReset, officerAccount }

/// The wording for one [OtpPurpose].
class _PurposeCopy {
  final String subject;
  final String heading;
  final String lead;

  /// What to do if the reader did not ask for this. ⚠️ Different per purpose:
  /// an unexpected sign-in code means someone has your password; an unexpected
  /// account code means someone typed your address by mistake.
  final String unexpected;

  const _PurposeCopy({
    required this.subject,
    required this.heading,
    required this.lead,
    required this.unexpected,
  });
}

/// Everything one e-mail needs, flat enough to cross an isolate boundary.
///
/// ⚠️ A `Message` cannot be sent to an isolate -- it is not a simple
/// value -- so the pieces travel and the message is built on the far side.
class _MailJob {
  final String user;
  final String pass;
  final String fromName;
  final String to;
  final String subject;
  final String html;

  const _MailJob({
    required this.user,
    required this.pass,
    required this.fromName,
    required this.to,
    required this.subject,
    required this.html,
  });
}

/// Send one message. Runs INSIDE a background isolate.
///
/// ⚠️ Top-level and static by necessity: `Isolate.run` can only take a
/// closure that captures sendable values, so this must not touch `this`.
Future<void> _sendInIsolate(_MailJob job) async {
  // ⚠️ Port 465 with implicit TLS, not the package's 587 default.
  // Measured on this machine: TCP connect is 91ms to 465 against 184ms to
  // 587, and a full send 3101ms against 3360ms. Worth taking, but small --
  // the port was never where the twenty seconds went.
  final smtp = SmtpServer('smtp.gmail.com',
      username: job.user, password: job.pass, port: 465, ssl: true);
  final message = Message()
    ..from = Address(job.user, job.fromName)
    ..recipients.add(job.to)
    ..subject = job.subject
    ..html = job.html;
  await send(message, smtp);
}

/// Send one message off the UI isolate.
///
/// ⚠️ THIS is the fix. A Gmail send measures ~4.2 seconds of TLS
/// handshake and socket waiting, and it was being done on the isolate that
/// draws the screen -- so every frame stopped, the spinner froze, and the
/// wait an officer reported was twenty to thirty seconds rather than four.
/// The work is identical; it simply no longer holds the UI.
Future<void> _sendOffThread(_MailJob job) =>
    Isolate.run(() => _sendInIsolate(job));

class GmailOtpService {
  GmailOtpService._();
  static final GmailOtpService instance = GmailOtpService._();

  final Map<String, _OtpEntry> _codes = {};

  /// How long a code stays valid. ⚠️ THE one source of truth: the e-mail
  /// text, every on-screen countdown and the server-side check all read this.
  ///
  /// They did not. The countdown was a literal `120` copied into twelve
  /// screens while this said five minutes, so the e-mail promised five, the
  /// screen expired at two, and the code went on working for three minutes
  /// after the UI said it had not.
  static const Duration codeLifetime = Duration(minutes: 5);
  static const Duration _ttl = codeLifetime;
  static const int _maxAttempts = 5;

  String _generate() => (100000 + Random.secure().nextInt(900000)).toString();
  String _norm(String email) => email.trim().toLowerCase();

  /// Why a code is being sent, so the e-mail can say so.
  ///
  /// ⚠️ Every one of these used to arrive as the same message: "Your SL
  /// Customs verification code", with no hint of what it unlocked. A code for
  /// a password reset and a code for a new account are very different things
  /// to receive — one is expected, the other may be a stranger using your
  /// address — and the reader can only judge that if the e-mail says which.
  ///
  /// It also matters for a code the reader did NOT request: "someone tried to
  /// sign in" and "someone is creating an account with your address" call for
  /// different action.
  static const Map<OtpPurpose, _PurposeCopy> _copy = {
    OtpPurpose.signIn: _PurposeCopy(
      subject: 'Your SL Customs sign-in code',
      heading: 'Signing in',
      lead: 'Use this code to finish signing in to the SR Management System:',
      unexpected:
          'If you did not try to sign in, someone else may have your password '
          '— change it and tell your administrator.',
    ),
    OtpPurpose.createAccount: _PurposeCopy(
      subject: 'Confirm your SL Customs account',
      heading: 'Creating your account',
      lead: 'Use this code to confirm your e-mail address and finish creating '
          'your account:',
      unexpected:
          'If you did not ask for an account, someone has used your address by '
          'mistake. Ignore this e-mail — nothing is created until the code is '
          'entered.',
    ),
    OtpPurpose.passwordReset: _PurposeCopy(
      subject: 'Reset your SL Customs password',
      heading: 'Resetting your password',
      lead: 'Use this code to set a new password:',
      unexpected:
          'If you did not ask to reset your password, ignore this e-mail. Your '
          'current password still works and nothing has changed.',
    ),
    OtpPurpose.officerAccount: _PurposeCopy(
      subject: 'Confirm your SL Customs officer account',
      heading: 'Confirming your officer account',
      lead: 'An administrator is setting up your officer account. Use this '
          'code to confirm your e-mail address:',
      unexpected:
          'If you were not expecting this, ignore the e-mail and tell your '
          'administrator — nothing is created until the code is entered.',
    ),
  };

  /// Generate a 6-digit code, e-mail it via Gmail and remember it for
  /// verification. Throws Exception(message) if e-mail can't be sent.
  ///
  /// [purpose] chooses the wording — see [_copy].
  Future<void> sendCode(
    String email, {
    String? recipientName,
    OtpPurpose purpose = OtpPurpose.signIn,
  }) async {
    if (!kGmailConfigured) {
      throw Exception(
          'E-mail is not configured. Add the Gmail address and App Password '
          'in lib/core/otp_config.dart.');
    }
    final key = _norm(email);
    final code = _generate();
    _codes[key] = _OtpEntry(code, DateTime.now().add(_ttl), 0);

    final c = _copy[purpose]!;
    final html =
        _shell(heading: c.heading, recipientName: recipientName, body: '''
  <p style="margin:0 0 6px">${c.lead}</p>
  <p style="font-size:30px;font-weight:bold;letter-spacing:8px;color:#111;
            margin:14px 0">$code</p>
  <p style="color:#555;margin:0">This code expires in ${_ttl.inMinutes}
     minutes.</p>
  <p style="color:#555;margin:10px 0 0">${c.unexpected}</p>''');

    try {
      await _sendOffThread(_MailJob(
        user: kGmailUser,
        pass: kGmailAppPassword,
        fromName: kGmailFromName,
        to: email.trim(),
        subject: c.subject,
        html: html,
      ));
    } catch (_) {
      _codes.remove(key);
      throw Exception('Could not send the verification e-mail. Please check '
          'your connection and the Gmail configuration, then try again.');
    }
  }

  /// E-mail a newly-created officer their sign-in credentials (via Gmail).
  ///
  /// ⚠️ [isReissue] changes what this says, and it must. A WELCOME to an
  /// account you were expecting reads very differently from "your password has
  /// been changed" arriving unannounced — the second is the one that has to
  /// tell the reader what to do if it was not them.
  ///
  /// Throws Exception(message) if the e-mail can't be sent.
  Future<void> sendCredentials(
    String email,
    String fullName,
    String username,
    String password, {
    bool isReissue = false,
    String? roleLabel,
  }) async {
    if (!kGmailConfigured) {
      throw Exception('E-mail is not configured. Add the Gmail address and App '
          'Password in lib/core/otp_config.dart.');
    }
    final who = (roleLabel != null && roleLabel.trim().isNotEmpty)
        ? roleLabel.trim()
        : 'officer';

    final html = _shell(
        heading: isReissue ? 'New sign-in details' : 'Welcome aboard',
        recipientName: fullName,
        body: '''
  <p style="margin:0 0 10px">${isReissue ? 'Your $who sign-in details have been reissued. The previous password no longer works. Use these from now on:' : 'Your $who account has been created. Welcome to the SR Management System — use these details to sign in for the first time:'}</p>
  <table style="border-collapse:collapse;margin:12px 0;background:#f6f7fb;
                border-radius:8px">
    <tr><td style="padding:8px 14px;color:#555"><b>Username</b></td>
        <td style="padding:8px 14px;font-family:monospace;font-size:15px">$username</td></tr>
    <tr><td style="padding:8px 14px;color:#555"><b>Password</b></td>
        <td style="padding:8px 14px;font-family:monospace;font-size:15px">$password</td></tr>
  </table>
  <p style="color:#555;margin:0">You can sign in with your
     <b>username or e-mail</b>. Please change this password from
     <b>Edit Profile</b> once you are in.</p>
  <p style="color:#555;margin:10px 0 0">${isReissue ? 'If you did not ask for new sign-in details, tell your administrator at once — someone else has reset your account.' : 'Keep this e-mail until you have changed the password, then delete it: it carries a working credential.'}</p>''');
    // ⚠️ Off the UI isolate, like the OTP send. This one runs while an
    // admin waits on the officer-creation dialog, and a frozen dialog reads
    // as a hung app -- so they press the button again and a second officer
    // is created.
    await _sendOffThread(_MailJob(
      user: kGmailUser,
      pass: kGmailAppPassword,
      fromName: kGmailFromName,
      to: email.trim(),
      subject: isReissue
          ? 'Your SL Customs sign-in details have been reissued'
          : 'Welcome to SL Customs — your account is ready',
      html: html,
    ));
  }

  /// The frame every one of these e-mails shares, so they read as one system
  /// rather than as several.
  static String _shell({
    required String heading,
    required String body,
    String? recipientName,
  }) {
    final greeting = (recipientName != null && recipientName.trim().isNotEmpty)
        ? '<p style="margin:0 0 10px">Hello ${recipientName.trim()},</p>'
        : '';
    return '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:auto;
            padding:24px;color:#222">
  <h2 style="color:#1a1764;margin:0 0 2px">Sri Lanka Customs</h2>
  <p style="color:#777;margin:0 0 18px;font-size:13px">SR Management System</p>
  <p style="margin:0 0 14px;font-size:17px;font-weight:bold;color:#1a1764">
    $heading</p>
  $greeting
  $body
  <hr style="border:none;border-top:1px solid #e5e7eb;margin:22px 0 10px">
  <p style="color:#999;font-size:12px;margin:0">This is an automated message
     from the Sri Lanka Customs SR Management System. Please do not reply.</p>
</div>''';
  }

  /// Verify [code] for [email]. Throws Exception(message) on any failure;
  /// returns normally on success.
  ///
  /// ⚠️ By default this CONSUMES the code, which is right when verifying is
  /// the last thing that can fail. It is wrong when more work follows: the
  /// password reset verified the code, then failed on the new password (too
  /// short, or one used before) -- and the code was already gone. Pressing
  /// the button again reported "No verification code was sent", so the
  /// officer was told the code was missing when the real complaint was about
  /// the password, and was bounced back to re-enter a code that no longer
  /// existed.
  ///
  /// Pass [consume] false to check without spending it, then call
  /// [consumeCode] once the whole operation has succeeded.
  void verifyCode(String email, String code, {bool consume = true}) {
    final key = _norm(email);
    final entry = _codes[key];
    if (entry == null) {
      throw Exception(
          'No verification code was sent. Please request a new one.');
    }
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _codes.remove(key);
      throw Exception('The code has expired. Please resend.');
    }
    if (entry.attempts >= _maxAttempts) {
      _codes.remove(key);
      throw Exception('Too many attempts. Please resend a new code.');
    }
    if (entry.code != code.trim()) {
      entry.attempts++;
      throw Exception('Invalid code. Please try again.');
    }
    if (consume) _codes.remove(key);
  }

  /// Spend a code that [verifyCode] already accepted. Safe to call when the
  /// code is gone -- a completed reset should not fail on its own cleanup.
  void consumeCode(String email) => _codes.remove(_norm(email));

  /// Issue a code for [email] WITHOUT sending an e-mail. Tests only: the
  /// consume/retain behaviour cannot be exercised otherwise without a live
  /// SMTP round trip.
  @visibleForTesting
  String debugSeedCode(String email) {
    final code = _generate();
    _codes[_norm(email)] = _OtpEntry(code, DateTime.now().add(_ttl), 0);
    return code;
  }
}
