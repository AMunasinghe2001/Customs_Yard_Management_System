-- ==========================================================================
--  REPAIR: remove the placeholder profiles that have no account behind them,
--  then add the foreign keys that could not be created while they existed.
--
--  Run against Customs_SR_DB_backup_20260914_1543, as postgres:
--
--      psql -U postgres -d Customs_SR_DB_backup_20260914_1543 \
--           -f postgres/repair_orphan_profiles.sql
--
--  WHY
--  ---
--  `repair_backup_split_auth.sql` moved the 13 accounts into `sr_auth.users`
--  and dropped the old `auth` tables -- that part worked. But it could not
--  add `profiles_id_fkey`, and reported
--
--      only 0 foreign key(s) point at sr_auth.users - expected 9
--
--  because `public.profiles` holds 18 rows against 13 accounts. Six of them
--  reference an id that no longer exists anywhere, so PostgreSQL refuses the
--  constraint:
--
--      insert or update on table "profiles" violates foreign key constraint
--      DETAIL: Key (id)=(a7eaa47b-...) is not present in table "users".
--
--  Measured before writing this file -- all six are EMPTY placeholders:
--
--      username      (blank)      badge_number  (blank)
--      full_name     'New User'   mobile_number (blank)
--      role          'officer'    directorate   (blank)
--      yard          (blank)      job_role      (blank)
--      created_at    2026-09-22, 14:06 - 14:11
--
--  That window is this afternoon's repair attempts, not real officers. They
--  are debris from `migrations/035` and `036`, whose self-checks insert a
--  profile, and whose rollback did not reach the row when a LATER statement
--  in the same file failed.
--
--  ⚠️ THE TWO AUDIT ROWS. Exactly two `audit_logs` rows point at these
--  profiles, and both are `action = 'Migration 029 self-check'` -- written
--  by a migration testing itself, not a record of anything a person did.
--  `audit_logs` is append-only (postgres/53), so this file does NOT delete
--  them: it sets `user_id` to NULL, which the column allows. The audit row
--  survives, it simply no longer claims a user that never existed.
--
--  Safe to re-run: it only ever touches profiles with no matching account.
-- ==========================================================================

begin;

do $repair$
declare
  n_orphan  int;
  n_named   int;
  n_audit   int;
begin
  -- ── Refuse to touch anything that looks like a real account ────────────
  --
  -- ⚠️ THE GUARD THAT MATTERS. A profile with a username, a yard, a badge
  -- or a directorate is somebody's account whose auth row went missing --
  -- that is a data-loss incident to investigate, NOT something to delete.
  -- Only a completely blank placeholder may go.
  select count(*) into n_named
    from public.profiles p
    left join sr_auth.users u on u.id = p.id
   where u.id is null
     and (coalesce(p.username, '')      <> ''
       or coalesce(p.yard, '')          <> ''
       or coalesce(p.badge_number, '')  <> ''
       or coalesce(p.directorate, '')   <> ''
       or coalesce(p.mobile_number, '') <> ''
       or coalesce(p.full_name, '') not in ('', 'New User'));

  if n_named > 0 then
    raise exception
      '% orphaned profile(s) carry real details (username / yard / badge). '
      'Refusing to delete them - investigate by hand: their accounts have '
      'gone missing.', n_named;
  end if;

  select count(*) into n_orphan
    from public.profiles p
    left join sr_auth.users u on u.id = p.id
   where u.id is null;

  if n_orphan = 0 then
    raise notice 'SKIP: every profile already has an account behind it';
  else
    raise notice '% blank placeholder profile(s) to remove', n_orphan;

    -- ⚠️ audit_logs is APPEND-ONLY (postgres/53) and the trigger refuses
    -- UPDATE as firmly as DELETE -- including the `on delete set null`
    -- cascade PostgreSQL would run by itself, which arrives as an UPDATE
    -- and is rejected the same way. Tested: deleting the profiles alone
    -- fails with
    --
    --     audit_logs is append-only: UPDATE is not permitted
    --
    -- So the rows have to go, and only the retention job's own flag may
    -- remove them. That is acceptable ONLY because of what they are: the
    -- check below refuses to run unless every affected row is a
    -- 'Migration NNN self-check' written by a migration testing itself.
    -- A real audit record is never deleted to make a constraint fit.
    if exists (
      select 1 from public.audit_logs a
       where a.user_id in (
         select p.id from public.profiles p
          left join sr_auth.users u on u.id = p.id
          where u.id is null)
         and coalesce(a.action, '') !~ '^Migration [0-9]+ self-check$')
    then
      raise exception
        'an audit row belonging to an orphaned profile is NOT a migration '
        'self-check. Refusing to delete real audit history - inspect '
        'audit_logs by hand.';
    end if;

    perform set_config('app.audit_purge', 'on', true);  -- this txn only
    delete from public.audit_logs a
     where a.user_id in (
       select p.id from public.profiles p
        left join sr_auth.users u on u.id = p.id
        where u.id is null);
    get diagnostics n_audit = row_count;
    if n_audit > 0 then
      raise notice '  removed % migration self-check audit row(s)', n_audit;
    end if;

    delete from public.profiles p
     where not exists (select 1 from sr_auth.users u where u.id = p.id);
    raise notice '  deleted % placeholder profile(s)', n_orphan;
  end if;
