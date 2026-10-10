-- ============================================================================
--  04 · Auth — sign-in, sign-up and password change without Supabase's GoTrue
--
--  Supabase ran a separate auth service. Here the same jobs are done by SQL
--  functions over sr_auth.users, using pgcrypto's bcrypt:
--
--      sr_auth.sign_in(identifier, password) -> the user row, or nothing
--      sr_auth.sign_up(email, password, meta)-> the new user row
--      sr_auth.change_password(id, new)      -> void
--      sr_auth.update_user(id, email, meta)  -> the updated row
--      sr_auth.user_by_id(id)                -> the user row
--
--  Passwords: crypt(pw, gen_salt('bf', 10)) stores a bcrypt hash. Verifying is
--  crypt(attempt, stored) = stored — bcrypt re-reads its own salt and cost out
--  of the stored hash, so this compares two hashes, never plaintext. The
--  plaintext is never stored and never logged.
--
--  SECURITY DEFINER: these run as the owner of the function, so the app can
--  sign in before it has any identity — at that moment sr_auth.uid() is still
--  NULL and ordinary RLS would deny everything. They are deliberately narrow:
--  they take an identifier and a password, and return a row only on a match.
--
--  Run AFTER 02_schema.sql (public.email_for_login and public.profiles must
--  exist). Idempotent — safe to re-run.
-- ============================================================================

set client_min_messages = warning;

-- ⚠️ Dropped before creating: CREATE OR REPLACE cannot change a function's
--  RETURN TYPE, and these gained an `email_confirmed_at` column. Without the
--  drop, re-running this file against an older database fails with
--  "cannot change return type of existing function".
drop function if exists sr_auth.sign_in(text, text);
drop function if exists sr_auth.sign_up(text, text, jsonb);
drop function if exists sr_auth.user_by_id(uuid);
drop function if exists sr_auth.record_failed_login(text);
drop function if exists sr_auth.clear_failed_login(text);

-- ── Sign in ─────────────────────────────────────────────────────────────────
--  `p_identifier` may be an email OR a username: officers are issued
--  usernames, and public.email_for_login() already resolves either to an
--  email. That function came over from the Supabase migrations unchanged.
--
--  A wrong password and an unknown user both return zero rows, on purpose —
--  telling them apart would reveal which accounts exist.
create or replace function sr_auth.sign_in(
  p_identifier text,
  p_password   text
)
-- ⚠️ The column is `raw_user_meta_data`, NOT `meta`.
--
-- Migrations 032 and 047 re-create this function as a wrapper and name it
-- `raw_user_meta_data`; PostgreSQL refuses to change a returned column's
-- NAME, so a database built from this file then failed both with
--
--     cannot change return type of existing function
--
-- The app selects `raw_user_meta_data as meta` (pg_auth.dart), so the
-- migrations were right and this file was the outlier. Local databases hid
-- it because the function already existed there.
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

create or replace function sr_auth.record_failed_login(p_email text)
returns void
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
begin
  if p_email is null then
    return;
  end if;

  update sr_auth.users u
     set failed_login_attempts = coalesce(u.failed_login_attempts, 0) + 1,
         locked_until = case
           when coalesce(u.failed_login_attempts, 0) + 1 >= 5 then now() + interval '15 minutes'
           else null
         end,
         updated_at = now()
   where lower(u.email) = lower(trim(p_email));
end;
$fn$;

create or replace function sr_auth.clear_failed_login(p_email text)
returns void
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
begin
  if p_email is null then
    return;
  end if;

  update sr_auth.users u
     set failed_login_attempts = 0,
         locked_until = null,
         updated_at = now()
   where lower(u.email) = lower(trim(p_email));
end;
$fn$;

-- ── Sign up ─────────────────────────────────────────────────────────────────
--  Raises on a duplicate email with SQLSTATE 23505, which the Dart side maps
--  back to the 'user_already_exists' code the Supabase SDK used — so the
--  existing catch blocks keep working unchanged.
create or replace function sr_auth.sign_up(
  p_email    text,
  p_password text,
  p_meta     jsonb default '{}'::jsonb
)
returns table (
  id                 uuid,
  email              text,
  meta               jsonb,
  -- Mirrors sr_auth.sign_in: the app gates on emailConfirmedAt, so every function
  -- that produces an AuthUser has to report it.
  email_confirmed_at timestamptz
)
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_id uuid;
begin
  if p_email is null or length(trim(p_email)) = 0 then
    raise exception 'email is required' using errcode = '22023';
  end if;
  if p_password is null or length(p_password) < 6 then
    raise exception 'password must be at least 6 characters'
      using errcode = '22023';
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
          -- No confirmation mail to click: accounts are created by an officer
          -- who has already verified the person, so they start confirmed.
          -- This matches how the Supabase project was configured.
          now())
  returning users.id into v_id;

  return query
  select u.id, u.email, u.raw_user_meta_data, u.email_confirmed_at
    from sr_auth.users u
   where u.id = v_id;
