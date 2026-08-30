import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import 'pg_connection.dart';

/// Which changes a subscription wants. Named to match the SDK's enum so the
/// `event: PostgresChangeEvent.all` arguments already in the providers still
/// compile.
enum PostgresChangeEvent { all, insert, update, delete }

/// The payload handed to a callback.
///
/// The app's 19 callbacks all ignore their argument and just fire a refresh,
/// so this carries only what the NOTIFY actually sends — the table and the
/// operation. Row data is deliberately not pushed: see 03_realtime.sql.
@immutable
class PostgresChangePayload {
  const PostgresChangePayload({required this.table, required this.eventType});
  final String table;
  final String eventType;
}

typedef PgChangeCallback = void Function(PostgresChangePayload payload);

@immutable
class _Subscription {
  const _Subscription(this.table, this.event, this.callback);
  final String table;
  final PostgresChangeEvent event;
  final PgChangeCallback callback;
}

/// One named group of table subscriptions — the shape `supabase.channel(...)`
/// returned, so the `..onPostgresChanges(...)..subscribe()` cascades in
/// lib/core/providers.dart are unchanged.
class PgChannel {
  PgChannel(this.name, this._owner);

  final String name;
  final PgRealtime _owner;
  final List<_Subscription> _subs = [];

  PgChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    required String table,
    required PgChangeCallback callback,
  }) {
    _subs.add(_Subscription(table, event, callback));
    return this;
  }

  PgChannel subscribe([void Function(String status, Object? error)? onStatus]) {
    _owner._register(this);
    onStatus?.call('SUBSCRIBED', null);
    return this;
  }

  void _dispatch(String table, String op) {
    for (final s in _subs) {
      if (s.table != table) continue;
      if (s.event != PostgresChangeEvent.all &&
          s.event.name.toUpperCase() != op.toUpperCase()) {
        continue;
      }
      s.callback(PostgresChangePayload(table: table, eventType: op));
    }
  }
}

/// Delivers change notifications over Postgres LISTEN/NOTIFY.
///
/// Supabase pushed row changes over a websocket. Postgres does the same job
/// with LISTEN: a trigger on each watched table calls pg_notify('db_changes',
/// ...), and this class holds one connection listening for them and fans each
/// one out to the channels that care.
///
/// A dedicated connection, not the shared one: a listener is blocked waiting
/// for notifications, and Postgres only delivers them between transactions, so
/// sharing would mean notifications arriving late or not at all while a query
/// is in flight.
class PgRealtime {
  PgRealtime._();
  static final PgRealtime instance = PgRealtime._();

  Connection? _conn;
  StreamSubscription<String>? _sub;
  final List<PgChannel> _channels = [];
  bool _starting = false;

  /// How long to wait before reconnecting a dropped listener. Backs off so a
  /// server that is down does not get hammered, but stays responsive when the
  /// drop was a blip.
  static const _minRetry = Duration(seconds: 2);
  static const _maxRetry = Duration(seconds: 30);
  Duration _retry = _minRetry;
  Timer? _retryTimer;

  bool get isListening => _conn?.isOpen ?? false;

  PgChannel channel(String name) {
    // Reuse a channel of the same name, as the SDK did: providers rebuild and
    // would otherwise stack duplicate subscriptions on every rebuild.
    for (final c in _channels) {
      if (c.name == name) return c;
    }
    return PgChannel(name, this);
  }

  void _register(PgChannel c) {
    if (!_channels.contains(c)) _channels.add(c);
    unawaited(start());
  }

  void removeChannel(PgChannel c) {
    _channels.remove(c);
  }

  /// Opens the listening connection. Safe to call repeatedly.
  Future<void> start() async {
    if (isListening || _starting) return;
    _starting = true;
    try {
      final conn = await Connection.open(
        PgConfig.endpoint,
        settings: PgConfig.settings,
      );
      _conn = conn;
      _sub = conn.channels['db_changes'].listen(
        _onNotification,
        onError: (Object e) {
          debugPrint('PgRealtime error: $e');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
      );
      _retry = _minRetry;
      debugPrint('PgRealtime listening on db_changes');
    } catch (e) {
      debugPrint('PgRealtime could not start: $e');
      _scheduleReconnect();
    } finally {
      _starting = false;
    }
  }

  void _onNotification(String payload) {
    if (payload.isEmpty) return;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final table = map['table'] as String? ?? '';
      final op = map['op'] as String? ?? 'UPDATE';
      if (table.isEmpty) return;
      // Snapshot: a callback may add or remove a channel while we iterate.
      for (final c in List<PgChannel>.from(_channels)) {
        c._dispatch(table, op);
      }
    } catch (e) {
      debugPrint('PgRealtime bad payload "$payload": $e');
    }
  }

  void _scheduleReconnect() {
    _retryTimer?.cancel();
    _closeQuietly();
    // Without realtime the app still works — it just stops refreshing itself,
    // so a failed reconnect degrades rather than breaks.
    _retryTimer = Timer(_retry, () {
      _retry = _retry * 2 > _maxRetry ? _maxRetry : _retry * 2;
      unawaited(start());
    });
  }

  void _closeQuietly() {
    final s = _sub;
    final c = _conn;
    _sub = null;
    _conn = null;
    unawaited(s?.cancel().catchError((_) {}));
    unawaited(c?.close().catchError((_) {}));
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _channels.clear();
    _closeQuietly();
  }
}
