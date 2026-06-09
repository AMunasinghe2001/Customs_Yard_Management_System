import 'dart:io';
import 'package:auto_updater/auto_updater.dart';
import 'supabase_client.dart';

/// PUBLIC Supabase Storage bucket that holds the Windows installer (.exe) and
/// the `appcast.xml` feed. Create a public bucket with this name and upload
/// both files there on every release.
const String kUpdatesBucket = 'updates';

/// Appcast feed URL, derived from the active Supabase project so it always
/// points at the same backend the app is already using.
/// → https://<project>.supabase.co/storage/v1/object/public/updates/appcast.xml
String get updateFeedUrl =>
    '$supabaseUrl/storage/v1/object/public/$kUpdatesBucket/appcast.xml';

/// How often (seconds) to re-check for updates while the app stays open.
const int _checkIntervalSeconds = 6 * 60 * 60; // 6 hours

/// Wires up background auto-updates. Desktop-only (Windows/macOS via WinSparkle/
/// Sparkle). Safe to call unconditionally — every failure is swallowed so a
/// missing feed / offline machine / unsupported platform never blocks startup.
Future<void> initAutoUpdater() async {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
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
  try {
    await autoUpdater.setFeedURL(updateFeedUrl);
    await autoUpdater.checkForUpdates();
  } catch (e) {
    // ignore: avoid_print
    print('DEBUG: manual update check failed: $e');
  }
}
