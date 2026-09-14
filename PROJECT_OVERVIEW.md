# Sri Lanka Customs — SR Management System

**A desktop system for the Seizure Report register: what was seized, where it
is being held, what it cost, and what finally happened to it.**

| | |
|---|---|
| Platform | Windows desktop (Flutter 3.41, Dart) |
| Database | PostgreSQL 18 — no cloud service, no third-party backend |
| Scale built for | ~100 concurrent officers across the yards |
| Code | 141 Dart files · ~112,000 lines |
| Schema | 33 tables · 24 views · 169 functions · 74 triggers |
| Tests | 146 test files |

---

## 1 · The problem this solves

When Customs seizes goods, an SR (Seizure Report) is raised. From that moment
the goods generate obligations: they occupy warehouse space that costs money
each day, the owner has 30 days to appeal, a valuation must be set, a tender
must be run — perhaps four times — and eventually the goods are sold,
destroyed, released, re-exported or handed to another arm of government.

That whole life used to live in paper registers and spreadsheets held
separately by each yard and each directorate. Nobody could answer, from one
place, "where is SR 47, what has it cost us, and who decided that?"

This system is that one place.

---

## 2 · Who uses it — seven portals

Each office signs in to its own portal, sees only its own work, and carries its
own colour so nobody is ever unsure which system they are looking at.

### Yard side

**SC / DSC / ASC — Yard Officers**
Raise SRs, admit goods to a warehouse zone, record detentions and abandonments,
release goods back to their owner.

**SDDC / DDC — Yard Administration**
Everything an officer can do, plus the decisions an officer may not make:
recording a final disposition, and sending goods to Central Disposal.

### Head office directorates

**Valuation Directorate** — prices goods before each tender round, and re-prices
them after a round fails.

**Central Disposal Directorate** — runs tender sales, records bids, marks goods
sold or unsold, manages destruction and its costs, and keeps the disposal
expense ledger.

**Appeal Directorate** — holds goods while an appeal is heard, and records the
ruling: release, sell, destroy, re-export.

**Top Management (DGC / ADGC / SDC / DC)** — appoints a valuation committee when
three tenders have failed, and rules on goods that remain unsold after that.

**ICT Directorate** — provisions every account, edits yards and directorates,
sets storage rates and taxes, and reads the audit trail.

---

## 3 · The life of a seizure

```
    SR raised in a yard
            │
            ▼
    Goods admitted to a warehouse zone ──► storage charge accrues daily
            │
            ▼
    30-day appeal window ──────────────► Appeal Directorate may HOLD it
            │                                        │
            │                                        ▼
            │                              ruling: release / sell /
            │                                      destroy / re-export
            ▼
    Yard Administration sends a DISPOSAL REQUEST to Central Disposal
            │
            ▼
    Valuation Directorate prices it
            │
            ▼
    ┌─────────────────────────────────────────────┐
    │  Round 1   Valuation Tender                 │
    │  Round 2   Tender 1   ─┐                    │
    │  Round 3   Tender 2    ├ priced from the    │
    │  Round 4   Tender 3   ─┘ previous round's   │
    │                          unsold bids        │
    └─────────────────────────────────────────────┘
            │
            ▼ all four failed
    Top Management appoints a 5-member COMMITTEE, which sets a value
            │
            ▼
    Round 5   Committee Tender ── takes NO bids; it is a decision,
            │                     not an auction
            ▼ still unsold
    UNSOLD GOODS ──► the DG rules on the final outcome
```

Every step is enforced, not merely suggested — see §6.

---

## 4 · What each screen does

### Yard portals

| Screen | Purpose |
|---|---|
| SR Register | Raise and edit SR entries; consignee, goods, HS code, quantities |
| Warehouse | Admit goods to a zone; see occupancy and remaining capacity |
| Detained / Abandoned / Other | The three holding states, each with its appeal window |
| Perishable Goods | No warehouse, no appeal window — straight to disposal |
| Forfeited Packages | Goods past their window, ready for disposal |
| Released Goods | Handed back to the owner, with the receipt |
| Reports | Register extracts, storage charges, activity |

### Central Disposal

| Screen | Purpose |
|---|---|
| Disposal Requests | Incoming requests from the yards |
| Tender Sales | Schedule a sale, record bids, mark items sold or unsold |
| Unsold Tenders | Failed rounds awaiting re-valuation and re-tender |
| Committees | Packages past Tender 3, awaiting a Top Management committee |
| Sold / Unsold / Destroyed Goods | Final outcome tables |
| Government Use / Auction / Re-export / Converted | The other outcomes |
| Disposal Expenses | The money ledger: deposits, destruction, advertising, labour, transport, auction, refunds |

