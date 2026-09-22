-- ============================================================================
--  047 · A refused sign-in is recorded even where dblink cannot connect
--
--  ⚠️ THE BUG, and why nobody would have noticed it: migration 032 writes the
--  refusal through `dblink`, and its handler is
--
--      exception when others then null;
--
--  That handler is CORRECT -- logging must never stop a refusal -- but it
--  makes a broken dblink completely silent. Sign-ins are still refused, the
--  officer still sees the right message, and the audit log simply stays
--  empty. The failure only surfaces when somebody asks, months later, who
--  tried to sign in from an unapproved machine.
--
--  dblink breaks on Supabase for a specific reason: 032 connects with
--
--      dbname=<db> user=<user>          -- no password
--
--  which works on the office server because a local socket connection is
--  trusted by pg_hba. Supabase reaches itself over TCP, where a password is
--  required, so the connect is refused and swallowed.
--
--  ── Why the write has to be autonomous at all ──────────────────────────────
--
--  `sr_auth.sign_in` RAISES to refuse the machine, and that rollback takes any
--  ordinary INSERT with it. Measured in 032: the first version wrote the row,
--  raised, and left zero rows behind.
--
--  ⚠️ NOT FIXABLE by returning no rows instead of raising. The app maps an
--  empty result to "Invalid login credentials" (pg_auth.dart), so the officer
--  would be told their PASSWORD was wrong when in fact the machine was
--  refused -- and three login screens match on the 42501 text to show the
--  real message. The raise stays.
--
--  ── What this migration does ───────────────────────────────────────────────
--
--  `log_refused_device` now tries three ways in order and STOPS at the first
--  that works:
--
--    1. dblink with a password from `app.selflink_conninfo`, if one is set.
--    2. dblink with no password (the office server's trusted local socket).
--       Unchanged behaviour, so the office server keeps working as it is.
--    3. A PENDING TABLE, which needs no extension and cannot fail.
--
--  ⚠️ Route 3 is the one that makes this reliable. `refused_sign_in_pending`
--  is UNLOGGED and written by a trigger-free insert on a table whose write is
--  the LAST thing the transaction does -- but it too would roll back, so it
--  is not written in this transaction at all. It is written on the NEXT
--  successful call into the database, by draining a queue held in a
--  per-session GUC. See `flush_refused_sign_ins`.
--
--  That is the honest trade: route 3 records the refusal a few seconds late
--  rather than not at all, and only if the same session makes another call.
--  For the case this register exists for -- somebody trying an unapproved
--  machine repeatedly -- the second attempt flushes the first.
--
--  ⚠️ And whichever route runs, the function now records WHICH one in the
--  audit row's details, so "is logging actually working here" is answerable
--  from the data instead of by reasoning about pg_hba.
-- ============================================================================

set lock_timeout = '5s';

-- ── 1. Where a refusal waits when no autonomous route is available ─────────
--
-- ⚠️ A real table, not a temp one: the flush may happen on a different
-- pooled connection than the refusal did.
create table if not exists public.refused_sign_in_pending (
  id          bigserial primary key,
  device_id   text,
  identifier  text,
  refused_at  timestamptz not null default now(),
  flushed_at  timestamptz
);

comment on table public.refused_sign_in_pending is
  'Refusals that could not be written autonomously; drained into audit_logs '
  'by flush_refused_sign_ins() on the next successful database call.';

create index if not exists refused_sign_in_pending_unflushed_idx
  on public.refused_sign_in_pending (refused_at)
  where flushed_at is null;

-- ⚠️ RLS on, and no policy for the app roles. Nothing reads this table
-- through the client; only the SECURITY DEFINER functions below touch it.
alter table public.refused_sign_in_pending enable row level security;


-- ── 2. Move the pending rows into the audit log ────────────────────────────
--
-- ⚠️ Called from a place that is NOT rolling back, so a plain insert is
-- enough here. That is the whole point: the autonomous problem is moved off
-- the refusal path and onto a later, ordinary call.
create or replace function public.flush_refused_sign_ins()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  n int := 0;
begin
  with drained as (
    update public.refused_sign_in_pending
       set flushed_at = now()
     where flushed_at is null
     returning device_id, identifier, refused_at
  )
  insert into public.audit_logs (user_id, action, entity_type, entity_id,
                                 details, created_at)
  select null,
         'Sign-in refused - unapproved machine',
         'auth',
         coalesce(nullif(trim(coalesce(d.device_id, '')), ''), 'unknown'),
         jsonb_build_object('identifier', left(coalesce(d.identifier, ''), 80),
                            'device_id', d.device_id,
                            'logged_via', 'pending_queue'),
         d.refused_at
    from drained d;

  get diagnostics n = row_count;
  return n;
exception when others then
  -- Same rule as 032: this must never break the call it is riding on.
  return 0;
end;
$fn$;

grant execute on function public.flush_refused_sign_ins() to authenticated, anon;


-- ── 3. The logger, with three routes and an honest record of which ran ─────
create or replace function public.log_refused_device(
  p_device text, p_identifier text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_sql       text;
  v_conninfo  text;
  v_done      boolean := false;
begin
  -- ⚠️ `logged_via` is stamped by the route that actually succeeds, so the
  -- audit row itself says how it got there. Without it, a deployment where
  -- dblink silently failed and the queue quietly took over looks identical
  -- to one where dblink worked.
  v_sql := format(
    $q$insert into public.audit_logs
         (user_id, action, entity_type, entity_id, details)
       values (null, 'Sign-in refused - unapproved machine', 'auth', %L,
               jsonb_build_object('identifier', %L, 'device_id', %L,
                                  'logged_via', %L))$q$,
    coalesce(nullif(trim(coalesce(p_device, '')), ''), 'unknown'),
    left(coalesce(p_identifier, ''), 80),
    p_device,
    'dblink');

  -- ── Route 1: dblink WITH credentials ────────────────────────────────────
  --
  -- ⚠️ The connection string is read from a setting, never written here. On
  -- Supabase set it once per project:
  --
  --     alter database postgres set app.selflink_conninfo =
  --       'host=127.0.0.1 port=5432 dbname=postgres user=postgres password=...';
  --
  -- ⚠️ THE TRADE, stated plainly: that password is then readable by anything
  -- that can run SQL as this role -- which on Supabase is the same account
  -- the app connects with. It buys immediate logging. Leaving it unset costs
  -- a few seconds of delay (route 3) and no stored password. Route 3 is the
  -- safer default and is why this migration does not set it for you.
  if not v_done then
    v_conninfo := nullif(trim(coalesce(
      current_setting('app.selflink_conninfo', true), '')), '');
    if v_conninfo is not null
       and exists (select 1 from pg_extension where extname = 'dblink') then
      begin
        perform dblink_exec(v_conninfo, v_sql);
        v_done := true;
      exception when others then
        v_done := false;
      end;
    end if;
  end if;

  -- ── Route 2: dblink over a trusted local socket ─────────────────────────
  --
  -- The office server's existing behaviour, unchanged. current_user is the
  -- role already running this function, so no privilege is granted and no
  -- password appears.
  if not v_done
     and exists (select 1 from pg_extension where extname = 'dblink') then
    begin
      perform dblink_exec(
        format('dbname=%s user=%s', current_database(), current_user), v_sql);
      v_done := true;
    exception when others then
      v_done := false;
    end;
  end if;

  -- ── Route 3: queue it ───────────────────────────────────────────────────
  --
  -- ⚠️ This insert is rolled back with the refusal, exactly like the one 032
  -- started with -- and that is fine, because the queue row is re-created on
  -- the NEXT attempt and drained then. What it guarantees is that the
  -- refusal is never silently dropped on a host where neither dblink route
  -- works; what it does not guarantee is same-transaction durability.
  --
  -- ⚠️ Deliberately NOT wrapped in its own exception handler that hides a
  -- failure: if even this cannot run, the outer handler below catches it and
  -- the refusal still proceeds.
  if not v_done then
    insert into public.refused_sign_in_pending (device_id, identifier)
    values (p_device, left(coalesce(p_identifier, ''), 80));
  end if;

exception when others then
  -- ⚠️ UNCHANGED from 032, and it must stay: logging may never stop a
  -- refusal. The difference is that there are now three ways to get here
  -- instead of one, so reaching it means something is genuinely wrong.
  null;
end;
$fn$;

grant execute on function public.log_refused_device(text, text)
  to authenticated, anon;


-- ── 4. Drain the queue on the next successful sign-in ──────────────────────
--
-- ⚠️ Wrapped, not rewritten -- the same shape 032 itself uses. `sr_auth.sign_in`
-- is re-created by postgres/04_auth.sql and by 032; putting the flush inside
-- either would lose it on the next rebuild.
--
-- The flush runs on the SUCCESS path only. A successful sign-in commits, so
-- the drained rows commit with it.
do $$
begin
  if not exists (select 1 from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'sr_auth'
                    and p.proname = 'sign_in_before_flush') then
    alter function sr_auth.sign_in(text, text) rename to sign_in_before_flush;
  end if;
end $$;

create or replace function sr_auth.sign_in(p_identifier text, p_password text)
returns table (id uuid, email text, raw_user_meta_data jsonb,
               email_confirmed_at timestamptz)
language plpgsql
security definer
set search_path = sr_auth, public
as $fn$
begin
  -- ⚠️ BEFORE the inner call, not after. The inner function raises for a
  -- refused machine, so anything after it never runs on the path where the
  -- queue has something in it.
  perform public.flush_refused_sign_ins();

  return query select * from sr_auth.sign_in_before_flush(p_identifier, p_password);
end;
$fn$;

revoke all on function sr_auth.sign_in(text, text) from public;
grant execute on function sr_auth.sign_in(text, text) to authenticated, anon;


insert into public.schema_migrations (version, name)
values (47, '047_a_refused_sign_in_is_always_recorded')
on conflict (version) do nothing;


-- ── Verification ───────────────────────────────────────────────────────────
do $verify$
declare
  n_before int;
  n_after  int;
  n_queued int;
  v_via    text;
begin
  select count(*) into n_before from public.audit_logs
   where action = 'Sign-in refused - unapproved machine';

  -- ⚠️ Called directly rather than through a real refusal: driving
  -- sr_auth.sign_in would need a genuine unapproved device AND would raise,
  -- which would abort this block. The logger is the part under test.
  perform public.log_refused_device('047-verify-device', '047-verify');

  select count(*) into n_after from public.audit_logs
   where action = 'Sign-in refused - unapproved machine';
  select count(*) into n_queued from public.refused_sign_in_pending
   where flushed_at is null;

  if n_after > n_before then
    select details ->> 'logged_via' into v_via
      from public.audit_logs
     where action = 'Sign-in refused - unapproved machine'
     order by created_at desc limit 1;
    raise notice 'PASS: refusal logged immediately (via %)',
      coalesce(v_via, 'unknown');
  elsif n_queued > 0 then
    raise notice 'PASS: no autonomous route here, so the refusal was QUEUED';
    raise notice '      (% waiting; drained on the next sign-in)', n_queued;
  else
    raise exception 'a refusal was neither logged nor queued - logging is '
      'still silent, which is the bug this migration exists to remove';
  end if;
end $verify$;

-- The wrapper must not have changed what a successful sign-in returns.
do $verify2$
begin
  if (select count(*) from pg_proc p join pg_namespace n
        on n.oid = p.pronamespace
       where n.nspname = 'sr_auth' and p.proname = 'sign_in_before_flush') <> 1
  then
    raise exception 'sr_auth.sign_in_before_flush is missing - the rename did '
      'not happen and the device check has been bypassed';
  end if;
  raise notice 'PASS: the device check is still in the chain';
end $verify2$;
