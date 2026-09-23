import 'package:flutter/material.dart';
import 'dart:io';
import 'package:auto_updater/auto_updater.dart';

import 'app_log.dart';
/// Where the installer and the `appcast.xml` feed are published.
///
/// This used to be derived from the Supabase project URL, because the feed
/// lived in a public Storage bucket. The office PostgreSQL server serves the
/// database and nothing else — it has no HTTP endpoint to host a file — so the
/// feed now needs somewhere of its own: a share on the server PC behind IIS or
/// nginx, or any internal web server.
///
/// Set it at build time:
///     --dart-define=UPDATE_FEED_URL=http://192.168.1.50/updates/appcast.xml
///
/// Left empty, auto-update is simply off: initAutoUpdater() returns without
/// doing anything, which is the right behaviour for an office that installs
/// releases by hand.
const String updateFeedUrl =
    String.fromEnvironment('UPDATE_FEED_URL', defaultValue: 'https://knqpwufqpcoevjaxuihp.supabase.co/storage/v1/object/public/updates/appcast.xml');

/// Allow an update feed served over plain HTTP.
///
/// ⚠️ The appcast decides which installer this app downloads and RUNS. Over
/// HTTP, anyone able to answer for that host — or sit on the path — can point
/// it at their own .exe and the updater will fetch and execute it with the
/// user's privileges. That is remote code execution, not eavesdropping, so an
/// http:// feed is refused unless a deployment says explicitly that it accepts
/// the risk on a trusted LAN.
const bool allowInsecureUpdateFeed =
    bool.fromEnvironment('ALLOW_INSECURE_UPDATE_FEED');

/// Whether [updateFeedUrl] is safe to hand to the updater.
///
/// https:// always passes. http:// passes only with the opt-in above, and to a
/// loopback or private-range host — an internal IIS box is the intended case;
/// a public http:// URL is refused outright, because no opt-in makes that
/// anything but an invitation to ship someone else's binary.
bool isUpdateFeedAcceptable(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  if (!allowInsecureUpdateFeed) return false;
  return _isPrivateHost(uri.host);
}

/// Loopback, RFC1918 and link-local ranges — the addresses that cannot be
/// routed in from the internet.
bool _isPrivateHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.startsWith('127.') || h == '::1') return true;
  if (h.startsWith('10.') || h.startsWith('192.168.')) return true;
  if (h.startsWith('169.254.')) return true;
  // 172.16.0.0 – 172.31.255.255
  final m = RegExp(r'^172\.(\d{1,2})\.').firstMatch(h);
  if (m != null) {
    final second = int.tryParse(m.group(1)!) ?? 0;
    if (second >= 16 && second <= 31) return true;
  }
  return false;
}

/// Logs and rejects a feed that fails the check, so a misconfigured build is
/// visible rather than silently updating over an unauthenticated channel.
bool _feedAllowed() {
  if (isUpdateFeedAcceptable(updateFeedUrl)) return true;
  AppLog.security('refusing update feed "$updateFeedUrl" — use https://, or '
      'set ALLOW_INSECURE_UPDATE_FEED=true for an internal http:// host.');
  return false;
}

/// Wires up background auto-updates. Desktop-only (Windows/macOS via WinSparkle/
/// Sparkle). Safe to call unconditionally — every failure is swallowed so a
/// missing feed / offline machine / unsupported platform never blocks startup.
Future<void> initAutoUpdater() async {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  // No feed configured — nothing to check against.
  if (updateFeedUrl.isEmpty) return;
  if (!_feedAllowed()) return;
  try {
    // ⚠️ THE FEED IS SET, BUT NO AUTOMATIC CHECK IS STARTED.
    //
    // WinSparkle draws its own native Win32 window -- grey, with its own
    // sun icon and its own fonts. Nothing in this package exposes its
    // colours or layout, because the dialog belongs to a C library rather
    // than to Flutter.
    //
    // The app already has a themed strip for this
    // (widgets/update_banner.dart), fed by core/update_check.dart. Running
    // both meant the officer got the native window ON TOP of the app's own
    // notice, which is the one that matches everything else they use.
    //
    // So the feed is registered -- that is what makes the "Check for
    // Updates" button work, and WinSparkle's window is reasonable when
    // somebody ASKED for it -- but the unattended check stays off, and
    // the strip is what appears by itself.
    await autoUpdater.setFeedURL(updateFeedUrl);
  } catch (e) {
    AppLog.warn('auto-updater init failed', error: e, tag: 'update');
  }
}

