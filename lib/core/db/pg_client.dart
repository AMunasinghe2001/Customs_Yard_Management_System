import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'pg_auth.dart';
import 'pg_connection.dart';
import 'pg_query.dart';
import 'pg_realtime.dart';
import 'pg_schema.dart';

/// The single object the whole app reaches the database through.
///
/// It exposes the four members the code already uses — `from`, `auth`,
/// `channel`, `rpc` — with the same signatures the Supabase client had. That
/// is the entire point: the app has 198 call sites across 24 files, and this
/// makes almost all of them compile and behave unchanged against a local
/// PostgreSQL server instead of Supabase's cloud.
class PgClient {
  PgClient._();
  static final PgClient instance = PgClient._();

  /// Opens the connection, caches the foreign keys the query builder needs,
  /// and restores the last session. Call once from main().
  Future<void> initialize() async {
    await PgDatabase.instance.connect();
    await PgSchema.instance.load();
    // Restore before the first query so RLS sees the right user; a failure
    // here just means signed out, which the router already handles.
    await PgAuth.instance.restoreSession();
    await PgRealtime.instance.start();
  }

  PgQuery from(String table) => PgQuery(table);

  PgAuth get auth => PgAuth.instance;

  PgChannel channel(String name) => PgRealtime.instance.channel(name);

  void removeChannel(PgChannel channel) =>
      PgRealtime.instance.removeChannel(channel);

  /// Calls a SQL function.
  ///
  /// The 15 RPCs the app uses were already PostgreSQL functions on Supabase,
  /// so they carry over untouched — only the transport changes.
  ///
  /// Returns the bare value for a scalar function, a list of maps for a
  /// set-returning one, matching what the SDK handed back.
  Future<dynamic> rpc(String function, {Map<String, Object?>? params}) async {
    final args = params ?? const <String, Object?>{};
    // Named arguments (`fn(name => @name`) rather than positional, because
    // that is how the SDK called them and how the functions declare defaults.
    //
    // ⚠️ An argument NAME is the one thing here that is pasted into SQL rather
    // than bound: `@k` binds the value, but the `k =>` before it cannot be a
    // parameter — Postgres needs the argument name as syntax. Every call site
    // today passes a literal, so nothing user-controlled reaches this; the
    // check is what keeps that true if a later refactor ever builds a params
    // map from a field name. A rejected name fails loudly instead of
    // extending the statement.
    for (final k in args.keys) {
      _requirePlainIdentifier(k, 'RPC argument name');
    }
    final argSql = args.keys.map((k) => '$k => @$k').join(', ');

    // jsonb parameters have to be sent as text and cast, or the driver infers
    // the wrong type for a Map.
    final bound = <String, Object?>{};
    args.forEach((k, v) {
      bound[k] = (v is Map || v is List) ? jsonEncode(v) : v;
    });

    final sql = 'select * from ${_qualify(function)}($argSql)';
    // ⚠️ The driver's `Severity.error 22023: ` prefix is stripped in
    // PgDatabase._run, which both query() and execute() go through — not
    // here, where it only covered RPCs and left a direct
    // `select auth.change_password(...)` still showing the raw string.
    final rows = await PgDatabase.instance.query(sql, parameters: bound);

    if (rows.isEmpty) return null;
    // A scalar function comes back as one row of one column; hand back the
    // value itself so `res == true` and `resolved as String` keep working.
    if (rows.length == 1 && rows.first.length == 1) {
      return rows.first.values.first;
    }
    return rows;
  }

  /// A function or argument name that is safe to paste into SQL as syntax.
  ///
  /// Deliberately stricter than "escape the quotes": these names are never
  /// user data — all 30-odd RPC call sites pass a string literal — so anything
  /// outside `[A-Za-z_][A-Za-z0-9_$]*` means a caller is building a name from
  /// somewhere it should not, and guessing at its intent by escaping it would
  /// hide that. Length is capped at Postgres's own 63-byte identifier limit.
  static void _requirePlainIdentifier(String name, String what) {
    if (!_identifierPattern.hasMatch(name)) {
      throw ArgumentError.value(name, what,
          'must be a plain SQL identifier (letters, digits, underscore)');
    }
  }

  static final RegExp _identifierPattern =
      RegExp(r'^[A-Za-z_][A-Za-z0-9_$]{0,62}$');

  /// Schema-qualifies and quotes a function name.
  ///
  /// Both halves are validated, then quoted, so a name containing a dot is
  /// read as `"schema"."function"` and never as one identifier — and a stray
  /// quote is rejected outright rather than escaped into something that still
  /// parses. `auth.record_failed_login` is a real call site, so the two-part
  /// form has to keep working.
  static String _qualify(String fn) {
    final parts = fn.split('.');
    if (parts.length > 2) {
      throw ArgumentError.value(fn, 'RPC function', 'too many name parts');
    }
    for (final p in parts) {
      _requirePlainIdentifier(p, 'RPC function name');
    }
    final schema = parts.length == 2 ? parts.first : 'public';
    final name = parts.last;
    return '"$schema"."$name"';
  }
}

/// The app-wide handle. Named `supabase` on purpose: it keeps 198 call sites
/// reading exactly as they did, so this migration is a change of what the name
/// refers to rather than a rewrite of every file that uses it.
///
/// Renaming it would be cosmetic churn across 24 files with no behavioural
/// benefit — and would make the diff for this migration impossible to review.
PgClient get supabase => PgClient.instance;

/// Where the database lives, for the diagnostics screen.
String get databaseDescription => PgConfig.describe;

/// Prints generated SQL while debugging a query.
set logSql(bool on) {
  PgQuery.logSql = on;
  if (on) debugPrint('PgQuery SQL logging on');
}
