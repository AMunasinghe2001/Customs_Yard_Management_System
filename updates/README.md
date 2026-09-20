# Releasing an update to the branch offices

The app is installed at several offices against one cloud database. Nobody
visits the branches, so the app checks for itself whether a newer version has
been published and shows a strip across the top when there is one.

```
  Cloud server (Namecheap)          GitHub Releases (free)
  ────────────────────────          ──────────────────────
  PostgreSQL only                   SLCustoms-SR-Setup-x.y.z.exe
  (no web server needed)            release notes
                                    ▲
  Branch PC ──── reads data ────────┘ checks at start-up
```

Nothing is pushed to the branches. Each copy asks GitHub at start-up, and
shows the strip only when the published version is **higher** than its own.

---

## Cutting a release

```powershell
.\tool\release.ps1 -Version 1.2.0
```

That writes the version into all three places that must agree, builds, and
packages the installer into `installer\output\`.

> ⚠️ **Why a script.** The version lives in `pubspec.yaml`,
> `installer/setup.iss` **and** `lib/core/update_check.dart`. If the app's own
> constant is left *behind* the published tag, every branch is told forever to
> install what they already have. If it is left *ahead*, nobody is ever told
> anything. `test/update_check_test.dart` fails the build if the three drift.

Then publish it:

1. `git commit -am "release 1.2.0"` and `git push`
2. `git tag v1.2.0` and `git push origin v1.2.0`
3. GitHub → **Releases** → **Draft a new release**
   - **Tag:** `v1.2.0`
   - **Title:** `1.2.0`
   - **Notes:** what changed, in plain words — officers read this in the app
   - **Attach** the `.exe` from `installer\output\`
   - **Publish** (not as a draft, not as a pre-release — the app skips both)

Within one restart, every branch sees the strip.

---

## What the officer sees

A gold strip at the top: *"Version 1.2.0 is available · 24.3 MB"*, with
**What's new**, **Update** and a close button.

- **Update** opens the download in their browser.
- The dialog tells them to **close the app before running the setup** —
  Windows cannot replace a running `.exe`, and the installer fails with an
  error that does not explain itself.
- The setup installs **over** the old copy: same folder, same shortcuts, and
  their `.env` is kept (see `installer/DEPLOYMENT.txt`).

> ⚠️ **It never installs by itself, and never blocks work.** An officer
> halfway through registering a consignment must not be interrupted by a
> software notice, and an app that silently downloads and runs an `.exe` is
> indistinguishable from malware — it would also bypass SmartScreen and the
> antivirus prompt, which are the only places "should I run this?" gets
> asked. The browser downloads it; a person decides.

Dismissing the strip silences it **for that run only**. It returns at the next
start-up, deliberately: a branch that keeps skipping updates should keep being
asked, or the offices drift apart on versions.

---

## When an update needs a DATABASE change

This is the part that can take a branch down during working hours, so it has
its own guard.

`migrations/043` gave the database a version of its own:

```sql
select public.schema_version();   -- e.g. 43
```

Every migration inserts its number into `public.schema_migrations`, and the
app knows the minimum it needs (`kRequiredSchemaVersion` in
`lib/core/update_check.dart`).

**Order matters — always the server first:**

1. Apply the new migration(s) to the cloud database.
2. *Then* publish the release.

Done in that order, a branch still running the old app keeps working (the
check is a **minimum**, not an exact match — a database ahead of the app is
normal and fine while the offices update over the following days).

Done the other way round, a branch that updates early meets a column that is
not there yet, and the app says so in one sentence naming the versions —
instead of failing later with a raw `column ... does not exist` from whichever
screen happens to touch it first.

> ⚠️ **The app never migrates the database itself.** A branch PC silently
> altering a live customs database is a far worse failure than one that
> refuses to start. Schema changes stay a deliberate act by whoever
> administers the server.

When you add a migration the app depends on:

- give it the next number, and have it `insert into public.schema_migrations`
- bump `kRequiredSchemaVersion` **in the same commit**

---

## Checking without publishing

Pretend to be an older build:

```powershell
flutter run -d windows --dart-define=APP_VERSION=0.0.1
```

Point at a different repo or a test feed:

```powershell
flutter build windows --release `
  --dart-define=UPDATE_MANIFEST_URL=https://api.github.com/repos/OWNER/REPO/releases/latest
```

An empty `UPDATE_MANIFEST_URL` turns the check off entirely.

---

## Notes

- The check is **not awaited** at start-up. On a branch PC with a slow link it
  would otherwise hold the splash screen for its whole timeout before anyone
  could sign in.
- Every failure — offline, DNS down, rate-limited, no release yet, a release
  with no `.exe` attached — is treated the same: say nothing. None of them is
  worth interrupting an officer over.
- `lib/core/app_updater.dart` (WinSparkle) is the **older** mechanism and is
  inert unless `UPDATE_FEED_URL` is set. It needs a web server to host an
  appcast; this approach does not, which is why the cloud box can stay
  database-only.
