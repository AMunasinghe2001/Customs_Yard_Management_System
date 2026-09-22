-- ============================================================================
--  91 · The least-privilege login, for SUPABASE
--
--  Supabase's own `postgres` role has **rolbypassrls = true**. Measured on a
--  live project:
--
--      postgres       super=false  bypassrls=TRUE
--      service_role   super=false  bypassrls=TRUE
--      authenticator  super=false  bypassrls=false   (inherit=false)
--      authenticated  super=false  bypassrls=false
--      anon           super=false  bypassrls=false
--
--  ⚠️ SO THE APP MUST NOT CONNECT AS `postgres`. Every one of the 155
--  per-yard policies is skipped for a BYPASSRLS role, which would show every
--  yard's goods to every office. The app already refuses to start on such a
--  connection (pg_connection.dart checks `rolsuper`/`rolbypassrls`), so this
--  is not optional — without it the app will not run at all.
--
--  ⚠️ NOT `authenticator` either, tempting as it looks. It is granted
--  `service_role`, which bypasses RLS, and it is `inherit=false` — so its
--  privileges depend on an explicit SET ROLE the app never issues. A login
--  of our own is clearer and is what the office server already uses
--  (postgres/66).
--
--  This is postgres/66 adapted to Supabase: the database is `postgres`, not
--  `Customs_SR_DB`, and the role is created only if absent so the file is
--  safe to re-run.
--
--  ── RUN THIS AS `postgres`, AFTER the schema is loaded ─────────────────────
--
--  The grants below are "on ALL tables in schema public", which only covers
--  what exists WHEN THEY RUN. Load the schema first, then this file. If you
--  add tables later, re-run it — it is idempotent.
-- ============================================================================

\set ON_ERROR_STOP on

-- ── 1. Choose the password ────────────────────────────────────────────────
--
-- ⚠️ CHANGE THIS before running, and put the same value in the .env as
-- PG_PASSWORD__supabase. Do not reuse the project's postgres password: the
-- whole point is that a leaked application password cannot alter the schema.
--  ⚠️ A `set_config`, not a `\set`. A psql variable does NOT interpolate
--  inside a dollar-quoted block -- `:'name'` there is a syntax error at the
--  colon, which is easy to miss because the file looks reasonable. Tested
--  before shipping this. A GUC is readable from PL/pgSQL and, being `false`
--  (session-scoped), disappears when the connection closes.
select set_config('app.new_yard_app_password',
                  'CHANGE_ME_BEFORE_RUNNING', false);

do $$
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
      'Set a real password in the set_config() line above before running.';
  end if;
  if length(v_pw) < 12 then
    raise exception
      'That password is % characters. This account is reachable from the '
      'public internet; use at least 12.', length(v_pw);
  end if;

  if not exists (select 1 from pg_roles where rolname = 'yard_app') then
    execute format(
      'create role yard_app login password %L '
      'nosuperuser nocreatedb nocreaterole inherit nobypassrls', v_pw);
    raise notice 'created role yard_app';
  else
    -- Re-run: refresh the password, then re-assert the safety attributes.
    --
    -- ⚠️ TWO STATEMENTS, and the second is allowed to fail.
    --
    -- On Supabase the admin account is CREATEROLE but NOT superuser, and
    -- PostgreSQL only lets a superuser change another role's attributes
    -- (NOSUPERUSER / NOBYPASSRLS / ...). A single combined ALTER therefore
    -- died with `permission denied to alter role` -- and because the
    -- password was in that same failed statement, the role was left with
    -- its OLD password and the app could no longer log in. A cosmetic
    -- re-assertion broke a working deployment.
    --
    -- The password is the part that must succeed, so it goes first and
    -- alone. The attributes were set correctly at CREATE time and nothing
    -- short of a superuser can have changed them since, so failing to
    -- re-state them is not a problem -- the verification below still
    -- proves they are right.
    execute format('alter role yard_app password %L', v_pw);
    raise notice 'role yard_app already existed - password reset';

    begin
      execute 'alter role yard_app nosuperuser nocreatedb nocreaterole '
              'inherit nobypassrls';
    exception when insufficient_privilege then
      raise notice '  (cannot re-assert attributes here - not superuser; '
                   'they are checked below instead)';
    end;
  end if;
end $$;

-- Do not leave it sitting in the session.
select set_config('app.new_yard_app_password', '', false);


