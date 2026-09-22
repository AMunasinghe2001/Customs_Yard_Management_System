-- ==========================================================================
--  REPAIR: the backup database ended up HALF migrated -- it has BOTH
--  `auth` (the real accounts) and `sr_auth` (created empty).
--
--  Run against Customs_SR_DB_backup_20260914_1543 ONLY, as postgres:
--
--      psql -U postgres -d Customs_SR_DB_backup_20260914_1543 \
--           -f postgres/repair_backup_split_auth.sql
--
--  WHAT HAPPENED
--  -------------
--  `migrate_local_to_sr_auth.ps1` failed on its first attempt (a broken file
--  path), so migration 048 never ran. install_all.ps1 was reached on a later
--  attempt and `postgres/01_auth_and_session.sql` created a FRESH, EMPTY
--  `sr_auth` -- exactly what it should do on a NEW database. The real
--  accounts stayed behind in `auth`. Measured:
--
--      auth.users               13 rows   <- the real accounts
--      auth.password_history    13 rows
--      sr_auth.users             0 rows   <- placeholder, never used
--      sr_auth.password_history  0 rows
--
--  The app reads `sr_auth.users`, finds nobody, and every sign-in fails.
--  Forgot-password is silent too: it says "if that account exists" on
--  purpose, so a missing account looks exactly like a sent mail.
--
--  ⚠️ WHY NOT `drop schema sr_auth cascade`
--  ---------------------------------------
--  Because the install got FURTHER than just creating the schema. Measured
--  in this database before writing this file:
--
--      21 RLS policies already call `sr_auth.uid()`
--      16 RLS policies still call `auth.uid()`
--      sr_auth holds 16 functions, auth holds 15
--
--  A cascade drop would take those 21 policies with it, SILENTLY. A table
--  whose policies are gone is not locked down -- it is readable by every
--  role that can reach it. That is far worse than the broken login this
--  file is fixing.
--
--  So: move the DATA into the sr_auth tables that already exist, leave the
--  schema, its functions and every policy alone, and drop only the two old
--  `auth` tables afterwards. `install_all.ps1` then re-applies the 16
--  policies that still name the old schema, along with everything else.
--
--  Safe to re-run: it stops if sr_auth already holds rows.
-- ==========================================================================

begin;

do $repair$
declare
  n_sr_users int;
  n_sr_hist  int;
  n_auth     int;
  n_hist     int;
  n_fk       int := 0;
  r          record;
