-- ============================================================================
--  Realtime for Admin Panel config tables: hold_reasons + storage_rates.
--
--  Symptom this fixes: adding/editing a Hold Reason (or a Storage Charge) in one
--  logged-in session does NOT appear in another open session until that page is
--  manually refreshed. package_categories already live-updates because it is in
--  the publication; these two were missing.
--
--  The app subscribes to these tables via onPostgresChanges
--  (hold-reasons-realtime / storage-rates-realtime channels in providers.dart),
--  but Supabase only broadcasts row changes for tables in the
--  `supabase_realtime` publication — so the callback never fired.
--
--  IDEMPOTENT (safe to re-run). Run in the Supabase SQL Editor.
--  ⚠️  CLOSE THE RUNNING APP FIRST (the ALTERs take a brief lock).
-- ============================================================================

-- 1. ── Add the two tables to the realtime publication if missing ────────────
do $$
declare
  t text;
begin
  foreach t in array array['hold_reasons', 'storage_rates'] loop
    if to_regclass('public.' || t) is not null
       and not exists (
         select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = t
       ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
      raise notice 'added % to supabase_realtime', t;
    else
      raise notice 'skipped % (missing or already published)', t;
    end if;
  end loop;
end $$;

-- 2. ── REPLICA IDENTITY FULL so UPDATE/DELETE broadcast the whole row ────────
--    (e.g. toggling a hold reason's Active flag, or editing a storage rate).
alter table public.hold_reasons  replica identity full;
alter table public.storage_rates replica identity full;

-- 3. ── Verify: both should show published = true ─────────────────────────────
with app_tables(tablename) as (
  values ('hold_reasons'), ('storage_rates')
)
select a.tablename,
       (pt.tablename is not null) as published
  from app_tables a
  left join pg_publication_tables pt
    on pt.pubname = 'supabase_realtime'
   and pt.schemaname = 'public'
   and pt.tablename = a.tablename
 order by a.tablename;

-- Done. Relaunch the app — Hold Reasons and Storage Charges now live-update
-- across every open session (Admin Panel + SR-form reason pickers).
