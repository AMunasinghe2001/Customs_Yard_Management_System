-- ============================================================================
--  RESTORE — roll `public` back to the last backup_data_snapshot.sql snapshot.
--
--  ⚠ DESTRUCTIVE: this WIPES the current data in the listed public tables and
--    re-inserts the snapshot rows, so the DB returns to exactly the moment the
--    backup was taken. Anything created after the backup is lost.
--
--  Requires backup_data_snapshot.sql to have been run first (schema
--  `backup_snapshot` must exist). Run in the Supabase SQL Editor.
--  ⚠ CLOSE THE RUNNING APP FIRST (avoids realtime read-lock contention).
--
--  Wrapped in a transaction — inspect the NOTICE counts, then it COMMITs.
-- ============================================================================

do $$
begin
  if to_regclass('backup_snapshot._meta') is null then
    raise exception
      'No snapshot found. Run backup_data_snapshot.sql first.';
  end if;
end $$;

begin;

-- 1. ── Clear current data (children first; CASCADE covers the rest) ──────────
--    profiles is intentionally restored too — but truncated with CASCADE would
--    also clear auth-linked rows, so we handle profiles via delete+insert below
--    rather than truncate. Business tables use truncate for speed.
do $$
declare
  t text;
  -- Children-before-parents so truncate/restart identity is clean.
  business text[] := array[
    'tender_sale_items', 'tender_sales', 'tender_disposals', 'tenders',
    'destruction_items', 'destructions',
    'disposal_taxes',
    'disposal_request_items', 'disposal_requests',
    'forfeited_packages',
    'warehouse_entries', 'package_items', 'packages',
    'audit_logs', 'hold_reasons', 'storage_rates', 'package_categories',
    'warehouses', 'officer_signup_otps'
  ];
begin
  foreach t in array business loop
    if to_regclass('public.' || t) is not null
       and to_regclass('backup_snapshot.' || t) is not null then
      execute format(
        'truncate table public.%I restart identity cascade', t);
    end if;
  end loop;
end $$;

-- 1b. ── Restore profiles via UPSERT (never delete them), BEFORE business rows ─
--     Deleting profiles fails: restored packages reference them
--     (packages.inspected_by → profiles.id). And packages must be inserted only
--     after their inspecting officer's profile exists — so upsert profiles here,
--     between the truncate and the business re-insert. Upsert = update any that
--     changed + insert any missing (whose auth.users row exists); profiles that
--     exist now but aren't in the snapshot are left untouched.
do $$
declare
  cols text;
  updates text;
begin
  if to_regclass('backup_snapshot.profiles') is null then
    return;
  end if;

  -- Build the column list + "col = excluded.col" update list dynamically so we
  -- don't have to hard-code every profile column.
  select string_agg(quote_ident(column_name), ', '),
         string_agg(
           quote_ident(column_name) || ' = excluded.' || quote_ident(column_name),
           ', ')
    into cols, updates
    from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles';

  execute format($f$
    insert into public.profiles (%1$s)
    select %1$s from backup_snapshot.profiles p
     where exists (select 1 from auth.users u where u.id = p.id)
    on conflict (id) do update set %2$s
  $f$, cols, updates);

  -- Nobody is actually online at restore time — clear any is_online the
  -- snapshot carried, so the dashboard doesn't show stale "online" users.
  update public.profiles set is_online = false where is_online is true;
end $$;

-- 2. ── Re-insert snapshot rows (parents first, respecting FKs) ───────────────
do $$
declare
  t text;
  -- Parents → children insert order.
  ordered text[] := array[
    'warehouses', 'package_categories', 'hold_reasons', 'storage_rates',
    'packages', 'package_items', 'warehouse_entries',
    'forfeited_packages',
    'disposal_requests', 'disposal_request_items',
    'tenders', 'tender_disposals', 'tender_sales', 'tender_sale_items',
    'destructions', 'destruction_items',
    'disposal_taxes',
    'audit_logs', 'officer_signup_otps'
  ];
  n bigint;
begin
  foreach t in array ordered loop
    if to_regclass('public.' || t) is not null
       and to_regclass('backup_snapshot.' || t) is not null then
      execute format(
        'insert into public.%I select * from backup_snapshot.%I', t, t);
      execute format('select count(*) from public.%I', t) into n;
      raise notice 'restored %-24s % rows', t, n;
    end if;
  end loop;
end $$;

-- 4. ── Fix identity/serial sequences so new inserts don't collide ────────────
--    For any table with an `id` integer identity, bump its sequence past the
--    max restored id. (No-op for uuid PKs.)
do $$
declare
  r record;
begin
  for r in
    select c.relname as tbl, a.attname as col,
           pg_get_serial_sequence('public.'||c.relname, a.attname) as seq
      from pg_class c
      join pg_attribute a on a.attrelid = c.oid
     where c.relkind = 'r'
       and c.relnamespace = 'public'::regnamespace
       and a.attname = 'id'
       and pg_get_serial_sequence('public.'||c.relname, a.attname) is not null
  loop
    execute format(
      'select setval(%L, coalesce((select max(%I) from public.%I), 0) + 1, false)',
      r.seq, r.col, r.tbl);
  end loop;
end $$;

-- Review the NOTICE counts above. If they match the backup, keep it:
commit;
-- Otherwise: rollback;

-- Done. Relaunch the app — the data is back to the snapshot state.
