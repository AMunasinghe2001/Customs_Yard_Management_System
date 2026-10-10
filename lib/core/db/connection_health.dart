import 'package:flutter/foundation.dart';

/// Whether the app can currently reach the database.
///
/// ⚠️ Exists because a branch office is no longer on the office LAN. On the
/// LAN a dropped link meant the server was down and somebody walked over to
/// it; over the internet it usually means *this* PC lost its connection, and
/// the officer needs to be told that rather than watching a screen that
/// quietly renders nothing.
///
/// `_withNetworkRetry` already retries the transient cases — it is the only
/// thing that knows whether a failure was a dropped socket or a genuine error
/// — so this records what it saw and the UI reads it. No polling and no extra
/// connections: the signal comes from traffic the app was making anyway.
///
/// A `ValueNotifier` rather than a provider because the connection layer sits
/// below Riverpod and must not depend on it; the banner listens directly.
class ConnectionHealth {
  ConnectionHealth._();

  /// True while the last database attempt failed for a transport reason and
  /// nothing has succeeded since.
  static final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  /// What went wrong, for the banner's detail line. Null when online.
  static final ValueNotifier<String?> lastReason = ValueNotifier<String?>(null);

  /// Called after any successful database call.
  ///
  /// ⚠️ Cheap on purpose: this runs on every query, and 228 call sites reach
  /// it. Assigning the same value to a ValueNotifier does not notify, so the
  /// common case — already online, still online — costs one comparison.
  static void reportSuccess() {
    offline.value = false;
    lastReason.value = null;
  }

  /// Called when a database call failed for a TRANSPORT reason, after the
  /// retries are exhausted.
  ///
  /// ⚠️ Only transport failures. A permission denial or a constraint
  /// violation is the database answering, which means the link is fine — a
  /// banner there would blame the network for a bug.
  static void reportOffline(String reason) {
    lastReason.value = reason;
    offline.value = true;
  }

  /// Turns a raw exception into something an officer can act on.
  ///
  /// The distinction that matters to them is WHOSE fault it is: their own
  /// internet, or the office end. They can do something about the first.
  static String describe(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('failed host lookup')) {
      return 'The server address could not be resolved. This PC may have no '
          'internet connection.';
    }
    if (s.contains('timed out') || s.contains('timeout')) {
      return 'The server did not respond in time. The connection may be slow '
          'or interrupted.';
    }
    if (s.contains('refused')) {
      return 'The server refused the connection. It may be restarting, or the '
          'office link may be down.';
    }
    if (s.contains('certificate') || s.contains('handshake')) {
      return 'The secure connection could not be established. The server '
          'certificate may have changed — contact ICT before continuing.';
    }
    return 'The connection to the office server was lost.';
  }
}
