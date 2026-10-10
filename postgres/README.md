# Running this project on the office PostgreSQL server

The app used to talk to Supabase's cloud. It now connects straight to a
PostgreSQL server on the office PC. These files build that database.

## Run order (pgAdmin 4, against `Customs_SR_DB`)

| # | File | What it does |
|---|------|--------------|
| 1 | `01_auth_and_session.sql` | Creates the project's own `sr_auth` schema — `sr_auth.uid()`, `sr_auth.role()`, `sr_auth.users` — plus the `anon` / `authenticated` / `service_role` grant-target roles and the change-notification publication. **Standard PostgreSQL only**: the sole extensions are `uuid-ossp` and `pgcrypto`, both shipped with Postgres. |
| 2 | `02_schema.sql` | Every table, function, policy and trigger: the base schema followed by all source migrations in date order. |
| 3 | `03_realtime.sql` | NOTIFY triggers on the 18 tables the app watches, replacing Supabase's realtime channels. |
| 4 | `04_auth.sql` | `sign_in` / `sign_up` / `change_password` over `sr_auth.users`, using bcrypt. ⚠️ Re-creates `sr_auth.change_password` UNWRAPPED, which undoes the caller-owns-the-account guard from `migrations/018`. Re-apply 018 after this file, or an expired session can change somebody else's password. |
| 5 | `66_yard_app_role.sql` | Creates the non-superuser account the desktop clients use, so PostgreSQL RLS actually enforces each yard boundary. |

Run them in order. Each depends on the one before: `02_schema.sql` references
`sr_auth.uid()` 66 times, `03_realtime.sql` needs the tables to exist, and
`04_auth.sql` calls `public.email_for_login()` which arrives with the schema.

All four are idempotent — re-running them is safe and changes nothing. Each
ends with a VERIFY query; `04_auth.sql` raises if bcrypt is not working.

## Creating the first account

`sr_auth.users` starts empty, so nobody can log in yet. Create the first admin in
the Query Tool, then sign in through the app and use the ICT portal for the
rest:

```sql
select * from sr_auth.sign_up(
  'admin@customs.gov.lk',
  'choose-a-strong-password',
  '{"full_name":"System Admin","role":"admin"}'::jsonb
);

-- profiles.id is a foreign key to sr_auth.users(id), so use the id returned above
insert into public.profiles (id, full_name, role, is_active)
values ('<the id from above>', 'System Admin', 'admin', true)
on conflict (id) do update set role = 'admin', is_active = true;
```

## Why the compatibility layer exists

All 73 RLS policies were written against `sr_auth.uid()`. Recreating that one
function means **not a single policy had to be rewritten** — they carry over
exactly as they were. Rewriting them by hand would have been 73 chances to
widen access by accident, in a system where data isolation is the point.

`sr_auth.uid()` reads a session variable the app sets right after connecting:

```sql
select set_config('app.current_user_id', '<uuid>', false);
select set_config('app.current_role',    'authenticated', false);
```

See `PgDatabase.setCurrentUser()` in `lib/core/db/pg_connection.dart`. Signed
out, the variable is empty, `sr_auth.uid()` is NULL, and every user-scoped policy
denies — a bug that forgets to set it locks the user out rather than showing
them everything.

## Connection settings

The app reads these at build time, with defaults for a local server:

```
flutter run \
  --dart-define=PG_HOST=192.168.1.50 \
  --dart-define=PG_PORT=5432 \
  --dart-define=PG_DATABASE=Customs_SR_DB \
  --dart-define=PG_USER=yard_app \
  --dart-define=PG_PASSWORD=...
```

For other machines to reach the server, the server PC needs `listen_addresses`
in `postgresql.conf` and a LAN rule in `pg_hba.conf`.

## Regenerating the schema

`02_schema.sql` is generated — do not edit it by hand. After adding a migration
under `migrations/`:

```
python postgres/build_schema.py
```

The migrations stay the source of truth; the script only stitches them together
and adds the guards that make a second run a no-op.
