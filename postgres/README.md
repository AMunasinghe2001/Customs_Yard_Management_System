# Running this project on the office PostgreSQL server

The app used to talk to Supabase's cloud. It now connects straight to a
PostgreSQL server on the office PC. These files build that database.

## Run order (pgAdmin 4, against `Customs_SR_DB`)

| # | File | What it does |
|---|------|--------------|
| 1 | `01_supabase_compat.sql` | Recreates the `auth` schema Supabase provided — `auth.uid()`, `auth.role()`, `auth.users` — plus the `anon` / `authenticated` / `service_role` roles and the `supabase_realtime` publication. |
| 2 | `02_schema.sql` | Every table, function, policy and trigger: the base schema followed by all 76 migrations in date order. |

Run 1 first. `02_schema.sql` references `auth.uid()` 66 times and alters the
publication 11 times, so without it the very first migration fails.

Both files are idempotent — re-running them is safe and changes nothing.

## Why the compatibility layer exists

All 73 RLS policies were written against `auth.uid()`. Recreating that one
function means **not a single policy had to be rewritten** — they carry over
exactly as they were. Rewriting them by hand would have been 73 chances to
widen access by accident, in a system where data isolation is the point.

`auth.uid()` reads a session variable the app sets right after connecting:

```sql
select set_config('app.current_user_id', '<uuid>', false);
select set_config('app.current_role',    'authenticated', false);
```

See `PgDatabase.setCurrentUser()` in `lib/core/db/pg_connection.dart`. Signed
out, the variable is empty, `auth.uid()` is NULL, and every user-scoped policy
denies — a bug that forgets to set it locks the user out rather than showing
them everything.

## Connection settings

The app reads these at build time, with defaults for a local server:

```
flutter run \
  --dart-define=PG_HOST=192.168.1.50 \
  --dart-define=PG_PORT=5432 \
  --dart-define=PG_DATABASE=Customs_SR_DB \
  --dart-define=PG_USER=postgres \
  --dart-define=PG_PASSWORD=...
```

For other machines to reach the server, the server PC needs `listen_addresses`
in `postgresql.conf` and a LAN rule in `pg_hba.conf`.

## Regenerating the schema

`02_schema.sql` is generated — do not edit it by hand. After adding a migration
under `supabase/migrations/`:

```
python postgres/build_schema.py
```

The migrations stay the source of truth; the script only stitches them together
and adds the guards that make a second run a no-op.