/// What a user-triggered check was able to do.
///
/// ⚠️ The check itself CANNOT report "you are up to date" — WinSparkle owns
/// that conversation and puts its own window on screen. What this does tell
/// the caller is whether the check ran at all, which is the part an officer
/// otherwise cannot see: a build with no feed, or one whose feed was
/// refused, looks exactly like a button that does nothing.
enum UpdateCheckOutcome {
  /// WinSparkle was handed the feed and is now showing its own UI.
  started,

  /// This build was compiled without UPDATE_FEED_URL, so it never checks.
  notConfigured,

  /// The feed was rejected — see [isUpdateFeedAcceptable].
  feedRefused,

  /// Desktop-only; nothing to do on other platforms.
  unsupportedPlatform,

  /// The updater threw. Offline, usually.
  failed,
}

/// User-triggered "Check for Updates" (e.g. from a menu/button). Shows the
/// updater UI even when already up to date.
///
/// Returns what happened so the caller can say something useful instead of
/// leaving a button that appears dead.
Future<UpdateCheckOutcome> checkForUpdatesNow() async {
  if (!(Platform.isWindows || Platform.isMacOS)) {
    return UpdateCheckOutcome.unsupportedPlatform;
  }
  // No feed configured — nothing to check against.
  if (updateFeedUrl.isEmpty) return UpdateCheckOutcome.notConfigured;
  if (!_feedAllowed()) return UpdateCheckOutcome.feedRefused;
  try {
    await autoUpdater.setFeedURL(updateFeedUrl);
    await autoUpdater.checkForUpdates();
    return UpdateCheckOutcome.started;
  } catch (e) {
    AppLog.warn('manual update check failed', error: e, tag: 'update');
    return UpdateCheckOutcome.failed;
  }
}

/// "Check for Updates", from wherever a portal offers it.
///
/// ⚠️ ONE implementation, called from both shells. The Yard portal
/// (widgets/app_shell.dart) and the ICT console (screens/ict/) have
/// separate headers -- the console never uses AppShell -- so a second
/// copy of this logic would be the obvious way to add the button there,
/// and the two would drift the first time one was corrected.
///
/// ⚠️ WinSparkle owns the conversation once the check STARTS: it
/// puts its own window on screen whether or not anything is newer. So
/// this reports only the cases it will never show a window for --
/// otherwise an officer on a build with no feed presses a button that
/// does nothing at all and reasonably concludes the app is broken.
Future<void> runUpdateCheck(
  BuildContext context, {
  String? pendingVersion,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  // The start-up check already found a release. Say so rather than
  // making them wait for a second answer to the same question.
  if (pendingVersion != null) {
    messenger.showSnackBar(SnackBar(
      content: Text('Version $pendingVersion is available.'),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }

  final outcome = await checkForUpdatesNow();
  if (!context.mounted) return;

  final String? message;
  switch (outcome) {
    case UpdateCheckOutcome.started:
      // WinSparkle is showing its own window now; a snack bar on top
      // of it would just be noise.
      message = null;
    case UpdateCheckOutcome.notConfigured:
      message = 'This build does not check for updates. '
          'Ask ICT for the latest installer.';
    case UpdateCheckOutcome.feedRefused:
      message = 'The update source is not trusted, so it was not used. '
          'Tell ICT.';
    case UpdateCheckOutcome.unsupportedPlatform:
      message = 'Updates are checked on Windows only.';
    case UpdateCheckOutcome.failed:
      message = 'Could not reach the update server. '
          'Check the connection and try again.';
  }
  if (message != null) {
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
