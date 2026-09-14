-- ============================================================================
--  The five tables that had no Row-Level Security.
--
--  132 of 137 policies covered the register itself. These five were left
--  open, and one of them matters a great deal:
--
--    storage_rates          the daily rate charged for warehouse space, in
--                           EVERY yard. `yard_app` could INSERT — measured —
--                           so any signed-in officer could change what every
--                           consignee in the country is billed.
--    hold_reasons           the list of reasons goods may be held
--    package_categories     the categories and their default warehouse/zone
--    app_migration_flags    which migrations have run
--    sr_number_migration_log  old -> new SR numbers from the numbering change
--
--  The first four are REFERENCE data: every officer must read them, and
--  changing them is an ICT act. The fifth is register history — it maps SR
--  numbers, so it is read-only to everyone and written by nothing at run time.
--
--  ⚠️ Reading stays open. A yard officer who cannot read `hold_reasons`
--  cannot fill in the form; a locked-down rate table would break the storage
--  charge on every screen. What changes is WRITING.
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. Reference data: everyone reads, ICT writes ───────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['hold_reasons', 'package_categories',
                           'storage_rates'] loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists %I on public.%I',
                   t || '_read_all', t);
    execute format(
      'create policy %I on public.%I for select using (true)',
      t || '_read_all', t);

    -- ⚠️ Four separate policies, not one FOR ALL. A single `for all` policy
    -- would also govern SELECT, and its USING clause would then hide these
    -- rows from every officer who is not ICT — breaking the very forms that
    -- depend on them.
    execute format('drop policy if exists %I on public.%I',
                   t || '_ict_insert', t);
    execute format(
      'create policy %I on public.%I for insert '
      'with check (public.auth_user_is_ict())',
      t || '_ict_insert', t);

    execute format('drop policy if exists %I on public.%I',
                   t || '_ict_update', t);
    execute format(
      'create policy %I on public.%I for update '
      'using (public.auth_user_is_ict()) '
      'with check (public.auth_user_is_ict())',
      t || '_ict_update', t);

    execute format('drop policy if exists %I on public.%I',
                   t || '_ict_delete', t);
    execute format(
      'create policy %I on public.%I for delete '
      'using (public.auth_user_is_ict())',
      t || '_ict_delete', t);
  end loop;
end $$;


-- ── 2. Migration bookkeeping: read-only to the application ──────────────────
--
-- ⚠️ No write policy at all, deliberately. These two are written by
-- MIGRATIONS, which run as an administrator and bypass RLS entirely. The
-- application has no business writing either, and saying so with the absence
-- of a policy is clearer than a policy nobody can satisfy.
do $$
declare
  t text;
begin
  foreach t in array array['app_migration_flags',
                           'sr_number_migration_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I',
                   t || '_read_all', t);
    execute format(
      'create policy %I on public.%I for select using (true)',
      t || '_read_all', t);
  end loop;
end $$;


-- ── 3. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_open text;
  v_officer uuid;
  v_ict uuid;
  v_allowed boolean;
begin
  -- Every table in public now carries RLS.
  select string_agg(c.relname, ', ') into v_open
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if v_open is not null then
    raise exception 'these tables still have no RLS: %', v_open;
  end if;

  select id into v_officer
    from public.profiles where role = 'officer' and is_active limit 1;
  select id into v_ict from public.profiles where role = 'ict' limit 1;
  if v_officer is null or v_ict is null then
    raise notice 'need an officer and an ICT account to verify - skipped';
    return;
  end if;

  perform set_config('app.current_role', 'authenticated', true);
  set local role yard_app;

  -- ⚠️ An officer must still READ the rate, or the storage charge breaks on
  -- every screen that shows it.
  perform set_config('app.current_user_id', v_officer::text, true);
  perform count(*) from public.storage_rates;

  -- ...but must NOT be able to set it.
  v_allowed := false;
  begin
    insert into public.storage_rates (rate, effective_from)
    values (999999, now());
    v_allowed := true;
  exception when insufficient_privilege then
    null;
  end;
  if v_allowed then
    delete from public.storage_rates where rate = 999999;
    reset role;
    raise exception
      'a yard officer can still set the storage rate for every yard';
  end if;

  -- ICT can.
  perform set_config('app.current_user_id', v_ict::text, true);
  insert into public.storage_rates (rate, effective_from)
  values (999999, now());
  delete from public.storage_rates where rate = 999999;

  reset role;
  raise notice
    'verified: officers read reference data, only ICT writes it';
end $$;
