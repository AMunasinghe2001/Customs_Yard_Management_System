-- ============================================================================
--  FIX: cross-directorate tables not auto-updating (e.g. forwarding a request
--  from the Valuation Directorate doesn't appear in Central Disposal until a
--  manual reload).
--
--  Root cause: Supabase Realtime only broadcasts row changes for tables that are
--  members of the `supabase_realtime` publication. The app subscribes to these
--  tables via onPostgresChanges, but if a table is NOT in the publication the
--  callback never fires, so dependent dashboards in OTHER sessions don't refresh.
--
--  This script (idempotent — safe to re-run):
--    1. PREVIEW: shows which app tables are currently published.
--    2. Adds every channelled table to the publication if missing.
--    3. Sets REPLICA IDENTITY FULL so UPDATE/DELETE payloads carry the full row
--       (needed so e.g. a valuation_status change broadcasts as a real event).
--
--  Run in the Supabase SQL Editor. No app-close needed (no exclusive table
--  locks beyond the ALTER PUBLICATION add, which is quick). Relaunch / refresh
--  the app afterwards and forwarding will live-update both dashboards.
-- ============================================================================

-- 1. ── PREVIEW: which of the app's realtime tables are published? ────────────
--    Anything showing published = false is the problem.
with app_tables(tablename) as (
  values
    ('packages'), ('package_items'), ('warehouse_entries'), ('profiles'),
    ('package_categories'), ('audit_logs'), ('forfeited_packages'),
    ('destructions'), ('destruction_items'),
    ('disposal_requests'), ('disposal_request_items'), ('tender_sale_items')
)
select a.tablename,
       (pt.tablename is not null) as published
  from app_tables a
  left join pg_publication_tables pt
    on pt.pubname = 'supabase_realtime'
   and pt.schemaname = 'public'
   and pt.tablename = a.tablename
 order by published, a.tablename;

-- 2. ── Add any missing table to the publication ─────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array[
    'packages', 'package_items', 'warehouse_entries', 'profiles',
    'package_categories', 'audit_logs', 'forfeited_packages',
    'destructions', 'destruction_items',
    'disposal_requests', 'disposal_request_items', 'tender_sale_items'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- 3. ── REPLICA IDENTITY FULL so UPDATE/DELETE broadcast the whole row ─────────
--    Without this, an UPDATE that changes only e.g. valuation_status may not
--    surface as a usable realtime event. Cheap for these low-write tables.
alter table public.disposal_requests       replica identity full;
alter table public.disposal_request_items  replica identity full;
alter table public.forfeited_packages      replica identity full;
alter table public.tender_sale_items       replica identity full;
alter table public.destructions            replica identity full;
alter table public.destruction_items       replica identity full;

-- 4. ── VERIFY: re-run the preview from step 1 — every row should be true now.

-- Done.
