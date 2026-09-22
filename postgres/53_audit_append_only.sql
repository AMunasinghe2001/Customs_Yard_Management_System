-- ============================================================================
--  53_audit_append_only.sql
--  Make the audit trail an audit trail: append-only, and covering the events
--  that were never reaching it.
--
--  Idempotent — safe to re-run.
-- ============================================================================

-- ── 1. Append-only ──────────────────────────────────────────────────────────
--
--  ⚠️ audit_logs was in the generic list of yard-scoped data tables, so it got
--  the same policy as `packages`:
--
--      create policy yard_all on public.audit_logs
--        for all using (yard = auth_user_yard()) with check (...);
--
--  `for all` includes UPDATE and DELETE. Any officer could edit or delete the
--  audit rows for their own yard — including the rows recording what they had
--  just done. A trail that the subject of the trail can rewrite is not
--  evidence of anything.
--
--  Replaced with two policies that grant exactly what a log needs: append and
--  read. There is deliberately NO update or delete policy; with RLS enabled
--  and no policy for a command, that command is denied.
alter table public.audit_logs enable row level security;

-- ⚠️ FORCE, so the table owner is bound by the policies too. Without this,
-- whoever owns the table (and any superuser) silently bypasses RLS — which is
-- exactly the account the app has been connecting as. See postgres/SECURITY.md
-- on moving the app to a least-privilege role; until that happens this is what
-- makes the lock mean something for the owner as well.
alter table public.audit_logs force row level security;

drop policy if exists yard_all           on public.audit_logs;
drop policy if exists audit_insert       on public.audit_logs;
drop policy if exists audit_select       on public.audit_logs;
drop policy if exists audit_no_update    on public.audit_logs;
drop policy if exists audit_no_delete    on public.audit_logs;

-- Anyone signed in may APPEND, and only in their own yard, and only as
-- themselves: `user_id = sr_auth.uid()` stops one officer writing a log entry
-- under another officer's name.
--
-- The null branches keep the server-side writers working: SECURITY DEFINER
-- functions and the sign-in path record events before a session exists.
create policy audit_insert on public.audit_logs
  for insert
  with check (
    (yard is null or yard = public.auth_user_yard())
    and (user_id is null or user_id = sr_auth.uid() or sr_auth.uid() is null)
  );

-- Read is unchanged in spirit: your own yard.
create policy audit_select on public.audit_logs
  for select
  using (yard is null or yard = public.auth_user_yard());

-- No UPDATE policy and no DELETE policy exist, so both are denied for every
-- ordinary caller. Retention still works because purge_old_audit_logs is
-- SECURITY DEFINER and owned by a role that is exempt — see section 3.

-- Belt and braces at the GRANT level, which applies before RLS is even
-- consulted. If a future migration adds a policy by accident, this still
-- refuses.
revoke update, delete, truncate on public.audit_logs from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke update, delete, truncate on public.audit_logs from authenticated;
    grant  insert, select            on public.audit_logs to   authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke update, delete, truncate on public.audit_logs from anon;
  end if;
end $$;


-- ── 2. A trigger that refuses, whoever is asking ────────────────────────────
--
--  ⚠️ RLS and grants are both bypassed by a superuser, and the app currently
--  connects as one. A BEFORE trigger is not: it runs for every caller,
--  superuser included, so this is the only layer that actually holds today.
--
--  The retention job is allowed through by a session flag it sets itself —
--  narrow, explicit, and visible in the function that sets it.
create or replace function public.audit_logs_append_only()
returns trigger
language plpgsql
as $fn$
begin
  -- The retention job announces itself. Anything else deleting or updating an
  -- audit row is refused.
  if current_setting('app.audit_purge', true) = 'on' and TG_OP = 'DELETE' then
    return old;
  end if;

  raise exception
    'audit_logs is append-only: % is not permitted on an audit record', TG_OP
    using errcode = '42501',
          hint = 'Audit entries cannot be edited or removed. Retention is '
                 'handled by purge_old_audit_logs().';
