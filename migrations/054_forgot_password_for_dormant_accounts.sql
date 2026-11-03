-- ============================================================================
--  Migration 054 — Forgot Password works for dormant accounts
--
--  Previously reset_email_for_identifier blocked ALL inactive accounts, which
--  meant a dormant officer could not reset their own password. The only path
--  was to call ICT, who reactivated the account, and then the officer could
--  log in — but they still did not know their password.
--
--  This migration changes the rule:
--    • DORMANT accounts (deactivated_reason = 'dormant')  → password reset ALLOWED
--    • MANUALLY deactivated accounts (deactivated_reason = 'manual' or other) → still blocked
--
--  A successful password reset for a dormant account also auto-reactivates it
--  (sets is_active = true, clears deactivated_reason/deactivated_at, resets
--  last_seen_at and sr_auth.users.last_sign_in_at so the next sign-in sweep
--  does not immediately re-disable the account).
--
--  Safe to re-run.
-- ============================================================================

set client_min_messages = warning;

-- ── Allow dormant accounts to reset their password ──────────────────────────
create or replace function public.reset_email_for_identifier(
  p_identifier text
)
returns text
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_email text;
begin
  if p_identifier is null or btrim(p_identifier) = '' then
    return null;
  end if;

  v_email := public.email_for_login(btrim(p_identifier));
  if v_email is null or btrim(v_email) = '' then
    return null;
  end if;

  -- Active accounts and dormant accounts are both resettable.
  -- Dormant = automatically disabled after 30 days of no sign-in.
  -- Manually deactivated = ICT chose to disable; only ICT can reactivate.
  if not exists (
    select 1
    from   public.profiles p
    join   sr_auth.users u on u.id = p.id
    where  lower(u.email) = lower(v_email)
      and  (
             p.is_active
             or p.deactivated_reason = 'dormant'
           )
  ) then
    return null;
  end if;

  return v_email;
end;
$fn$;

-- ── Auto-reactivate dormant accounts on successful password reset ────────────
create or replace function public.reset_password_for_identifier(
  p_identifier text,
  p_password   text
)
returns void
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_email  text;
  v_id     uuid;
  v_reason text;
begin
  v_email := public.reset_email_for_identifier(p_identifier);
  if v_email is null then
    raise exception 'reset_not_available' using errcode = '22023';
  end if;

  select u.id, p.deactivated_reason
    into v_id, v_reason
    from sr_auth.users u
    join public.profiles p on p.id = u.id
   where lower(u.email) = lower(v_email);

  if v_id is null then
    raise exception 'reset_not_available' using errcode = '22023';
  end if;

  perform sr_auth.change_password(v_id, p_password);

  update public.profiles
     set password_updated_at = now()
   where id = v_id;

  -- Dormant account: reactivate now that the holder proved mailbox ownership.
  if v_reason = 'dormant' then
    update public.profiles
       set is_active          = true,
           deactivated_reason = null,
           deactivated_at     = null,
           last_seen_at       = now(),
           updated_at         = now()
     where id = v_id;

    -- Reset the sign-in clock so the dormancy sweep on the NEXT login
    -- does not immediately flip the account back to dormant.
    update sr_auth.users
       set last_sign_in_at = now(),
           updated_at      = now()
     where id = v_id;
  end if;

  begin
    perform sr_auth.clear_failed_login(v_email);
  exception when undefined_function then
    null;
  end;
end;
$fn$;

grant execute on function public.reset_email_for_identifier(text)
  to anon, authenticated, service_role;
grant execute on function public.reset_password_for_identifier(text, text)
  to anon, authenticated, service_role;

-- ── Verify ───────────────────────────────────────────────────────────────────
do $verify$
declare
  v_id uuid;
begin
  insert into sr_auth.users (email, encrypted_password, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values ('reset054.probe@local.invalid',
          crypt('probe-pw-054', gen_salt('bf', 10)),
          '{"full_name":"Reset054 Probe"}'::jsonb, now(), now(), now())
  returning id into v_id;

  update public.profiles
     set username = 'reset054probe', role = 'officer', is_active = true
   where id = v_id;

  -- Dormant: resettable
  update public.profiles
     set is_active = false, deactivated_reason = 'dormant', deactivated_at = now()
   where id = v_id;
  if public.reset_email_for_identifier('reset054probe') is null then
    raise exception 'VERIFY FAILED: dormant account should be resettable';
  end if;

  -- Dormant: reset reactivates account
  perform public.reset_password_for_identifier('reset054probe', 'new-probe-pw-054!');
  if not (select is_active from public.profiles where id = v_id) then
    raise exception 'VERIFY FAILED: dormant account not reactivated after reset';
  end if;

  -- Manual: NOT resettable
  update public.profiles
     set is_active = false, deactivated_reason = 'manual', deactivated_at = now()
   where id = v_id;
  if public.reset_email_for_identifier('reset054probe') is not null then
    raise exception 'VERIFY FAILED: manually deactivated account must not be resettable';
  end if;

  delete from public.profiles where id = v_id;
  delete from sr_auth.users where id = v_id;
  raise notice 'migration 054 VERIFY passed';
end
$verify$;
