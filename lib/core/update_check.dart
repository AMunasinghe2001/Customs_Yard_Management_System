import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';

/// The version this build IS.
///
/// ⚠️ A compile-time constant, not `package_info_plus`. The comparison below
/// decides whether to tell an officer to install something, so the number has
/// to be the one the release was cut from — and this is the same string the
/// installer stamps (`installer/setup.iss`, `AppVersion`) and the same one
/// `pubspec.yaml` carries. tool/release.ps1 keeps all three in step.
///
/// Overridable at build time so a test build can pretend to be older:
///     --dart-define=APP_VERSION=1.0.0
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.0.2');

/// Where the published release lives.
///
/// GitHub Releases, because it is free, already holds this project, serves
/// over HTTPS, and needs no web server on the database host — the cloud box
/// runs PostgreSQL and nothing else.
///
/// ⚠️ The API, not the HTML page: `/releases/latest` returns JSON naming the
/// newest tag and every file attached to it, so there is nothing to scrape.
const String kUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue: 'https://knqpwufqpcoevjaxuihp.supabase.co/storage/v1/object/public/updates/latest.json',
);

/// A release newer than the one running.
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.downloadUrl,
    this.notes = '',
    this.sizeBytes,
  });

  /// The published version, e.g. `1.2.0`.
  final String version;

  /// The installer to download — the `.exe` attached to the release.
  final String downloadUrl;

  /// What changed, as written on the release.
  final String notes;

  /// Installer size, so the officer knows what they are about to download.
  final int? sizeBytes;

  String get sizeLabel {
    final b = sizeBytes;
    if (b == null || b <= 0) return '';
    final mb = b / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Compares two dotted version strings.
///
/// Returns a negative number when [a] is older than [b], 0 when they are the
/// same release, positive when [a] is newer.
///
/// ⚠️ Compared SEGMENT BY SEGMENT as integers, never as text. `'1.10.0'` is
/// newer than `'1.9.0'`, but string comparison puts `'1.10.0'` first because
/// `'1' < '9'` — so a string compare would hide every update from 1.9 onward.
///
/// A leading `v` is tolerated (GitHub tags are usually `v1.2.0`), as is a
/// build suffix (`1.2.0+7`), which names the same release.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    var s = v.trim();
    if (s.toLowerCase().startsWith('v')) s = s.substring(1);
    s = s.split('+').first.split('-').first;
    return [
      for (final p in s.split('.')) int.tryParse(p.trim()) ?? 0,
    ];
  }

  final pa = parts(a);
  final pb = parts(b);
  // Compare over the longer of the two, treating a missing segment as 0, so
  // `1.2` and `1.2.0` are the same release rather than different ones.
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// Picks the Windows installer out of a release's attached files.
///
/// ⚠️ The `.exe`, specifically. A release also carries source archives
/// (`zipball_url`, `tarball_url`) and may carry a checksum file; handing the
/// officer a `.zip` of source code to "install" would be worse than saying
/// nothing.
Map<String, dynamic>? pickWindowsInstaller(List<dynamic> assets) {
  for (final raw in assets) {
    final a = (raw as Map).cast<String, dynamic>();
    final name = (a['name'] ?? '').toString().toLowerCase();
    if (name.endsWith('.exe')) return a;
  }
  return null;
}