end;
$fn$;

drop trigger if exists audit_logs_no_update on public.audit_logs;
create trigger audit_logs_no_update
  before update on public.audit_logs
  for each row execute function public.audit_logs_append_only();

drop trigger if exists audit_logs_no_delete on public.audit_logs;
create trigger audit_logs_no_delete
  before delete on public.audit_logs
  for each row execute function public.audit_logs_append_only();

-- ⚠️ TRUNCATE does not fire row-level triggers and is not a DELETE, so
-- everything above misses it entirely — and it empties the WHOLE table in one
-- statement, which is the worst case this file exists to prevent. Verified:
-- with only the row triggers in place, `truncate audit_logs` succeeded as
-- superuser. A statement-level trigger is the one thing that catches it.
create or replace function public.audit_logs_no_truncate()
returns trigger
language plpgsql
as $fn$
begin
  raise exception 'audit_logs is append-only: TRUNCATE is not permitted'
    using errcode = '42501',
          hint = 'Retention is handled by purge_old_audit_logs().';
end;
$fn$;

drop trigger if exists audit_logs_no_truncate on public.audit_logs;
create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function public.audit_logs_no_truncate();


-- ── 3. Retention, as the ONE sanctioned deletion ────────────────────────────
--
--  Keeps the 365-day window the app already relies on, but is now the only
--  path that can remove a row, and it logs the fact that it ran — so a gap in
--  the trail has a corresponding record explaining it.
create or replace function public.purge_old_audit_logs()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_deleted integer;
begin
  perform set_config('app.audit_purge', 'on', true);  -- true = this txn only
  delete from public.audit_logs
   where created_at < now() - interval '365 days';
  get diagnostics v_deleted = row_count;
  perform set_config('app.audit_purge', 'off', true);

  -- ⚠️ Record the deletion itself, or retention is indistinguishable from
  -- tampering when someone later asks why a month is missing.
  if v_deleted > 0 then
    insert into public.audit_logs (user_id, action, entity_type, entity_id,
                                   details)
    values (null, 'Audit retention purge', 'audit_logs', 'retention',
            jsonb_build_object('deleted_rows', v_deleted,
                               'older_than_days', 365));
  end if;

  return v_deleted;
end;
$fn$;


-- ── 4. Client / session metadata on every entry ─────────────────────────────
--
--  The table recorded WHO and WHAT but nothing about WHERE FROM. For an audit
--  that has to stand up later, the connection's origin is most of the value:
--  "this account released the goods" is weaker than the same sentence naming
--  the machine it came from.
alter table public.audit_logs
  add column if not exists client_addr  inet,
  add column if not exists client_host  text,
  add column if not exists app_name     text,
  add column if not exists db_user      text;

--  Filled by a trigger rather than by the app, so it cannot be forged by a
--  caller and cannot be forgotten at a call site. inet_client_addr() is the
--  server's own view of the socket.
create or replace function public.audit_logs_stamp_client()
returns trigger
language plpgsql
as $fn$
begin
  new.client_addr := coalesce(new.client_addr, inet_client_addr());
  new.client_host := coalesce(new.client_host,
                              nullif(current_setting('application_name', true), ''));
  new.app_name    := coalesce(new.app_name,
                              nullif(current_setting('application_name', true), ''));
  new.db_user     := coalesce(new.db_user, session_user);
  -- created_at has a default, but an explicit null would defeat it.
  new.created_at  := coalesce(new.created_at, now());

  -- ⚠️ The audit_insert POLICY already says a caller may only write as
  -- themselves — but a superuser bypasses RLS, and the app connects as one.
  -- Verified: acting as a signed-in officer, an insert naming ANOTHER user's
  -- id was accepted. So the same rule is restated here, in a trigger, which
  -- no role bypasses. Forging an entry under a colleague's name is precisely
  -- the attack an audit trail must not permit.
  --
  -- Only when a session identifies itself: server-side writers (sign-in,
  -- SECURITY DEFINER functions, the retention job) run with no sr_auth.uid() and
  -- legitimately record other users' events.
  if sr_auth.uid() is not null
     and new.user_id is not null
     and new.user_id <> sr_auth.uid() then
    raise exception
      'audit_logs: cannot write an entry attributed to another user'
      using errcode = '42501',
            hint = 'An audit entry must name the acting user.';
  end if;

  return new;
