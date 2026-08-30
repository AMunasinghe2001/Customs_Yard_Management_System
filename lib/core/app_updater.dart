import 'dart:io';
import 'package:auto_updater/auto_updater.dart';
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
    String.fromEnvironment('UPDATE_FEED_URL', defaultValue: '');

/// How often (seconds) to re-check for updates while the app stays open.
const int _checkIntervalSeconds = 6 * 60 * 60; // 6 hours

/// Wires up background auto-updates. Desktop-only (Windows/macOS via WinSparkle/
/// Sparkle). Safe to call unconditionally — every failure is swallowed so a
/// missing feed / offline machine / unsupported platform never blocks startup.
Future<void> initAutoUpdater() async {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  // No feed configured — nothing to check against.
  if (updateFeedUrl.isEmpty) return;
  try {
    await autoUpdater.setFeedURL(updateFeedUrl);
    await autoUpdater.setScheduledCheckInterval(_checkIntervalSeconds);
    // inBackground: true → silent check; the framework prompts the user only
    // when a newer version is actually published in the appcast.
    await autoUpdater.checkForUpdates(inBackground: true);
  } catch (e) {
    // ignore: avoid_print
    print('DEBUG: auto-updater init failed: $e');
  }
}

/// User-triggered "Check for Updates" (e.g. from a menu/button). Shows the
/// updater UI even when already up to date.
Future<void> checkForUpdatesNow() async {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  // No feed configured — nothing to check against.
  if (updateFeedUrl.isEmpty) return;
  try {
    await autoUpdater.setFeedURL(updateFeedUrl);
    await autoUpdater.checkForUpdates();
  } catch (e) {
    // ignore: avoid_print
    print('DEBUG: manual update check failed: $e');
  }
}
