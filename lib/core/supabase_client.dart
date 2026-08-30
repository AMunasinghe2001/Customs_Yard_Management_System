/// The database handle.
///
/// This used to construct a Supabase client against a cloud project. The app
/// now talks to the office PostgreSQL server directly, so the name `supabase`
/// resolves to a local client with the same API instead — see lib/core/db/.
///
/// The name is kept deliberately. It appears at 198 call sites across 24
/// files; renaming it would be churn with no behavioural change, and would
/// bury the real diff of this migration in noise.
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