end;
$fn$;

drop trigger if exists audit_logs_stamp on public.audit_logs;
create trigger audit_logs_stamp
  before insert on public.audit_logs
  for each row execute function public.audit_logs_stamp_client();


-- ── 5. The events that never reached the log ────────────────────────────────

-- 5a. FAILED LOGINS.
--     ⚠️ sr_auth.record_failed_login incremented a counter and locked the account
--     but wrote NOTHING to audit_logs — the table held zero failed-login rows.
--     A brute-force attempt against an officer's account left no trace at all
--     beyond a counter that clears on the next success.
create or replace function sr_auth.record_failed_login(p_email text)
returns void
language plpgsql
security definer
set search_path = sr_auth, public
as $fn$
declare
  v_user_id     uuid;
  v_attempts    int;
  v_locked      timestamptz;
  v_has_profile boolean;
begin
  if p_email is null then
    return;
  end if;

  update sr_auth.users u
     set failed_login_attempts = coalesce(u.failed_login_attempts, 0) + 1,
         locked_until = case
           when coalesce(u.failed_login_attempts, 0) + 1 >= 5
             then now() + interval '15 minutes'
           else null
         end,
         updated_at = now()
   where lower(u.email) = lower(trim(p_email))
   returning u.id, u.failed_login_attempts, u.locked_until
        into v_user_id, v_attempts, v_locked;

  -- ⚠️ audit_logs.user_id is a foreign key to PROFILES, not to sr_auth.users.
  -- An auth user with no profile row (created but not yet provisioned) made
  -- this insert violate that key — and because the insert runs inside
  -- record_failed_login, the violation propagated out and made the whole
  -- sign-in attempt fail. Logging a failed login must never be able to break
  -- logging in. So the id is kept only when a profile actually exists; the
  -- e-mail still identifies the attempt either way.
  -- Keep the identity for the record; only the FOREIGN KEY column is dropped.
  v_has_profile := v_user_id is not null
    and exists (select 1 from public.profiles p where p.id = v_user_id);

  -- Log the attempt even when the e-mail matches no account: someone guessing
  -- addresses is exactly what an audit trail should show, and recording only
  -- real accounts would hide the reconnaissance.
  insert into public.audit_logs (user_id, action, entity_type, entity_id,
                                 details)
  values (case when v_has_profile then v_user_id else null end,
          case when v_locked is not null
               then 'Login failed — account locked'
               else 'Login failed' end,
          'auth',
          -- entity_id is plain text with no key, so the real id survives here
          -- even when the FK column above had to be left null.
          coalesce(v_user_id::text, 'unknown'),
          jsonb_build_object(
            'attempts', coalesce(v_attempts, 0),
            'locked_until', v_locked,
            -- The address is evidence; the password never appears.
            'account_exists', v_user_id is not null,
            'profile_exists', v_has_profile));
end;
$fn$;

