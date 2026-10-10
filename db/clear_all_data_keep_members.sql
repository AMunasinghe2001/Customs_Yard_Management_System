-- ============================================================================
--  RESET to a clean slate — KEEP only the registered members (profiles/auth).
--
--  Wipes ALL business + admin-panel data so real data can be entered from
--  scratch via the SR form:
--    • Business: packages, package_items, warehouse_entries, forfeited_packages,
--      tenders, tender_disposals, tender_sales, tender_sale_items, destructions,
--      destruction_items, disposal_requests, disposal_request_items.
--    • Admin Panel: audit_logs, hold_reasons, storage_rates, package_categories,
--      warehouses.
--
--  KEEPS: profiles (members) + auth.users (login accounts), officer_signup_otps,
--         app_migration_flags (migration sentinels — do NOT wipe or migrations
--         re-run), customs_rules (system config).
--
--  ⚠ DESTRUCTIVE + IRREVERSIBLE. Take a Supabase backup first. Review, then run.
--     Wrapped in a transaction — inspect the NOTICE counts, then COMMIT.
-- ============================================================================

begin;

-- Truncate each target table IF it exists (skips silently otherwise), CASCADE so
-- FK-dependent rows go too, RESTART IDENTITY to reset serial counters. Listed
-- children-before-parents for clarity (CASCADE makes order irrelevant).
do $$
declare
  t text;
  targets text[] := array[
    'tender_sale_items', 'tender_sales', 'tender_disposals', 'tenders',
    'destruction_items', 'destructions',
    'disposal_request_items', 'disposal_requests',
    'forfeited_packages', 'warehouse_entries', 'package_items', 'packages',
    'audit_logs', 'hold_reasons', 'storage_rates', 'package_categories',
    'warehouses'
  ];
begin
  foreach t in array targets loop
    if to_regclass('public.' || t) is not null then
      execute format('truncate table public.%I restart identity cascade', t);
      raise notice 'truncated %', t;
    else
      raise notice 'skipped % (does not exist)', t;
    end if;
  end loop;
end $$;

-- ── Sanity check: every cleared table should be 0; profiles should be > 0 ────
do $$
declare
  t text;
  n bigint;
  checks text[] := array[
    'packages', 'package_items', 'warehouse_entries', 'forfeited_packages',
    'tenders', 'tender_disposals', 'tender_sales', 'tender_sale_items',
    'destructions', 'destruction_items', 'disposal_requests',
    'disposal_request_items', 'audit_logs', 'hold_reasons', 'storage_rates',
    'package_categories', 'warehouses', 'profiles'
  ];
begin
  foreach t in array checks loop
    if to_regclass('public.' || t) is not null then
      execute format('select count(*) from public.%I', t) into n;
      raise notice '% = % rows%', t, n,
        case when t = 'profiles' then '  (KEPT)' else '' end;
    end if;
  end loop;
end $$;

-- Review the NOTICE output above. If correct (all 0 except profiles):
commit;
-- Otherwise: rollback;
