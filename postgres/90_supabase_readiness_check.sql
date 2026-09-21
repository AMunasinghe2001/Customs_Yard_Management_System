-- ============================================================================
--  90 · Is this Supabase project ready to run the SR system?
--
--  Read-only except for ONE audit row, which it leaves behind: `audit_logs`
--  is append-only by trigger, so the probe cannot tidy up after itself.
--  Safe to run against a live project, and safe to re-run.
--
--  Run it in the Supabase SQL editor, or:
--      psql "<session pooler connection string>" -f postgres/90_supabase_readiness_check.sql
--
--  ⚠️ READ THE NOTICES. Every check reports PASS or FAIL and keeps going, so
--  one run tells you everything that needs fixing rather than stopping at the
--  first problem. Nothing here raises, because a half-answered readiness
--  check is worse than none.
--
--  The thing this exists for is CHECK 3. Migration 032 logs a refused
--  sign-in through `dblink`, and its handler is `exception when others then
--  null` -- deliberately, so that logging can never block a refusal. The cost
--  is that a broken dblink is COMPLETELY SILENT: sign-ins are still refused
--  correctly, and the audit log simply stays empty. Nobody notices until it
--  is needed as evidence.
-- ============================================================================

\set ON_ERROR_STOP off

do $check$
declare
  n int;
  txt text;
  ok boolean;
begin
  raise notice '';
  raise notice '=== SR SYSTEM · SUPABASE READINESS =====================';
  raise notice '';

  -- ── 1. Are we who we think we are, and is RLS actually binding? ─────────
  --
  -- ⚠️ THE SECURITY QUESTION, and the one that caught a wrong assumption:
  -- Supabase's `postgres` has rolbypassrls = TRUE. Connecting as it would
  -- skip all 155 per-yard policies and show every yard to every office.
  --
  -- Run postgres/91 to create `yard_app` (Supabase DOES allow it -- its
  -- postgres has rolcreaterole) and connect as that instead. The app itself
  -- refuses a bypassing role, so this check mirrors what it will do.
  select rolsuper or rolbypassrls into ok
    from pg_roles where rolname = current_user;
  if ok then
    raise notice 'FAIL  1. % BYPASSES RLS. Per-yard isolation is OFF.',
      current_user;
    raise notice '         Run postgres/91_supabase_yard_app_role.sql and';
    raise notice '         connect as yard_app.<project-ref> instead.';
  else
    raise notice 'PASS  1. % is subject to RLS (not superuser).', current_user;
  end if;

  -- ── 2. Extensions ───────────────────────────────────────────────────────
  for txt in select unnest(array['uuid-ossp', 'pgcrypto', 'dblink']) loop
    if exists (select 1 from pg_extension where extname = txt) then
      raise notice 'PASS  2. extension % is installed', txt;
    elsif exists (select 1 from pg_available_extensions where name = txt) then
      raise notice 'WARN  2. extension % is AVAILABLE but not installed', txt;
      raise notice '         create extension if not exists "%";', txt;
    else
      raise notice 'FAIL  2. extension % is NOT available on this project', txt;
    end if;
  end loop;

  raise notice '';
end $check$;

-- ── 3. Does dblink actually write on THIS host? ────────────────────────────
--
-- ⚠️ Separated into its own block on purpose. The call can fail in a way
-- that aborts the surrounding transaction, and a DO block that dies takes
-- every later check with it.
--
-- ⚠️ THE LIKELY FAILURE, and why this whole file exists: migration 032
-- connects with `dbname=<db> user=<user>` and NO PASSWORD. On the office
-- server that works because a local socket connection is trusted. Supabase
-- reaches itself over TCP through the pooler, where a password IS required
-- -- so the connection is refused, the handler swallows it, and refused
-- sign-ins are never recorded.
do $dblink$
declare
  before_n int;
  after_n  int;
  conn     text;
begin
  if not exists (select 1 from pg_extension where extname = 'dblink') then
    raise notice 'SKIP  3. dblink not installed - install it, then re-run';
    return;
  end if;

  select count(*) into before_n from public.audit_logs
   where action = 'SUPABASE READINESS PROBE';

  conn := format('dbname=%s user=%s', current_database(), current_user);

  begin
    perform dblink_exec(conn, $q$
      insert into public.audit_logs (user_id, action, entity_type, entity_id,
                                     details)
      values (null, 'SUPABASE READINESS PROBE', 'auth', 'probe',
              '{"probe": true}'::jsonb)
    $q$);
  exception when others then
    raise notice 'WARN  3. dblink could NOT connect back to this database.';
    raise notice '         %', sqlerrm;
    raise notice '';
    raise notice '         Expected on Supabase: 032 connects with no';
    raise notice '         password, which only a trusted local socket';
    raise notice '         accepts.';
    raise notice '';
    raise notice '         >>> APPLY migrations/047. It adds a queue route';
    raise notice '         >>> that needs no extension, so the refusal is';
    raise notice '         >>> recorded a few seconds late instead of never.';
    raise notice '         >>> Without 047 this is SILENT - see migration 032.';
    return;
  end;

  -- ⚠️ Counted in a SEPARATE statement. The point of dblink here is that it
  -- commits on its own connection, so the row must be visible even though
  -- this transaction has not committed. If the count does not move, dblink
  -- "worked" but did not do the one thing it is used for.
  select count(*) into after_n from public.audit_logs
   where action = 'SUPABASE READINESS PROBE';

  if after_n > before_n then
    raise notice 'PASS  3. dblink wrote an autonomous row (% -> %)',
      before_n, after_n;
    -- ⚠️ The probe row STAYS. `audit_logs` is append-only by trigger
    -- (postgres/53) and a DELETE here raises, which aborted this whole
    -- block on the first run of this script. That rule is correct -- an
    -- audit trail nobody can edit is the point -- so the probe leaves its
    -- mark and says so rather than fighting it.
    raise notice '         one probe row left behind (audit_logs is';
    raise notice '         append-only by design - postgres/53)';
  else
    raise notice 'FAIL  3. dblink connected but the row is not visible.';
    raise notice '         The write was not autonomous; 032 will log nothing.';
  end if;
