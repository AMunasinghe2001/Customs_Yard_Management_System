-- ============================================================================
--  Ensure EVERY table that has a realtime channel in the app is in the
--  `supabase_realtime` publication, so changes broadcast to all open views live
--  (no page reload needed). The Appeal Directorate dashboard + the yard
--  Forfeited Packages screen subscribe to `forfeited-packages-realtime` but
--  received nothing while `forfeited_packages` was absent from the publication —
--  this backfills it together with every other channelled table.
--  Idempotent — safe to run more than once.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'packages',
    'package_items',
    'warehouse_entries',
    'profiles',
    'package_categories',
    'audit_logs',
    'forfeited_packages',
    'destructions',
    'destruction_items',
    'disposal_requests',
    'disposal_request_items',
    'tender_sale_items'
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

-- Send the full row on UPDATE/DELETE so realtime payloads carry the changed
-- columns (e.g. forfeited_packages.appeal_decision), not just the primary key.
alter table public.forfeited_packages replica identity full;

-- Done.