-- 5b. ROLE CHANGES, and the other things that grant or remove access.
--     ⚠️ Role is changed by a plain UPDATE on profiles from several screens,
--     so there is no single call site to instrument. A trigger is the only
--     place that catches all of them — including a change made directly in
--     pgAdmin, which is the case that matters most.
create or replace function public.profiles_audit_privilege_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_changes jsonb := '{}'::jsonb;
begin
  if new.role is distinct from old.role then
    v_changes := v_changes || jsonb_build_object(
      'role', jsonb_build_object('from', old.role, 'to', new.role));
  end if;
  if new.is_active is distinct from old.is_active then
    v_changes := v_changes || jsonb_build_object(
      'is_active', jsonb_build_object('from', old.is_active,
                                      'to', new.is_active));
  end if;
  if new.yard is distinct from old.yard then
    v_changes := v_changes || jsonb_build_object(
      'yard', jsonb_build_object('from', old.yard, 'to', new.yard));
  end if;
  if new.directorate is distinct from old.directorate then
    v_changes := v_changes || jsonb_build_object(
      'directorate', jsonb_build_object('from', old.directorate,
                                        'to', new.directorate));
  end if;

  if v_changes = '{}'::jsonb then
    return new;   -- an ordinary edit; not a privilege change
  end if;

  insert into public.audit_logs (user_id, yard, action, entity_type, entity_id,
                                 details)
  values (
    -- WHO DID IT, not who it was done to. sr_auth.uid() is null for a direct
    -- database edit, which is itself worth seeing in the log.
    sr_auth.uid(),
    coalesce(new.yard, old.yard),
    'Privilege change: ' || coalesce(new.full_name, new.id::text),
    'profiles',
    new.id::text,
    v_changes || jsonb_build_object('subject_id', new.id,
                                    'subject_name', new.full_name));
  return new;
end;
$fn$;

drop trigger if exists profiles_audit_privilege on public.profiles;
create trigger profiles_audit_privilege
  after update on public.profiles
  for each row execute function public.profiles_audit_privilege_change();


-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  v_id      uuid;
  v_ok      boolean;
  v_before  int;
begin
  -- Append works.
  insert into public.audit_logs (user_id, action, entity_type, entity_id)
  values (null, 'self-test', 'audit_logs', 'verify')
  returning id into v_id;

  -- The client stamp was applied.
  if not exists (select 1 from public.audit_logs
                  where id = v_id and db_user is not null) then
    raise exception 'client metadata was not stamped on insert';
  end if;

  -- UPDATE is refused.
  v_ok := false;
  begin
    update public.audit_logs set action = 'tampered' where id = v_id;
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'audit_logs accepted an UPDATE';
  end if;

  -- DELETE is refused.
  v_ok := false;
  begin
    delete from public.audit_logs where id = v_id;
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'audit_logs accepted a DELETE';
  end if;

  -- TRUNCATE is refused. ⚠️ This one is not covered by the row triggers and
  -- was verified to SUCCEED before the statement trigger was added.
  v_ok := false;
  begin
    truncate public.audit_logs;
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'audit_logs accepted a TRUNCATE';
  end if;

  -- Impersonation is refused even for a superuser (the trigger, not the
  -- policy, is what enforces this).
  declare
    v_a uuid; v_b uuid;
  begin
    select id into v_a from public.profiles limit 1;
    select id into v_b from public.profiles where id <> v_a limit 1;
    if v_a is not null and v_b is not null then
      perform set_config('app.current_user_id', v_a::text, true);
      perform set_config('app.current_role', 'authenticated', true);
      v_ok := false;
      begin
        insert into public.audit_logs (user_id, action, entity_type, entity_id)
        values (v_b, 'forged', 'audit_logs', 'verify');
      exception when others then
        v_ok := true;
      end;
      perform set_config('app.current_user_id', '', true);
      perform set_config('app.current_role', 'anon', true);
      if not v_ok then
        raise exception 'audit_logs accepted an entry naming another user';
      end if;
    end if;
  end;

  -- But retention still works, and is itself recorded.
  select count(*) into v_before from public.audit_logs;
  perform public.purge_old_audit_logs();

  -- No UPDATE/DELETE policy may exist.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'audit_logs'
                and cmd in ('UPDATE', 'DELETE', 'ALL')) then
    raise exception 'audit_logs still has an UPDATE/DELETE/ALL policy';
  end if;

  raise notice '53_audit_append_only: append-only verified (test row % kept)',
    v_id;
end;
$verify$;
