-- ============================================================================
--  Officer/Admin username support + username-or-email login + officer OTP flow
--  Run this once in the Supabase SQL editor.
--
--  Adds:
--   1. profiles.username        — unique (case-insensitive) login handle.
--   2. officer_signup_otps      — short-lived OTP store for admin-created
--                                 officers (service_role only).
--   3. email_for_login(text)    — resolves a username OR email to the auth
--                                 email, so the app can sign in with either.
--
--  Used together with the `admin-officers` Edge Function (service_role) which
--  creates the auth user, generates the random username/password and emails
--  the credentials.
-- ============================================================================

-- 1. ── Username column ──────────────────────────────────────────────────────
alter table public.profiles add column if not exists username text;

-- Case-insensitive uniqueness (only enforced for rows that have a usernameල්R).
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username))
  where username is not null;

-- 2. ── OTP store for admin-created officers ─────────────────────────────────
--    Holds the pending officer details + OTP until the admin verifies the code.
--    RLS is enabled with NO policies, so only the service_role key (used by the
--    Edge Function) can read/write it. The anon/authenticated keys cannot.
create table if not exists public.officer_signup_otps (
  email         text primary key,
  otp           text not null,
  full_name     text not null,
  badge_number  text,
  mobile_number text,
  yard          text,
  attempts      int  not null default 0,
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now()
);

alter table public.officer_signup_otps enable row level security;
-- (intentionally no policies — service_role bypasses RLS)

-- 3. ── Resolve a username OR email to the login email ───────────────────────
--    The login screen accepts a single identifier. If it looks like an email
--    we return it as-is; otherwise we look it up by username and return the
--    matching auth email. SECURITY DEFINER so it can read auth.users; granted
--    to anon because login happens before the user is authenticated.
create or replace function public.email_for_login(identifier text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  found_email text;
begin
  if identifier is null or length(trim(identifier)) = 0 then
    return null;
  end if;

  -- Looks like an email → use directly.
  if position('@' in identifier) > 0 then
    return trim(identifier);
  end if;

  select u.email
    into found_email
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(p.username) = lower(trim(identifier))
  limit 1;

  return found_email;
end;
$$;

grant execute on function public.email_for_login(text) to anon, authenticated;

-- Done.