### Directorates

| Portal | Screens |
|---|---|
| Valuation | Pending valuations · per-item forwarding · re-valuation per round |
| Appeal | Active appeals (hold / window) · decided goods with their rulings |
| Top Management | Tender committees · committee valuations · unsold decisions · financials · reports |
| ICT | Staff accounts · directorate access · yards & directorates · rates & taxes · activity logs |

---

## 5 · Technical design

### 5.1 Shape

A **thin Windows client over PostgreSQL**. There is no application server and
no cloud service: the desktop app connects straight to the database with the
`postgres` Dart driver, and the database itself enforces every rule about who
may see and change what.

That choice is deliberate. A rule enforced in Dart protects only the officers
who use this app; a rule enforced in PostgreSQL protects the data from
*anything* that connects to it — this app, a future app, or `psql`.

```
   Windows desktop (Flutter)
            │  postgres driver, TLS
            ▼
   PostgreSQL 18
     ├── Row-Level Security ....... 153 policies (24 RESTRICTIVE), on every table
     ├── SECURITY DEFINER functions  auth, provisioning, workflow rules
     ├── Triggers ................. 74, including an append-only audit trail
     └── security_invoker views ... 23 of 24, so a view cannot bypass RLS
```

### 5.2 Stack

| Layer | Choice | Why |
|---|---|---|
| UI | Flutter 3.41 | One codebase, native Windows performance, no browser to secure |
| State | Riverpod | Providers are cached per session and dropped wholesale on sign-out |
| Routing | go_router | One place that decides which routes a session may reach |
| DB access | `postgres` (pure Dart) | Direct to PostgreSQL; no REST layer to secure separately |
| PDF / Excel | `pdf`, `printing`, `excel` | Register extracts and reports the office already needs |
| Charts | `fl_chart` | Financial summaries |

### 5.3 Performance work worth naming

**Paging in SQL, not in Dart.** Tables fetch twenty rows and a count, not the
whole table. Before this a page of the disposition tables pulled a year of rows
and paged them in memory, and the fetch grew all year.

**Heavy parsing on a background isolate.** Building several hundred package
models from driver rows blocks the UI thread, and Flutter delivers a click only
*between* frames — so a blocked thread does not make a button slow, it makes it
do nothing. Lists above a threshold are parsed off-thread.

**Closed-form storage charge.** The daily storage cost was a loop over every day
since admission, scanning every rate on each day. For an entry 500 days old,
run for every warehouse entry of every package, that took 1.5 seconds on the UI
thread. It is now a sum over rate *periods* — same figure to the rupee, a
handful of operations however old the entry.

**A permanent frame watchdog.** Any frame over 250ms is written to
`frame_watch.log` beside the executable, so a "the button does nothing" report
can be answered by reading a file instead of guessing.

### 5.4 Testing

146 test files. Alongside ordinary widget and logic tests, two kinds are worth
noting:

- **Rule tests that read the SQL**, so a migration cannot quietly drop a
  guarantee the app depends on.
- **Equivalence tests.** When the storage-charge loop was replaced, the old
  loop was kept in the test file and the new closed form was checked against it
  over 500 randomised spans and rate tables — because the figure is money.

Each migration also **verifies itself when applied**: it makes the change, then
proves the change did what it says, and refuses to complete if not.

---

## 6 · Security

Security here is not a feature list bolted on at the end. The consistent
principle is: **the database enforces it, the UI merely reflects it.**

### 6.1 Authentication

| Control | Detail |
|---|---|
| Passwords | bcrypt via `pgcrypto`; never stored or logged in the clear |
| Strength | 12–24 characters, upper, lower, digit, symbol, no common word — the same rule in Dart and in SQL, stated once |
| Rotation | Every 90 days, then the change is **mandatory** — the session can reach nothing but the change form |
| Reuse | The last 5 passwords are remembered and refused |
| Two-factor | One-time code by e-mail on sign-in, valid 5 minutes |
| Lockout | Repeated failures lock the account; every attempt is logged |
| Idle lock | The screen locks after 5 minutes and returns to that portal's own sign-in |
| Dormancy | An account unused for 30 days is disabled; only ICT can restore it |

