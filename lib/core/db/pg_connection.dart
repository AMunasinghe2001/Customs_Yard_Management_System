import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import '../app_env.dart';

/// Where the office server's PostgreSQL lives.
///
/// Each setting is resolved at START-UP, in this order:
///
///   1. `--dart-define=PG_HOST=...` — a build-time override always wins, so
///      any existing deployment that passes one behaves exactly as before.
///   2. `PG_HOST=...` in a `.env` beside the executable (or the project root
///      when running from source). Editing that file and restarting is enough
///      to point the app at another server — no rebuild.
///   3. The compiled-in default below.
///
/// ⚠️ A `.env` on a desktop app is NOT a secret store — it ships to the user's
/// machine and can be read in Notepad. Its real value is keeping the password
/// out of the source tree and out of git. See [AppEnv].
///
///     flutter run --dart-define=PG_HOST=192.168.1.50 --dart-define=PG_PASSWORD=...
class PgConfig {
  // ── The raw --dart-define values ──────────────────────────────────────────
  //  These must be `const` initialisers: String.fromEnvironment is only folded
  //  by the compiler, so it cannot be called with a runtime key. They are read
  //  here and handed to AppEnv, which applies the precedence above.
  static const String _hostDefine = String.fromEnvironment('PG_HOST');
  static const int _portDefine = int.fromEnvironment('PG_PORT', defaultValue: -1);
  static const String _databaseDefine = String.fromEnvironment('PG_DATABASE');
  static const String _userDefine = String.fromEnvironment('PG_USER');
  static const String _passwordDefine = String.fromEnvironment('PG_PASSWORD');
  static const bool _sslDefine = bool.fromEnvironment('PG_SSL');
  static const bool _sslVerifyDefine = bool.fromEnvironment('PG_SSL_VERIFY');
  static const int _connectTimeoutDefine =
      int.fromEnvironment('PG_CONNECT_TIMEOUT', defaultValue: -1);
  static const int _queryTimeoutDefine =
      int.fromEnvironment('PG_QUERY_TIMEOUT', defaultValue: -1);

  /// The server PC on the office LAN. `localhost` suits running the app on the
  /// same machine as the database.
  static String get host => AppEnv.read('PG_HOST',
      dartDefine: _hostDefine, fallback: 'localhost');

  static int get port => AppEnv.readInt('PG_PORT',
      dartDefine: _portDefine, fallback: 5432, dartDefineSentinel: -1);

  /// Created in pgAdmin 4 as `Customs_SR_DB`.
  static String get database => AppEnv.read('PG_DATABASE',
      dartDefine: _databaseDefine, fallback: 'Customs_SR_DB');

  static String get username => AppEnv.read('PG_USER',
      dartDefine: _userDefine, fallback: 'postgres');

  static String get password => AppEnv.read('PG_PASSWORD',
      dartDefine: _passwordDefine, fallback: 'postgres');

  /// A LAN server usually has no TLS certificate, so the default is a plain
  /// connection. Set `PG_SSL=true` where the server does offer TLS.
  static bool get useSsl =>
      AppEnv.readBool('PG_SSL', dartDefine: _sslDefine, fallback: false);

  /// Whether to VERIFY the server's certificate, not merely encrypt.
  ///
  /// ⚠️ This matters the moment the database stops being on the office LAN.
  /// `SslMode.require` encrypts but accepts **any** certificate, so anything
  /// sitting between the app and a cloud database (AWS RDS, another office)
  /// can present its own certificate and read every query in clear — a
  /// man-in-the-middle, despite the traffic "being TLS".
  ///
  /// On a LAN with a self-signed certificate that is usually an acceptable
  /// trade. Over the public internet, carrying seizure records and officer
  /// credentials, it is not: set `PG_SSL_VERIFY=true` there. It is not the
  /// default only because it would break existing self-signed LAN installs.
  static bool get verifySsl => AppEnv.readBool('PG_SSL_VERIFY',
      dartDefine: _sslVerifyDefine, fallback: false);

  static Endpoint get endpoint => Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      );

  static SslMode get sslMode {
    if (!useSsl) return SslMode.disable;
    return verifySsl ? SslMode.verifyFull : SslMode.require;
  }

  static ConnectionSettings get settings => ConnectionSettings(
        sslMode: sslMode,
        // The app is long-running and mostly idle between actions; without a
        // timeout a dropped LAN link would hang the first query after it.
        //
        // A cloud database is several hundred ms away rather than one hop, and
        // a laptop on mobile data is slower still, so the connect timeout is
        // overridable — 10s is right for a LAN and tight for the internet.
        connectTimeout: Duration(seconds: connectTimeoutSeconds),
        queryTimeout: Duration(seconds: queryTimeoutSeconds),
      );

  static int get connectTimeoutSeconds => AppEnv.readInt('PG_CONNECT_TIMEOUT',
      dartDefine: _connectTimeoutDefine, fallback: 10, dartDefineSentinel: -1);

  static int get queryTimeoutSeconds => AppEnv.readInt('PG_QUERY_TIMEOUT',
      dartDefine: _queryTimeoutDefine, fallback: 60, dartDefineSentinel: -1);

  /// Human-readable target, for error messages and the connection banner.
  ///
  /// Names the TLS state too: "no TLS" against a remote host is the single
  /// most important thing to notice on the connection-failure screen.
  static String get describe {
    final tls = !useSsl
        ? 'no TLS'
        : verifySsl
            ? 'TLS, verified'
            : 'TLS, unverified';
    return '$username@$host:$port/$database ($tls)';
  }
}

