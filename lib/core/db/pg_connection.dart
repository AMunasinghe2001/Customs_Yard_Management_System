import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

/// Where the office server's PostgreSQL lives.
///
/// Everything here is a compile-time default that a deployment can override
/// with `--dart-define`, so one build runs against any office without a code
/// change:
///
///     flutter run --dart-define=PG_HOST=192.168.1.50 --dart-define=PG_PASSWORD=...
class PgConfig {
  /// The server PC on the office LAN. `localhost` suits running the app on the
  /// same machine as the database.
  static const String host =
      String.fromEnvironment('PG_HOST', defaultValue: 'localhost');

  static const int port =
      int.fromEnvironment('PG_PORT', defaultValue: 5432);

  /// Created in pgAdmin 4 as `Customs_SR_DB`.
  static const String database =
      String.fromEnvironment('PG_DATABASE', defaultValue: 'Customs_SR_DB');

  static const String username =
      String.fromEnvironment('PG_USER', defaultValue: 'postgres');

  static const String password =
      String.fromEnvironment('PG_PASSWORD', defaultValue: 'postgres');

  /// A LAN server usually has no TLS certificate, so the default is a plain
  /// connection. Set `PG_SSL=true` where the server does offer TLS.
  static const bool useSsl =
      bool.fromEnvironment('PG_SSL', defaultValue: false);

  static Endpoint get endpoint => Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      );

  static ConnectionSettings get settings => ConnectionSettings(
        sslMode: useSsl ? SslMode.require : SslMode.disable,
        // The app is long-running and mostly idle between actions; without a
        // timeout a dropped LAN link would hang the first query after it.
        connectTimeout: const Duration(seconds: 10),
        queryTimeout: const Duration(seconds: 60),
      );

  /// Human-readable target, for error messages and the connection banner.
  static String get describe => '$username@$host:$port/$database';
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
