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
//   3. Fill in the two values below (or override at build time with
//      --dart-define=GMAIL_USER=... --dart-define=GMAIL_APP_PASSWORD=...).
//
//  ⚠️ These credentials are compiled into the app binary. Fine for an internal
//     desktop tool, but anyone with the binary can extract them — use a
//     dedicated Gmail account, not a personal one. Free Gmail sends ~500
//     e-mails/day.
// ============================================================================

/// The Gmail address that sends the OTP e-mails.
const String kGmailUser = String.fromEnvironment(
  'GMAIL_USER',
  defaultValue: 'otpproject3@gmail.com',
);

/// A 16-character Google App Password for [kGmailUser] (spaces removed).
const String kGmailAppPassword = String.fromEnvironment(
  'GMAIL_APP_PASSWORD',
  defaultValue: 'ugtidrtwitbdtcha',
);

/// Display name shown as the sender.
const String kGmailFromName = String.fromEnvironment(
  'GMAIL_FROM_NAME',
  defaultValue: 'SL Customs',
);

/// True once the Gmail credentials have been provided.
bool get kGmailConfigured =>
    kGmailUser.trim().isNotEmpty && kGmailAppPassword.trim().isNotEmpty;