/// The app's single PostgreSQL connection.
///
/// Holds one live [Connection] and hands it to every query. A pool would be
/// wasted here: a desktop client issues one query at a time, and a single
/// connection is also what makes `LISTEN`-based realtime possible — the
/// notifications arrive on the same socket the queries use.
///
/// Reconnects on demand. A LAN cable pulled out or a server restart closes the
/// socket; the next query notices, reconnects, and runs.
class PgDatabase {
  PgDatabase._();
  static final PgDatabase instance = PgDatabase._();

  Connection? _conn;

  /// Guards against a burst of queries each opening their own connection while
  /// the first one is still handshaking.
  Future<Connection>? _connecting;

  /// Who the database should believe is running each statement.
  ///
  /// This is what makes RLS work without a rewrite. Supabase gave every policy
  /// `auth.uid()`; here `auth.uid()` is a SQL function that reads the session
  /// variable `app.current_user_id`, so the 73 existing policies keep working
  /// exactly as written — see supabase_compat in the schema.
  ///
  /// Null while signed out, which makes `auth.uid()` null and every
  /// user-scoped policy deny. That is the correct default: a bug that forgets
  /// to set it locks the user out rather than showing them everything.
  String? _currentUserId;

  /// The role name `auth.role()` reports. Supabase used 'authenticated' for a
  /// signed-in user and 'anon' otherwise; policies test for the former.
  String get _currentRole => _currentUserId == null ? 'anon' : 'authenticated';

  /// Tells the database who is acting. Called on sign-in, and cleared on
  /// sign-out.
  ///
  /// Applied to the live connection immediately AND remembered, because the
  /// setting is per-session: a reconnect starts a fresh session that would
  /// otherwise come back as 'anon'.
  Future<void> setCurrentUser(String? userId) async {
    _currentUserId = userId;
    final conn = _conn;
    if (conn != null && conn.isOpen) await _applySession(conn);
  }

  String? get currentUserId => _currentUserId;

  /// Writes the session variables the compatibility functions read.
  ///
  /// `set_config(..., false)` makes them last for the whole session rather
  /// than one transaction, so every later query sees them.
  Future<void> _applySession(Connection conn) async {
    await conn.execute(
      Sql.named(
          "select set_config('app.current_user_id', @uid, false), "
          "set_config('app.current_role', @role, false)"),
      parameters: {
        // An empty string, not null: `current_setting` returns '' for an unset
        // variable anyway, and the SQL side treats '' as "nobody".
        'uid': _currentUserId ?? '',
        'role': _currentRole,
      },
    );
  }

  /// Whether a live connection is currently held. Never assume from this that
  /// the next query will succeed — the socket can drop between the check and
  /// the query, which is why [_run] retries.
  bool get isConnected => _conn?.isOpen ?? false;

  Future<Connection> _open() async {
    final existing = _conn;
    if (existing != null && existing.isOpen) return existing;

    // Someone else is already opening one — wait for theirs.
    final pending = _connecting;
    if (pending != null) return pending;

    final future = Connection.open(PgConfig.endpoint,
        settings: PgConfig.settings);
    _connecting = future;
    try {
      final conn = await future;
      _conn = conn;
      // A new session starts with no settings, so the signed-in user has to be
      // re-declared or RLS would see 'anon' after every reconnect.
      await _applySession(conn);
      debugPrint('PostgreSQL connected: ${PgConfig.describe}');
      return conn;
    } finally {
      _connecting = null;
    }
  }

  /// Opens the connection eagerly, so a failure surfaces at start-up rather
  /// than on whichever screen happens to query first.
  Future<void> connect() async {
    await _open();
  }

  Future<void> close() async {
    final conn = _conn;
    _conn = null;
    if (conn != null && conn.isOpen) await conn.close();
  }

  /// Runs [sql], reconnecting once if the socket has died.
  ///
  /// The retry is deliberate and single: a dropped connection is the normal
  /// case on an office LAN (server reboot, sleep, cable), and failing the
  /// user's action for it would be wrong. Retrying more than once would mask a
  /// server that is genuinely down.
  Future<Result> _run(String sql, {Map<String, Object?>? parameters}) async {
    try {
      final conn = await _open();
      return await conn.execute(Sql.named(sql), parameters: parameters ?? {});
    } on PgException catch (e) {
      // A server-side error (bad SQL, constraint violation) is the caller's to
      // handle — reconnecting would not change the outcome.
      if (!_looksLikeDroppedConnection(e)) rethrow;
      await close();
      final conn = await _open();
      return await conn.execute(Sql.named(sql), parameters: parameters ?? {});
    } on SocketException {
      await close();
      final conn = await _open();
      return await conn.execute(Sql.named(sql), parameters: parameters ?? {});
    }
  }

  static bool _looksLikeDroppedConnection(PgException e) {
    final m = e.toString().toLowerCase();
    return m.contains('connection') &&
        (m.contains('closed') || m.contains('reset') || m.contains('broken'));
  }

  /// Runs a query and returns its rows as JSON-like maps — the same shape the
  /// models already parse from Supabase, so nothing downstream changes.
  Future<List<Map<String, dynamic>>> query(String sql,
      {Map<String, Object?>? parameters}) async {
    final result = await _run(sql, parameters: parameters);
    return [
      for (final row in result) row.toColumnMap(),
    ];
  }

  /// Runs a statement for its effect and reports how many rows it touched.
  Future<int> execute(String sql, {Map<String, Object?>? parameters}) async {
    final result = await _run(sql, parameters: parameters);
    return result.affectedRows;
  }

  /// Runs [body] inside a transaction, rolling back if it throws.
  Future<T> transaction<T>(Future<T> Function(TxSession tx) body) async {
    final conn = await _open();
    return conn.runTx(body);
  }
}
