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
class GmailOtpService {
  GmailOtpService._();
  static final GmailOtpService instance = GmailOtpService._();

  final Map<String, _OtpEntry> _codes = {};
  static const Duration _ttl = Duration(minutes: 5);
  static const int _maxAttempts = 5;

  String _generate() => (100000 + Random.secure().nextInt(900000)).toString();
  String _norm(String email) => email.trim().toLowerCase();

  /// Generate a 6-digit code, e-mail it via Gmail and remember it for
  /// verification. Throws Exception(message) if e-mail can't be sent.
  Future<void> sendCode(String email, {String? recipientName}) async {
    if (!kGmailConfigured) {
      throw Exception(
          'E-mail is not configured. Add the Gmail address and App Password '
          'in lib/core/otp_config.dart.');
    }
    final key = _norm(email);
    final code = _generate();
    _codes[key] = _OtpEntry(code, DateTime.now().add(_ttl), 0);

    final smtp = gmail(kGmailUser, kGmailAppPassword);
    final message = Message()
      ..from = Address(kGmailUser, kGmailFromName)
      ..recipients.add(email.trim())
      ..subject = 'Your SL Customs verification code'
      ..html = '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:480px;margin:auto">
  <h2 style="color:#1a1764;margin-bottom:4px">Sri Lanka Customs</h2>
  <p style="color:#555;margin-top:0">SR Management System</p>
  ${recipientName != null && recipientName.trim().isNotEmpty ? '<p>Hello ${recipientName.trim()},</p>' : ''}
  <p>Your one-time verification code is:</p>
  <p style="font-size:30px;font-weight:bold;letter-spacing:8px;color:#111">$code</p>
  <p style="color:#555">This code expires in ${_ttl.inMinutes} minutes. If you
     did not request it, you can safely ignore this e-mail.</p>
</div>''';

    try {
      await send(message, smtp);
    } catch (_) {
      _codes.remove(key);
      throw Exception('Could not send the verification e-mail. Please check '
          'your connection and the Gmail configuration, then try again.');
    }
  }

  /// E-mail a newly-created officer their sign-in credentials (via Gmail).
  /// Throws Exception(message) if the e-mail can't be sent.
  Future<void> sendCredentials(
      String email, String fullName, String username, String password) async {
    if (!kGmailConfigured) {
      throw Exception('E-mail is not configured. Add the Gmail address and App '
          'Password in lib/core/otp_config.dart.');
    }
    final smtp = gmail(kGmailUser, kGmailAppPassword);
    final message = Message()
      ..from = Address(kGmailUser, kGmailFromName)
      ..recipients.add(email.trim())
      ..subject = 'Your SL Customs account is ready'
      ..html = '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:480px;margin:auto">
  <h2 style="color:#1a1764;margin-bottom:4px">Sri Lanka Customs</h2>
  <p style="color:#555;margin-top:0">SR Management System</p>
  <p>Hello ${fullName.trim()},</p>
  <p>An administrator has created your officer account. Use these credentials
     to sign in:</p>
  <table style="border-collapse:collapse;margin:12px 0">
    <tr><td style="padding:4px 12px"><b>Username</b></td>
        <td style="padding:4px 12px">$username</td></tr>
    <tr><td style="padding:4px 12px"><b>Password</b></td>
        <td style="padding:4px 12px">$password</td></tr>
  </table>
  <p style="color:#555">You can sign in with your <b>username or e-mail</b>.
     Please change your password from <b>Edit Profile</b> after your first
     login.</p>
</div>''';
    await send(message, smtp);
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