/// Reads the published release and reports one only if it is NEWER.
///
/// Returns null for every ordinary "nothing to do" case — up to date, offline,
/// rate-limited, no release published yet, a release with no installer
/// attached. None of those is worth interrupting an officer over.
///
/// ⚠️ Never throws. This runs at startup, and a failed update check must not
/// be able to stop the app from opening.
Future<AvailableUpdate?> fetchAvailableUpdate({
  String currentVersion = kAppVersion,
  String manifestUrl = kUpdateManifestUrl,
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (!Platform.isWindows) return null;
  if (manifestUrl.trim().isEmpty) return null;

  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final res = await c.get(
      Uri.parse(manifestUrl),
      // GitHub asks for this; without it the API can answer with a redirect
      // to a page rather than the JSON.
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(timeout);

    if (res.statusCode != 200) {
      AppLog.warn('update check: HTTP ${res.statusCode}', tag: 'update');
      return null;
    }

    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    final json = body.cast<String, dynamic>();

    // A draft is unfinished and a prerelease is deliberately not for
    // everyone; neither should be offered to a yard.
    if (json['draft'] == true || json['prerelease'] == true) return null;

    final tag = (json['tag_name'] ?? json['name'] ?? '').toString();
    if (tag.trim().isEmpty) return null;
    if (compareVersions(currentVersion, tag) >= 0) return null;

    final asset = pickWindowsInstaller((json['assets'] as List?) ?? const []);
    if (asset == null) {
      AppLog.warn('update $tag has no .exe attached', tag: 'update');
      return null;
    }

    return AvailableUpdate(
      version: tag.toLowerCase().startsWith('v') ? tag.substring(1) : tag,
      downloadUrl: (asset['browser_download_url'] ?? '').toString(),
      notes: (json['body'] ?? '').toString().trim(),
      sizeBytes: (asset['size'] as num?)?.toInt(),
    );
  } catch (e) {
    // Offline, DNS down, timeout, malformed JSON — all the same to an
    // officer who just wants the app to open.
    AppLog.warn('update check failed', error: e, tag: 'update');
    return null;
  } finally {
    if (owned) c.close();
  }
}

/// Opens the installer's download URL in the officer's browser.
///
/// ⚠️ The browser downloads it; the app does not fetch and run an .exe
/// itself. Downloading and executing a binary silently is exactly the shape
/// of an attack, and it would also bypass SmartScreen and any antivirus
/// prompt the officer's PC would otherwise show them. The browser is the
/// place where "should I run this?" already has an answer.
Future<bool> openUpdateDownload(String url) async {
  if (!Platform.isWindows) return false;
  final uri = Uri.tryParse(url);
  // https only: this URL ends in something the officer will RUN.
  if (uri == null || uri.scheme != 'https') {
    AppLog.security('refusing to open a non-https update URL: $url');
    return false;
  }
  try {
    // ⚠️ `start` needs an empty title argument first, or it treats a quoted
    // URL as the window title and opens nothing.
    final r = await Process.run('cmd', ['/c', 'start', '', url]);
    return r.exitCode == 0;
  } catch (e) {
    AppLog.warn('could not open the update link', error: e, tag: 'update');
    return false;
  }
}

// ── The other half of an update: the DATABASE ──────────────────────────────

/// The lowest `schema_version()` this build can work against.
///
/// ⚠️ Bump this in the SAME commit as any migration the app depends on, and
/// not before. It is what turns "a column is missing" — discovered as a raw
/// Postgres error from whichever screen touches it first — into one sentence
/// naming the problem at start-up.
///
/// ⚠️ The MINIMUM, not the exact version. A database ahead of the app is
/// normal and fine: the server is migrated first, then the branches update
/// over the following days, and every older copy must keep working
/// throughout. Requiring an exact match would break every branch the moment
/// the server was touched.
const int kRequiredSchemaVersion = 43;

/// What the database reports, or null when the question could not be asked.
///
/// Null means "unknown", never "old": a database that predates
/// `schema_version()` (migration 043) answers with an error, and treating
/// that as version 0 would refuse to start against every yard that has not
/// been migrated yet — the opposite of helpful.
Future<int?> fetchSchemaVersion(
    Future<dynamic> Function(String fn) callRpc) async {
  try {
    final v = await callRpc('schema_version');
    if (v is int) return v;
    return int.tryParse('$v');
  } catch (e) {
    AppLog.warn('could not read schema_version()', error: e, tag: 'update');
    return null;
  }
}

/// The sentence to show when the database is behind this app, or null when
/// there is nothing to say.
///
/// ⚠️ Written for an officer, not an administrator: it names the version,
/// says plainly that this is not their mistake, and tells them the one thing
/// they can actually do.
String? schemaMismatchMessage(int? dbVersion,
    {int required = kRequiredSchemaVersion}) {
  if (dbVersion == null) return null; // unknown, not old — see above
  if (dbVersion >= required) return null;
  return 'This copy of the app (needs database version $required) is newer '
      'than the database it is connected to (version $dbVersion). Ask the '
      'system administrator to apply the pending database updates. Until '
      'then, use the previous version of the app.';
}
