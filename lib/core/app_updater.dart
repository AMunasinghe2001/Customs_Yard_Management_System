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
  // ignore: avoid_print
  print('SECURITY: refusing update feed "$updateFeedUrl" — use https://, or '
      'set ALLOW_INSECURE_UPDATE_FEED=true for an internal http:// host.');
  return false;
}

/// How often (seconds) to re-check for updates while the app stays open.
const int _checkIntervalSeconds = 6 * 60 * 60; // 6 hours

/// Wires up background auto-updates. Desktop-only (Windows/macOS via WinSparkle/
/// Sparkle). Safe to call unconditionally — every failure is swallowed so a
/// missing feed / offline machine / unsupported platform never blocks startup.
Future<void> initAutoUpdater() async {
  if (!(Platform.isWindows || Platform.isMacOS)) return;
  // No feed configured — nothing to check against.
  if (updateFeedUrl.isEmpty) return;
  if (!_feedAllowed()) return;
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
  if (!_feedAllowed()) return;
  try {
    await autoUpdater.setFeedURL(updateFeedUrl);
    await autoUpdater.checkForUpdates();
  } catch (e) {
    // ignore: avoid_print
    print('DEBUG: manual update check failed: $e');
  }
}
