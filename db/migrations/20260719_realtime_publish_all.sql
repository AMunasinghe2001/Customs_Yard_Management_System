-- ============================================================================
--  Realtime: publish every table the app subscribes to, so a change on ONE
--  table live-updates all related tables across every open portal/session.
--  Idempotent — adds only the tables not already in supabase_realtime.
-- ============================================================================

do $$
declare
  t text;
  tables text[] := array[
    'packages',
    'package_items',
    'warehouse_entries',
    'warehouses',
    'forfeited_packages',
    'disposal_requests',
    'disposal_request_items',
    'tenders',
    'tender_sales',
    'tender_sale_items',
    'tender_bids',
    'tender_revaluations',
    'tender_committees',
    'destructions',
    'destruction_items',
    'storage_rates',
    'package_categories',
    'hold_reasons',
    'audit_logs',
    'profiles',
    'disposal_taxes'
  ];
begin
  foreach t in array tables loop
    -- Skip tables that do not exist in this database.
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = t
    ) then
      continue;
    end if;
    -- Add to the realtime publication only if not already a member.
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I;', t);
    end if;
  end loop;
end $$;
