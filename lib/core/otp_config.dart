import 'app_env.dart';

// ============================================================================
//  OTP e-mail (Gmail SMTP) configuration
// ----------------------------------------------------------------------------
//  Every OTP e-mail (login + sign-up) is sent DIRECTLY from the app over Gmail
//  SMTP — NOT through Supabase — so it is not subject to Supabase's free-tier
//  limit of ~2 OTP e-mails per hour. See lib/services/otp_service.dart.
//
//  ── Setup ──────────────────────────────────────────────────────────────────
//   1. The sender Gmail account must have 2-Step Verification ON.
//   2. Google Account → Security → App passwords → generate a 16-char password
//      (this is NOT the normal Gmail password).
//   3. Put them in `.env` beside the app (copy `.env.example` to start):
//          GMAIL_USER=...
//          GMAIL_APP_PASSWORD=...
//      or override at build time with --dart-define=GMAIL_USER=... etc.
//
//  ⚠️ Whichever route you pick, the credentials reach the user's machine —
//     in the binary, or in a file next to it — so anyone running the app can
//     recover them. Use a DEDICATED Gmail account, never a personal one.
//     Free Gmail sends ~500 e-mails/day.
//
//  ⚠️ There are no longer any default values here. Until `.env` is filled in,
//     kGmailConfigured is false and the app reports that e-mail is not set up
//     rather than silently using someone's old account.
// ============================================================================

const String _gmailUserDefine = String.fromEnvironment('GMAIL_USER');
const String _gmailPassDefine = String.fromEnvironment('GMAIL_APP_PASSWORD');
const String _gmailNameDefine = String.fromEnvironment('GMAIL_FROM_NAME');

/// The Gmail address that sends the OTP e-mails.
String get kGmailUser =>
    AppEnv.read('GMAIL_USER', dartDefine: _gmailUserDefine, fallback: '');

/// A 16-character Google App Password for [kGmailUser] (spaces removed).
///
/// ⚠️ There is deliberately NO default. An earlier version hard-coded a real
/// App Password here, and it is still in the git history (commit 875e445) —
/// anyone with the repo can read it. That password should be REVOKED in the
/// Google account and a fresh one put in `.env`.
String get kGmailAppPassword => AppEnv.read('GMAIL_APP_PASSWORD',
    dartDefine: _gmailPassDefine, fallback: '');

/// Display name shown as the sender.
String get kGmailFromName => AppEnv.read('GMAIL_FROM_NAME',
    dartDefine: _gmailNameDefine, fallback: 'SL Customs');

/// True once the Gmail credentials have been provided.
bool get kGmailConfigured =>
    kGmailUser.trim().isNotEmpty && kGmailAppPassword.trim().isNotEmpty;
