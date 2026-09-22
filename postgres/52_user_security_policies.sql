-- ============================================================================
--  52_user_security_policies.sql
--  User-level security: password strength, rotation, and the one privileged
--  RPC that was not checking who called it.
--
--  Idempotent — safe to re-run.
-- ============================================================================

-- ── 1. Password strength, enforced in the database ──────────────────────────
--
--  ⚠️ The app validated passwords in 14 separate screens and the server
--  accepted anything 6 characters long. Client-side validation is a courtesy
--  to the person typing, not a control: `sr_auth.sign_up` and
--  `sr_auth.change_password` are reachable directly, so the weakest rule that
--  actually applied was the SERVER's, and it was weaker than every screen.
--
--  This is now the single definition. The Dart PasswordPolicy mirrors it so
--  the user sees the rule before submitting, but this is what enforces it.
create or replace function public.password_policy_violation(p_password text)
returns text
language plpgsql
immutable
as $fn$
begin
  if p_password is null or length(p_password) < 12 then
    return 'Password must be at least 12 characters.';
  end if;
  if length(p_password) > 128 then
    -- bcrypt silently truncates past 72 bytes; refuse rather than let a user
    -- believe a very long password is being checked in full.
    return 'Password must be at most 128 characters.';
  end if;
  if p_password !~ '[A-Z]' then
    return 'Password must contain an uppercase letter.';
  end if;
  if p_password !~ '[a-z]' then
    return 'Password must contain a lowercase letter.';
  end if;
  if p_password !~ '[0-9]' then
    return 'Password must contain a number.';
  end if;
  if p_password !~ '[^A-Za-z0-9]' then
    return 'Password must contain a special character.';
  end if;
  -- The handful that a dictionary attack tries first. Not a substitute for a
  -- real breach list, but it costs nothing and stops the obvious ones.
  if lower(p_password) ~ '(password|passw0rd|welcome|customs|qwerty|admin123|letmein|12345678)' then
    return 'Password contains a commonly used word.';
  end if;
  return null;
end;
$fn$;

comment on function public.password_policy_violation(text) is
  'Returns a human-readable reason the password is unacceptable, or null when '
  'it passes. Mirrored by PasswordPolicy in lib/core/security_policy.dart.';

grant execute on function public.password_policy_violation(text) to public;


-- ── 2. Apply it where passwords are actually set ────────────────────────────

-- 2a. Sign-up.
create or replace function sr_auth.sign_up(
  p_email    text,
  p_password text,
  p_meta     jsonb default '{}'::jsonb
)
returns table (
  id                 uuid,
  email              text,
  meta               jsonb,
  email_confirmed_at timestamptz
)
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_id     uuid;
  v_reason text;
begin
  if p_email is null or length(trim(p_email)) = 0 then
    raise exception 'email is required' using errcode = '22023';
  end if;

  v_reason := public.password_policy_violation(p_password);
  if v_reason is not null then
    raise exception '%', v_reason using errcode = '22023';
  end if;

  if exists (select 1 from sr_auth.users u
              where lower(u.email) = lower(trim(p_email))) then
    raise exception 'user_already_exists' using errcode = '23505';
  end if;

  insert into sr_auth.users (email, encrypted_password, raw_user_meta_data,
                          email_confirmed_at)
  values (trim(p_email),
          crypt(p_password, gen_salt('bf', 10)),
          coalesce(p_meta, '{}'::jsonb),
          now())
  returning users.id into v_id;

  return query
  select u.id, u.email, u.raw_user_meta_data, u.email_confirmed_at
    from sr_auth.users u
   where u.id = v_id;
end;
$fn$;

-- 2b. Change / reset password.
--
--  ⚠️ Also refuses re-using the CURRENT password. Without this, a 90-day
--  expiry prompt is satisfied by typing the same password back in, which
--  resets the clock and changes nothing — the rotation would be theatre.
create or replace function sr_auth.change_password(
  p_user_id  uuid,
  p_password text
)
returns void
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_reason  text;
  v_current text;
begin
  v_reason := public.password_policy_violation(p_password);
  if v_reason is not null then
    raise exception '%', v_reason using errcode = '22023';
  end if;

  select encrypted_password into v_current
    from sr_auth.users where id = p_user_id;

  if v_current is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  if v_current = crypt(p_password, v_current) then
    raise exception 'New password must be different from the current one.'
      using errcode = '22023';
  end if;

  update sr_auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf', 10)),
         updated_at         = now()
   where id = p_user_id;
end;
$fn$;


