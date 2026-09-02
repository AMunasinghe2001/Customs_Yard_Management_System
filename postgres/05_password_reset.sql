-- ============================================================================
--  Password reset — "I forgot my password", without a session
--
--  A signed-in user changes their password through auth.change_password, which
--  needs their id. Someone who has FORGOTTEN it has no session and no id, so
--  the app can only offer an identifier (username or email). These functions
--  close that gap.
--
--  The one-time code itself is NOT checked here. It is generated and verified
--  by GmailOtpService in the app, against the address the account is
--  registered to, so a caller who reaches reset_password_for_identifier has
--  already proved they can read that mailbox.
--
--  SECURITY DEFINER, for the same reason as auth.sign_in: at this moment
--  auth.uid() is NULL and ordinary RLS would deny everything. Both are
--  deliberately narrow.
--
--  Run AFTER 04_auth.sql. Idempotent — safe to re-run.
-- ============================================================================

set client_min_messages = warning;

-- ── The address to send a reset code to ─────────────────────────────────────
--  Returns the account's email for a username OR an email, or NULL when no
--  such account exists.
--
--  ⚠️ The CALLER must not tell the user which it was. Reporting "no such
--  account" would let anyone test which usernames and addresses are real; the
--  screens above say "if that account exists, a code has been sent" either
--  way.
create or replace function public.reset_email_for_identifier(
  p_identifier text
)
returns text
language plpgsql
security definer
set search_path = auth, public
as $fn$
declare
  v_email text;
begin
  if p_identifier is null or btrim(p_identifier) = '' then
    return null;
  end if;

  -- email_for_login already resolves either shape, and is the same resolver
  -- the sign-in path uses -- so a reset can never reach an account that could
  -- not have signed in.
  v_email := public.email_for_login(btrim(p_identifier));
  if v_email is null or btrim(v_email) = '' then
    return null;
  end if;

  -- Only for an account that can actually sign in. A deactivated one must not
  -- be resettable into life.
  if not exists (
    select 1
    from   public.profiles p
    join   auth.users u on u.id = p.id
    where  lower(u.email) = lower(v_email)
      and  p.is_active
  ) then
    return null;
  end if;

  return v_email;
end;
$fn$;

-- ── Set a new password for an identifier ────────────────────────────────────
--  Called only after the app has verified the one-time code it emailed to the
--  address reset_email_for_identifier returned.
create or replace function public.reset_password_for_identifier(
  p_identifier text,
  p_password   text
)
returns void
language plpgsql
security definer
set search_path = auth, public
as $fn$
declare
  v_email text;
  v_id    uuid;
begin
  v_email := public.reset_email_for_identifier(p_identifier);
  if v_email is null then
    -- Same message the app shows for an expired code: a caller who got this
    -- far has already passed the code check, so this is a race (the account
    -- was deactivated meanwhile), not a guess to be told apart.
    raise exception 'reset_not_available' using errcode = '22023';
  end if;

  select u.id into v_id
  from   auth.users u
  where  lower(u.email) = lower(v_email);

  if v_id is null then
    raise exception 'reset_not_available' using errcode = '22023';
  end if;

  -- Reuses the same setter a signed-in change goes through, so the hashing
  -- and the minimum length live in exactly one place.
  perform auth.change_password(v_id, p_password);

  -- The 90-day rotation clock restarts from the change, and any lockout from
  -- failed attempts is cleared: the holder has just proved control of the
  -- mailbox, so making them wait out a lockout would serve no one.
  update public.profiles
     set password_updated_at = now()
   where id = v_id;

  begin
    perform auth.clear_failed_login(v_email);
  exception when undefined_function then
    -- Older database without the lockout functions; nothing to clear.
    null;
  end;
end;
$fn$;

grant execute on function public.reset_email_for_identifier(text)
  to anon, authenticated, service_role;
grant execute on function public.reset_password_for_identifier(text, text)
  to anon, authenticated, service_role;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  v_id    uuid;
  v_email text;
begin
  insert into auth.users (email, encrypted_password, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values ('reset.probe@local.invalid',
          crypt('probe-password-123', gen_salt('bf', 10)),
          '{"full_name":"Reset Probe"}'::jsonb, now(), now(), now())
  returning id into v_id;

  -- The on_auth_user_created trigger already made the profile row; give it
  -- the username and role this probe needs.
  update public.profiles
     set username = 'reset.probe', role = 'officer', is_active = true
   where id = v_id;

  -- Resolves by username and by email.
  if public.reset_email_for_identifier('reset.probe') is distinct from
     'reset.probe@local.invalid' then
    raise exception 'VERIFY FAILED: username did not resolve';
  end if;
  if public.reset_email_for_identifier('reset.probe@local.invalid') is distinct from
     'reset.probe@local.invalid' then
    raise exception 'VERIFY FAILED: email did not resolve';
  end if;

  -- An unknown identifier resolves to nothing.
  if public.reset_email_for_identifier('no.such.person') is not null then
    raise exception 'VERIFY FAILED: an unknown identifier resolved';
  end if;

  -- The reset actually changes the password.
  perform public.reset_password_for_identifier('reset.probe', 'brand-new-pw-1');
  if (select count(*) from auth.sign_in('reset.probe', 'brand-new-pw-1')) <> 1 then
    raise exception 'VERIFY FAILED: the new password does not sign in';
  end if;
  if (select count(*) from auth.sign_in('reset.probe', 'probe-password-123')) <> 0 then
    raise exception 'VERIFY FAILED: the old password still signs in';
  end if;

  -- A deactivated account is not resettable.
  update public.profiles set is_active = false where id = v_id;
  if public.reset_email_for_identifier('reset.probe') is not null then
    raise exception 'VERIFY FAILED: a deactivated account resolved';
  end if;

  delete from public.profiles where id = v_id;
  delete from auth.users where id = v_id;
  raise notice 'password reset VERIFY passed';
end
$verify$;
