import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import '../app_session.dart';
import 'pg_connection.dart';

/// Which changes a subscription wants. Named to match the SDK's enum so the
/// `event: PostgresChangeEvent.all` arguments already in the providers still
/// compile.
enum PostgresChangeEvent { all, insert, update, delete }

/// The payload handed to a callback.
///
/// The app's 19 callbacks all ignore their argument and just fire a refresh,
/// so this carries only what the NOTIFY actually sends — the table, the
/// operation, and which yard it happened in. Row data is deliberately not
/// pushed: see 03_realtime.sql.
@immutable
class PostgresChangePayload {
  const PostgresChangePayload({
    required this.table,
    required this.eventType,
    this.yard,
  });
  final String table;
  final String eventType;

  /// The yard the change belongs to, or null for a table that has no yard
  /// column (profiles, categories, storage rates) — those concern everyone.
  final String? yard;
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

  /// Changes seen since the last flush, and the timer that will deliver them.
  ///
  /// ⚠️ The debounce is per CHANNEL, not global: coalescing across channels
  /// would let a busy table (audit_logs, which every action writes) delay an
  /// unrelated screen's refresh.
  final Map<String, PostgresChangePayload> _pending = {};
  Timer? _debounce;

  void _dispatch(String table, String op, String? yard) {
    // Does any subscription on this channel care? Checked BEFORE starting a
    // timer, so a channel watching three tables is not woken by a fourth.
    final wanted = _subs.any((s) =>
        s.table == table &&
        (s.event == PostgresChangeEvent.all ||
            s.event.name.toUpperCase() == op.toUpperCase()));
    if (!wanted) return;

    // Keyed by table: ten inserts into `packages` inside the debounce window
    // are one refresh, because the callback re-reads the whole list anyway.
    _pending[table] = PostgresChangePayload(
      table: table,
      eventType: op,
      yard: yard,
    );

    _debounce?.cancel();
    _debounce = Timer(PgRealtime.debounceWindow, _flush);
  }

  /// Delivers one callback per distinct table changed during the window.
  void _flush() {
    _debounce = null;
    if (_pending.isEmpty) return;
    final batch = List<PostgresChangePayload>.from(_pending.values);
    _pending.clear();

    for (final payload in batch) {
      for (final s in _subs) {
        if (s.table != payload.table) continue;
        if (s.event != PostgresChangeEvent.all &&
            s.event.name.toUpperCase() != payload.eventType.toUpperCase()) {
          continue;
        }
        s.callback(payload);
      }
    }
  }

  void _cancelPending() {
    _debounce?.cancel();
    _debounce = null;
    _pending.clear();
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

  /// How long to gather notifications before delivering them.
  ///
  /// Saving one form typically writes several tables in one transaction (the
  /// package, its items, an audit row), and each is a separate NOTIFY. Without
  /// a window every client refetches once per table; with it, once per burst.
  ///
  /// 300ms is chosen to sit under the threshold where a person perceives the
  /// update as anything but instant, while being long enough to absorb a
  /// multi-table save. The sub-second sync requirement is comfortably met:
  /// worst case is 300ms of batching plus the query itself.
  static const Duration debounceWindow = Duration(milliseconds: 300);

  /// Set by the cross-yard screens (Disposal and Executive directorates, ICT)
  /// which legitimately read every yard's data and must therefore refresh on
  /// any yard's change.
  ///
  /// ⚠️ Defaults to TRUE — filtering is opt-IN per client session. A client
  /// that has not yet established which yard it is showing must not silently
  /// miss updates; [AppSession.applyYardFilterToRealtime] turns it off once a
  /// single-yard user signs in.
  bool watchAllYards = true;

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
    // Cancel the debounce first: a pending timer would otherwise fire into a
    // provider that has already been disposed.
    c._cancelPending();
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
      final yard = map['yard'] as String?;
      if (table.isEmpty) return;

      // ⚠️ The storm stops HERE. One officer saving a form notifies every
      // connected PC; without this each of them re-queries, so one click costs
      // the server one query per client. A PC showing yard GL1 has nothing to
      // redraw when CED changes, so it drops the notification and never asks.
      //
      // A null yard is NOT filtered: it means the table has no yard column
      // (profiles, categories, storage rates) and the change concerns everyone.
      // Erring that way keeps correctness independent of the optimisation.
      if (!_concernsThisClient(yard)) return;

      // Snapshot: a callback may add or remove a channel while we iterate.
      for (final c in List<PgChannel>.from(_channels)) {
        c._dispatch(table, op, yard);
      }
    } catch (e) {
      debugPrint('PgRealtime bad payload "$payload": $e');
    }
  }

  /// Whether a change in [yard] should wake this client.
  ///
  /// Deliberately permissive in every uncertain case — a missed refresh shows
  /// the user stale data, which is far worse than a redundant query:
  ///
  ///   * null yard        → a shared table; everyone cares.
  ///   * no yard selected → we cannot tell yet; take it.
  ///   * cross-yard views → the Disposal and Executive directorates read every
  ///     yard, so they opt out of filtering entirely via [watchAllYards].
  bool _concernsThisClient(String? yard) {
    if (yard == null || yard.isEmpty) return true;
    if (watchAllYards) return true;
    final mine = AppSession.currentYard;
    if (mine.isEmpty) return true;
    return yard == mine;
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
    for (final c in _channels) {
      c._cancelPending();
    }
    _channels.clear();
    _closeQuietly();
  }
}
