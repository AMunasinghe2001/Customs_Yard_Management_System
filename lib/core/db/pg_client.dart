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
    final argSql = args.keys.map((k) => '$k => @$k').join(', ');

    // jsonb parameters have to be sent as text and cast, or the driver infers
    // the wrong type for a Map.
    final bound = <String, Object?>{};
    args.forEach((k, v) {
      bound[k] = (v is Map || v is List) ? jsonEncode(v) : v;
    });

    final sql = 'select * from ${_qualify(function)}($argSql)';
    final rows = await PgDatabase.instance.query(sql, parameters: bound);

    if (rows.isEmpty) return null;
    // A scalar function comes back as one row of one column; hand back the
    // value itself so `res == true` and `resolved as String` keep working.
    if (rows.length == 1 && rows.first.length == 1) {
      return rows.first.values.first;
    }
    return rows;
  }

  static String _qualify(String fn) =>
      fn.contains('.') ? fn : 'public.${'"$fn"'}';
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
