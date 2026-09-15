-- 036  ICT may provision yard accounts again; a stranger still may not.
--
-- ⚠️ THIS FIXES A REGRESSION I INTRODUCED IN 035.
--
-- 035 stopped `auth.sign_up` creating 'admin' (SDDC/DDC) or 'officer', because
-- a public sign-up form must not be able to mint a yard administrator. That
-- part was right. What it missed is that ICT's own "Create Yard Staff Account"
-- screen goes through the SAME function — so the screen that is SUPPOSED to
-- create yard accounts stopped working:
--
--     role admin cannot be created from a sign-up form; ICT provisions it
--
-- The guard could not tell the two apart because it never asked WHO was
-- calling. A person filling in a sign-up form is not signed in; an ICT admin
-- creating staff is. `public.auth_user_is_ict()` already answers exactly that
-- question and is used by the `profiles_ict_write` policy for the same purpose.
--
-- So the rule becomes: the directorate roles may be self-created from a portal
-- sign-up form, and the yard roles may be created ONLY by a signed-in, active
-- ICT user. Everything else is still refused.

begin;

create or replace function auth.sign_up(
  p_email    text,
  p_password text,
  p_meta     jsonb default '{}'::jsonb
)
returns table(id uuid, email text, meta jsonb, email_confirmed_at timestamptz)
language plpgsql
security definer
set search_path = auth, public
as $fn$
declare
  v_id     uuid;
  v_reason text;
  v_role   text;
  v_yard   text;
  v_is_ict boolean;
