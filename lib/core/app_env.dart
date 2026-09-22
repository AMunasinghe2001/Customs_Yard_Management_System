import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:flutter/foundation.dart';

/// Runtime configuration read from a `.env` file sitting beside the app.
///
/// Why a file at all, when `--dart-define` already works: a `--dart-define`
/// value is baked in at COMPILE time, so changing the database password means
/// rebuilding and redistributing the app. A `.env` is read at START-UP, so an
/// office can point the same build at a different server, or rotate a
/// password, by editing one line and restarting.
///
/// ⚠️ **This is convenience, not secrecy.** On a desktop app the file ships to
/// the user's machine, where anyone can open it in Notepad. A `--dart-define`
/// is marginally better hidden (it is inside the binary) but is still
/// extractable with `strings`. Neither makes a credential safe from the person
/// running the app — for that the app would have to stop talking to PostgreSQL
/// directly and go through a server that holds the credentials itself.
///
/// What this DOES buy: the secret leaves the source tree, so it stops being
/// committed to git.
///
/// ── Precedence (first match wins) ──────────────────────────────────────────
///   1. `--dart-define` — an explicit build-time override always wins, so
///      existing deployments that pass one keep behaving exactly as before.
///   2. `.env` beside the executable, then the project root (dev runs).
///   3. The compiled-in default.
class AppEnv {
  AppEnv._();

  static DotEnv? _env;
  static String? _loadedFrom;

  /// Where the `.env` was read from, or null if none was found. Shown on the
  /// connection-failure screen so a misplaced file is obvious.
  static String? get loadedFrom => _loadedFrom;

  /// Reads the first `.env` found. Safe to call more than once; never throws —
  /// a missing or malformed file just means "use the defaults".
  static void load() {
    if (_env != null) return;
    final env = DotEnv(includePlatformEnvironment: false);

    for (final path in _candidatePaths()) {
      try {
        final f = File(path);
        if (!f.existsSync()) continue;
        env.load([path]);
        _loadedFrom = f.absolute.path;
        break;
      } catch (e) {
        // A bad file must not stop the app starting; fall through to defaults.
        debugPrint('Could not read $path: $e');
      }
    }
    _env = env;

    // ⚠️ A `#` IN A VALUE NEEDS QUOTES, and the failure is silent.
    //
    // The dotenv parser treats `#` as the start of a comment, so
    //
    //     PG_PASSWORD__supabase=SrYard#2026Customs
    //
    // does not come back truncated -- the key DISAPPEARS. The app then sends
    // no password at all and the server answers
    // `28P01: password authentication failed`, which reads as a wrong
    // password while psql with the very same string connects fine. Measured;
    // it cost an evening. Quoting it fixes it:
    //
    //     PG_PASSWORD__supabase="SrYard#2026Customs"
    //
    // Warned about rather than auto-quoted: rewriting somebody's `.env`
    // silently is worse than telling them which line is wrong.
    for (final key in const ['PG_PASSWORD', 'GMAIL_APP_PASSWORD']) {
      for (final k in env.map.keys.where((k) => k.startsWith(key))) {
        if ((env[k] ?? '').isEmpty) {
          debugPrint('CONFIG: $k is EMPTY. If its value contains "#", wrap '
              'it in double quotes - dotenv reads # as a comment.');
        }
      }
    }
  }

  static List<String> _candidatePaths() {
    final sep = Platform.pathSeparator;
    final paths = <String>[];

    // A previous `flutter run` can leave a stale .env beside the debug EXE.
    // While developing, the project-root .env is the file just edited and
    // must win. Installed/release copies still prefer the EXE-side file.
    if (kDebugMode) paths.add('.env');

    // Beside the .exe — where it lands for an installed copy.
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      paths.add('$exeDir$sep.env');
    } catch (_) {}

    // The working directory — `flutter run` from the project root.
    if (!kDebugMode) paths.add('.env');

    return paths;
  }

  /// Which named block of the `.env` is in force, e.g. `supabase` or
  /// `local`. Empty means the plain, unsuffixed keys.
  ///
  /// ⚠️ ONE FILE, SEVERAL SERVERS. Before this, switching between the
  /// Supabase project and the local database meant commenting out one block
  /// and uncommenting another — every line of both — and a half-finished
  /// edit produced a mixed configuration: a cloud host with a local
  /// password, which fails as an authentication error and looks like a wrong
  /// password rather than a half-applied change.
  ///
  /// Now every server keeps its own suffixed keys and only this one line
  /// moves:
  ///
  ///     PG_PROFILE=supabase
  ///     PG_HOST__supabase=aws-0-....pooler.supabase.com
  ///     PG_HOST__local=localhost
  ///
  /// ⚠️ A double underscore, not a single one. `PG_SSL_VERIFY` already
  /// contains underscores, so `PG_SSL_VERIFY_local` could not be told from a
  /// key of that name in its own right.
  static String get profile {
    load();
    return (_env?['PG_PROFILE'] ?? '').trim();
  }

  /// The raw value for [key] under the active profile, falling back to the
  /// unsuffixed key.
  ///
  /// ⚠️ The fallback is what makes this safe to adopt gradually: a
  /// `.env` with no profiles at all behaves exactly as it did, and a profile
  /// that names only the keys that differ inherits the rest.
  static String? _lookup(String key) {
    final p = profile;
    if (p.isNotEmpty) {
      final scoped = _env?['${key}__$p'];
      if (scoped != null && scoped.trim().isNotEmpty) return scoped;
    }
    return _env?[key];
  }

  /// A value from the `.env`, or [fallback].
  ///
  /// [dartDefine] is the value `String.fromEnvironment` produced. It is passed
  /// in rather than read here because `fromEnvironment` only folds constants at
  /// compile time — it cannot be called with a runtime key.
  static String read(
    String key, {
    required String dartDefine,
    required String fallback,
  }) {
    if (dartDefine.isNotEmpty) return dartDefine;
    load();
    final v = _lookup(key);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return fallback;
  }

  static int readInt(
    String key, {
    required int dartDefine,
    required int fallback,
    required int dartDefineSentinel,
  }) {
    if (dartDefine != dartDefineSentinel) return dartDefine;
    load();
    final v = _lookup(key);
    final parsed = v == null ? null : int.tryParse(v.trim());
    return parsed ?? fallback;
  }

  static bool readBool(
    String key, {
    required bool dartDefine,
    required bool fallback,
  }) {
    // A false `--dart-define` is indistinguishable from an absent one, so the
    // .env is consulted whenever the define is false and can only turn it ON.
    if (dartDefine) return true;
    load();
    final v = _lookup(key)?.trim().toLowerCase();
    if (v == null || v.isEmpty) return fallback;
    return v == 'true' || v == '1' || v == 'yes';
  }
}
