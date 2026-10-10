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

---

## 6. User-level policies (MFA, passwords, RBAC)

Applied by [52_user_security_policies.sql](52_user_security_policies.sql).
Audit with `python tool/audit_user_security.py`.

### Second factor

The OTP-gated portals are Central Disposal, Valuation, Appeal, Executive and
ICT. `kDevSkipOtp` used to be a plain `const bool` a developer flipped to
`true` and was trusted to flip back — a second-factor bypass for every
privileged portal, one forgotten line from shipping, with nothing in the built
`.exe` to reveal it.

It is now the AND of two things:

```dart
const bool kDevSkipOtp = _devSkipOtpDefine && !kReleaseMode;
```

- **`!kReleaseMode`** — a release build can never skip OTP, whatever the source
  says. This is the half that cannot be forgotten.
- **`--dart-define=DEV_SKIP_OTP=true`** — an explicit per-build opt-in, so
  skipping OTP is something typed on a command line, not a state the repository
  can be committed in.

⚠️ `kReleaseMode`, not `!kDebugMode`: a **profile** build is neither, and
keying off `kDebugMode` would have left profile builds able to skip the code.

### Password strength

**`public.password_policy_violation(text)` is the single definition** —
12+ characters, upper, lower, digit, special, no common word, 128 max (bcrypt
only hashes 72 bytes, so a longer one is refused rather than silently
truncated). It returns the first failure as a sentence, or null.

Called by `auth.sign_up` and `auth.change_password`, which is what makes it a
control: both are reachable as RPCs without going through any screen.

⚠️ Before this, **14 screens each carried their own `length < 8` check, one
still allowed 6, and the server accepted anything over 5.** The weakest rule
anywhere is the one that actually applies — and it was the server's.
`PasswordPolicy` in `lib/core/security_policy.dart` now mirrors the SQL so the
user sees the rule before submitting; a test pins the mirror to the migration
so the two cannot drift.

`auth.change_password` also **refuses the current password**. Without that, a
90-day expiry prompt is satisfied by retyping the same password, which resets
the clock and changes nothing.

### Rotation

`profiles.password_updated_at` (trigger-maintained) anchors a 90-day life with
a 7-day warning. `public.password_age_status(uuid)` answers server-side —
defaulting to the caller, and allowing another user's row only for `admin` /
`ict`. `public.password_rotation_status` lists ages for the admin panel.

⚠️ The SQL warns from **day 83** because the client warns for the last 7 days
of 90. If you change one, change the other, or the app nags on a different day
than the server and it reads as a bug.

### RBAC

Roles are enforced **in the database**, not by hiding buttons. 16 screens hide
controls by role, and that is cosmetic — every privileged path is re-checked
server-side by RLS policies and by explicit guards inside the functions.

⚠️ **`SECURITY DEFINER` functions run with the definer's rights, so RLS does
not apply inside them.** Whatever such a function does not check, it permits.
The audit therefore checks every `SECURITY DEFINER` function that *writes*:
19 of them, each re-verifying the caller (or listed as exempt with a reason —
pre-authentication functions and triggers).

**Found and fixed:** `disposal_toggle_outcome_delivery` was `SECURITY DEFINER`,
granted to **`public`** (which includes `anon`), and asked nothing about its
caller — while marking goods handed over *and* closing the warehouse entry. Any
account could release any consignment in any yard. It now carries the same
guard as its sibling `disposal_toggle_delivery_status` (Central Disposal, or an
officer of that yard) and is granted to `authenticated` only. Verified live: a
wrong-yard officer gets `not authorized`; Central Disposal is allowed.

---

## 7. Audit trail: append-only

Applied by [53_audit_append_only.sql](53_audit_append_only.sql).
Audit with `python tool/audit_backup_readiness.py`.

### What was wrong

`audit_logs` sat in the generic list of yard-scoped data tables, so it received
the same policy as `packages`:

```sql
create policy yard_all on public.audit_logs
  for all using (yard = auth_user_yard()) with check (...);
```

**`for all` includes UPDATE and DELETE.** Any officer could edit or delete the
audit rows for their own yard - including the rows recording what they had just
done. A trail whose subject can rewrite it is not evidence of anything.

### What enforces it now

Several layers, because each one alone has a hole:

