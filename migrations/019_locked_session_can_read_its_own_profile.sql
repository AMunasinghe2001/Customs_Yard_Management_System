-- ============================================================================
-- A locked session must still be able to read ITS OWN profile row.
--
-- ⚠️ Migration 018 locked an expired password out of everything by making
-- sr_auth.uid() null and sr_auth.role() 'anon'. That was too complete: the app
-- discovers that a password has expired by READING THE PROFILE
-- (ProfileModel.isPasswordExpired is computed from password_updated_at), and
-- the profile is exactly what 018 stopped it from reading.
--
-- The result was a dead end. finishOtpLogin signs in, then does
--
--   supabase.from('profiles').select().eq('id', user.id).single()
--
-- which came back with ZERO rows, so `.single()` threw and the login screen
-- showed "Sign in failed. Please try again." The officer never reached the
-- password-change dialog that 018 exists to force them into, and the code
-- they had just spent was gone. Verified against the live database: the
-- Disposal DC account returned 0 rows for its own id.
--
-- ⚠️ The fix is ONE row, not a relaxation. This policy matches a single
-- profile -- the caller's own -- and only while the session is flagged
-- expired. It is written against `app.current_user_id` rather than
-- sr_auth.uid(), because sr_auth.uid() is precisely what is null here; that is the
-- same reasoning that lets sr_auth.change_password keep working.
--
-- Everything else stays shut: other people's profiles, packages, warehouses,
-- tender sales. The session can see who it is and that its password has
-- expired, and it can change that password. Nothing more.
--
-- Safe to re-run.
-- ============================================================================

-- The caller's REAL id, regardless of the expiry flag.
--
-- ⚠️ Deliberately separate from sr_auth.uid(). sr_auth.uid() answers "who may act",
-- which is nobody while a password is expired; this answers "whose session is
-- this", which still has a truthful answer. Keeping them apart is what stops
-- a future edit from accidentally re-opening the lock by widening one of them.
create or replace function sr_auth.session_user_id()
returns uuid
language sql
stable
as $fn$
  select nullif(current_setting('app.current_user_id', true), '')::uuid;
$fn$;

comment on function sr_auth.session_user_id() is
  'The signed-in user id, even when the password has expired and sr_auth.uid() '
  'is therefore null. For the narrow set of things a locked session must '
  'still do: read its own profile, and change its own password.';

-- Only while locked, and only your own row.
--
-- ⚠️ Scoped with `password_expired = 'on'` so it adds nothing for a healthy
-- session -- those are already covered by "Users can view own profile". A
-- policy that applied always would be a second, parallel route to the same
-- row, and the day someone edits one they would not think to check the other.
drop policy if exists profiles_expired_self_read on public.profiles;
create policy profiles_expired_self_read on public.profiles
  for select
  using (
    current_setting('app.password_expired', true) = 'on'
    and id = sr_auth.session_user_id()
  );

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  v_id    uuid;
  v_seen  int;
  v_other int;
begin
  select id into v_id from public.profiles limit 1;
  if v_id is null then
    return;  -- empty database (a fresh server); nothing to assert against
  end if;

  -- Stand up a locked session for that user.
  perform set_config('app.current_user_id', v_id::text, false);
  perform set_config('app.current_role', 'authenticated', false);
  perform set_config('app.password_expired', 'on', false);

  -- The lock must still be in force.
  if sr_auth.uid() is not null or sr_auth.role() <> 'anon' then
    raise exception 'migration 018 is not in effect; apply it first';
  end if;

  -- ⚠️ These run as the table OWNER, which bypasses RLS, so they cannot
  -- prove the policy works -- only that the pieces it needs are right. The
  -- real check is the yard_app session in the migration header, which
  -- returned 1 own row and 0 of everything else.
  if sr_auth.session_user_id() <> v_id then
    raise exception
      'sr_auth.session_user_id() must survive the expiry flag, or a locked '
      'session cannot find out why it is locked';
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'profiles'
                    and policyname = 'profiles_expired_self_read') then
    raise exception 'profiles_expired_self_read was not created';
  end if;

  -- Leave the session clean.
  perform set_config('app.current_user_id', '', false);
  perform set_config('app.current_role', '', false);
  perform set_config('app.password_expired', 'off', false);
end $$;
