-- ============================================================================
--  RECOVERY: un-forward disposal requests that the (old) unconditional backfill
--  in 20260617_valuation_directorate.sql wrongly flipped to 'forwarded'.
--
--  Background: that migration's backfill had NO guard, so every time it was
--  re-run it set valuation_status='forwarded' on ALL requests — including brand
--  new ones still awaiting valuation. Those silently disappeared from the
--  Valuation Directorate dashboard (Pending Valuation showed 0).
--
--  This script moves the WRONGLY-forwarded ones back to 'pending_valuation'.
--  We must NOT touch legitimately forwarded requests, so we only revert rows
--  that bear no sign of having actually been valued:
--    • valued_by IS NULL            (the forward RPC always sets valued_by), and
--    • NO line item has a valuation_cost (a real valuation costs every item).
--
--  Safe to run once. Review the SELECT preview before running the UPDATE.
--  Run in the Supabase SQL Editor. CLOSE THE APP FIRST is NOT required (no DDL,
--  no locks beyond row updates), but a quick refresh of the app afterwards will
--  show the requests back under Pending Valuation.
-- ============================================================================

-- 1. ── PREVIEW: which requests would be reverted ────────────────────────────
--    Run this first and sanity-check the list (yard, date, item count).
select dr.id,
       dr.yard,
       dr.request_date,
       dr.created_at,
       dr.valuation_status,
       dr.valued_by,
       count(dri.id)                                   as item_count,
       count(dri.valuation_cost)                       as items_with_cost
  from public.disposal_requests dr
  left join public.disposal_request_items dri on dri.request_id = dr.id
 where dr.valuation_status = 'forwarded'
   and dr.valued_by is null
 group by dr.id
having count(dri.valuation_cost) = 0   -- no item was ever costed
 order by dr.created_at desc;

-- 2. ── REVERT: move those rows back to pending_valuation ─────────────────────
--    Uncomment and run after confirming the preview above looks right.
-- update public.disposal_requests dr
--    set valuation_status = 'pending_valuation',
--        valued_at        = null
--  where dr.valuation_status = 'forwarded'
--    and dr.valued_by is null
--    and not exists (
--      select 1 from public.disposal_request_items dri
--       where dri.request_id = dr.id
--         and dri.valuation_cost is not null
--    );

-- 3. ── Mark the backfill as already applied so the fixed migration's guarded
--    backfill never re-forwards anything (in case the migration is re-run).
-- create table if not exists public.app_migration_flags (
--   flag       text primary key,
--   applied_at timestamptz not null default now()
-- );
-- insert into public.app_migration_flags(flag)
-- values ('valuation_directorate_backfilled')
-- on conflict (flag) do nothing;

-- 4. ── (Optional) Delete empty disposal requests (no line items) ─────────────
--    Some requests were created with a header but zero disposal_request_items
--    (item_count = 0 in the preview). They can never be valued or forwarded, so
--    they're dead clutter in the Valuation dashboard. This removes ONLY requests
--    that have no items AND were never valued — never one carrying packages.
--
--    PREVIEW first:
select dr.id, dr.yard, dr.request_date, dr.created_at
  from public.disposal_requests dr
 where dr.valued_by is null
   and not exists (
     select 1 from public.disposal_request_items dri where dri.request_id = dr.id
   )
 order by dr.created_at desc;

--    Then DELETE (uncomment):
-- delete from public.disposal_requests dr
--  where dr.valued_by is null
--    and not exists (
--      select 1 from public.disposal_request_items dri where dri.request_id = dr.id
--    );

-- Done.
