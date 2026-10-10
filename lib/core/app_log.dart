import 'package:flutter/foundation.dart';

/// The one place that decides what reaches the console.
///
/// Before this, the app used bare `print()` in 40 places. `print` is NOT
/// stripped from a release build — it writes to stdout in the shipped .exe
/// exactly as it does in debug — and several of those lines carried real user
/// data: the e-mail being signed in with, the signed-in user's id, and the
/// code/status/message of failed authentication attempts. On a shared office
/// PC that is a log of who logged in and when, readable by anyone who starts
/// the app from a console or captures its output.
///
/// So the rule here is simple and deliberately hard to get wrong:
///
///   * [debug] — developer noise. **Compiled out of release entirely.**
///   * [warn] / [error] — operational problems worth seeing in the field, but
///     written WITHOUT the payload: a message the developer chose, never an
///     interpolated user record.
///   * [security] — refusals and policy failures. These survive into release
///     on purpose: an update feed rejected for being unsigned HTTP is exactly
///     the line an administrator needs to find.
///
/// ⚠️ The guard is `kReleaseMode`, not `kDebugMode`. They are not opposites:
/// a PROFILE build is neither, and profile builds are what performance work
/// runs on. Keying off `kDebugMode` would silence profile runs too, which is
/// how a timing problem becomes invisible exactly when someone is measuring
/// it. Only release — the build officers actually receive — is quiet.
class AppLog {
  AppLog._();

  /// Whether verbose developer output is allowed. False in release builds.
  ///
  /// Exposed so a caller can skip EXPENSIVE work that only feeds a log line —
  /// building a big string, walking a list — rather than computing it and
  /// throwing it away.
  static bool get verbose => !kReleaseMode;

  /// Developer tracing. Never appears in a release build.
  ///
  /// Use freely: because the whole call is behind [verbose], anything
  /// interpolated here is also absent from release. This is the right home for
  /// a line that names a user, an id or a query.
  static void debug(String message, {String? tag}) {
    if (kReleaseMode) return;
    debugPrint(tag == null ? message : '[$tag] $message');
  }

  /// Something failed but the app carried on.
  ///
  /// ⚠️ [message] must describe WHAT failed, not the data it failed on. The
  /// exception goes in [error] and is printed only outside release, because an
  /// exception's `toString()` is the usual way a record or a credential ends
  /// up in a log without anyone intending it — a Postgres error quotes the row
  /// it rejected, and an auth error quotes the address it rejected.
  static void warn(String message, {Object? error, String? tag}) {
    final prefix = tag == null ? 'WARN' : 'WARN [$tag]';
    if (kReleaseMode) {
      debugPrint('$prefix: $message');
    } else {
      debugPrint('$prefix: $message${error == null ? '' : ' — $error'}');
    }
  }

  /// A failure the user probably noticed. Same payload rule as [warn].
  static void error(String message, {Object? error, StackTrace? stack,
      String? tag}) {
    final prefix = tag == null ? 'ERROR' : 'ERROR [$tag]';
    if (kReleaseMode) {
      debugPrint('$prefix: $message');
    } else {
      debugPrint('$prefix: $message${error == null ? '' : ' — $error'}');
      if (stack != null) debugPrint('$stack');
    }
  }

  /// A security control that refused something.
  ///
  /// Kept in release deliberately. These lines say the app declined to do
  /// something unsafe — a rejected update feed, a transport that failed
  /// policy — and an administrator diagnosing "why is auto-update off" needs
  /// to see it in the build they actually run. Write them about the
  /// CONFIGURATION, never about a user.
  static void security(String message) {
    debugPrint('SECURITY: $message');
  }
}
