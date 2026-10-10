-- ============================================================================
-- Enforced per-yard isolation for EVERY yard in the direct PostgreSQL client.
--
-- The desktop app must connect as the non-superuser `yard_app` role created by
-- postgres/66_yard_app_role.sql.  PostgreSQL superusers bypass RLS, so a
-- connection as `postgres` makes UI filters the only barrier between any two
-- yards.  This migration closes the database side of that gap:
--
--   * tables that carry operational data force their existing dynamic RLS
--     policy: `row.yard = auth_user_yard()`;
--   * reporting/list views run with the caller's permissions, so their base
--     table RLS policies apply too (views otherwise use their owner's rights).
--
-- Apply after 001_multi_yard.sql and 002_strict_yard_isolation.sql.
-- Requires PostgreSQL 15+ for `security_invoker`; the deployed server meets
-- that requirement.  Safe to re-run.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'packages', 'package_items', 'warehouse_entries',
    'forfeited_packages', 'tenders', 'tender_disposals', 'audit_logs',
    'disposal_requests', 'disposal_request_items',
    'tender_sales', 'tender_sale_items', 'tender_bids',
    'tender_revaluations', 'tender_committees', 'unsold_proposals',
    'destructions', 'destruction_items', 'financial_expenses'
  ]
  loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('alter table public.%I force row level security', t);
    end if;
  end loop;
end $$;

-- `auth_user_yard()` reads the logged-in account's profiles.yard.  It does
-- not contain a yard-code list: therefore a new ICT-created code (for example
-- `NEWYARD`) is isolated the instant an account is assigned to it, with no
-- Flutter rebuild, SQL edit, or special GL1/GL2 branch.
do $$
declare
  t text;
  policy_sql text;
begin
  foreach t in array array[
    'packages', 'package_items', 'warehouse_entries', 'forfeited_packages',
    'tenders', 'tender_disposals'
  ]
  loop
    select pg_get_expr(p.polqual, p.polrelid) into policy_sql
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = t and p.polname = 'yard_all';
    if policy_sql is null or policy_sql not like '%auth_user_yard%' then
      raise exception 'public.% does not have the dynamic yard_all RLS policy', t;
    end if;
  end loop;
end $$;

-- These views power Old Entries, Goods History, Warehouses, Held Goods,
-- Forfeited/Disposed tables, dashboard cards, and reports.  SECURITY INVOKER
-- means a GL2 user sees only rows permitted by the underlying table policies;
-- no view-owner (normally postgres) can accidentally widen the result set.
do $$
declare
  v text;
begin
  foreach v in array array[
    'held_goods_rows', 'perishable_rows', 'warehouse_rows', 'forfeit_rows',
    'disposition_rows', 'sr_financials', 'sr_expense_summary',
    'recent_package_activity', 'accrued_storage_by_yard',
    'appeal_rows', 'valuation_rows', 'disposal_request_summary',
    'tender_sale_summary', 'destruction_summary', 'unsold_retender_pool',
    'unsold_perishables', 'exhausted_unsold', 'committee_pool',
    'item_appeal_outcomes', 'zone_occupancy_entries'
  ]
  loop
    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v and c.relkind = 'v'
    ) then
      execute format('alter view public.%I set (security_invoker = true)', v);
    end if;
  end loop;
end $$;

-- A report or view accidentally created without SECURITY INVOKER is a data
-- isolation regression.  Fail this deployment instead of silently releasing
-- a report that can read another yard's records.
do $$
declare
  v text;
  invoker text;
begin
  foreach v in array array[
    'held_goods_rows', 'perishable_rows', 'warehouse_rows', 'forfeit_rows',
    'disposition_rows', 'sr_financials', 'sr_expense_summary',
    'recent_package_activity', 'accrued_storage_by_yard',
    'appeal_rows', 'valuation_rows', 'disposal_request_summary',
    'tender_sale_summary', 'destruction_summary', 'unsold_retender_pool',
    'unsold_perishables', 'exhausted_unsold', 'committee_pool',
    'item_appeal_outcomes', 'zone_occupancy_entries'
  ]
  loop
    if to_regclass('public.' || v) is not null then
      select coalesce(c.reloptions::text, '') into invoker
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v;
      if invoker not like '%security_invoker=true%' then
        raise exception 'view public.% must use security_invoker', v;
      end if;
    end if;
  end loop;
end $$;