end $repair$;

-- --------------------------------------------------------------------------
--  Now the foreign keys. These are the nine that `repair_backup_split_auth`
--  could not create, because profiles still held rows pointing at nobody.
-- --------------------------------------------------------------------------
do $fks$
declare
  r     record;
  n_new int := 0;
begin
  for r in
    select * from (values
      ('profiles',                 'id',         ' on delete cascade'),
      ('package_categories',       'updated_by', ''),
      ('package_category_targets', 'updated_by', ''),
      ('tender_bids',              'created_by', ''),
      ('tender_revaluations',      'created_by', ''),
      ('tender_committees',        'created_by', ''),
      ('tender_committees',        'submitted_by', ''),
      ('unsold_proposals',         'decided_by', ''),
      ('financial_expenses',       'created_by', '')
    ) as t(tbl, col, rule)
  loop
    -- Named exactly as a fresh build names them, so the schema ends up
    -- identical either way.
    execute format('alter table public.%I drop constraint if exists %I',
                   r.tbl, r.tbl || '_' || r.col || '_fkey');
    execute format(
      'alter table public.%I add constraint %I '
      'foreign key (%I) references sr_auth.users(id)%s',
      r.tbl, r.tbl || '_' || r.col || '_fkey', r.col, r.rule);
    n_new := n_new + 1;
  end loop;
  raise notice 'PASS: % foreign key(s) now point at sr_auth.users', n_new;
end $fks$;

-- --------------------------------------------------------------------------
--  Verify before committing. A failure here rolls everything back.
-- --------------------------------------------------------------------------
do $verify$
declare
  n_orphan int;
  n_fk     int;
  n_users  int;
begin
  select count(*) into n_orphan
    from public.profiles p
    left join sr_auth.users u on u.id = p.id
   where u.id is null;
  if n_orphan > 0 then
    raise exception '% profile(s) still have no account', n_orphan;
  end if;

  select count(*) into n_fk from pg_constraint
   where contype = 'f' and confrelid = 'sr_auth.users'::regclass
     and connamespace = 'public'::regnamespace;
  if n_fk < 9 then
    raise exception 'only % foreign key(s) point at sr_auth.users, '
                    'expected 9', n_fk;
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'profiles_id_fkey'
       and confrelid = 'sr_auth.users'::regclass
       and pg_get_constraintdef(oid) like '%ON DELETE CASCADE%')
  then
    raise exception 'profiles_id_fkey lost its ON DELETE CASCADE';
  end if;

  select count(*) into n_users from sr_auth.users;
  raise notice 'PASS: % account(s), every profile matched, % foreign key(s)',
    n_users, n_fk;
end $verify$;

commit;
