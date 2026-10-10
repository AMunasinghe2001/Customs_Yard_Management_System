-- ============================================================================
--  Clear GL1's TEST data before entering real data.
--
--  Scope: every yard-scoped table that carries yard = 'GL1' — packages and
--  everything that cascades from them (package_items, warehouse_entries,
--  forfeited_packages, and whatever forfeited_packages itself cascades to:
--  tenders, tender_disposals, and their own children) — PLUS GL1's
--  warehouses and warehouse_zones, which are also test data per this
--  session's decision and are not yard-cascaded from packages at all.
--
--  Does NOT touch: profiles/auth (kept — members), any other yard's rows
--  (there are none in this project yet, but the WHERE clause still scopes to
--  GL1 explicitly rather than assuming), customs_rules, hold_reasons,
--  package_categories, storage_rates (shared reference data).
--
--  Run this in the Supabase SQL Editor (Dashboard → SQL Editor). An editor
--  session runs as the table owner, so it bypasses RLS the way this script
--  needs to — the app's own `yard_app` role cannot do this by design.
--
--  ⚠ DESTRUCTIVE. Wrapped in a transaction: run it, read the NOTICE output,
--  then either `commit;` or `rollback;` — nothing is permanent until you
--  explicitly commit.
-- ============================================================================

begin;

-- ── 1. Snapshot counts before, for every table this touches ────────────────
do $$
declare
  t text;
  n bigint;
  tables text[] := array[
    'packages', 'package_items', 'warehouse_entries', 'forfeited_packages',
    'tenders', 'tender_disposals', 'warehouses', 'warehouse_zones'
  ];
begin
  raise notice '── BEFORE ──────────────────────────────';
  foreach t in array tables loop
    if to_regclass('public.' || t) is not null then
      execute format('select count(*) from public.%I', t) into n;
      raise notice '% = %', t, n;
    end if;
  end loop;
end $$;

-- ── 2. Delete GL1's packages — cascades to package_items, warehouse_entries,
--       forfeited_packages, and forfeited_packages' own children (tenders,
--       tender_disposals) via ON DELETE CASCADE already on those FKs. ──────
delete from public.packages where yard = 'GL1';

-- ── 3. Delete GL1's warehouses — cascades to warehouse_zones (ON DELETE
--       CASCADE) and would be blocked by any warehouse_entries still
--       pointing at them, but step 2 already removed those. ────────────────
delete from public.warehouses where yard = 'GL1';

-- ── 4. Catch anything the two deletes above didn't reach: any yard-scoped
--       BASE TABLE (discovered live from the schema, not hand-listed) that
--       still has a GL1 row after the cascade. This is the self-check — if
--       this finds rows, the cascade assumption above was wrong somewhere
--       and the transaction should be rolled back and investigated, not
--       committed.
--
--    Deliberately excludes:
--      • VIEWS (information_schema.columns includes both tables and views;
--        `password_rotation_status` is a view over `profiles` and will
--        always show whatever `profiles` shows — checking it here doesn't
--        test the delete, it just re-tests `profiles`, and it's a view
--        besides, not a row to delete).
--      • profiles — deliberately kept (members), per this script's header.
--      • audit_logs — deliberately kept: it is append-only by trigger (no
--        UPDATE/DELETE/TRUNCATE for anyone, by design, per PROJECT_OVERVIEW
--        §6.4), and history staying after the goods it describes are gone
--        is the correct outcome for an audit trail, not a leftover to clear.
do $$
declare
  t text;
  n bigint;
  leftover text := '';
begin
  raise notice '── AFTER — verifying no GL1 rows remain anywhere ──────────';
  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name
     where c.table_schema = 'public'
       and c.column_name = 'yard'
       and tb.table_type = 'BASE TABLE'
       and c.table_name not in ('profiles', 'audit_logs')
  loop
    execute format('select count(*) from public.%I where yard = %L', t, 'GL1') into n;
    raise notice '% (GL1) = %', t, n;
    if n > 0 then
      leftover := leftover || t || '(' || n || ') ';
    end if;
  end loop;

  if leftover <> '' then
    raise exception 'GL1 rows still remain in: % — rollback and investigate before re-running', leftover;
  end if;
end $$;

-- ── 5. Confirm the warehouse/zone wipe too (no yard column on zones) ───────
do $$
declare n bigint;
begin
  select count(*) into n from public.warehouses where yard = 'GL1';
  raise notice 'warehouses (GL1) = %', n;
  select count(*) into n from public.warehouse_zones;
  raise notice 'warehouse_zones (total, should be 0 if all zones were GL1''s) = %', n;
end $$;

-- Review every NOTICE above.
--   • "── AFTER ──" section: every count must be 0.
--   • No exception raised.
-- If both hold:
commit;
-- Otherwise:
-- rollback;