⚠️ **Password expiry is enforced in the database, not the screen.** An expired
session's `auth.uid()` returns null, so RLS grants it nothing — it can read its
own profile row and change its password, and that is all. Walking back through
the UI cannot reach a dashboard, because there is nothing behind the door.

### 6.2 Who may see what

**Row-Level Security on every table**, 153 policies — verified: zero tables in `public` are without it.

- A yard officer sees **only their own yard's** packages, warehouse entries,
  forfeitures and tenders. This is enforced by policy, not by a `WHERE` clause
  the app remembers to add.
- Head-office directorates read across all yards by design — Appeal hears every
  yard's appeals — but each has its own explicit read policy rather than
  inheriting a yard's.
- **24 policies are RESTRICTIVE.** A permissive policy grants; a restrictive one
  can only subtract. The yard boundary and the "only SDDC/DDC may raise a
  disposal request" rule are restrictive, so no other policy can widen them.
- **23 of 24 views are `security_invoker`.** A view without it runs as its
  owner, and the officer's policies never apply — an unscoped view is a leak
  waiting for its first caller.

### 6.3 Separation of duties

| Act | Who |
|---|---|
| Raise an SR, admit goods | Yard officer |
| Record a final disposition | SDDC / DDC only |
| Send a disposal request | SDDC / DDC only — enforced by RESTRICTIVE policy |
| Price goods for tender | Valuation Directorate |
| Run a tender, record bids | Central Disposal |
| Rule on an appeal | Appeal Directorate |
| Appoint a committee, rule on unsold goods | Top Management |
| Create or restore any account | ICT only |

### 6.4 The audit trail

Every sign-in, failed attempt, account change and record change is written to
`audit_logs`, which is **append-only by trigger** — no UPDATE, no DELETE, no
TRUNCATE, for anyone. Retention is a year.

Two details matter:

- **A log row keeps the role its actor held that day.** Reading the role by
  joining `profiles` means a promotion silently rewrites history — every action
  an officer ever took becomes an SDDC action the day they are promoted.
- **A failed sign-in records the yard it targeted**, so ICT can see which office
  someone was guessing at.

### 6.5 Connection security

- The app **refuses to run as the `postgres` superuser.** It connects as
  `yard_app`, a non-superuser that cannot bypass RLS — the whole point of the
  separate role.
- TLS with optional certificate verification (`PG_SSL`, `PG_SSL_ROOT_CERT`).
- Connection settings live in a `.env` **beside the executable**, never inside
  the installer — shipping one would put a live credential in every copy and
  point every branch at the same server.
- A shipped build using the compiled-in default password says so out loud.

### 6.6 Data-integrity rules the database will not let you break

These are triggers and constraints, so they hold against a direct `INSERT` as
firmly as against the app:

- A package gets **at most five tender rounds**, and the fifth only after Top
  Management has submitted a committee value.
- The **committee round takes no bids** — it is a decision, not an auction.
- A **directorate account carries no yard**; a CHECK constraint refuses one.
- An officer may **change only their own password**.
- Goods **already destroyed cannot be given an appeal ruling** to sell or
  re-export.

### 6.7 Two problems found and fixed during development

Worth showing, because they are the kind that do not announce themselves:

**Same-email account takeover.** Signing up on a second portal with an existing
officer's e-mail did not fail — the app signed in as that account and wrote the
new role over it. One e-mail, one id: an ICT account *became* a Disposal
account and ICT ceased to exist. That is privilege escalation through a sign-up
form. The role is now compared before the profile is written, and a mismatch is
refused.

**Stale data between sessions.** Riverpod caches a provider's value for the life
of its container, and none of the ~100 data providers were `autoDispose` — so
one officer's rows stayed in memory after they signed out and rendered under the
next officer's name. GL1 packages under a GL2 officer. The database was scoping
correctly the whole time; the leak was in memory, which is why a `psql` session
and a database-level test both reported the boundary as sound. Sign-out now
rebuilds the whole provider container.

### 6.8 Hardening added after the first security review

A review asked for a set of enterprise controls. Most were already in place;
these are the ones that genuinely were not, with what was found.

**Saved passwords were not really encrypted.** "Remember me" on all seven
portals XOR-ed the password against a SHA-256 digest and wrote it to
SharedPreferences — a plain JSON file in the user's roaming profile. Three
things were wrong: XOR with a repeating key is not encryption; the key derived
from an `APP_SECRET` whose fallback was a string literal in that same source
file, so every build that did not pass `--dart-define` shipped the same secret;
and the file could be copied to another machine and read there. It now goes to
**Windows Credential Manager** through `flutter_secure_storage`, which encrypts
with the logged-in Windows account's own keys — copy the file elsewhere and it
yields nothing. An old blob found on a machine is deleted rather than migrated:
migrating it would mean decrypting the weak value to re-encrypt it, and the
officer types the password once instead.

