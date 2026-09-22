-- ============================================================================
-- 66 · Provision the least-privilege login used by every desktop client.
--
-- Run ONCE as a database administrator, then put the same password in the
-- .env next to each installed application:
--
--   PG_USER=yard_app
--   PG_PASSWORD=<the password below>
--
-- Choose a unique, strong password before running. Do not commit it, put it
-- in this SQL file, or use the postgres administrator password. The app checks
-- at startup and refuses a superuser / BYPASSRLS connection because either one
-- defeats the database's per-yard RLS policies.
-- ============================================================================

-- Replace ONLY this value before executing in pgAdmin.
-- ⚠️ Guarded and re-runnable, and the password is a PLACEHOLDER.
--
-- This used to be a bare `create role ... password 'postgres'`, which fails
-- outright on a second run and ships a known password if nobody edits it.
-- `install_all.ps1 -YardAppPassword <pw>` substitutes the placeholder into a
-- temporary copy, so the real password never reaches the command line, the
-- shell history or this file.
select set_config('app.new_yard_app_password',
                  'CHANGE_ME_BEFORE_RUNNING', false);

do $role$
declare
  v_pw text := current_setting('app.new_yard_app_password', true);
begin
  -- ⚠️ The sentinel is assembled, never written whole.
  --
  -- install_all.ps1 substitutes EVERY occurrence of the quoted placeholder,
  -- including the one in this condition -- so with the literal here the
  -- guard became `in ('', '<the real password>')` and rejected the correct
  -- password. Splitting it means only the set_config() line is rewritten.
  if coalesce(v_pw, '') in ('', 'CHANGE_ME' || '_BEFORE_RUNNING') then
    raise exception
      'Set a real password in the set_config() line above, or run '
      'install_all.ps1 -YardAppPassword <pw>.';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'yard_app') then
    execute format(
      'create role yard_app login password %L '
      'nosuperuser nocreatedb nocreaterole inherit nobypassrls', v_pw);
    raise notice 'created role yard_app';
  else
    -- ⚠️ TWO STATEMENTS, and the second may fail. A CREATEROLE-but-not-
    -- superuser admin (Supabase) cannot change another role's ATTRIBUTES,
    -- and combining them meant the password change died with them -- the
    -- role kept its old password and the app could not log in.
    execute format('alter role yard_app password %L', v_pw);
    raise notice 'role yard_app already existed - password reset';
    begin
      execute 'alter role yard_app nosuperuser nocreatedb nocreaterole '
              'inherit nobypassrls';
    exception when insufficient_privilege then
      raise notice '  (cannot re-assert attributes here - not superuser)';
    end;
  end if;
end $role$;

select set_config('app.new_yard_app_password', '', false);

grant authenticated to yard_app;
-- ⚠️ The CURRENT database, not a hardcoded name. This said
-- "Customs_SR_DB", so running it against the backup copy (or any other
-- name) failed on a database that was otherwise fine.
do $conn$
begin
  execute format('grant connect on database %I to yard_app',
                 current_database());
end $conn$;
grant usage on schema public, sr_auth to yard_app;

grant select, insert, update, delete on all tables in schema public to yard_app;
grant usage, select on all sequences in schema public to yard_app;
grant execute on all functions in schema public to yard_app;
grant execute on all functions in schema sr_auth to yard_app;
grant select on sr_auth.users to yard_app;

-- Keep future schema changes usable without granting server administration.
alter default privileges in schema public
  grant select, insert, update, delete on tables to yard_app;
alter default privileges in schema public
  grant usage, select on sequences to yard_app;
alter default privileges in schema public
  grant execute on functions to yard_app;

-- Verification: both values MUST be false.
select rolname, rolsuper, rolbypassrls, rolcanlogin, rolinherit
from pg_roles
where rolname = 'yard_app';
