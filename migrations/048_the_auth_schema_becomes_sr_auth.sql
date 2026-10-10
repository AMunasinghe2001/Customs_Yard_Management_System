-- ============================================================================
--  048 · Our `auth` schema becomes `sr_auth`
--
--  ⚠️ WHY, and it is not cosmetic: Supabase OWNS the `auth` schema.
--
--      auth owner            supabase_admin
--      can create in auth    FALSE          <- measured on a live project
--      auth.users owner      supabase_auth_admin
--
--  So 14 of our SQL files died with "permission denied for schema auth", and
--  the app could never have signed anybody in there.
--
--  ⚠️ THE SUBTLER HALF, which is the real reason a rename is the only way
--  out: Supabase ALREADY HAS an `auth.uid()`, and it reads a JWT claim --
--
--      current_setting('request.jwt.claim.sub')
--
--  while ours reads the session variable the desktop app sets --
--
--      current_setting('app.current_user_id')
--
--  Both are called `auth.uid()`. Had we somehow loaded our policies there,
--  all 189 of them would have called THEIRS, got NULL, and denied every row
--  silently. A different schema name is what makes the two coexist.
--
--  ── What this migration does ───────────────────────────────────────────────
--
--  Moves an EXISTING `auth` schema (office server, local, backup) across to
--  `sr_auth`, keeping every row. `alter schema ... rename to` carries the
--  tables, the functions, the data and the grants in one step -- no dump, no
--  reload, nothing to mis-copy.
--
--  ⚠️ BUT A RENAME DOES NOT REACH INSIDE FUNCTION BODIES, and that is the
--  trap this file exists to close. `sr_auth.sign_in` was still calling
--  `auth.sign_in_before_flush` -- the name was baked into its source when it
--  was created -- so the very first login failed with
--
--      ERROR: schema "auth" does not exist
--
--  Measured right after the rename: 48 function bodies still named the old
--  schema. So the rename is step ONE; the definitions must then be
--  re-applied from the (already renamed) SQL files:
--
--      postgres/01_auth_and_session.sql
--      postgres/04_auth.sql
--      postgres/05_password_reset.sql
--      migrations/018, 021, 023, 024, 032, 035, 036, 047
--
--  `install_all.ps1` does exactly that, so the simplest correct recipe on an
--  EXISTING database is: run this file, then re-run install_all.ps1. The
--  verification at the bottom refuses to pass until no body names the old
--  schema, so a half-done migration cannot be mistaken for a finished one.
--
--  ⚠️ It does NOT touch Supabase's `auth`. The guard below refuses to run
--  where the schema is owned by somebody else, so pointing this at a
--  Supabase project is a no-op rather than an error you have to undo.
--
--  Safe to re-run: if `sr_auth` is already there and `auth` is not ours,
--  there is nothing to do.
-- ============================================================================

set lock_timeout = '10s';

do $rename$
declare
  v_auth_owner  text;
  v_me          text := current_user;
  v_has_sr      boolean := to_regnamespace('sr_auth') is not null;
  v_has_auth    boolean := to_regnamespace('auth') is not null;
  n_users       int;