**Any PC could sign in.** A machine that could reach the database and knew an
officer's credentials was accepted — a home laptop on the branch VPN, or a PC
taken out of a yard. There is now an **approved-device register**: the client
sends a hashed Windows machine GUID as a session variable, and `auth.sign_in`
refuses an unknown machine before the password is even checked.

⚠️ It is enforced **in the database, not the app**. A check in Dart is a check
the attacker controls — they are not obliged to run our client.

⚠️ It is **opt-in by design**. An empty register allows every machine, because
a migration that locks every officer out of a working system the moment it is
applied is worse than the gap it closes. Enforcement begins when ICT approves
the first PC — so every Department machine should be approved in one sitting.

⚠️ A refused attempt is written to the audit trail **over a separate
connection**. The first version wrote the row and then raised, and the raise
rolled the row back with it — measured: zero rows survived. It now uses
`dblink` on its own connection, which commits independently of the caller. That
too needed a correction: without an explicit `user=`, libpq fell back to the OS
account, which on Windows is `SYSTEM` — not a database role — and every write
failed silently inside an exception handler.

**Five tables had no Row-Level Security.** 132 of the policies covered the
register; these were missed. Four are reference data, but one was
`storage_rates` — the daily rate charged for warehouse space in every yard,
and `yard_app` could INSERT into it, so any signed-in officer could change what
every consignee in the country is billed. All five now carry RLS: every officer
reads, only ICT writes.

⚠️ Four separate policies per table, not one `FOR ALL`. A single `for all`
policy also governs SELECT, and its `USING` clause would have hidden these rows
from every officer who is not ICT — breaking the very forms that depend on
them. An officer who cannot read `hold_reasons` cannot fill in the form.

**Already in place, and confirmed rather than assumed:** account lockout after
5 failed attempts for 15 minutes; bcrypt hashing through `pgcrypto`; the
90-day rotation with mandatory change; one-time codes on sign-in; TLS with
three verification modes; `auth.begin_session` stamping user, role and now
device on every pooled connection; every query parameterised through
`Sql.named` — the repository contains no string-concatenated SQL; connection
pooling sized against `max_connections` with the arithmetic written down and
pinned by a test; and an append-only audit trail.

**Asked for but deliberately not done:** column-level encryption with
`pgcrypto`, and invalidating a previous session when the same account signs in
again. Neither is free — encrypted columns cannot be indexed or searched, which
would break the SR-number and consignee lookups the whole system turns on, and
single-session enforcement would log an officer out of the yard terminal when
they open the register on a second machine, which is ordinary practice here.
Both are judgements for the Department rather than defaults I should impose,
and I would rather name them than quietly skip them.

---

## 7 · Deployment

