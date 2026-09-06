import 'dart:math';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';

import '../core/otp_config.dart';

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

class GmailOtpService {
  GmailOtpService._();
  static final GmailOtpService instance = GmailOtpService._();

  final Map<String, _OtpEntry> _codes = {};
  static const Duration _ttl = Duration(minutes: 5);
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
    final smtp = gmail(kGmailUser, kGmailAppPassword);
    final message = Message()
      ..from = Address(kGmailUser, kGmailFromName)
      ..recipients.add(email.trim())
      ..subject = c.subject
      ..html = _shell(
        heading: c.heading,
        recipientName: recipientName,
        body: '''
  <p style="margin:0 0 6px">${c.lead}</p>
  <p style="font-size:30px;font-weight:bold;letter-spacing:8px;color:#111;
            margin:14px 0">$code</p>
  <p style="color:#555;margin:0">This code expires in ${_ttl.inMinutes}
     minutes.</p>
  <p style="color:#555;margin:10px 0 0">${c.unexpected}</p>''',
      );

    try {
      await send(message, smtp);
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

    final smtp = gmail(kGmailUser, kGmailAppPassword);
    final message = Message()
      ..from = Address(kGmailUser, kGmailFromName)
      ..recipients.add(email.trim())
      ..subject = isReissue
          ? 'Your SL Customs sign-in details have been reissued'
          : 'Welcome to SL Customs — your account is ready'
      ..html = _shell(
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
  <p style="color:#555;margin:10px 0 0">${isReissue ? 'If you did not ask for new sign-in details, tell your administrator at once — someone else has reset your account.' : 'Keep this e-mail until you have changed the password, then delete it: it carries a working credential.'}</p>''',
      );
    await send(message, smtp);
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
  /// returns normally (and consumes the code) on success.
  void verifyCode(String email, String code) {
    final key = _norm(email);
    final entry = _codes[key];
    if (entry == null) {
      throw Exception('No verification code was sent. Please request a new one.');
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
    _codes.remove(key);
  }
}