begin
  if to_regnamespace('auth') is null then
    raise notice 'SKIP: no auth schema - nothing to repair';
    return;
  end if;
  if to_regnamespace('sr_auth') is null then
    raise notice 'SKIP: no sr_auth schema - run migration 048 instead';
    return;
  end if;

  -- ⚠️ Refuse a Supabase-owned auth, exactly as 048 does. Recognised by
  -- OWNER, not by hostname, so a restored dump cannot fool it.
  if (select pg_get_userbyid(nspowner) from pg_namespace
       where nspname = 'auth')
     in ('supabase_admin', 'supabase_auth_admin') then
    raise exception 'the auth schema belongs to Supabase - not ours';
  end if;

  select count(*) into n_sr_users from sr_auth.users;
  select count(*) into n_sr_hist  from sr_auth.password_history;
  select count(*) into n_auth     from auth.users;
  select count(*) into n_hist     from auth.password_history;

  -- ⚠️ THE SAFETY CHECK. Copying into a NON-empty sr_auth could collide on
  -- the primary key or, worse, quietly mix two sets of accounts. Only an
  -- untouched placeholder may be filled.
  if n_sr_users <> 0 or n_sr_hist <> 0 then
    raise exception
      'sr_auth is NOT empty (% users, % history rows) - refusing to touch '
      'it. Inspect both schemas by hand.', n_sr_users, n_sr_hist;
  end if;

  if n_auth = 0 then
    raise exception
      'auth.users is empty too - there is nothing to rescue. Inspect by hand.';
  end if;

  raise notice 'sr_auth is empty; auth holds % account(s) - moving them',
    n_auth;

  -- The data moves; the schema, its functions and every policy stay put.
  --
  -- ⚠️ EVERY COLUMN NAMED, never `select *`. The two tables hold the same
  -- ten columns in a DIFFERENT ORDER: `auth.users` has
  -- raw_user_meta_data / created_at / updated_at before
  -- failed_login_attempts / locked_until, and `sr_auth.users` has them
  -- after. A positional `select *` would line jsonb up against integer --
  -- either an error, or silently the wrong values in the wrong columns.
  insert into sr_auth.users (
    id, email, encrypted_password, email_confirmed_at, last_sign_in_at,
    failed_login_attempts, locked_until, raw_user_meta_data,
    created_at, updated_at)
  select
    id, email, encrypted_password, email_confirmed_at, last_sign_in_at,
    failed_login_attempts, locked_until, raw_user_meta_data,
    created_at, updated_at
  from auth.users;

  insert into sr_auth.password_history (id, user_id, password_hash, changed_at)
  select id, user_id, password_hash, changed_at from auth.password_history;

  -- ⚠️ The ids were copied across, but the two tables have SEPARATE
  -- sequences and sr_auth's is still sitting at 1. The next password
  -- change would then try to reuse id 1 and fail on the primary key.
  -- Move it past the highest id that now exists.
  perform setval('sr_auth.password_history_id_seq',
                 coalesce((select max(id) from sr_auth.password_history), 0) + 1,
                 false);

  raise notice '  copied % users, % password_history rows', n_auth, n_hist;

  -- ⚠️ REPOINT THE FOREIGN KEYS FIRST. Nine tables in `public` still
  -- reference `auth.users` -- profiles, tender_bids, financial_expenses
  -- and the rest. They cannot simply be dropped along with the old table:
  -- `drop table auth.users` would refuse while they exist, and forcing it
  -- with CASCADE would remove the constraints entirely, leaving rows whose
  -- created_by / updated_by point at nobody and no longer have to.
  --
  -- Each one is rebuilt against sr_auth.users with the SAME name and the
  -- same delete rule, so the schema ends up exactly as a fresh build.
  for r in
    select c.conname,
           c.conrelid::regclass::text as tbl,
           pg_get_constraintdef(c.oid) as def
      from pg_constraint c
     where c.contype = 'f'
       and c.confrelid = 'auth.users'::regclass
       and c.connamespace <> 'auth'::regnamespace
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    -- The definition only differs by the schema it points at.
    execute format('alter table %s add constraint %I %s',
                   r.tbl, r.conname,
                   replace(r.def, 'REFERENCES auth.users',
                                  'REFERENCES sr_auth.users'));
    n_fk := n_fk + 1;
  end loop;
  raise notice '  repointed % foreign key(s) to sr_auth.users', n_fk;

  -- ⚠️ The old tables go only AFTER the copy and the FK moves succeeded,
  -- and only these two BY NAME -- never the schema itself, in case
  -- something else was put in it. A leftover `auth` object is harmless; a
  -- dropped policy or a dropped constraint is not.
  drop table auth.password_history;
  drop table auth.users;

  raise notice 'PASS: % account(s) now live in sr_auth', n_auth;
end $repair$;

-- --------------------------------------------------------------------------
-- Verify BEFORE committing. Anything wrong here rolls the whole thing back.
-- --------------------------------------------------------------------------
do $verify$
declare
  n     int;
  n_pol int;
  n_fk  int;
begin
  select count(*) into n from sr_auth.users;
  if n = 0 then
    raise exception 'sr_auth.users is empty - the accounts did not move';
  end if;

  -- ⚠️ The whole reason this file does not cascade: prove the policies that
  -- call sr_auth are still there.
  select count(*) into n_pol from pg_policies
   where qual like '%sr_auth%' or with_check like '%sr_auth%';
  if n_pol = 0 then
    raise exception 'no policy references sr_auth any more - RLS was lost';
  end if;

  -- ⚠️ Every foreign key that pointed at the old table must now point at
  -- the new one. A missing constraint here would mean created_by /
  -- updated_by columns that are no longer checked against anything.
  select count(*) into n_fk from pg_constraint
   where contype = 'f' and confrelid = 'sr_auth.users'::regclass
     and connamespace <> 'sr_auth'::regnamespace;
  if n_fk < 9 then
    raise exception
      'only % foreign key(s) point at sr_auth.users - expected 9 '
      '(profiles, tender_bids, financial_expenses and the rest)', n_fk;
  end if;

  -- profiles is the one with ON DELETE CASCADE; losing that rule would
  -- leave orphan profiles behind whenever an account is deleted.
  if not exists (
    select 1 from pg_constraint
     where conname = 'profiles_id_fkey'
       and confrelid = 'sr_auth.users'::regclass
       and pg_get_constraintdef(oid) like '%ON DELETE CASCADE%')
  then
    raise exception 'profiles_id_fkey lost its ON DELETE CASCADE';
  end if;

  raise notice 'PASS: % account(s), % policy(ies), % foreign key(s) intact',
    n, n_pol, n_fk;
  raise notice 'NOW RUN: install_all.ps1 -Target backup';
  raise notice '  (the policies still naming the old schema are re-applied there)';
end $verify$;

commit;