| | |
|---|---|
| Installer | Inno Setup, ~16 MB, with a licence agreement the officer must accept |
| Install path | `C:\Program Files\SL Customs\SR Management System\` |
| Configuration | A `.env` placed beside the executable after install |
| Upgrade | Run the newer setup over the top; the `.env` survives |
| Auto-update | Built in (`auto_updater`) |

⚠️ **Not yet done:** the installer is unsigned, so Windows SmartScreen warns on
first run. Removing that needs a code-signing certificate purchased in the
Department's name.

---

## 8 · Current state

**Working and tested:** all seven portals, the full seizure-to-outcome
workflow, the tender and committee route, appeals, the expense ledger, reports
and PDF/Excel extracts, the audit trail, and the account lifecycle.

**Deployed to:** a local PostgreSQL instance for development, with the schema
and 31 migrations applied and self-verified.

**Ready but not yet applied to the office server** (`10.10.71.15`): migrations
021–031, packaged as one ordered script with its own verification. They cover
dormancy, password history, the disposal-request restriction, directorate
yards, the audit role snapshot, and the tender-round rules.

---

## 9 · Questions you are likely to be asked

Grouped the way a review usually runs: the design choices first, then the hard
questions, then the honest gaps.

### 9.1 "Why did you build it this way?"

**Q. Why a desktop app and not a web application?**
Three reasons. The yards already run Windows PCs, so there is nothing new to
stand up on the server side. A desktop client talks to PostgreSQL directly, so
there is no web server or REST layer to secure, patch and keep available. And a
browser adds its own attack surface — sessions in cookies, XSS, CSRF — none of
which exists here.

**Q. Why no application server between the app and the database?**
Because the rules would then live in the middle tier, and anything that
bypassed it — a second app, a script, `psql` — would bypass the rules with it.
Putting Row-Level Security and the workflow triggers *in PostgreSQL* means the
data defends itself whatever connects to it. The app is a thin client on
purpose.

**Q. Then what stops the desktop app doing anything it likes?**
It connects as `yard_app`, a non-superuser with no RLS bypass. Every query it
sends is filtered by the same 153 policies. The app refuses to start as the
`postgres` superuser at all — that check is in the connection code, not a
convention.

**Q. Why PostgreSQL rather than SQL Server or Oracle?**
Row-Level Security, `SECURITY DEFINER` functions and `security_invoker` views
are exactly the tools this problem needs, and they are first-class in
PostgreSQL. It is also free, which matters for a system that may end up on a
machine in every yard.

**Q. Why Flutter?**
One codebase, native performance, and no browser runtime. If the Department
later wants this on a tablet at the warehouse door, the same code runs there.

**Q. Why did you drop Supabase?**
It was a hosted dependency for something that must run inside the Department's
own network on the Department's own server. Everything it provided — auth,
row-level security, realtime — PostgreSQL already does. Removing it also
removed a recurring cost and an outside party holding Customs data.

### 9.2 "How do you know it works?"

**Q. How is this tested?**
146 test files. Beyond ordinary widget and logic tests, two kinds carry real
weight: tests that read the SQL itself, so a migration cannot quietly drop a
guarantee; and equivalence tests, where a rewritten calculation is checked
against the original over hundreds of randomised inputs. The storage-charge
rewrite was verified that way over 500 random spans, because the figure is
money.

**Q. What if a migration is wrong?**
Each one verifies itself as it is applied: it makes the change, proves the
change did what it says, and fails if not. Migration 025 tries to insert a
disposal request *as a yard officer* and refuses to complete unless the
database rejects it.

**Q. Has anything actually been caught that way?**
Yes, and I would rather show these than hide them. Migration 021 read the wrong
column — a presence heartbeat that sign-out sets to NULL — so accounts in daily
use were being disabled as dormant. Migration 022 fixed it and restored every
account 021 had wrongly switched off. Separately, a verification that ran as
the superuser reported a pass while the rule it tested was doing nothing,
because RLS never applies to a superuser; it now runs as `yard_app`.

**Q. Will it hold 100 officers at once?**
The arithmetic is written down in `postgres/63_server_tuning.conf` and pinned
by a test. Each client opens a small pool (default 3) plus a listener, so 100
clients need roughly 400 connections while the stock server allows 100. The
tuning file raises `max_connections` and shows the working; the test fails if
the pool size drifts back to a number that would not fit.

### 9.3 "What about security?"

**Q. Where is security actually enforced?**
In the database. 153 RLS policies across every table, 24 of them RESTRICTIVE — a permissive policy
grants, a restrictive one can only subtract, so the yard boundary and the "only
SDDC/DDC may raise a disposal request" rule cannot be widened by any other
policy. 23 of 24 views are `security_invoker`, because a view without it runs
as its owner and the officer's policies never apply.

**Q. Can a yard officer see another yard's goods?**
No. The scope is a policy on the table, not a `WHERE` clause the app has to
remember. A directorate reads across yards by design — Appeal hears every
yard's appeals — but through its own explicit policy.

**Q. What happens if someone gets an officer's password?**
They still need the one-time code sent to that officer's registered address.
Repeated failures lock the account, and every attempt — including which yard it
targeted — is in the audit trail.

**Q. Can the audit trail be edited?**
No. `audit_logs` is append-only by trigger: no UPDATE, no DELETE, no TRUNCATE.
When a column genuinely had to be added to it, the migration stood the UPDATE
guard down for that one statement, in the open, with the reason written down —
and restored it on the error path too.

**Q. If an officer is promoted, does the trail still make sense?**
Yes, and this was a real bug. The role used to be read by joining `profiles`,
so a promotion silently relabelled every action that officer had ever taken.
Each row now carries the role its actor held that day; the 1,011 historical
rows were backfilled from recorded privilege changes where the evidence existed
and marked as inferred where it did not — presenting a guess as fact would have
been a worse lie than the one being fixed.

**Q. What is the worst bug you found?**
An account takeover. Signing up on a second portal with an existing officer's
e-mail did not fail — the app signed in as that account and wrote the new role
over it. One e-mail, one id: an ICT account *became* a Disposal account and ICT
ceased to exist. Anyone who knew an officer's address and password could
re-point their account at whichever portal they chose. The role is now compared
before the profile is written, and a mismatch is refused with an explanation.

**Q. And the subtlest one?**
Stale data between sessions. Riverpod caches each provider for the life of its
container and none of the ~100 data providers were `autoDispose`, so one
officer's rows stayed in memory after sign-out and rendered under the next
officer's name — GL1 packages under a GL2 officer. The database was scoping
correctly the whole time, which is why a `psql` session and a database-level
test both reported the boundary sound. Sign-out now rebuilds the entire
provider container rather than invalidating providers one by one, because the
day someone adds the hundred-and-first provider without touching a list, the
leak is silently back.

**Q. Is the data encrypted in transit?**
Yes, TLS, with optional certificate verification. ⚠️ The office server's
`pg_hba.conf` currently ends with `host`, which accepts a plaintext client as
readily as an encrypted one; it should be `hostssl`. It is written up in
`postgres/67_internet_deployment.md`.

### 9.4 "What about the business rules?"

**Q. How do you stop a package being tendered forever?**
Four rounds on Central Disposal's own authority, then a Top Management
committee must set a value, then exactly one committee round. A sixth is
refused by a trigger, and the fifth is refused unless the committee value has
been submitted. The re-tender pool will not even offer it.

**Q. Why does the committee round take no bids?**
Because it is a decision, not an auction. The committee sets a value; if the
goods still do not move they pass to Unsold Goods for the DG. A trigger refuses
a bid on that round, and the screen does not offer the form.

**Q. Who can send goods for disposal?**
Only a yard SDDC or DDC. It asks Central Disposal to sell or destroy goods the
State is holding, which is an administration act rather than an officer's. It
is enforced by a RESTRICTIVE policy, so hiding the button is a courtesy — the
database is what refuses.

**Q. What if a storage charge is disputed?**
It is computed from the admission date, the exit date and the historical rate
table, applying the rate in force on each day. The calculation was rewritten
for speed and checked against the original over 500 randomised cases, to the
rupee.

### 9.5 "What is not finished?"

Each of these was checked against the repository before being written down.

**Deployment to the office server.** Migrations 021–033 are written, applied to
a development database and self-verified — but the office server has not been
reachable from where this was built. They are packaged as one ordered script
that verifies itself on arrival.

**`pg_hba.conf` allows plaintext.** The office server's rule ends with `host`,
which accepts an unencrypted client as readily as an encrypted one. It should
be `hostssl`, and `0.0.0.0/0` should be narrowed to the branches' own
addresses. Written up in `postgres/67_internet_deployment.md`.

**The installer is unsigned.** Windows SmartScreen warns on first run. Removing
that needs a code-signing certificate bought in the Department's name — a
procurement decision, not a technical one.

**`yard_app`'s password on the office server.** Still to be set by the
Department, and it must not be the `postgres` password.

**No automated backup.** The database holds the entire SR register. A backup
schedule and a *tested restore* are the next thing to do; an untested backup is
not a backup.

**Device enforcement is switched off.** The approved-machine register is built
and proven, but it is empty — and an empty register allows every machine by
design, so that applying it cannot lock out a working system. It begins
enforcing the moment ICT approves the first PC, which means every Department
machine should be approved in one sitting.

**23 known failing tests.** Recorded, not hidden. They fall into two groups:
assertions that pin source-code text and broke when a formatter rewrapped a
line, and one that searches for a `\n` marker in a file saved with `\r\n`. They
are noise to clear — but noise is where a real regression hides.

### 9.6 "What would you do next?"

In the order I would actually do them:

1. **Backup and a tested restore.** Nothing else matters if the register is
   lost.
2. **Apply 021–033 to the office server**, and switch `pg_hba.conf` to
   `hostssl`.
3. **Approve every Department PC** in the device register, in one sitting, and
   with it switch device enforcement on.
4. **A code-signing certificate**, so officers are not trained to click past a
   security warning.
5. **Clear the 23 brittle tests**, so a real regression is never lost in known
   noise.
6. **A second yard on the live system**, to prove the yard boundary with real
   users rather than seeded data.

---

*ICT Directorate, Sri Lanka Customs.*