| Layer | Stops | Bypassed by |
|---|---|---|
| RLS policies (`audit_insert`, `audit_select` only - no UPDATE/DELETE policy exists) | ordinary roles | a superuser |
| `force row level security` | the table owner | a superuser |
| `revoke update, delete, truncate` | roles without the grant | a superuser |
| **BEFORE UPDATE / DELETE row triggers** | **everyone, superuser included** | - |
| **BEFORE TRUNCATE statement trigger** | **everyone** | - |

**The triggers are the layer that actually holds today**, because the app
connects as the superuser `postgres`, which bypasses RLS and grants (see the
open finding in section 3). Until that moves to `yard_app`, the policies are
defence in depth and the triggers are the control.

**TRUNCATE does not fire row triggers and is not a DELETE.** With only the row
triggers in place, `truncate audit_logs` succeeded as superuser and would have
emptied the entire table in one statement - the worst case this section exists
to prevent. It needs its own statement-level trigger.

**Impersonation needed a trigger too.** The `audit_insert` policy already says
a caller may only write as themselves, but a superuser ignores policies: acting
as a signed-in officer, an insert naming *another* user's id was accepted. The
same rule is now restated in the insert trigger, which no role bypasses.

Verified as superuser - the strongest possible caller:

```
INSERT (own id)          -> ALLOWED     (logging works)
INSERT (another user id) -> BLOCKED     (no forging entries)
UPDATE                   -> BLOCKED
DELETE                   -> BLOCKED
TRUNCATE                 -> BLOCKED
```

### The one sanctioned deletion

`purge_old_audit_logs()` keeps the 365-day window the app relies on. It is the
only path that can remove a row, via a transaction-local flag
(`app.audit_purge`) the trigger recognises - and **it records its own run** in
the log, so a gap in the trail has a matching entry explaining it rather than
looking like tampering.

### What is recorded

Every entry now carries `client_addr` (the server's own view of the socket,
from `inet_client_addr()`), `app_name`, `db_user` and `created_at`, stamped by
a trigger so a caller can neither forge them nor forget them.

Two event classes that were **never reaching the log** now do:

- **Failed logins.** `auth.record_failed_login` incremented a counter and
  locked the account but wrote nothing - the table held **zero** failed-login
  rows, so a brute-force attempt left no trace beyond a counter that clears on
  the next success. It now logs every attempt with the attempt count, the
  client address, and the lockout event at attempt 5. It logs attempts against
  **non-existent** e-mails too: someone guessing addresses is exactly what an
  audit trail should show.

  `audit_logs.user_id` is a foreign key to **`profiles`**, not `auth.users`.
  An auth user with no profile row made this insert violate that key, and
  because the insert runs inside `record_failed_login`, the violation
  propagated out and **broke the sign-in attempt itself**. Logging a failed
  login must never be able to break logging in - so the FK column is left null
  when no profile exists, while `entity_id` (plain text, no key) keeps the real
  id.

- **Role and privilege changes.** Role is changed by a plain `UPDATE` on
  `profiles` from several screens, so there is no single call site to
  instrument. An `AFTER UPDATE` trigger catches `role`, `is_active`, `yard` and
  `directorate` changes with before/after values - **including a change made
  directly in pgAdmin**, which is the case that matters most. It records
  *who did it* (`auth.uid()`), not who it was done to; a null there means a
  direct database edit, which is itself worth seeing.

---

## 8. Backups and Point-in-Time Recovery

### Daily backups

[tool/backup_database.ps1](../tool/backup_database.ps1) takes a compressed
custom-format dump, **verifies it**, then retires old ones.

```powershell
.\tool\backup_database.ps1
.\tool\backup_database.ps1 -Destination E:\Backups -RetentionDays 90
```

**A backup nobody has restored is a guess.** The script runs
`pg_restore --list` over every file it writes - that reads the whole archive
and fails on a truncated one, the failure mode that otherwise stays invisible
until the day it matters. It also asserts `audit_logs` is in the archive: a
dump that restores cleanly but without the trail would look like a success and
leave you with a system that has no history.

Retention deletes old files **last**, only after the new one is written and
verified, so a failed run never leaves you with nothing.

`pg_dump` is **not on PATH on this machine** - PostgreSQL 18.6 was unpacked to
`C:\pgsql-extract` rather than installed - so the script locates the binaries
itself. A scheduled task would otherwise fail with "not recognized as the name
of a cmdlet", and its only symptom is a failed run nobody reads.

