import 'dart:async';
import 'dart:io' show File, Platform, SecurityContext, SocketException;

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import '../app_env.dart';
import 'pg_query.dart';
import '../device_id.dart';

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
  static const int _portDefine =
      int.fromEnvironment('PG_PORT', defaultValue: -1);
  static const String _databaseDefine = String.fromEnvironment('PG_DATABASE');
  static const String _userDefine = String.fromEnvironment('PG_USER');
  static const String _passwordDefine = String.fromEnvironment('PG_PASSWORD');
  static const bool _sslDefine = bool.fromEnvironment('PG_SSL');
  static const bool _sslVerifyDefine = bool.fromEnvironment('PG_SSL_VERIFY');
  static const bool _requireTlsDefine = bool.fromEnvironment('PG_REQUIRE_TLS');
  static const int _connectTimeoutDefine =
      int.fromEnvironment('PG_CONNECT_TIMEOUT', defaultValue: -1);
  static const int _poolSizeDefine =
      int.fromEnvironment('PG_POOL_SIZE', defaultValue: -1);
  static const int _maxConnAgeDefine =
      int.fromEnvironment('PG_MAX_CONN_AGE', defaultValue: -1);
  static const int _queryTimeoutDefine =
      int.fromEnvironment('PG_QUERY_TIMEOUT', defaultValue: -1);
  static const String _sslRootCertDefine =
      String.fromEnvironment('PG_SSL_ROOT_CERT');

  /// The server PC on the office LAN. `localhost` suits running the app on the
  /// same machine as the database.
  ///
  /// Accepts a domain name, an IPv4 address, or a bracketed IPv6 literal. The
  /// raw value is normalised by [_normaliseHost], because a branch office is
  /// configured by someone pasting into Notepad rather than by a build script.
  static String get host => _normaliseHost(
      AppEnv.read('PG_HOST', dartDefine: _hostDefine, fallback: 'localhost'));

  /// Trims the shapes people actually paste into a `.env`.
  ///
  /// ⚠️ Not cosmetic. `postgres://` or a trailing `:5432` reaches the resolver
  /// verbatim and fails as "host lookup failed", which reads like the server
  /// is down rather than like the line has an extra six characters on it —
  /// and the person reading it is at a branch office with no one to ask.
  ///
  /// A bare IPv6 literal is BRACKETED rather than rejected: `::1` is a
  /// perfectly reasonable thing to type, and the socket layer needs `[::1]`
  /// to tell the address from a port separator.
  ///
  /// A value that is still empty after trimming falls back to `localhost`, so
  /// `PG_HOST=` (set but blank) behaves like "not set" instead of failing to
  /// resolve the empty string.
  static String _normaliseHost(String raw) {
    var h = raw.trim();
    if (h.isEmpty) return 'localhost';

    // A whole URL, or just a scheme someone left on.
    final schemeAt = h.indexOf('://');
    if (schemeAt >= 0) h = h.substring(schemeAt + 3);
    // Anything after the authority: a database path, a query string.
    for (final cut in ['/', '?']) {
      final i = h.indexOf(cut);
      if (i >= 0) h = h.substring(0, i);
    }
    // user:pass@host
    final at = h.lastIndexOf('@');
    if (at >= 0) h = h.substring(at + 1);
    h = h.trim();
    if (h.isEmpty) return 'localhost';

    if (h.startsWith('[')) {
      // Already a bracketed IPv6 literal; drop any :port after the bracket.
      final close = h.indexOf(']');
      if (close > 0) return h.substring(0, close + 1);
      return h;
    }

    // ⚠️ Count the colons before stripping one. A single colon is host:port;
    // several mean a bare IPv6 literal, where stripping at the first colon
    // would leave a fragment that resolves to nothing.
    final colons = ':'.allMatches(h).length;
    if (colons == 1) {
      h = h.substring(0, h.indexOf(':'));
    } else if (colons > 1) {
      return '[$h]';
    }
    return h.trim().isEmpty ? 'localhost' : h.trim();
  }

  /// Test seam: is THIS host a loopback address?
  ///
  /// The rule, asked of a given value rather than of whatever the machine's
  /// `.env` currently names — a test of the latter breaks the moment the
  /// file points at a real deployment.
  @visibleForTesting
  static bool debugIsLoopback(String h) {
    final v = h.trim().toLowerCase();
    return v == 'localhost' ||
        v == '127.0.0.1' ||
        v == '::1' ||
        v == '[::1]' ||
        v.startsWith('127.');
  }

  /// Test seam for [_normaliseHost]: the rule is worth pinning directly
  /// rather than only through whatever `.env` the test machine happens to
  /// have.
  @visibleForTesting
  static String debugNormaliseHost(String raw) => _normaliseHost(raw);

  static int get port => AppEnv.readInt('PG_PORT',
      dartDefine: _portDefine, fallback: 5432, dartDefineSentinel: -1);

  /// Created in pgAdmin 4 as `Customs_SR_DB`.
  static String get database => AppEnv.read('PG_DATABASE',
      dartDefine: _databaseDefine, fallback: 'Customs_SR_DB');

  static String get username =>
      AppEnv.read('PG_USER', dartDefine: _userDefine, fallback: 'postgres');

  /// ⚠️ The fallback is the stock PostgreSQL development password, and it is
  /// compiled into the binary. That is a convenience for a fresh local
  /// checkout, NOT a credential — [usingDefaultPassword] reports when it is in
  /// use so a shipped build can say so out loud rather than quietly
  /// authenticating with a password anyone can guess.
  ///
  /// Removing the default outright would break every existing local install
  /// on the next run, so it stays and is flagged instead.
  static const String defaultPassword = 'postgres';

  static String get password => AppEnv.read('PG_PASSWORD',
      dartDefine: _passwordDefine, fallback: defaultPassword);

  /// True when no `.env` or `--dart-define` supplied a password and the
  /// compiled-in development default is being used.
  static bool get usingDefaultPassword => password == defaultPassword;

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

  /// Path to the server's CA certificate (`ca.crt`), for verified TLS.
  ///
  /// ⚠️ Needed the moment the server's certificate is SELF-SIGNED, which is
  /// the normal case for an office PostgreSQL behind a static IP: nobody
  /// buys a public certificate for `203.0.113.10`. `SslMode.verifyFull` then
  /// checks the chain against the machine's trust store, which has never
  /// heard of that certificate, and every connection fails — so the usual
  /// "fix" is to drop back to `require`, which encrypts but accepts ANY
  /// certificate and leaves the link open to a man in the middle.
  ///
  /// Naming the CA here keeps verification ON while trusting exactly one
  /// issuer: your own. A relative path is resolved beside the executable, so
  /// `PG_SSL_ROOT_CERT=ca.crt` works on an installed copy.
  ///
  /// Empty means "use the operating system's trust store", which is correct
  /// when the certificate comes from a real CA (Let's Encrypt on a domain).
  static String get sslRootCertPath => AppEnv.read('PG_SSL_ROOT_CERT',
      dartDefine: _sslRootCertDefine, fallback: '');

  /// [sslRootCertPath] resolved to something openable: absolute as given,
  /// relative taken from the executable's own folder rather than from
  /// whatever directory the app happens to be launched from.
  static String? get resolvedSslRootCertPath {
    final raw = sslRootCertPath.trim();
    if (raw.isEmpty) return null;
    final f = File(raw);
    if (f.isAbsolute) return f.path;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final beside = File('$exeDir${Platform.pathSeparator}$raw');
      if (beside.existsSync()) return beside.path;
    } catch (_) {
      // Fall through to the path as given.
    }
    return f.path;
  }

  /// Why the configured CA file cannot be used, or null when it is fine.
  static String? get sslRootCertProblem {
    final path = resolvedSslRootCertPath;
    if (path == null) return null;
    if (!File(path).existsSync()) {
      return 'PG_SSL_ROOT_CERT points at "$path", which does not exist. '
          'Copy ca.crt beside the executable.';
    }
    return null;
  }

  /// The trust anchor for a verified connection, or null to use the OS store.
  ///
  /// ⚠️ Built once and cached. `setTrustedCertificates` reads the file from
  /// disk, and the pool opens a fresh connection whenever it grows or retires
  /// one — re-reading on every open would put a file read on the hot path for
  /// no benefit, since the certificate cannot change while the app runs.
  static SecurityContext? _cachedContext;
  static bool _contextBuilt = false;

  static SecurityContext? get securityContext {
    if (_contextBuilt) return _cachedContext;
    _contextBuilt = true;
    final path = resolvedSslRootCertPath;
    if (path == null) return _cachedContext = null;
    try {
      final ctx = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificates(path);
      return _cachedContext = ctx;
    } catch (e) {
      // A bad certificate must not be silent: without this the app would fall
      // back to the OS trust store, verification would fail against a
      // self-signed server, and the error would name TLS rather than the file
      // that is actually wrong.
      debugPrint('SECURITY: could not load PG_SSL_ROOT_CERT "$path": $e');
      return _cachedContext = null;
    }
  }

  /// Test seam: forget the cached context so a changed path is re-read.
  @visibleForTesting
  static void resetSecurityContextCache() {
    _cachedContext = null;
    _contextBuilt = false;
  }

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

  /// Refuse to run without TLS. Off by default so existing LAN installs keep
  /// working; set `PG_REQUIRE_TLS=true` on any deployment that leaves the
  /// office network, and a misconfigured `.env` becomes a startup failure
  /// rather than a silent downgrade to plaintext.
  static bool get requireTls => AppEnv.readBool('PG_REQUIRE_TLS',
      dartDefine: _requireTlsDefine, fallback: false);

  /// Whether [host] is this machine. A loopback connection never leaves the
  /// box, so there is no wire for anyone to tap and plaintext is genuinely
  /// fine; anything else is a network hop, however short.
  static bool get isLoopbackHost {
    final h = host.trim().toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h == '[::1]' ||
        h.startsWith('127.');
  }

  /// What is wrong with the transport configuration, or null when it is sound.
  ///
  /// Three distinct states, because they carry very different risk:
  ///
  ///   * plaintext to a REMOTE host — every query, every seizure record and
  ///     the login password itself cross the network readable by anything on
  ///     the path. This is the one that matters.
  ///   * TLS without verification — encrypted, but any machine in the middle
  ///     may present its own certificate and decrypt the lot. Acceptable on a
  ///     LAN with a self-signed certificate, not over the internet.
  ///   * plaintext to localhost — not a finding; the traffic never leaves.
  static String? get transportWarning {
    if (!useSsl) {
      if (isLoopbackHost) return null;
      return 'PostgreSQL at $host is reached WITHOUT TLS. Queries, seizure '
          'records and credentials cross the network in clear text. '
          'Set PG_SSL=true (and PG_SSL_VERIFY=true off-LAN).';
    }
    if (!verifySsl && !isLoopbackHost) {
      return 'TLS to $host is UNVERIFIED: the connection is encrypted but the '
          'server certificate is not checked, so a machine in the middle can '
          'still read it. Set PG_SSL_VERIFY=true outside a trusted LAN.';
    }
    // ⚠️ A CA path that does not resolve is worse than none: verifyFull then
    // falls back to the OS trust store, which has never heard of a
    // self-signed office certificate, so every connection fails with a TLS
    // error that names the handshake rather than the missing file.
    final certProblem = sslRootCertProblem;
    if (certProblem != null) return certProblem;
    return null;
  }

  /// Checked at start-up, before the first query. Logs whatever is wrong, and
  /// throws only when the deployment has asked to be strict — a warning that
  /// no one reads is the reason plaintext deployments survive.
  static void enforceTransportPolicy() {
    // A shipped build authenticating with the stock 'postgres' password means
    // no .env reached the machine. Worth saying in release, where it is the
    // difference between "configured" and "running on a guessable default" —
    // and it names no secret, only the fact that the default is in play.
    if (usingDefaultPassword && kReleaseMode) {
      debugPrint('SECURITY: PG_PASSWORD is unset — using the compiled-in '
          'development default. Set it in the .env beside the executable.');
    }

    final warning = transportWarning;
    if (warning == null) return;
    if (requireTls) {
      throw StateError('PG_REQUIRE_TLS is set but the connection is not '
          'adequately secured. $warning');
    }
    debugPrint('⚠️  TRANSPORT SECURITY: $warning');
  }

  /// How many physical connections the pool may open.
  ///
  /// ⚠️ A SINGLE connection serialises every statement: Postgres runs one
  /// query at a time per connection, so a dashboard that loads a dozen
  /// providers at once queues them all behind each other, and whichever
  /// happens to be last waits out the whole queue. That is what produced
  /// `57014: canceling statement due to user request` on a screen whose own
  /// query takes 13ms -- it was never slow, it was ninth in line.
  ///
  /// ⚠️ But the cap cannot be chosen from ONE client's point of view alone.
  /// This is a desktop app talking straight to Postgres, so every PC on the
  /// LAN holds its own pool, and the server's `max_connections` is divided
  /// between all of them:
  ///
  ///     clients x (poolSize + 1 listener) <= max_connections - reserved
  ///
  /// At the old default of 8 that is 9 sockets per PC, so a stock server
  /// (`max_connections = 100`, 3 reserved) ran out after ELEVEN users — the
  /// twelfth got `53300: too many connections for role`, which reads like a
  /// server fault but is only arithmetic. 3 keeps a dashboard's panels
  /// genuinely parallel while fitting 24 users into a stock server, and ~97
  /// into the 400 the deployment guide now sets. See postgres/63.
  static int get poolSizeSetting => AppEnv.readInt('PG_POOL_SIZE',
      dartDefine: _poolSizeDefine, fallback: 3, dartDefineSentinel: -1);

  /// How long a pooled connection may live before the pool retires it.
  ///
  /// A desktop client is open all day, so without this the pool reaches its
  /// high-water mark during the busiest minute and then holds every one of
  /// those sockets idle until the app closes — 100 PCs keeping their peak
  /// allocation forever, each costing the server a backend process with its
  /// own ~work_mem. Retiring them returns the memory and the connection slot
  /// to everyone else; the next query just opens a fresh one.
  static int get maxConnectionAgeSeconds => AppEnv.readInt('PG_MAX_CONN_AGE',
      dartDefine: _maxConnAgeDefine, fallback: 600, dartDefineSentinel: -1);

  /// Pool settings: the same connection settings, plus the size cap and the
  /// per-connection session hook.
  ///
  /// ⚠️ [onOpen] is not optional. The session variables RLS reads
  /// (`app.current_user_id`, `app.current_role`) are PER CONNECTION, so a
  /// pool that opens a second one without re-applying them would run that
  /// user's queries as 'anon' -- every user-scoped policy denying, on some
  /// queries and not others, depending purely on which connection the pool
  /// handed out.
  static PoolSettings poolSettings(Future<void> Function(Connection) onOpen) =>
      PoolSettings(
        maxConnectionCount: poolSizeSetting,
        // Bounded lifetime, so an all-day client hands its idle sockets back
        // rather than hoarding its peak. `maxSessionUse` is the same bound
        // applied to a connection currently in use: it finishes the query it
        // is running and is retired after, never mid-statement.
        maxConnectionAge: Duration(seconds: maxConnectionAgeSeconds),
        maxSessionUse: Duration(seconds: maxConnectionAgeSeconds),
        connectTimeout: Duration(seconds: connectTimeoutSeconds),
        queryTimeout: Duration(seconds: queryTimeoutSeconds),
        sslMode: sslMode,
        securityContext: securityContext,
        onOpen: onOpen,
      );

  static ConnectionSettings get settings => ConnectionSettings(
        sslMode: sslMode,
        securityContext: securityContext,
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
    // ⚠️ The PROFILE is named when one is active. Switching servers is a
    // one-line change now, so "which server am I actually on" has to be
    // answerable from the screen -- otherwise a stale PG_PROFILE looks like
    // a broken network.
    final p = AppEnv.profile;
    final tag = p.isEmpty ? '' : ' [$p]';
    return '$username@$host:$port/$database ($tls)$tag';
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

  /// The pool, not a single connection.
  ///
  /// ⚠️ One connection ran every statement in the app one after another,
  /// because Postgres allows only one active query per connection. A screen
  /// that loads a dozen providers at once therefore queued them, and the ones
  /// at the back timed out -- reported as `57014`, which reads like a broken
  /// query but was only a queue.
  Pool? _pool;

  /// Whether [close] has retired the pool. A closed pool cannot be reused, so
  /// holding the reference alone is not enough to know it is usable.
  bool _poolClosed = false;

  /// Guards against a burst of queries each opening their own connection while
  /// the first one is still handshaking.
  Future<Pool>? _connecting;

  /// Who the database should believe is running each statement.
  ///
  /// This is what makes RLS work without a rewrite. Supabase gave every policy
  /// `auth.uid()`; here `auth.uid()` is a SQL function that reads the session
  /// variable `app.current_user_id`, so the 73 existing policies keep working
  /// exactly as written — see postgres/01_auth_and_session.sql.
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
  /// ⚠️ Signing in or out must reach EVERY pooled connection, not just one.
  /// The variables are per-connection, so a pool holding several idle ones
  /// would keep answering as the previous user on whichever the next query
  /// happened to get. Closing the pool is the only way to be certain: the
  /// next query opens fresh connections, and [_applySession] runs on each.
  Future<void> setCurrentUser(String? userId) async {
    final changed = _currentUserId != userId;
    _currentUserId = userId;
    if (changed) await close();
  }

  String? get currentUserId => _currentUserId;

  /// Re-asks the database what this user may do, on every connection.
  ///
  /// ⚠️ Needed after a password change, which [setCurrentUser] cannot notice:
  /// the user id does not change, so the pool is never dropped, and the idle
  /// connections keep the `app.password_expired = on` they were opened with.
  /// The officer would have set a valid new password and still been locked
  /// out by whichever stale connection their next query landed on.
  Future<void> refreshSessionState() => close();

  /// Announces who this connection is acting as.
  ///
  /// ⚠️ Calls `auth.begin_session` rather than writing the session variables
  /// directly, so the CLIENT does not get to decide whether its own password
  /// is still valid. It supplies an identity; the database decides what that
  /// identity may do, and sets `app.password_expired` accordingly. An expired
  /// password then reads as signed-out to `auth.uid()` and as `anon` to
  /// `auth.role()`, which is every RLS policy in the schema — while
  /// `auth.change_password` keeps working, because it takes the user id as an
  /// argument instead of asking who is calling. See migration 018.
  ///
  /// `set_config(..., false)` inside it makes the variables last for the whole
  /// session rather than one transaction, so every later query sees them.
  Future<void> _applySession(Session conn) async {
    await conn.execute(
      Sql.named('select auth.begin_session(@uid, @role)'),
      parameters: {
        // An empty string, not null: `current_setting` returns '' for an unset
        // variable anyway, and the SQL side treats '' as "nobody".
        'uid': _currentUserId ?? '',
        'role': _currentRole,
      },
    );

    // ⚠️ Which MACHINE this is, for the approved-device check in
    // auth.sign_in (migration 032).
    //
    // Set on the connection rather than passed to sign_in, for two reasons:
    // a pooled connection is reused, so like the three variables above it
    // must be stamped on every connection and never left over from the
    // previous occupant; and the device is a property of the CLIENT, not of
    // one call — anything else the database wants to refuse per machine can
    // read the same variable without a new argument.
    //
    // A failure here is swallowed on purpose. An empty id is what an
    // unidentified machine sends, and with an empty device register the
    // database allows it; refusing to connect would take the app down over a
    // check that is not yet switched on.
    try {
      await conn.execute(
        Sql.named("select set_config('app.device_id', @dev, false)"),
        parameters: {'dev': await DeviceId.get()},
      );
    } catch (_) {
      // Left unset; current_setting returns '' and the register decides.
    }
  }

  /// Whether a live connection is currently held. Never assume from this that
  /// the next query will succeed — the socket can drop between the check and
  /// the query, which is why [_run] retries.
  bool get isConnected => _pool != null && !_poolClosed;

  Future<Pool> _open() async {
    final existing = _pool;
    if (existing != null && !_poolClosed) return existing;

    // Someone else is already opening one — wait for theirs.
    final pending = _connecting;
    if (pending != null) return pending;

    // Before the socket, not after: a plaintext connection to a remote server
    // has already leaked the password by the time the first query runs, so a
    // deployment that set PG_REQUIRE_TLS must fail here rather than connect
    // and complain.
    PgConfig.enforceTransportPolicy();

    // ⚠️ Every physical connection the pool opens starts a FRESH session with
    // no settings, so the signed-in user has to be re-declared on each one or
    // RLS sees 'anon'. Doing it here rather than after the first open is what
    // makes a pool safe: the pool decides when to open a connection and never
    // tells us, so any later application would be too late for whichever
    // query got that connection first.
    final future = Future<Pool>(() async {
      final pool = Pool.withEndpoints(
        [PgConfig.endpoint],
        settings: PgConfig.poolSettings(_applySession),
      );
      // Prove the credentials now rather than on whichever screen queries
      // first: the pool opens lazily, so without this a bad password would
      // surface as a random panel failing.
      await pool.execute('select 1');
      // RLS is the boundary between every yard.  A superuser or BYPASSRLS
      // role ignores it, so reject that configuration before any screen can
      // query data. `yard_app` is intentionally neither and starts normally.
      final identity =
          await pool.execute('select rolsuper, rolbypassrls from pg_roles '
              'where rolname = current_user');
      final dbRole = identity.isEmpty ? null : identity.first.toColumnMap();
      if (dbRole == null ||
          dbRole['rolsuper'] == true ||
          dbRole['rolbypassrls'] == true) {
        await pool.close();
        throw StateError(
            'Database access must use the non-superuser yard_app account. '
            'Set PG_USER=yard_app in .env.');
      }
      return pool;
    });
    _connecting = future;
    try {
      final pool = await future;
      _pool = pool;
      _poolClosed = false;
      debugPrint('PostgreSQL connected: ${PgConfig.describe} '
          '(pool of ${PgConfig.poolSizeSetting})');
      return pool;
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
    final pool = _pool;
    _pool = null;
    _poolClosed = true;
    if (pool != null) await pool.close();
  }

  /// Runs [sql], reconnecting once if the socket has died.
  ///
  /// The retry is deliberate and single: a dropped connection is the normal
  /// case on an office LAN (server reboot, sleep, cable), and failing the
  /// user's action for it would be wrong. Retrying more than once would mask a
  /// server that is genuinely down.
  Future<Result> _run(String sql, {Map<String, Object?>? parameters}) async {
    try {
      final pool = await _open();
      return await pool.execute(Sql.named(sql), parameters: parameters ?? {});
    } on PgException catch (e) {
      // A server-side error (bad SQL, constraint violation) is the caller's to
      // handle — reconnecting would not change the outcome.
      //
      // ⚠️ A deliberate `raise exception` in a function is the schema talking
      // to a PERSON — "You have used this password before". Rethrowing the
      // driver's own exception put `Severity.error 22023: ` in front of that
      // sentence on the sign-in screen. Unwrapped HERE, in _run, because both
      // query() and execute() pass through it: the same message was cleaned
      // for rpc() calls and still raw for the direct `select auth.…` that
      // changes a password.
      if (!_looksLikeDroppedConnection(e)) {
        throw Exception(describeDatabaseError(e));
      }
      await close();
      final pool = await _open();
      return await pool.execute(Sql.named(sql), parameters: parameters ?? {});
    } on SocketException {
      await close();
      final pool = await _open();
      return await pool.execute(Sql.named(sql), parameters: parameters ?? {});
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
    final pool = await _open();
    return pool.runTx(body);
  }
}
