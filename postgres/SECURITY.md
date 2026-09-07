# Network & Database Security

How this app's traffic is protected, what the current server actually does,
and what has to change before the database is reachable from anywhere but the
machine it runs on.

Run the audit at any time — it checks all of this against the live server
rather than against this document, which can go stale:

```bash
python tool/audit_network_security.py                      # local install
python tool/audit_network_security.py --host 10.0.5.20 --expect-remote
```

Exit code 0 = clean, 1 = at least one CRITICAL finding, so it can gate a
release step.

---

## 1. Transport (TLS)

### How the app decides

Four settings, resolved by `AppEnv` in the usual order (`--dart-define` >
`.env` > compiled default). All live in `PgConfig`
([lib/core/db/pg_connection.dart](../lib/core/db/pg_connection.dart)):

| Setting | Default | Effect |
|---|---|---|
| `PG_SSL` | `false` | `true` → TLS. `false` → `SslMode.disable` (plaintext). |
| `PG_SSL_VERIFY` | `false` | `true` → `SslMode.verifyFull`; `false` → `SslMode.require`. |
| `PG_REQUIRE_TLS` | `false` | `true` → an inadequate transport **throws at start-up** instead of connecting. |
| `PG_HOST` | `localhost` | Loopback vs. remote decides whether plaintext is a finding. |

`require` vs `verifyFull` is the distinction that matters, and it is easy to
get wrong: **`require` encrypts but accepts any certificate.** Anything on the
path can present its own and read every query in clear — the traffic "is TLS"
and is still fully readable. Only `verifyFull` checks that the server is the
server. On a LAN with a self-signed certificate `require` is a reasonable
trade; over any network you do not own it is not.

Both the pool and the realtime `LISTEN` connection take their mode from the
same `PgConfig`, so there is no second connection quietly running in the
clear.

### The start-up check

`PgConfig.enforceTransportPolicy()` runs in `PgDatabase._open()` **before the
socket is opened** — a plaintext connection to a remote host has already sent
the password by the time the first query runs, so the check has to come first.

It classifies three states:

| State | Result |
|---|---|
| plaintext → `localhost` | fine, no warning (nothing crosses a wire) |
| TLS unverified → remote | warning (encrypted, but MITM-able) |
| plaintext → remote | warning, or **start-up failure** when `PG_REQUIRE_TLS=true` |

The default is warn-not-fail so existing LAN installs keep working. **Set
`PG_REQUIRE_TLS=true` on any deployment outside the office LAN** — that turns
a mistyped `.env` into a loud failure instead of a silent downgrade.

### Current state of this server

`ssl = off`. The app and the database are on the same machine and Postgres
listens on `localhost` only, so no query currently crosses a network. That is
the only reason plaintext is acceptable here.

### Enabling TLS (required before the DB moves off this machine)

1. Obtain a certificate for the server (internal CA, or self-signed for a LAN):

   ```bash
   openssl req -new -x509 -days 730 -nodes -text \
     -out server.crt -keyout server.key -subj "/CN=<server hostname>"
   chmod 600 server.key
   ```

2. In `postgresql.conf`:

   ```
   ssl = on
   ssl_cert_file = 'server.crt'
   ssl_key_file  = 'server.key'
   ssl_min_protocol_version = 'TLSv1.2'   # refuse TLS 1.0/1.1 outright
   ```

3. Force TLS for network clients in `pg_hba.conf` — `hostssl`, never `host`,
   so a client cannot negotiate down to plaintext:

   ```
   hostssl  all  all  10.0.5.0/24  scram-sha-256
   ```

4. On the client side set `PG_SSL=true`, `PG_SSL_VERIFY=true` and
   `PG_REQUIRE_TLS=true`, then re-run the audit — it reports the negotiated
   TLS version and cipher from `pg_stat_ssl`, so you can confirm 1.2+ rather
   than assume it.

---

## 2. SQL injection

### The short answer

Every **value** the app sends is a bound parameter. Nothing user-typed is ever
concatenated into SQL text.

### Why that holds

The app has no hand-written SQL. All 198 call sites go through `PgQuery`
([lib/core/db/pg_query.dart](../lib/core/db/pg_query.dart)), which builds the
statement and hands values to the driver separately:

```dart
// what a screen writes
supabase.from('packages').select('*').eq('sr_number', userTypedText)

// what reaches the server
select t.* from "packages" t where t."sr_number" = @p0
// with p0 bound out-of-band — never spliced into the string
```