`--verbose` and `2>&1` are deliberately absent: `pg_dump` writes progress to
stderr, and in Windows PowerShell 5.1 redirecting a native command's stderr
wraps each line in an ErrorRecord - a completely successful dump came back
looking like a failure. Judge the run by `$LASTEXITCODE`.

**Schedule it** (daily 01:00, as SYSTEM or a service account) - see
`Register-ScheduledTask` with `-Execute powershell.exe` and
`-Argument '-NoProfile -ExecutionPolicy Bypass -File <repo>\tool\backup_database.ps1'`,
on a `New-ScheduledTaskTrigger -Daily -At 1:00AM`, with `-RunLevel Highest`.

Give it credentials without putting a password in the task: create
`%APPDATA%\postgresql\pgpass.conf` containing
`localhost:5432:Customs_SR_DB:postgres:<password>`, readable only by that
account. `PGPASSWORD` also works but is visible in the process environment.

### Retention schedule

| Copy | Kept | Where |
|---|---|---|
| Daily full dump | 30 days | `D:\Backups` - **a different physical disk from the database** |
| Monthly archive (1st of month) | 12 months | off-machine: NAS, or an encrypted external drive held elsewhere |
| Yearly archive | 7 years | off-site, per record-retention policy |

The audit trail keeps **365 days**, so a 30-day backup window cannot answer an
audit question older than a month. The monthly archives are what make the
retention promise real - keep them at least as long as the trail.

A backup on the same disk as the database is not a backup: the failure that
takes the disk takes both. At least one copy must be off-machine.

### Point-in-Time Recovery (PITR)

**Current state: `archive_mode = off`.** PITR is *not* available today - the
most that can be recovered is the last nightly dump, so up to 24 hours of
seizure records, valuations and audit entries would be lost. `wal_level` is
already `replica`, which is sufficient; only archiving is missing.

To enable, in `postgresql.conf`:

```conf
wal_level = replica                 # already set
archive_mode = on                   # requires a restart, not a reload
archive_command = 'copy "%p" "E:\\WAL_Archive\\%f"'   # Windows
archive_timeout = 300               # force a segment every 5 min, so the
                                    # recovery window is bounded on a quiet day
```

Then restart the service and confirm archiving actually runs - a failing
`archive_command` silently fills `pg_wal` until the disk is full:

```sql
select archived_count, failed_count, last_archived_wal, last_failed_wal
  from pg_stat_archiver;
```

`failed_count` climbing is an outage in waiting, not a warning. The audit
script checks it.

**Taking a base backup** (the anchor PITR replays WAL onto):

```powershell
pg_basebackup -h localhost -U postgres -D E:\Backups\base_2026-09-07 -Ft -z -P
```

**Restoring to a point in time** - for example, just before a bad bulk update:

1. Stop PostgreSQL.
2. Move the current data directory aside (**do not delete it** - it is
   evidence, and the only copy of anything since the base backup).
3. Restore the base backup into a clean data directory.
4. Create `recovery.signal` in that directory, and in `postgresql.conf`:

   ```conf
   restore_command = 'copy "E:\\WAL_Archive\\%f" "%p"'
   recovery_target_time = '2026-09-07 14:25:00+05:30'
   recovery_target_action = 'promote'
   ```

5. Start PostgreSQL. It replays WAL to that instant and promotes.
6. **Verify before letting anyone in**: check `select count(*) from audit_logs`
   and the last `created_at`, and confirm the bad change is absent.

### Restore drill

Do this quarterly, on a scratch database - not on production, and not only on
paper. This exact sequence was run against a real backup of this database:

```
psql -U postgres -c "create database restore_test"
pg_restore -U postgres -d restore_test D:\Backups\Customs_SR_DB_<stamp>.dump
psql -U postgres -d restore_test -c "select count(*) from audit_logs"
psql -U postgres -c "drop database restore_test"
```

Result: 579 audit rows, 176 packages and 11 profiles recovered - **and the
append-only protections came back with them.** The triggers, the two policies
and `force row level security` are all part of the dump, so a restored copy is
as tamper-resistant as the original. Confirmed by attempting a `DELETE` on the
restored table: refused.

Record each drill (date, dump used, row counts, who ran it). An untested
backup procedure is the one that fails during the incident.
