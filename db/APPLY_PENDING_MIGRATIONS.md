# Pending migrations to run on the hosted Supabase DB

> ⚠️ **CLOSE THE RUNNING APP FIRST.** These migrations `ALTER` tables and
> replace RLS policies, which need a brief exclusive lock. If the app is open
> its realtime subscriptions hold a read lock and you'll get
> `40P01: deadlock detected`. Close the app, run the SQL, then relaunch.
> (Migration #2 also sets a 5s `lock_timeout` so it fails fast instead of
> deadlocking — if it errors, the app is still open. Both are idempotent:
> just re-run after closing it.)

Run these in the **Supabase SQL Editor**, in this exact order. Both are
idempotent (safe to re-run). Copy-paste each file's full contents and Run.

## 1. Fixes the current error

`forfeited_packages_source_check` violation when sending a disposal request for
an **Other**-source item:

```
new row for relation "forfeited_packages" violates check constraint
"forfeited_packages_source_check"
```

→ Run **`db/migrations/20260616_forfeited_source_other.sql`**
(adds `'other'` to the allowed `forfeited_packages.source` values).

## 2. Enables the Valuation Directorate feature

→ Run **`db/migrations/20260617_valuation_directorate.sql`**
(new `valuation` role, RLS, position guard, `valuation_status` / per-item
`valuation_cost` columns, `valuation_set_costs` RPC, and a **one-shot** backfill
that marks all *pre-existing* disposal requests `forwarded`).

> 🐛 **If you ran an OLDER copy of this migration:** its backfill had no guard
> and re-forwarded **every** request on each re-run — so a freshly created
> request awaiting valuation would silently vanish (Pending Valuation = 0). The
> migration is now fixed (backfill runs once, tracked via `app_migration_flags`).
> To restore requests that were wrongly forwarded, run
> **`supabase/fix_valuation_status_backfill.sql`** (preview first, then the
> UPDATE + flag insert).

## 3. (Optional) Backfill legacy bare `[CCCC]` Other-disposition tags

Only if you have old warehouse "Other" dispositions saved with a bare custom
tag (pre-fix). Review the SELECT previews inside first.

→ Run **`supabase/backfill_other_disposition_tags.sql`**

---

After running #1 and #2, restart the app (`flutter run`) and retry the
Disposal Request — it will succeed, and the request will appear in the
Valuation Directorate first.
