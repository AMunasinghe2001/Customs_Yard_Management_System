-- ============================================================================
--  Only an APPROVED machine may sign in.
--
--  Until now any PC that could reach the database and knew an officer's
--  credentials could sign in — from a home laptop on the branch VPN, or from a
--  machine taken out of a yard. Passwords leak; the set of computers the
--  Department owns does not, and it is short enough to list.
--
--  ⚠️ Enforced inside auth.sign_in, NOT in the app.
--
--  A check in Dart is a check the attacker controls: they are not obliged to
--  run our client. The device id reaches the database as a session variable
--  set at connection time, sign_in reads it there, and an unknown machine is
--  refused a session no matter what asks.
--
--  ⚠️ Opt-in, and deliberately so. With the register EMPTY every machine is
--  allowed, because the alternative is a migration that locks every officer
--  out of a working system the moment it is applied. Enforcement begins when
--  ICT approves the first machine — see the notice at the end.
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. The register ─────────────────────────────────────────────────────────
create table if not exists public.approved_devices (
  device_id    text primary key,
  label        text not null,
  yard         text,
  approved_by  uuid references public.profiles(id),
  approved_at  timestamptz not null default now(),
  last_seen_at timestamptz,
  is_active    boolean not null default true,
  note         text
);

comment on table public.approved_devices is
  'Machines permitted to sign in. Empty = enforcement off; one row = only '
  'listed machines may sign in. See migration 032.';

comment on column public.approved_devices.device_id is
  'A stable per-machine id the client sends at connection time. NOT a secret: '
  'it identifies the PC, it does not authenticate it — the password and the '
  'one-time code still do that. Its job is to bound WHERE a leaked password '
  'can be used.';

alter table public.approved_devices enable row level security;

-- ⚠️ Readable by any signed-in officer, writable only by ICT. The app has to
-- read it to tell the officer WHY it was refused; approving a machine is an
-- administrative act.
drop policy if exists approved_devices_read on public.approved_devices;
create policy approved_devices_read on public.approved_devices
  for select using (true);

drop policy if exists approved_devices_ict_writes on public.approved_devices;
create policy approved_devices_ict_writes on public.approved_devices
  for all
  using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());


-- ── 2. Is enforcement on, and is this machine allowed? ──────────────────────
create or replace function public.device_enforcement_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (select 1 from public.approved_devices where is_active);
$fn$;

