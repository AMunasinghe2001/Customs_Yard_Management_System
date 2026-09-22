-- ============================================================================
--  An account nobody has signed into for 90 days is disabled.
--
--  A leaver's account stays valid indefinitely today: the password rotates on
--  a schedule nobody follows once they have gone, and `is_active` is only ever
--  changed by hand. An account that no one is watching is the one worth
--  stealing, so the rule is time-based and automatic.
--
--  ⚠️ It flips the EXISTING `is_active` flag rather than adding a second kind
--  of disabled. Every sign-in path already refuses an inactive profile
--  (sr_auth.sign_in's callers, and four checks in services.dart), and ICT's
--  Staff Register already has the button that turns it back on — so
--  reactivation works on day one and there is one answer to "can this account
--  sign in", not two that can disagree.
--
--  90 days, matching the password rotation: an officer who has not signed in
--  for that long would have been stopped at the password gate anyway.
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. Why an account was disabled ──────────────────────────────────────────
--
-- Without this, a dormancy switch-off is indistinguishable from ICT
-- deactivating someone deliberately, and the next admin to look has no way to
-- tell whether turning it back on undoes a decision or just wakes an account.
alter table public.profiles
  add column if not exists deactivated_reason text,
  add column if not exists deactivated_at     timestamptz;

comment on column public.profiles.deactivated_reason is
  'Why is_active went false: ''dormant'' (automatic, 90 days unused) or '
  '''manual'' (ICT). Null while the account is active.';


-- ── 2. The cutoff, in one place ─────────────────────────────────────────────
create or replace function public.account_dormant_after_days()
returns integer language sql immutable as $fn$ select 90 $fn$;

comment on function public.account_dormant_after_days() is
  'Days of no sign-in before an account is disabled. Matches the 90-day '
  'password rotation.';


-- ── 3. Has this account gone quiet? ─────────────────────────────────────────
--
-- ⚠️ `last_seen_at` can be NULL — an account provisioned but never used. That
-- is dormancy too, so it counts from `created_at` instead. Reading NULL as
-- "never dormant" would have left exactly the unused accounts this is for.
create or replace function public.account_is_dormant(p_id uuid)
returns boolean
language sql
stable
as $fn$
  select coalesce(p.last_seen_at, p.created_at)
           < now() - make_interval(days => public.account_dormant_after_days())
    from public.profiles p
   where p.id = p_id;
$fn$;


-- ── 4. Disable the ones that have ───────────────────────────────────────────
--
-- Called from the sign-in path (below) and safe to call on a schedule.
create or replace function public.disable_dormant_accounts()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_count integer;
begin
  with disabled as (
    update public.profiles p
       set is_active = false,
           deactivated_reason = 'dormant',
           deactivated_at = now(),
           updated_at = now()
     where p.is_active
       and coalesce(p.last_seen_at, p.created_at)
             < now() - make_interval(days => public.account_dormant_after_days())
    returning 1
  )
  select count(*) into v_count from disabled;
  return v_count;
end;
$fn$;

comment on function public.disable_dormant_accounts() is
  'Sets is_active=false on every account unused for the dormancy period. '
  'Returns how many were disabled. Idempotent.';


-- ── 5. Reactivation is ICT's alone ──────────────────────────────────────────
--
-- ⚠️ The point of the rule. A dormant account that its own holder could wake
-- by signing in would be no protection at all — whoever holds the credentials
-- is exactly who we are unsure about. Only ICT can clear it, and clearing it
-- also clears the reason so the account starts fresh.
create or replace function public.reactivate_account(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  if not public.auth_user_is_ict() then
    raise exception 'Only the ICT Directorate can reactivate an account'
      using errcode = 'insufficient_privilege';
  end if;

  update public.profiles
     set is_active = true,
         deactivated_reason = null,
         deactivated_at = null,
         -- ⚠️ Reset the clock. Without this the account is dormant the moment
         -- it is woken -- last_seen_at is still 90 days old -- and the next
         -- sweep turns it straight back off.
         last_seen_at = now(),
         updated_at = now()
   where id = p_id;
end;
$fn$;

revoke all on function public.reactivate_account(uuid) from public;
grant execute on function public.reactivate_account(uuid) to authenticated;


-- ── 6. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_id uuid;
  v_active boolean;
  v_reason text;
begin
  select id into v_id from public.profiles where is_active limit 1;
  if v_id is null then
    raise notice 'no active profile to test with - skipping';
    return;
  end if;

  -- A freshly-seen account is NOT dormant.
  update public.profiles set last_seen_at = now() where id = v_id;
  if public.account_is_dormant(v_id) then
    raise exception 'an account seen just now reads as dormant';
  end if;

  -- Pushed past the cutoff, it is -- and the sweep disables it.
  update public.profiles
     set last_seen_at = now() - interval '91 days' where id = v_id;
  if not public.account_is_dormant(v_id) then
    raise exception 'an account unused for 91 days does not read as dormant';
  end if;

  perform public.disable_dormant_accounts();
  select is_active, deactivated_reason into v_active, v_reason
    from public.profiles where id = v_id;
  if v_active then
    raise exception 'the sweep did not disable a dormant account';
  end if;
  if v_reason is distinct from 'dormant' then
    raise exception 'the sweep did not record WHY (got %)', v_reason;
  end if;

  -- Put it back exactly as it was: this runs against live data.
  update public.profiles
     set is_active = true, deactivated_reason = null, deactivated_at = null,
         last_seen_at = now()
   where id = v_id;
  raise notice 'dormancy rule verified on % (restored)', v_id;
end $$;


-- ── 7. The sweep runs on sign-in ────────────────────────────────────────────
--
-- ⚠️ Server-side, inside sr_auth.sign_in, and NOT in the Dart client. A rule
-- enforced by the app is a rule that holds only for people using the app:
-- anyone with the database credentials would be exempt, which is backwards
-- for a control whose whole purpose is accounts nobody is watching. It also
-- means no scheduler has to exist for the rule to work -- pg_cron is not
-- installed here, and a rule that depends on an absent extension is a rule
-- that silently never runs.
--
-- ⚠️ Runs BEFORE the password is checked, so a dormant account is already
-- disabled by the time the caller reads the profile and finds is_active
-- false. Running it after would let the first sign-in through.
create or replace function sr_auth.sign_in(
  p_identifier text,
  p_password   text
)
-- ⚠️ `raw_user_meta_data`, not `meta`: migrations 032 and 047 wrap this
-- function later and name it that way, and PostgreSQL refuses to change a
-- returned column NAME -- a fresh build then died with "cannot change
-- return type of existing function". The app selects
-- `raw_user_meta_data as meta` (pg_auth.dart), so this is the right name.
returns table (
  id                 uuid,
  email              text,
  raw_user_meta_data jsonb,
  email_confirmed_at timestamptz
)
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_email text;
  v_user sr_auth.users%rowtype;
begin
  if p_identifier is null or p_password is null then
    return;
  end if;

  -- Accounts that have gone quiet are switched off before anyone signs in.
  perform public.disable_dormant_accounts();

  v_email := public.email_for_login(p_identifier);
  if v_email is null then
    return;
  end if;

  select *
    into v_user
    from sr_auth.users u
   where lower(u.email) = lower(trim(v_email));

  if v_user.id is null then
    return;
  end if;

  if v_user.locked_until is not null and v_user.locked_until > now() then
    return;
  end if;

  if v_user.encrypted_password is null then
    return;
  end if;

  if v_user.encrypted_password = crypt(p_password, v_user.encrypted_password) then
    return query
    update sr_auth.users u
       set last_sign_in_at = now(),
           failed_login_attempts = 0,
           locked_until = null,
           updated_at = now()
     where u.id = v_user.id
    returning u.id, u.email, u.raw_user_meta_data, u.email_confirmed_at;
    return;
  end if;

  update sr_auth.users u
     set failed_login_attempts = coalesce(u.failed_login_attempts, 0) + 1,
         locked_until = case
           when coalesce(u.failed_login_attempts, 0) + 1 >= 5 then now() + interval '15 minutes'
           else null
         end,
         updated_at = now()
   where u.id = v_user.id;
end;
$fn$;

-- ⚠️ postgres/04_auth.sql re-creates sign_in WITHOUT the sweep. If that file
-- is ever re-applied, re-run this migration after it -- the same hazard the
-- README already records for change_password and migration 018.