`.eq/.neq/.gt/.gte/.lt/.lte/.like/.ilike/.in/.contains`, every `insert`,
`update` and `upsert` value, and every leaf of an `or()` group all bind this
way. The audit greps the whole db layer for interpolation in a value position
and currently reports none.

Three places interpolate deliberately, because **Postgres cannot bind them** —
an identifier is syntax, not data:

| What | Protection |
|---|---|
| Column / table names | `_quoteIdent` / `_quoteRel` — double-quoted, embedded `"` doubled. All come from string literals in the app, never from user input. |
| Aliases (`t`, `f0`, `v3`) | Generated by a counter. No external input. |
| RPC function and argument names | Validated against `^[A-Za-z_][A-Za-z0-9_$]{0,62}$` and rejected outright otherwise ([pg_client.dart](../lib/core/db/pg_client.dart)). |

The RPC check is new. `rpc()` must write `name => @name`, and the `name =>`
half cannot be a parameter — so the name is pasted in. Every call site passes
a literal today; the validator is what keeps that true if someone later builds
a params map out of a field name. It fails loudly rather than escaping.

`isNull()` and the `is`/`in` branches emit `null`/`true`/`false` as literal
SQL keywords because `col is @p` does not parse — these are keywords chosen by
a `switch`, not user text.

Covered by [test/network_transport_security_test.dart](../test/network_transport_security_test.dart)
and [test/pg_query_sql_test.dart](../test/pg_query_sql_test.dart).

### Raw SQL is confined

`PgDatabase.query/execute` is only reachable from inside `lib/core/db/`. No
screen or service builds a statement of its own — the audit fails if one
starts to.

---

## 3. Row-Level Security

**112 policies across 27 tables.** RLS is the primary access control: the app
sets `app.current_user_id` / `app.current_role` per connection (re-applied on
every pooled connection via `onOpen`, since the settings are per-session), and
`auth.uid()` reads them, so the policies written for Supabase apply unchanged.

Signed out, `auth.uid()` is null and user-scoped policies deny. That default is
deliberate: a bug that forgets to set the user locks people out rather than
showing them everything.

Two intentional shapes the audit understands:

- **Reference tables with no RLS** — `hold_reasons`, `package_categories`,
  `storage_rates`, `app_migration_flags`, `sr_number_migration_log`. Fixed code
  lists, no personal or case data.
- **`officer_signup_otps`: RLS on, zero policies.** Not an oversight — with no
  policy, RLS denies everyone, making it a deny-all lockbox for signup OTPs and
  the applicant's name/badge/mobile. Only a role that *bypasses* RLS may read
  it (`service_role` on Supabase). The audit flags the opposite failure: RLS
  being switched off.

### ⚠️ Open finding: the app connects as `postgres`

`postgres` is a **SUPERUSER, and superusers bypass RLS entirely.** As it
stands, all 112 policies and the OTP lockbox are inert — enforcement rests
purely on the app's own checks.

Locally this is contained: the server is loopback-only, so nothing off-machine
can reach it. **Before the database accepts a single network connection, give
the app its own least-privilege role:**

```sql
create role yard_app with login password '<strong password>';

grant connect on database "Customs_SR_DB" to yard_app;
grant usage on schema public, auth to yard_app;

grant select, insert, update, delete
  on all tables in schema public to yard_app;
grant usage, select on all sequences in schema public to yard_app;
grant execute on all functions in schema public to yard_app;
grant execute on all functions in schema auth to yard_app;

-- future objects
alter default privileges in schema public
  grant select, insert, update, delete on tables to yard_app;
alter default privileges in schema public
  grant usage, select on sequences to yard_app;

-- NOT superuser, NOT bypassrls → policies actually apply.
-- officer_signup_otps stays unreachable for it, which is correct: the OTP
-- flow runs through SECURITY DEFINER functions, not direct table access.
```

Then set `PG_USER=yard_app` / `PG_PASSWORD=...` and re-run the audit — the
warning becomes an `ok`. Test the OTP signup flow afterwards; if it reaches
the table directly rather than through a `SECURITY DEFINER` function, that
function is what needs adding, not a policy.

---

## 4. Connection origin restriction

Defence in depth: TLS stops the traffic being read, this stops the connection
being made at all.

### Current state

`listen_addresses = localhost` — the server accepts nothing from the network.
This is the strongest possible setting and should stay until the database
genuinely has to serve other machines.

### ⚠️ Open finding: `trust` authentication

`C:/pgsql-extract/data/pg_hba.conf` lines 117–126 use `trust` for local and
`127.0.0.1` / `::1` connections, including replication:

```
local   all          all                trust
host    all          all  127.0.0.1/32  trust
host    all          all  ::1/128       trust
```