end;
$fn$;

-- ── Change password ─────────────────────────────────────────────────────────
--  Serves both a user changing their own and an admin resetting one; the
--  caller decides which, and RLS on profiles governs who may reach the screen.
create or replace function sr_auth.change_password(
  p_user_id  uuid,
  p_password text
)
returns void
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
begin
  if p_password is null or length(p_password) < 6 then
    raise exception 'password must be at least 6 characters'
      using errcode = '22023';
  end if;

  update sr_auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf', 10)),
         updated_at         = now()
   where id = p_user_id;

  if not found then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
end;
$fn$;

-- ── Change email / update metadata ──────────────────────────────────────────
--  Mirrors supabase.auth.updateUser(UserAttributes(email:..., data:...)).
--  A null argument leaves that field alone, so either can be set on its own.
create or replace function sr_auth.update_user(
  p_user_id uuid,
  p_email   text  default null,
  p_meta    jsonb default null
)
returns table (
  id    uuid,
  email text,
  meta  jsonb
)
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
begin
  if p_email is not null
     and exists (select 1 from sr_auth.users u
                  where lower(u.email) = lower(trim(p_email))
                    and u.id <> p_user_id) then
    raise exception 'user_already_exists' using errcode = '23505';
  end if;

  return query
  update sr_auth.users u
     set email = coalesce(nullif(trim(p_email), ''), u.email),
         -- Merge rather than replace: updateUser(data:) only ever set a subset
         -- of the metadata, and replacing would silently drop the rest.
         raw_user_meta_data = case
           when p_meta is null then u.raw_user_meta_data
           else u.raw_user_meta_data || p_meta
         end,
         updated_at = now()
   where u.id = p_user_id
  returning u.id, u.email, u.raw_user_meta_data;
end;
$fn$;

-- ── Who am I ────────────────────────────────────────────────────────────────
--  Restores a session on app start from the stored user id.
create or replace function sr_auth.user_by_id(p_user_id uuid)
returns table (
  id                 uuid,
  email              text,
  raw_user_meta_data jsonb,
  email_confirmed_at timestamptz
)
language sql
security definer
stable
set search_path = sr_auth, public, extensions
as $fn$
  select u.id, u.email, u.raw_user_meta_data, u.email_confirmed_at
    from sr_auth.users u
   where u.id = p_user_id
     and u.email_confirmed_at is not null
     and (u.locked_until is null or u.locked_until <= now());
$fn$;

-- ── No backfill needed ──────────────────────────────────────────────────────
--  public.profiles.id is `REFERENCES sr_auth.users(id) ON DELETE CASCADE`, so a
--  profile cannot exist without its sr_auth.users row — the two are always in
--  step and there is nothing to reconcile.
--
--  Note where the fields actually live: profiles has no `email` and no `yard`
--  column. The email is sr_auth.users.email, and the yard travels in
--  raw_user_meta_data, which is why AuthUser exposes `meta`.

-- ── Grants ──────────────────────────────────────────────────────────────────
--  sign_in and sign_up must be callable before any identity exists, hence anon.
grant execute on function sr_auth.sign_in(text, text)            to anon, authenticated;
grant execute on function sr_auth.sign_up(text, text, jsonb)     to anon, authenticated;
grant execute on function sr_auth.change_password(uuid, text)    to authenticated;
grant execute on function sr_auth.update_user(uuid, text, jsonb) to authenticated;
grant execute on function sr_auth.user_by_id(uuid)               to anon, authenticated;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  Round-trips a throwaway account: sign_up, then the right password, then a
--  wrong one. Raises if either result is not what it should be, and always
--  removes the account. Expect the notice 'auth VERIFY passed'.
do $verify$
declare
  v_id uuid;
  v_n  int;
begin
  delete from sr_auth.users where email = 'verify.probe@local.invalid';

  -- 'officer', not a made-up 'probe': a trigger mirrors this metadata into
  -- public.profiles, whose profiles_role_check only accepts the real roles.
  -- With 'probe' the whole file failed here on a fresh database.
  select s.id into v_id
    from sr_auth.sign_up('verify.probe@local.invalid', 'probe-password-123',
                      '{"role":"officer"}'::jsonb) s;

  select count(*) into v_n
    from sr_auth.sign_in('verify.probe@local.invalid', 'probe-password-123');
  if v_n <> 1 then
    raise exception 'VERIFY FAILED: the correct password did not sign in';
  end if;

  select count(*) into v_n
    from sr_auth.sign_in('verify.probe@local.invalid', 'not-the-password');
  if v_n <> 0 then
    raise exception 'VERIFY FAILED: a wrong password signed in';
  end if;

  delete from sr_auth.users where id = v_id;
  raise notice 'auth VERIFY passed';
end
$verify$;

-- How many officers still need a password set by an admin.
select count(*) as accounts_without_password
from   sr_auth.users
where  encrypted_password is null;
