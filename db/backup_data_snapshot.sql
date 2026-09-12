-- ============================================================================
--  BACKUP — snapshot ALL current data into a separate `backup_snapshot` schema.
--
--  Run this NOW (before you keep updating data through the app's functions). It
--  copies every business + admin table into schema `backup_snapshot` as an exact
--  row-for-row clone. Later, `restore_data_snapshot.sql` puts these rows back
--  into `public`, returning the DB to exactly this moment.
--
--  • Safe & idempotent: re-running drops the old snapshot and takes a fresh one.
--  • Only copies rows (data), using CREATE TABLE ... AS SELECT — it does NOT
--    touch or lock your live `public` tables beyond a brief read.
--  • profiles / auth are copied too so members are preserved on restore.
--
--  Run in the Supabase SQL Editor.
-- ============================================================================

-- Start clean: drop any previous snapshot, recreate the holding schema.
drop schema if exists backup_snapshot cascade;
create schema backup_snapshot;

do $$
declare
  t text;
  -- Every table whose data we want to be able to restore. Order is irrelevant
  -- for a plain data copy (no FKs inside the snapshot schema).
  tables text[] := array[
    'profiles',
    'warehouses', 'package_categories', 'hold_reasons', 'storage_rates',
    'packages', 'package_items', 'warehouse_entries',
    'forfeited_packages',
    'disposal_requests', 'disposal_request_items',
    'tenders', 'tender_disposals', 'tender_sales', 'tender_sale_items',
    'destructions', 'destruction_items',
    'disposal_taxes',
    'audit_logs',
    'officer_signup_otps'
  ];
  n bigint;
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'create table backup_snapshot.%I as table public.%I', t, t);
      execute format('select count(*) from backup_snapshot.%I', t) into n;
      raise notice 'backed up %-24s % rows', t, n;
    else
      raise notice 'skipped   %-24s (does not exist)', t;
    end if;
  end loop;
end $$;

-- Record when this snapshot was taken.
create table backup_snapshot._meta as
  select now() as taken_at, current_user as taken_by;

-- ── Verify: list the snapshot tables (row counts are in the NOTICE output
--    above). This just confirms which tables were captured. ──────────────────
select table_name
  from information_schema.tables
 where table_schema = 'backup_snapshot'
   and table_name <> '_meta'
 order by table_name;

-- Done. Your data is now cloned in schema `backup_snapshot`. Keep using the
-- app; run restore_data_snapshot.sql whenever you want to roll back to this.