-- ── 2. Membership ─────────────────────────────────────────────────────────
--
-- ⚠️ `authenticated` ONLY. The 155 policies are written against `anon`,
-- `authenticated` and `service_role`; granting `service_role` here would
-- hand back the BYPASSRLS this file exists to avoid.
grant authenticated to yard_app;

-- ⚠️ NOT service_role. Stated so a future edit has to argue with it.
-- revoke service_role from yard_app;   -- (never granted in the first place)


-- ── 3. Reach ──────────────────────────────────────────────────────────────
grant connect on database postgres to yard_app;
grant usage on schema public to yard_app;

grant select, insert, update, delete on all tables in schema public to yard_app;
grant usage, select on all sequences in schema public to yard_app;
grant execute on all functions in schema public to yard_app;

-- ⚠️ The `auth` schema is granted CONDITIONALLY. It always exists on
-- Supabase, but a bare `grant ... on schema sr_auth` aborts the whole file on
-- a database that has not loaded it yet -- which is exactly what happened
-- when this was rehearsed against a plain `postgres` database. The grants
-- above are the ones that matter; these are skipped with a notice instead
-- of taking the run down with them.
do $auth$
begin
  if exists (select 1 from pg_namespace where nspname = 'sr_auth') then
    execute 'grant usage on schema sr_auth to yard_app';
    execute 'grant execute on all functions in schema sr_auth to yard_app';
    if to_regclass('sr_auth.users') is not null then
      execute 'grant select on sr_auth.users to yard_app';
    end if;
    raise notice 'granted on schema sr_auth';
  else
    raise notice 'WARN: schema sr_auth does not exist - load the schema, then '
                 're-run this file';
  end if;
end $auth$;

-- ⚠️ Anything created AFTER this file runs would otherwise be unreachable,
-- and the failure looks like a missing table rather than a missing grant.
alter default privileges in schema public
  grant select, insert, update, delete on tables to yard_app;
alter default privileges in schema public
  grant usage, select on sequences to yard_app;
alter default privileges in schema public
  grant execute on functions to yard_app;


-- ── Verification ───────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  n_tables int;
begin
  select rolsuper, rolbypassrls, rolcanlogin, rolinherit into r
    from pg_roles where rolname = 'yard_app';

  if r.rolsuper or r.rolbypassrls then
    raise exception 'yard_app can bypass RLS - the app will refuse to start, '
      'and rightly so';
  end if;
  if not r.rolcanlogin then
    raise exception 'yard_app cannot log in';
  end if;
  if not r.rolinherit then
    -- Without inherit it holds `authenticated` only after an explicit
    -- SET ROLE, which the app never issues -- every policy would then see
    -- it as an unrecognised role.
    raise exception 'yard_app must INHERIT, or its grants do not apply';
  end if;
  raise notice 'PASS: yard_app is login, inherit, and subject to RLS';

  if exists (select 1 from pg_auth_members m
               join pg_roles g on g.oid = m.member
               join pg_roles p on p.oid = m.roleid
              where g.rolname = 'yard_app' and p.rolname = 'service_role') then
    raise exception 'yard_app is a member of service_role, which BYPASSES RLS';
  end if;
  raise notice 'PASS: yard_app is not a member of service_role';

  select count(*) into n_tables from information_schema.tables
   where table_schema = 'public' and table_type = 'BASE TABLE';
  if n_tables = 0 then
    raise notice 'WARN: schema public is EMPTY - load the schema, then re-run';
    raise notice '      this file so the ALL-TABLES grants actually cover it';
  else
    raise notice 'PASS: granted over % table(s) in public', n_tables;
  end if;
end $verify$;

-- ============================================================================
--  AFTER RUNNING
--
--    1. Put the password in .env as PG_PASSWORD__supabase
--    2. Change PG_USER__supabase to:   yard_app.<project-ref>
--
--       ⚠️ THE POOLER STILL WANTS THE REF IN THE USERNAME. It is
--       `<role>.<ref>`, not just the role. Measured with a throwaway role:
--
--         probe_rls        -> FATAL (ENOIDENTIFIER) no tenant identifier
--         probe_rls.<ref>  -> connects, current_user = probe_rls,
--                             rolbypassrls = false
--
--       So a custom role DOES work through the pooler, and it is correctly
--       subject to RLS -- which `postgres` is not.
--
--    3. Re-run postgres/90_supabase_readiness_check.sql. Check 1 must now
--       say PASS; while it says FAIL the app is refusing to start for the
--       right reason.
-- ============================================================================
