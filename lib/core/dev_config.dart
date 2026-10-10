import 'package:flutter/foundation.dart';

/// ⚠️ DEVELOPMENT / TESTING TOGGLES.
///
/// When [kDevSkipOtp] is true, the OTP-gated portals (Central Disposal,
/// Valuation, Appeal, Executive, ICT) sign in with the password ONLY — the
/// emailed one-time code step is skipped. The password is still verified, so
/// this is a testing convenience, not an auth removal.
///
/// ── Why this is not just a `const bool` any more ────────────────────────────
///
/// It used to be one line that a developer flipped to `true` and was expected
/// to remember to flip back. That is a bypass of second-factor authentication
/// for every privileged portal, one forgotten line away from shipping — and
/// nothing about the built .exe would say so. The comment said "flip back
/// before shipping", which is a note, not a control.
///
/// So the flag is now the AND of two things:
///
///   * `!kReleaseMode` — a release build can never skip OTP, whatever the
///     source says. This is the part that cannot be forgotten: even with the
///     define set, the shipped build requires the code.
///   * `--dart-define=DEV_SKIP_OTP=true` — an explicit, per-build opt-in, so
///     skipping OTP is a thing someone typed on the command line for one
///     build rather than a state the repository can be left in.
///
/// ⚠️ `kReleaseMode`, not `!kDebugMode`: a PROFILE build is neither debug nor
/// release, and profile is what performance runs use. Keying off kDebugMode
/// would have left profile builds able to skip OTP.
const bool _devSkipOtpDefine = bool.fromEnvironment('DEV_SKIP_OTP');

/// True only in a non-release build that explicitly asked to skip OTP.
///
/// Run without it, and every portal requires the emailed code:
///
///     flutter run --dart-define=DEV_SKIP_OTP=true
const bool kDevSkipOtp = _devSkipOtpDefine && !kReleaseMode;

/// Whether OTP is being enforced for the privileged portals.
///
/// Always true in a release build. Exposed so a screen or a diagnostic can
/// state the fact rather than infer it.
const bool kOtpEnforced = !kDevSkipOtp;