begin
  -- ── Already done ────────────────────────────────────────────────────────
  if v_has_sr and not v_has_auth then
    raise notice 'SKIP: sr_auth exists and there is no auth schema - done';
    return;
  end if;

  if not v_has_auth then
    raise notice 'SKIP: no auth schema here - a fresh build makes sr_auth '
                 'directly (postgres/01)';
    return;
  end if;

  select pg_get_userbyid(nspowner) into v_auth_owner
    from pg_namespace where nspname = 'auth';

  -- ── Supabase's auth: leave it strictly alone ────────────────────────────
  --
  -- ⚠️ Recognised by OWNERSHIP, not by hostname. A restored dump or a copied
  -- database could carry Supabase's auth anywhere, and renaming it would
  -- break their GoTrue rather than move ours.
  if v_auth_owner in ('supabase_admin', 'supabase_auth_admin') then
    raise notice 'SKIP: the auth schema belongs to % - not ours to move',
      v_auth_owner;
    if not v_has_sr then
      raise notice '      run postgres/01_auth_and_session.sql to create '
                   'sr_auth alongside it';
    end if;
    return;
  end if;

  -- ── Both exist and ours is the one called `auth` ────────────────────────
  if v_has_sr then
    raise exception
      'both sr_auth and a locally-owned auth exist. Refusing to guess which '
      'is current - inspect them and drop the stale one by hand.';
  end if;

  select count(*) into n_users from auth.users;

  -- ⚠️ RENAME, not create-and-copy. A copy would need every table, every
  -- function body, every grant and every default restated, and one missed
  -- column is a silent data loss. The rename moves all of it atomically and
  -- cannot drop a row.
  execute 'alter schema auth rename to sr_auth';

  raise notice 'PASS: auth -> sr_auth (% account(s) carried over)', n_users;
end $rename$;


-- ── Verification ───────────────────────────────────────────────────────────
do $verify$
declare
  n_users int;
  n_fns   int;
  n_stale int;
begin
  if to_regnamespace('sr_auth') is null then
    raise notice 'SKIP verify: no sr_auth here (Supabase, or not built yet)';
    return;
  end if;

  select count(*) into n_fns from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'sr_auth';

  -- ⚠️ The functions the app actually calls, by name. A schema that exists
  -- but is missing sign_in is worse than one that is absent: the app gets
  -- past start-up and fails at the login screen.
  if to_regproc('sr_auth.sign_in') is null then
    raise exception 'sr_auth.sign_in is missing - run postgres/04_auth.sql';
  end if;
  if to_regproc('sr_auth.uid') is null then
    raise exception 'sr_auth.uid is missing - run postgres/01';
  end if;

  select count(*) into n_users from sr_auth.users;
  raise notice 'PASS: sr_auth has % function(s) and % account(s)',
    n_fns, n_users;

  -- ⚠️ And nothing may still point at the OLD name. A policy or function
  -- left calling `auth.uid()` would silently read Supabase's JWT version on
  -- the cloud, or fail outright on the office server.
  if exists (
    select 1 from pg_policy p
     where pg_get_expr(p.polqual, p.polrelid) ~ '(?<!sr_)\mauth\.(uid|role)\('
        or pg_get_expr(p.polwithcheck, p.polrelid) ~ '(?<!sr_)\mauth\.(uid|role)\('
  ) then
    raise exception 'a policy still calls auth.uid()/auth.role() - the '
      'rename did not reach it';
  end if;
  raise notice 'PASS: no policy still calls the old auth.uid()/auth.role()';

  -- ⚠️ THE ONE THAT ACTUALLY BIT. A schema rename moves a function but
  -- leaves its SOURCE untouched, so `sr_auth.sign_in` kept calling
  -- `auth.sign_in_before_flush` and the first login died with
  -- 'schema "auth" does not exist'. Counted here rather than assumed.
  select count(*) into n_stale
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('sr_auth', 'public')
     and p.prosrc ~ ('(?<!sr_)\mauth\.(uid|role|users|sign_in|sign_up|'
                     'begin_session|change_password|session_user_id|'
                     'password_is_expired|user_by_id|password_history|'
                     'clear_failed_login|record_failed_login|update_user|'
                     'email)\M');
  if n_stale > 0 then
    raise exception
      '% function body(ies) still name the old auth schema. The rename moved '
      'them but not their source -- re-run install_all.ps1 (or at least '
      'postgres/01, 04, 05 and migrations 018/021/023/024/032/035/036/047) '
      'to re-create them against sr_auth.', n_stale;
  end if;
  raise notice 'PASS: no function body still names the old auth schema';
end $verify$;


insert into public.schema_migrations (version, name)
values (48, '048_the_auth_schema_becomes_sr_auth')
on conflict (version) do nothing;
