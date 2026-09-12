-- ============================================================================
--  FIX: cross-directorate / cross-session tables not auto-updating.
--
--  Symptoms this fixes:
--    • Admin sends a disposal request (or forwards one) → it does NOT appear
--      automatically in the Central Disposal / Valuation Directorate tables in
--      another open session until that page is manually reloaded.
--    • Any table that should "live-update" in one session after a change made in
--      another session stays stale.
--
--  Root cause: Supabase Realtime only broadcasts row changes for tables that are
--  members of the `supabase_realtime` publication. The app subscribes to these
--  tables via onPostgresChanges, but:
--    (a) if a table is NOT in the publication, the callback never fires; and
--    (b) for UPDATE/DELETE events the table needs REPLICA IDENTITY FULL, otherwise
--        an update that changes only e.g. `valuation_status` may not surface as a
--        usable realtime payload.
--
--  This script is IDEMPOTENT (safe to re-run). Run it in the Supabase SQL Editor.
--  ⚠️  CLOSE THE RUNNING APP FIRST — the ALTER statements take a brief lock and an
--      open app's realtime read locks can deadlock. Close app → Run → relaunch.
-- ============================================================================

-- 1. ── PREVIEW (BEFORE): which of the app's realtime tables are published? ────
--    Anything showing published = false is a problem this script will fix.
with app_tables(tablename) as (
  values
    ('packages'), ('package_items'), ('warehouse_entries'), ('profiles'),
    ('package_categories'), ('audit_logs'), ('forfeited_packages'),
    ('destructions'), ('destruction_items'),
    ('disposal_requests'), ('disposal_request_items'), ('tender_sale_items')
)
select 'BEFORE' as phase,
       a.tablename,
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
--    Needed so e.g. a `valuation_status` / request-status UPDATE surfaces as a
--    real realtime event (not just INSERTs). Cheap for these low-write tables.
alter table public.packages                 replica identity full;
alter table public.package_items            replica identity full;
alter table public.warehouse_entries        replica identity full;
alter table public.forfeited_packages       replica identity full;
alter table public.disposal_requests        replica identity full;
alter table public.disposal_request_items   replica identity full;
alter table public.tender_sale_items        replica identity full;
alter table public.destructions             replica identity full;
alter table public.destruction_items        replica identity full;

-- 4. ── PREVIEW (AFTER): re-run the check — every row should now be published. ─
with app_tables(tablename) as (
  values
    ('packages'), ('package_items'), ('warehouse_entries'), ('profiles'),
    ('package_categories'), ('audit_logs'), ('forfeited_packages'),
    ('destructions'), ('destruction_items'),
    ('disposal_requests'), ('disposal_request_items'), ('tender_sale_items')
)
select 'AFTER' as phase,
       a.tablename,
       (pt.tablename is not null) as published
  from app_tables a
  left join pg_publication_tables pt
    on pt.pubname = 'supabase_realtime'
   and pt.schemaname = 'public'
   and pt.tablename = a.tablename
 order by published, a.tablename;

-- Done. After running, relaunch the app — sending / forwarding a request now
-- live-updates the Central Disposal and Valuation tables in every open session.