begin
  if p_email is null or length(trim(p_email)) = 0 then
    raise exception 'email is required' using errcode = '22023';
  end if;

  v_reason := public.password_policy_violation(p_password);
  if v_reason is not null then
    raise exception '%', v_reason using errcode = '22023';
  end if;

  if exists (select 1 from auth.users u
              where lower(u.email) = lower(trim(p_email))) then
    raise exception 'user_already_exists' using errcode = '23505';
  end if;

  v_role := nullif(trim(coalesce(p_meta->>'role', '')), '');
  v_yard := nullif(trim(coalesce(p_meta->>'yard', '')), '');

  if v_role is null then
    raise exception 'a role is required' using errcode = '22023';
  end if;

  -- ⚠️ WHO is asking. A sign-up form has nobody signed in, so this is false
  -- there; ICT's staff screen runs with the admin's own session, so it is true.
  -- This is the whole difference between the two callers.
  v_is_ict := public.auth_user_is_ict();

  if v_role in ('admin','officer') then
    -- Yard roles: ICT only. 'admin' is SDDC/DDC — full control of a yard.
    if not v_is_ict then
      raise exception
        'role % may only be created by the ICT Directorate', v_role
        using errcode = '42501';
    end if;
    -- A yard account must say WHICH yard; without it the RLS policies that
    -- scope every query by yard have nothing to match on.
    if v_yard is null then
      raise exception 'a yard account needs an assigned yard'
        using errcode = '22023';
    end if;
  elsif v_role in ('ict','valuation','appeal','disposal','executive') then
    -- Directorate roles carry no yard (migration 027's CHECK constraint).
    v_yard := null;
  else
    raise exception 'role % is not a role this system issues', v_role
      using errcode = '42501';
  end if;

  insert into auth.users (email, encrypted_password, raw_user_meta_data,
                          email_confirmed_at)
  values (trim(p_email),
          crypt(p_password, gen_salt('bf', 10)),
          coalesce(p_meta, '{}'::jsonb),
          now())
  returning users.id into v_id;

  -- Complete the profile the `on_auth_user_created` trigger just inserted.
  -- See 035 for why this is an UPDATE and not an INSERT.
  update public.profiles p set
    full_name     = coalesce(nullif(trim(coalesce(p_meta->>'full_name','')), ''),
                             p.full_name),
    badge_number  = coalesce(nullif(trim(coalesce(p_meta->>'badge_number','')), ''),
                             p.badge_number),
    role          = v_role,
    is_active     = true,
    username      = coalesce(nullif(trim(coalesce(p_meta->>'username','')), ''),
                             p.username),
    mobile_number = coalesce(nullif(trim(coalesce(p_meta->>'mobile_number','')), ''),
                             p.mobile_number),
    job_role      = coalesce(nullif(trim(coalesce(p_meta->>'job_role','')), ''),
                             p.job_role),
    department    = coalesce(nullif(trim(coalesce(p_meta->>'department','')), ''),
                             p.department),
    yard          = v_yard,
    directorate   = coalesce(nullif(trim(coalesce(p_meta->>'directorate','')), ''),
                             p.directorate),
    profile_image_url =
                    coalesce(nullif(trim(coalesce(p_meta->>'profile_image_url','')), ''),
                             p.profile_image_url)
  where p.id = v_id;

  if not found then
    raise exception
      'no profile row for the new account — is on_auth_user_created present?'
      using errcode = 'P0002';
  end if;

  return query
  select u.id, u.email, u.raw_user_meta_data, u.email_confirmed_at
    from auth.users u
   where u.id = v_id;
end;
$fn$;

commit;

-- ---------------------------------------------------------------------------
-- Verification.
-- ---------------------------------------------------------------------------

-- 1. A stranger (nobody signed in) still cannot make a yard account.
do $v1$
declare r text;
begin
  perform auth.begin_session('', 'anon');
  foreach r in array array['admin','officer'] loop
    begin
      perform auth.sign_up('m036_' || r || '@example.invalid',
                           'Qz7&mVt2!Ryx9#36',
                           jsonb_build_object('role', r, 'full_name','X',
                                              'yard','Grey Line 1'));
      raise exception 'FAIL: % was creatable with nobody signed in', r;
    exception when sqlstate '42501' then
      null;  -- expected
    end;
  end loop;

  if exists (select 1 from auth.users where email like 'm036_%') then
    raise exception 'FAIL: a refused sign-up left an orphan account';
  end if;
  raise notice 'PASS: a stranger cannot create a yard account';
end $v1$;

-- 2. A signed-in ICT user CAN — the regression this migration fixes.
do $v2$
declare v_ict uuid; v_new uuid;
begin
  -- An ICT account to act as. Created through the directorate path, which
  -- needs no session.
  perform auth.begin_session('', 'anon');
  select s.id into v_ict from auth.sign_up(
    'm036_ict@example.invalid', 'Qz7&mVt2!Ryx9#36',
    jsonb_build_object('role','ict','full_name','M036 ICT')) s;

  -- Now act AS that ICT user.
  perform auth.begin_session(v_ict::text, 'authenticated');
  if not public.auth_user_is_ict() then
    raise exception 'FAIL: the test did not actually become an ICT user';
  end if;

  select s.id into v_new from auth.sign_up(
    'm036_sddc@example.invalid', 'Qz7&mVt2!Ryx9#36',
    jsonb_build_object('role','admin','full_name','M036 SDDC',
                       'username','m036.sddc','yard','Grey Line 1',
                       'job_role','sddc')) s;

  if (select role from public.profiles where id = v_new) <> 'admin' then
    raise exception 'FAIL: ICT could not create the yard admin';
  end if;
  if (select yard from public.profiles where id = v_new) <> 'Grey Line 1' then
    raise exception 'FAIL: the assigned yard never reached the profile';
  end if;
  if (select username from public.profiles where id = v_new)
       is distinct from 'm036.sddc' then
    raise exception 'FAIL: the username never reached the profile';
  end if;

  -- ⚠️ Triggers off for the cleanup. Changing a role fires
  -- `profiles_audit_privilege`, which writes an audit row, and the audit table
  -- is append-only — the delete then fails with "UPDATE is not permitted on an
  -- audit record". The test must not leave rows behind over its own bookkeeping.
  perform auth.begin_session('', 'anon');
  set session_replication_role = replica;
  delete from public.profiles where id in (v_ict, v_new);
  delete from auth.users    where id in (v_ict, v_new);
  delete from public.audit_logs where entity_id in (v_ict::text, v_new::text);
  set session_replication_role = default;
  raise notice 'PASS: ICT can provision a yard account again';
end $v2$;

-- 3. A yard account without a yard is refused, not silently made yard-less.
do $v3$
declare v_ict uuid;
begin
  perform auth.begin_session('', 'anon');
  select s.id into v_ict from auth.sign_up(
    'm036_ict2@example.invalid', 'Qz7&mVt2!Ryx9#36',
    jsonb_build_object('role','ict','full_name','M036 ICT2')) s;
  perform auth.begin_session(v_ict::text, 'authenticated');

  begin
    perform auth.sign_up('m036_noyard@example.invalid', 'Qz7&mVt2!Ryx9#36',
      jsonb_build_object('role','officer','full_name','No Yard'));
    raise exception 'FAIL: a yard account was created with no yard';
  exception when sqlstate '22023' then
    null;  -- expected
  end;

  perform auth.begin_session('', 'anon');
  set session_replication_role = replica;
  delete from public.profiles where id = v_ict;
  delete from auth.users    where id = v_ict;
  delete from public.audit_logs where entity_id = v_ict::text;
  set session_replication_role = default;
  raise notice 'PASS: a yard account must name its yard';
end $v3$;
