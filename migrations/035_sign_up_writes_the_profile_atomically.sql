-- 035  A sign-up creates the account AND its profile, or neither.
--
-- ⚠️ THE BUG THIS FIXES, as reported from the ICT sign-up screen: entering the
-- OTP showed "This account is not permitted to create that profile", pressing
-- the button again showed "No verification code was sent" — and the account was
-- in the database anyway. Three faults in one sequence:
--
--   1. `auth.sign_up` inserted into auth.users and RETURNED. That write is
--      committed, and the trigger `on_auth_user_created` created a MINIMAL
--      profile with it — id, full_name and role only (see handle_new_user).
--      The client then ran a SECOND statement, an `upsert` into profiles
--      carrying username, job_role and directorate. RLS refused that one: the
--      policy `yard_profiles_insert` requires `id = auth.uid()`, and someone
--      signing up is not signed in, so auth.uid() is null. Reproduced:
--          set role yard_app;
--          select auth.begin_session('', 'anon');
--          insert into profiles (id, full_name, role) values (...);
--          ERROR: new row violates row-level security policy for table "profiles"
--      That 42501 is mapped to the "not permitted to create that profile"
--      message, which is why the screen said exactly that.
--
--   2. The auth.users row and the minimal profile SURVIVED, because they were
--      committed by an earlier statement. Hence the account the officer found
--      in the database after being told the sign-up had failed — real, but
--      missing the username it is meant to be signed in with.
--
--   3. The client consumed the one-time code BEFORE all this, so the retry had
--      no code left and reported it missing. (Fixed on the Dart side.)
--
-- ⚠️ The first draft of this migration INSERTED the profile here and failed
-- its own verification with a duplicate key on profiles_pkey — because the
-- trigger had already inserted it. The trigger is the thing that makes the
-- account and its profile atomic, and it already works. What is missing is the
-- REST of the fields, so this fills them in, in the same transaction, where
-- RLS does not apply. Either the whole account is right, or nothing is written.
--
-- ⚠️ SECURITY DEFINER means this function decides what a stranger may create,
-- so it must not take a role from the caller unchecked. The guard below is the
-- point of the rewrite, and is tested at the bottom.

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

  -- ⚠️ A self-service sign-up may NOT mint a yard account.
  --
  -- 'admin' is SDDC/DDC — full control of a yard — and 'officer' is yard
  -- staff. Both are provisioned by ICT from the staff screen, where the caller
  -- is an authenticated ICT user and `profiles_ict_write` governs the write.
  -- Allowing them here would let anyone who can reach the sign-up form create
  -- a yard administrator for any yard: exactly the escalation the portal
  -- separation exists to prevent. The directorate roles are the ones whose
  -- portals carry a Create Account link, so those are what this accepts.
  if v_role is null then
    raise exception 'a role is required' using errcode = '22023';
  end if;
  if v_role not in ('ict','valuation','appeal','disposal','executive') then
    raise exception
      'role % cannot be created from a sign-up form; ICT provisions it',
      v_role using errcode = '42501';
  end if;

  -- A directorate carries no yard (migration 027's CHECK constraint). Drop a
  -- stale value rather than fail on it: refusing would be a worse experience
  -- than ignoring a field this role cannot have.
  v_yard := null;

  insert into auth.users (email, encrypted_password, raw_user_meta_data,
                          email_confirmed_at)
  values (trim(p_email),
          crypt(p_password, gen_salt('bf', 10)),
          coalesce(p_meta, '{}'::jsonb),
          now())
  returning users.id into v_id;

  -- ⚠️ Complete the profile the TRIGGER just made, in the SAME transaction.
  --
  -- `on_auth_user_created` has already inserted id, full_name and role. It
  -- cannot carry the rest, because it only sees raw_user_meta_data and was
  -- written for the minimum a row needs to exist. Updating here is what the
  -- client's blocked upsert was trying to do, done where RLS does not apply.
  --
  -- An UPDATE rather than an upsert: the row is guaranteed to be there by the
  -- trigger, and an INSERT would collide on profiles_pkey — which is exactly
  -- how the first draft of this migration failed.
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
    -- The trigger is what guarantees the profile exists. If it is ever removed
    -- this must fail loudly rather than return an account that cannot sign in.
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
-- Verification. Each block raises if the rule it names does not hold.
-- ---------------------------------------------------------------------------

-- 1. A directorate sign-up now yields BOTH rows.
do $v1$
declare v_id uuid; v_email text := 'm035_ok@example.invalid';
begin
  select s.id into v_id from auth.sign_up(
    v_email, 'Qz7&mVt2!Ryx9#35',
    jsonb_build_object('role','valuation','full_name','M035 Tester',
                       'username','m035user')) s;

  if not exists (select 1 from public.profiles p where p.id = v_id) then
    raise exception 'FAIL: sign_up created no profile row';
  end if;
  if (select role from public.profiles where id = v_id) <> 'valuation' then
    raise exception 'FAIL: profile did not take the requested role';
  end if;
  -- ⚠️ The fields the blocked upsert was carrying. Checking only that a row
  -- exists would have PASSED before this migration, because the trigger
  -- already made one — and the officer would still have no username to sign
  -- in with. This is the assertion that actually covers the reported bug.
  if (select username from public.profiles where id = v_id)
       is distinct from 'm035user' then
    raise exception 'FAIL: the username never reached the profile';
  end if;
  if (select yard from public.profiles where id = v_id) is not null then
    raise exception 'FAIL: a directorate account was given a yard';
  end if;

  delete from public.profiles where id = v_id;
  delete from auth.users    where id = v_id;
  raise notice 'PASS: account and profile are created together';
end $v1$;

-- 2. A refused sign-up leaves NO orphan — the whole point.
do $v2$
declare v_email text := 'm035_orphan@example.invalid';
begin
  begin
    perform auth.sign_up(v_email, 'Qz7&mVt2!Ryx9#35',
                         jsonb_build_object('role','admin','full_name','X'));
    raise exception 'FAIL: a yard role was accepted from the sign-up form';
  exception when sqlstate '42501' then
    null;  -- expected
  end;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'FAIL: a refused sign-up left an orphan auth.users row';
  end if;
  -- The trigger's profile must have gone with it. A profile whose auth.users
  -- row is missing is the mirror image of the orphan this migration is about.
  if exists (select 1 from public.profiles p
              left join auth.users u on u.id = p.id
             where u.id is null) then
    raise exception 'FAIL: a profile was left with no account behind it';
  end if;
  raise notice 'PASS: a refused sign-up leaves no orphan account';
end $v2$;

-- 3. The yard roles stay ICT-provisioned.
do $v3$
declare r text;
begin
  foreach r in array array['admin','officer'] loop
    begin
      perform auth.sign_up('m035_' || r || '@example.invalid',
                           'Qz7&mVt2!Ryx9#35',
                           jsonb_build_object('role', r, 'full_name','X'));
      raise exception 'FAIL: role % was creatable from the sign-up form', r;
    exception when sqlstate '42501' then
      null;
    end;
  end loop;
  raise notice 'PASS: yard roles cannot be self-provisioned';
end $v3$;