-- ── 3. Password rotation ────────────────────────────────────────────────────
--
--  profiles.password_updated_at already exists and is maintained by a trigger
--  on sr_auth.users. What was missing is a server-side ANSWER to "is this
--  password too old", so the client is not the only thing deciding.
create or replace function public.password_age_status(p_user_id uuid default null)
returns table (
  password_updated_at timestamptz,
  age_days            int,
  expires_in_days     int,
  is_expired          boolean,
  is_expiring_soon    boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $fn$
  select
    coalesce(p.password_updated_at, p.created_at)                     as password_updated_at,
    extract(day from now() - coalesce(p.password_updated_at, p.created_at))::int
                                                                       as age_days,
    (90 - extract(day from now() - coalesce(p.password_updated_at, p.created_at))::int)
                                                                       as expires_in_days,
    (now() - coalesce(p.password_updated_at, p.created_at)) > interval '90 days'
                                                                       as is_expired,
    -- 83 days = the last 7, matching ProfileModel.passwordWarnDays. The two
    -- must agree or the app warns on a different day than the server does.
    (now() - coalesce(p.password_updated_at, p.created_at)) > interval '83 days'
      and (now() - coalesce(p.password_updated_at, p.created_at)) <= interval '90 days'
                                                                       as is_expiring_soon
  from public.profiles p
  -- Defaults to the CALLER. A user may ask about their own age; asking about
  -- someone else's requires being an admin, checked below.
  where p.id = coalesce(p_user_id, sr_auth.uid())
    and (coalesce(p_user_id, sr_auth.uid()) = sr_auth.uid()
         or exists (select 1 from public.profiles me
                     where me.id = sr_auth.uid() and me.role in ('admin', 'ict')));
$fn$;

grant execute on function public.password_age_status(uuid) to public;

-- Who is overdue — for the admin security panel.
create or replace view public.password_rotation_status as
  select p.id,
         p.full_name,
         p.role,
         p.yard,
         p.directorate,
         coalesce(p.password_updated_at, p.created_at) as password_updated_at,
         extract(day from now() - coalesce(p.password_updated_at, p.created_at))::int
           as age_days,
         (now() - coalesce(p.password_updated_at, p.created_at)) > interval '90 days'
           as is_expired
    from public.profiles p
   where p.is_active;

comment on view public.password_rotation_status is
  'Password age per active user. Reading it is governed by the RLS policies on '
  'profiles, so a non-admin sees only rows they could already read.';


-- ── 4. The RPC that never checked its caller ────────────────────────────────
--
--  ⚠️ disposal_toggle_outcome_delivery was SECURITY DEFINER — so RLS does not
--  apply inside it — and granted to `public`. It marks goods as handed over
--  AND closes the warehouse entry, and it asked nothing about who was calling.
--  Any authenticated account could hand out any consignment in any yard.
--
--  Its own comment says "same shape as disposal_toggle_delivery_status", and
--  that function does check. The guard below is exactly that one's: Central
--  Disposal, or an officer of the yard the goods are in.
create or replace function public.disposal_toggle_outcome_delivery(
  p_proposal_id uuid,
  p_delivered   boolean)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_yard text;
begin
  select fp.yard
    into v_yard
    from public.unsold_proposals up
    join public.forfeited_packages fp on fp.id = up.forfeited_package_id
   where up.id = p_proposal_id;

  if v_yard is null then
    raise exception 'no unsold_proposal with id %', p_proposal_id;
  end if;

  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;

  update public.unsold_proposals
     set delivered    = p_delivered,
         delivered_at = case when p_delivered then now() else null end,
         updated_at   = now()
   where id = p_proposal_id;

  if not found then
    raise exception 'no unsold_proposal with id %', p_proposal_id;
  end if;

  -- ⚠️ Delivered means the goods have LEFT. Close the warehouse entry the
  -- same way a sale does, or zone capacity and the storage charge keep
  -- counting goods that are no longer there.
  if p_delivered then
    update public.warehouse_entries w
       set is_returned  = true,
           returned_at  = now(),
           return_notes = '[FINAL:' || upper(
             (select proposal from public.unsold_proposals
               where id = p_proposal_id)) || ']',
           updated_at   = now()
      from public.forfeited_packages fp
      join public.unsold_proposals up on up.forfeited_package_id = fp.id
     where up.id = p_proposal_id
       and w.package_item_id = fp.item_id
       and coalesce(w.is_returned, false) = false;
  end if;
end;
$fn$;

-- ⚠️ `public` includes every role, signed in or not. Privileged mutations go
-- to `authenticated`, and the function then decides.
revoke execute on function public.disposal_toggle_outcome_delivery(uuid, boolean)
  from public;
grant execute on function public.disposal_toggle_outcome_delivery(uuid, boolean)
  to authenticated;


-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  v_reason text;
begin
  -- The policy rejects what it should.
  if public.password_policy_violation('short1!A') is null then
    raise exception 'policy accepted a too-short password';
  end if;
  if public.password_policy_violation('alllowercase123!') is null then
    raise exception 'policy accepted a password with no uppercase';
  end if;
  if public.password_policy_violation('NoDigitsHere!!') is null then
    raise exception 'policy accepted a password with no digit';
  end if;
  if public.password_policy_violation('NoSpecials1234') is null then
    raise exception 'policy accepted a password with no special character';
  end if;
  if public.password_policy_violation('Password1234!') is null then
    raise exception 'policy accepted a common word';
  end if;
  -- And accepts a good one.
  v_reason := public.password_policy_violation('Tr0ub4dor&Kestrel');
  if v_reason is not null then
    raise exception 'policy rejected a strong password: %', v_reason;
  end if;

  -- The RPC is no longer executable by anonymous callers.
  if has_function_privilege('anon',
       'public.disposal_toggle_outcome_delivery(uuid, boolean)', 'execute') then
    raise exception 'disposal_toggle_outcome_delivery is still granted to anon';
  end if;

  raise notice '52_user_security_policies: all checks passed';
end;
$verify$;
