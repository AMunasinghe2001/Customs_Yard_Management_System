/// The database handle.
///
/// ⚠️ There is no Supabase here, and there is no cloud. The app talks to a
/// standard PostgreSQL server through the `postgres` Dart package — see
/// lib/core/db/ for the whole layer.
///
/// The identifier `supabase` survives as the handle's NAME at ~198 call sites
/// across 24 files. It is a variable name, not a dependency: renaming it
/// would touch every data-layer call in the app for no behavioural change,
/// and a mechanical rename of that size is a poor trade against the chance of
/// one silent mistake in it. The package itself is gone from pubspec.yaml.
export 'db/pg_client.dart' show supabase, databaseDescription, logSql;
export 'db/pg_auth.dart'
    show
        AuthUser,
        User,
        AuthSession,
        AuthResponse,
        UserAttributes,
        AuthException,
        AuthApiException,
        OAuthProvider;
export 'db/pg_realtime.dart'
    show PostgresChangeEvent, PostgresChangePayload, PgChannel;
export 'db/pg_query.dart' show PgQuery, PgQueryException;
export 'db/pg_client.dart' show PgClient;