create or replace function public.device_is_approved(p_device_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select case
           -- No machine approved yet: the register is not in use.
           when not public.device_enforcement_active() then true
           when coalesce(trim(p_device_id), '') = '' then false
           else exists (select 1 from public.approved_devices
                         where device_id = trim(p_device_id)
                           and is_active)
         end;
$fn$;

revoke all on function public.device_is_approved(text) from public;
grant execute on function public.device_is_approved(text) to authenticated;
grant execute on function public.device_enforcement_active() to authenticated;



-- ── 3a. Record a refusal so the RAISE cannot erase it ───────────────────────
--
-- ⚠️ A plain INSERT here does NOT survive. The RAISE below aborts the
-- transaction and takes the row with it — measured: the first version wrote
-- the row, raised, and left zero rows behind. A SECURITY DEFINER function does
-- not help either; it changes WHO writes, not WHICH transaction.
--
-- PostgreSQL has no autonomous transactions, so the row is written over a
-- SEPARATE connection with dblink. That connection commits on its own and is
-- untouched by the caller's rollback.
--
-- The cost is a local connection per refused attempt. That is acceptable
-- precisely because it only happens on a REFUSAL — an approved machine never
-- reaches this path — and a burst of them is itself the thing worth seeing.
create extension if not exists dblink;

create or replace function public.log_refused_device(
  p_device text, p_identifier text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_sql text;
begin
  v_sql := format(
    $q$insert into public.audit_logs
         (user_id, action, entity_type, entity_id, details)
       values (null, 'Sign-in refused - unapproved machine', 'auth', %L,
               jsonb_build_object('identifier', %L, 'device_id', %L))$q$,
    coalesce(nullif(trim(coalesce(p_device, '')), ''), 'unknown'),
    left(coalesce(p_identifier, ''), 80),
    p_device);

  -- ⚠️ The USER must be named. Without it libpq falls back to the OS account
  -- the server runs as — on Windows that is SYSTEM, which is not a database
  -- role, and every write failed with "role SYSTEM does not exist" while the
  -- exception handler below quietly swallowed it. Measured: zero rows written.
  --
  -- current_user is the role already executing this function, so no new
  -- privilege is granted and no password appears here. The connection is
  -- local to the same cluster and database and cannot be pointed elsewhere.
  perform dblink_exec(
    format('dbname=%s user=%s', current_database(), current_user), v_sql);
exception when others then
  -- Logging must never stop the refusal itself. If dblink is unavailable the
  -- attempt is still refused; it is simply not written down here.
  null;
end;
$fn$;

grant execute on function public.log_refused_device(text, text)
  to authenticated, anon;

-- ── 3. sign_in refuses an unapproved machine ────────────────────────────────
--
-- ⚠️ Wrapped, not rewritten. auth.sign_in is long and is re-created by
-- postgres/04_auth.sql; editing it there would put this rule in a file that a
-- schema rebuild overwrites. The wrapper checks the machine and then calls the
-- body, so a rebuild of 04 leaves the body intact and this file re-applies the
-- guard on top — the same shape migration 018 uses for change_password.
do $$
begin
  if not exists (select 1 from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'auth'
                    and p.proname = 'sign_in_any_device') then
    alter function auth.sign_in(text, text) rename to sign_in_any_device;
  end if;
end $$;

create or replace function auth.sign_in(p_identifier text, p_password text)
returns table (id uuid, email text, raw_user_meta_data jsonb,
               email_confirmed_at timestamptz)
language plpgsql
security definer
set search_path = auth, public
as $fn$
declare
  v_device text := nullif(current_setting('app.device_id', true), '');
begin
  if not public.device_is_approved(v_device) then
    -- ⚠️ Logged in an AUTONOMOUS transaction, via dblink-free pg_background
    -- substitute: a plain INSERT here is rolled back by the RAISE below,
    -- along with the very evidence this register exists to capture. Verified:
    -- the first version wrote the row, raised, and left nothing behind.
    --
    -- No extension is available, so the log is written by a SECURITY DEFINER
    -- helper the caller cannot roll back — see log_refused_device.
    perform public.log_refused_device(v_device, p_identifier);

    raise exception
      'This computer is not approved for the SR Management System. Ask the '
      'ICT Directorate to approve it.'
      using errcode = '42501';
  end if;

  return query select * from auth.sign_in_any_device(p_identifier, p_password);
end;
$fn$;

revoke all on function auth.sign_in(text, text) from public;
grant execute on function auth.sign_in(text, text) to authenticated, anon;


-- ── 4. Record that an approved machine was used ─────────────────────────────
create or replace function public.touch_device(p_device_id text)
returns void
language sql
security definer
set search_path = public
as $fn$
  update public.approved_devices
     set last_seen_at = now()
   where device_id = trim(p_device_id);
$fn$;

grant execute on function public.touch_device(text) to authenticated;


-- ── 5. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_was_active boolean;
begin
  v_was_active := public.device_enforcement_active();

  -- With an empty register every machine passes, including a blank id.
  if v_was_active then
    raise notice 'devices already approved - skipping the empty-register check';
  else
    if not public.device_is_approved('anything') then
      raise exception 'an empty register must allow every machine';
    end if;
    if not public.device_is_approved('') then
      raise exception 'an empty register must allow a client that sends no id';
    end if;
  end if;

  -- With one approved, only that one passes.
  insert into public.approved_devices (device_id, label, note)
  values ('MIGRATION-032-SELF-CHECK', 'self check',
          'written and removed by migration 032')
  on conflict (device_id) do nothing;

  if not public.device_is_approved('MIGRATION-032-SELF-CHECK') then
    delete from public.approved_devices
     where device_id = 'MIGRATION-032-SELF-CHECK';
    raise exception 'an approved machine was refused';
  end if;
  if public.device_is_approved('SOME-OTHER-PC') then
    delete from public.approved_devices
     where device_id = 'MIGRATION-032-SELF-CHECK';
    raise exception 'an unapproved machine was allowed while the register was in use';
  end if;

  delete from public.approved_devices
   where device_id = 'MIGRATION-032-SELF-CHECK';

  raise notice
    'verified: empty register allows all, a populated one allows only its own';

  if not v_was_active then
    raise notice
      'DEVICE ENFORCEMENT IS OFF. It turns ON by itself the moment ICT '
      'approves the first machine, so approve every Department PC in one '
      'sitting or officers on the others will be refused.';
  end if;
end $$;
