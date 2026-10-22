-- ============================================================================
--  050_sync_profiles_and_enhance_signup.sql
--  Ensure handle_new_user and sr_auth.sign_up populate all profile fields
--  from raw_user_meta_data, and backfill any profiles missing their metadata.
--
--  Idempotent — safe to re-run.
-- ============================================================================

begin;

-- 1. Sync any existing profiles from sr_auth.users.raw_user_meta_data
update public.profiles p set
  full_name     = coalesce(nullif(trim(p.full_name), ''), nullif(trim(u.raw_user_meta_data->>'full_name'), ''), p.full_name),
  badge_number  = coalesce(nullif(trim(p.badge_number), ''), nullif(trim(u.raw_user_meta_data->>'badge_number'), '')),
  username      = coalesce(nullif(trim(p.username), ''), nullif(trim(u.raw_user_meta_data->>'username'), '')),
  mobile_number = coalesce(nullif(trim(p.mobile_number), ''), nullif(trim(u.raw_user_meta_data->>'mobile_number'), '')),
  job_role      = coalesce(nullif(trim(p.job_role), ''), nullif(trim(u.raw_user_meta_data->>'job_role'), '')),
  department    = coalesce(nullif(trim(p.department), ''), nullif(trim(u.raw_user_meta_data->>'department'), '')),
  yard          = coalesce(nullif(trim(p.yard), ''), nullif(trim(u.raw_user_meta_data->>'yard'), '')),
  directorate   = coalesce(nullif(trim(p.directorate), ''), nullif(trim(u.raw_user_meta_data->>'directorate'), '')),
  profile_image_url = coalesce(nullif(trim(p.profile_image_url), ''), nullif(trim(u.raw_user_meta_data->>'profile_image_url'), ''))
from sr_auth.users u
where p.id = u.id;

-- 2. Enhance handle_new_user to capture all metadata fields immediately on trigger
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (
    id, full_name, role, username, badge_number, mobile_number,
    job_role, department, yard, directorate, profile_image_url
  )
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'New User'),
    coalesce(nullif(trim(new.raw_user_meta_data->>'role'), ''), 'officer'),
    nullif(trim(new.raw_user_meta_data->>'username'), ''),
    nullif(trim(new.raw_user_meta_data->>'badge_number'), ''),
    nullif(trim(new.raw_user_meta_data->>'mobile_number'), ''),
    nullif(trim(new.raw_user_meta_data->>'job_role'), ''),
    nullif(trim(new.raw_user_meta_data->>'department'), ''),
    nullif(trim(new.raw_user_meta_data->>'yard'), ''),
    nullif(trim(new.raw_user_meta_data->>'directorate'), ''),
    nullif(trim(new.raw_user_meta_data->>'profile_image_url'), '')
  );
  return new;
end;
$$ language plpgsql security definer;

-- 3. Ensure sr_auth.sign_up enforces password policy and completes profile update
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

  if exists (select 1 from sr_auth.users u
              where lower(u.email) = lower(trim(p_email))) then
    raise exception 'user_already_exists' using errcode = '23505';
  end if;

  v_role := nullif(trim(coalesce(p_meta->>'role', '')), '');
  v_yard := nullif(trim(coalesce(p_meta->>'yard', '')), '');

  if v_role is null then
    raise exception 'a role is required' using errcode = '22023';
  end if;

  v_is_ict := public.auth_user_is_ict();

  if v_role in ('admin','officer') then
    if not v_is_ict then
      raise exception
        'role % may only be created by the ICT Directorate', v_role
        using errcode = '42501';
    end if;
    if v_yard is null then
      raise exception 'a yard account needs an assigned yard'
        using errcode = '22023';
    end if;
  elsif v_role in ('ict','valuation','appeal','disposal','executive') then
    v_yard := null;
  else
    raise exception 'role % is not a role this system issues', v_role
      using errcode = '42501';
  end if;

  insert into sr_auth.users (email, encrypted_password, raw_user_meta_data,
                          email_confirmed_at)
  values (trim(p_email),
          crypt(p_password, gen_salt('bf', 10)),
          coalesce(p_meta, '{}'::jsonb),
          now())
  returning users.id into v_id;

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
    from sr_auth.users u
   where u.id = v_id;
end;
$fn$;

commit;