end $dblink$;

-- ── 3b. Is the fallback route in place? ────────────────────────────────────
--
-- ⚠️ This is what makes a dblink failure survivable. Without 047 a
-- refusal on a host where dblink cannot connect is dropped silently.
do $fallback$
begin
  if to_regclass('public.refused_sign_in_pending') is null then
    raise notice 'FAIL  3b. migrations/047 is NOT applied.';
    raise notice '          If check 3 warned, refusals are being LOST.';
  else
    raise notice 'PASS  3b. the queue fallback exists (047 applied)';
    if (select count(*) from public.refused_sign_in_pending
         where flushed_at is null) > 0 then
      raise notice '          % refusal(s) waiting to be drained',
        (select count(*) from public.refused_sign_in_pending
          where flushed_at is null);
    end if;
  end if;
end $fallback$;

-- ── 4. The schema the app expects ──────────────────────────────────────────
do $schema$
declare
  n_policies int;
  n_tables   int;
  n_defs     int;
  n          int;
begin
  raise notice '';
  select count(*) into n_policies from pg_policies where schemaname = 'public';
  select count(*) into n_tables from information_schema.tables
   where table_schema = 'public' and table_type = 'BASE TABLE';
  select count(*) into n_defs from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prosecdef;

  raise notice 'INFO  4. % tables, % RLS policies, % SECURITY DEFINER functions',
    n_tables, n_policies, n_defs;

  if n_policies = 0 then
    raise notice 'WARN  4. No policies yet - load the schema before judging 1.';
  end if;

  -- Any public table with RLS switched OFF is a hole, whatever the policies
  -- on its neighbours say.
  select count(*) into n from pg_tables t
    join pg_class c on c.relname = t.tablename
    join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = 'public'
   where t.schemaname = 'public' and not c.relrowsecurity;
  if n > 0 then
    raise notice 'WARN  4. % public table(s) have RLS DISABLED', n;
  end if;
exception when others then
  raise notice 'INFO  4. schema not loaded yet (%)', sqlerrm;
end $schema$;

-- ── 5. Connection budget ───────────────────────────────────────────────────
do $conns$
declare
  cap   int;
  used  int;
begin
  raise notice '';
  select setting::int into cap from pg_settings where name = 'max_connections';
  select count(*) into used from pg_stat_activity;
  raise notice 'INFO  5. % of % connections in use', used, cap;
  raise notice '         At PG_POOL_SIZE=1 each officer holds 2.';
  raise notice '         9 officers = 18. Raise the pool only with the plan.';
  raise notice '';
  raise notice '=== END =================================================';
  raise notice '';
end $conns$;

-- ============================================================================
--  IF CHECK 3 FAILED
--
--  Migration 032 needs an autonomous write: the refusal rolls its own
--  transaction back, so an ordinary insert disappears with it. dblink gives
--  a separate connection that commits on its own.
--
--  Two ways forward on Supabase, in order of preference:
--
--  1. GIVE THE dblink CALL A PASSWORD. Replace the connection string in
--     `public.log_refused_device` with one that authenticates, e.g. read
--     from a setting so the password is not in the function body:
--
--         perform dblink_exec(
--           format('host=127.0.0.1 port=5432 dbname=%s user=%s password=%s',
--                  current_database(), current_user,
--                  current_setting('app.selflink_password', true)),
--           v_sql);
--
--     ⚠️ The password then lives in the database's settings. That is a real
--     trade: it is readable by anything that can already run SQL as this
--     user, which on Supabase is the same account the app uses.
--
--  2. DROP THE AUTONOMY AND LOG FROM THE APP INSTEAD. The refusal is already
--     returned to the client; the client can write the audit row on its own
--     connection, where nothing is rolling back. Slower to implement, but no
--     stored password and no dblink.
--
--  ⚠️ What must NOT happen is leaving it failing. The handler in 032 is
--  `exception when others then null`, so a broken dblink looks exactly like
--  a working one until somebody asks who tried to sign in.
-- ============================================================================
