# The database layer

The app used to talk to Supabase's cloud over HTTP. It now talks to a
PostgreSQL server on the office LAN over the wire protocol. This directory is
everything that changed.

The guiding decision: **keep the call sites**. There are 198 of them across 24
files. Rather than rewrite each one, the pieces of Supabase the app actually
used are reimplemented against Postgres, behind the same names. `supabase`
still means "the database", and `supabase.from('packages').select(...)` still
works — it just generates SQL now.

## The files

| File | What it does |
|------|--------------|
| `pg_connection.dart` | The single live connection. Reconnects once on a dropped socket, and re-declares the session user each time. |
| `pg_client.dart` | The `supabase` object: `from`, `auth`, `channel`, `rpc`. |
| `pg_select_parser.dart` | Parses PostgREST select strings (`*, package_items(*)`) into a tree. |
| `pg_query.dart` | Turns that tree plus the filters into SQL, and runs it. |
| `pg_schema.dart` | Caches the foreign keys, read from the catalog, so embeds know how tables join. |
| `pg_auth.dart` | Sign in / sign up / password change, against `sr_auth.users`. |
| `pg_realtime.dart` | LISTEN/NOTIFY in place of Supabase's websocket channels. |

## How an embed becomes SQL

This is the part worth understanding. PostgREST let a query pull in related
tables:

```dart
supabase.from('packages').select(
  '*, package_items(*), warehouse_entries(*, warehouses(*))')
```

`pg_query.dart` turns each embed into a correlated subquery, choosing the shape
from the direction of the foreign key:

- **to-many** (the other table points back here) → `json_agg(...)` → a list
- **to-one** (this table points out) → `to_jsonb(...) limit 1` → an object

That distinction matters because the models depend on it: `json['profiles']` is
read as a `Map`, `json['package_items']` as a `List`. Getting it backwards
would not fail here — it would fail much later, inside `fromJson`.

The direction is read from the live catalog (`pg_schema.dart`), not hard-coded,
so a migration that adds a relationship needs no change in Dart.

Where two foreign keys join the same pair of tables — `warehouse_entries` has
both `admitted_by` and `returned_by` into `profiles` — the embed must say which
it means, exactly as it did under PostgREST:

```
returned_profile:profiles!returned_by(full_name, badge_number)
```

`returned_profile:` is the key the result comes back under; `!returned_by`
picks the foreign key. Without the hint the builder refuses rather than
guessing, because guessing would put the wrong officer's name on a record.

## How RLS still works

Every one of the 73 policies is written against `sr_auth.uid()`. On Supabase that
came from the JWT. Here `sr_auth.uid()` is a SQL function reading a session
variable, and `PgAuth` sets it on sign-in:

```
signInWithPassword() -> PgDatabase.setCurrentUser(id)
                     -> set_config('app.current_user_id', id, false)
                     -> sr_auth.uid() returns id
                     -> the same 73 policies apply, unchanged
```

Signed out, the variable is empty, `sr_auth.uid()` is NULL, and user-scoped
policies deny. A bug that forgets to set it locks the user out rather than
showing them everything — the failure falls the safe way.

`setCurrentUser` is re-applied on every reconnect, because the setting belongs
to the session and a new connection starts a fresh one.

## Sessions are not persisted

Closing the app signs the officer out. This is not an oversight: the Supabase
build installed a `LocalStorage` that stored nothing, and the same choice is
kept here. On a shared office machine the next person to open the app must sign
in as themselves.

`PgAuth.restoreSession()` therefore always returns null. It exists so start-up
reads the same either way, and so enabling persistence later would be one
change in one place.

## Realtime

The 19 change callbacks in `providers.dart` all ignore their payload and just
fire a refresh. So the notification carries only the table name and the
operation — no row data. That keeps it well under the 8000-byte NOTIFY limit,
and means a listener is never handed a row its own RLS policies would have
hidden: it re-reads through the normal queries instead.

`PgRealtime` holds its own connection for this. A listener spends its time
blocked waiting, and Postgres only delivers notifications between transactions,
so sharing the main connection would make them arrive late or not at all.

If the listener drops it reconnects with backoff. Realtime failing degrades the
app to manual refresh; it does not break it.

## What is deliberately not supported

- **Google sign-in.** There is no identity provider on an office LAN.
  `signInWithOAuth` throws a clear message rather than appearing to work.
- **Embeds in a mutation's `RETURNING`.** An insert returns its own columns; a
  call site that needs the related rows re-reads, which is what the HTTP client
  did anyway.
- **`delete()` with no filter.** It would empty the table. Every call site has
  a filter today; if a refactor drops one, this throws instead of obeying.

## Configuration

Compile-time, with defaults for a local server:

```
flutter run \
  --dart-define=PG_HOST=192.168.1.50 \
  --dart-define=PG_DATABASE=Customs_SR_DB \
  --dart-define=PG_USER=postgres \
  --dart-define=PG_PASSWORD=...
```

## Debugging a query

```dart
logSql = true;   // prints the generated SQL for every query
```