**`trust` means no password is checked at all.** Any process on this machine —
any user account, anything that gets code running on it — connects as
`postgres` (superuser, RLS-bypassing) by simply asking. `PG_PASSWORD` is not
being verified.

Not remotely exploitable while `listen_addresses = localhost`, but it removes
the last barrier for anything already on the box. Fix:

```
# pg_hba.conf — replace every `trust` with:
local   all          all                     scram-sha-256
host    all          all   127.0.0.1/32      scram-sha-256
host    all          all   ::1/128           scram-sha-256
```

Set a real password first (`ALTER ROLE postgres WITH PASSWORD '...';`),
confirm `password_encryption = scram-sha-256`, then reload
(`SELECT pg_reload_conf();`) — and keep a session open while testing, so a
mistake does not lock you out.

### When the database moves to a server

1. **Bind narrowly** — `listen_addresses = '10.0.5.20'`, not `'*'`.
2. **Range-restrict in `pg_hba.conf`**, most specific first. Never `0.0.0.0/0`:

   ```
   hostssl  Customs_SR_DB  yard_app  10.0.5.0/24   scram-sha-256
   hostssl  Customs_SR_DB  yard_app  10.0.6.40/32  scram-sha-256   # single kiosk
   host     all            all       0.0.0.0/0     reject
   ```

3. **Firewall 5432 as well** — `pg_hba` rejects after accepting the TCP
   connection; the firewall stops it being opened:

   ```powershell
   New-NetFirewallRule -DisplayName "PostgreSQL LAN only" `
     -Direction Inbound -Protocol TCP -LocalPort 5432 `
     -RemoteAddress 10.0.5.0/24 -Action Allow
   New-NetFirewallRule -DisplayName "PostgreSQL block all others" `
     -Direction Inbound -Protocol TCP -LocalPort 5432 -Action Block
   ```

4. **Remote officers use the VPN, never a port forward.** Publishing 5432 to
   the internet exposes the authentication handshake to everyone; a VPN keeps
   the client inside the allowed range, so `pg_hba` and the firewall stay
   meaningful. If a port forward is ever unavoidable, `PG_REQUIRE_TLS=true`
   plus `PG_SSL_VERIFY=true` is the minimum, and it is still worse than a VPN.

5. **Limit the blast radius** — `max_connections` sized to the fleet, plus
   `connection_throttling` / fail2ban-style lockout if the host offers it. The
   app already enforces its own 5-attempt account lockout in `auth.sign_in()`.

---

## 5. Other network traffic

| Destination | Transport | Notes |
|---|---|---|
| `date.nager.at` (public holidays) | **HTTPS** | Dart validates the certificate chain by default. Read-only, no app data sent. Failure degrades to weekend-only deadlines. |
| Update feed (`UPDATE_FEED_URL`) | **HTTPS enforced** | See below. Unset by default → auto-update off. |

The appcast is the sharpest of these, because it decides which installer the
app downloads **and runs**. Over plain HTTP, anyone answering for that host can
serve their own `.exe` — remote code execution, not eavesdropping. So
[app_updater.dart](../lib/core/app_updater.dart) refuses a feed unless it is:

- `https://` — always allowed; or
- `http://` **and** `ALLOW_INSECURE_UPDATE_FEED=true` **and** a private-range
  host (loopback, `10.x`, `192.168.x`, `172.16–31.x`, `169.254.x`).

A public `http://` URL is refused whatever the flags say. A rejected feed logs
`SECURITY: refusing update feed ...` and disables updates rather than failing
open. Prefer HTTPS even internally, and sign the installer so the updater
verifies the binary itself.

---

## Summary

| Control | State |
|---|---|
| Values parameterised, no SQL concatenation | ✅ verified, audited |
| RPC identifiers validated | ✅ added |
| Raw SQL confined to `lib/core/db` | ✅ verified |
| RLS: 112 policies, correct deny-by-default | ✅ verified |
| TLS config, warning + `PG_REQUIRE_TLS` enforcement | ✅ added |
| Update feed HTTPS enforcement | ✅ added |
| Repeatable audit script | ✅ `tool/audit_network_security.py` |
| Server `ssl = off` | ⚠️ acceptable **only** while loopback-only |
| App connects as superuser `postgres` | ⚠️ open — RLS bypassed; fix before networking |
| `pg_hba` uses `trust` | ⚠️ open — no password enforced on this machine |

The three open items are all server configuration on the live machine, not app
code. None is remotely exploitable while `listen_addresses = localhost`, and
**all three must be closed before the database accepts its first network
connection.**
