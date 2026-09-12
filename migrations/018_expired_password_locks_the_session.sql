-- ============================================================================
-- An expired password now blocks everything EXCEPT changing that password,
-- and the database is what enforces it.
--
-- Before this, the 90-day rotation rule lived entirely in the Flutter client:
-- the login screens hid "Skip for now" once a password was expired. That is a
-- hint, not a rule. Anything that talks to the database directly -- a second
-- copy of the app, a psql session, a modified build -- ignored it completely.
--
-- ⚠️ Rejecting the sign-in is NOT the fix, which is why this took a different
-- shape. A password is changed from INSIDE a signed-in session
-- (auth.change_password runs after auth.sign_in), so an account whose sign-in
-- is refused can never reach the screen that would fix it: the rule would
-- permanently lock out exactly the people it is meant to prompt. The account
-- would need ICT to reset it, turning a routine 90-day prompt into a support
-- ticket for every directorate.
--
-- So: the sign-in SUCCEEDS, and lands in a state where the only thing that
-- works is changing the password.
--
-- ── How ─────────────────────────────────────────────────────────────────────
--
-- `auth.uid()` is the root of the whole authorization model: all 132 RLS
-- policies in `public` are written in terms of it. If it returns NULL the user
-- is, to every policy, signed out -- no yard, no packages, no profile. That is
-- precisely the state we want an expired password to be in.
--
-- ⚠️ The age is NOT looked up inside auth.uid(). It is called once per policy
-- per row, so a `select ... from profiles` in its body would add a lookup to
-- every row of every query in the app. Instead the verdict is computed ONCE,
-- when the connection announces who it is, and parked in a session variable
-- that auth.uid() reads for free.
--
-- ⚠️ auth.change_password keeps working because it is SECURITY DEFINER and
-- takes the user id as an ARGUMENT -- it never calls auth.uid(). That is what
-- makes the one permitted action possible from inside the locked state. It is
-- also why this migration tightens that function: taking an id as a parameter
-- means it must verify the caller owns it, or a locked session could change
-- somebody else's password.
--
-- Safe to re-run.
-- ============================================================================

-- ── 1. The verdict, computed once per session ───────────────────────────────
--
-- SECURITY DEFINER: a session that is about to be locked out still has to be
-- able to ask whether it is locked out.
create or replace function auth.password_is_expired(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = auth, public
as $fn$
  select coalesce(
    (select (now() - coalesce(p.password_updated_at, p.created_at))
              > interval '90 days'
       from public.profiles p
      where p.id = p_user_id),
    false)  -- no profile row: not this rule's business to decide
$fn$;

revoke all on function auth.password_is_expired(uuid) from public;
grant execute on function auth.password_is_expired(uuid) to public;

-- ── 2. Announcing the session sets the flag ─────────────────────────────────
--
-- The client calls this instead of setting app.current_user_id by hand, so
-- the CLIENT cannot choose its own answer: it supplies who it is, and the
-- database decides whether that identity is still usable.
create or replace function auth.begin_session(p_user_id text, p_role text)
returns void
language plpgsql
security definer
set search_path = auth, public
as $fn$
declare
  v_id      uuid;
  v_expired boolean := false;
begin
  v_id := nullif(trim(coalesce(p_user_id, '')), '')::uuid;
  if v_id is not null then
    v_expired := auth.password_is_expired(v_id);
  end if;

  -- Always set all three, and never conditionally: a pooled connection is
  -- reused, so a variable left over from the previous occupant is how one
  -- user inherits another's state.
  perform set_config('app.current_user_id', coalesce(v_id::text, ''), false);
  perform set_config('app.current_role', coalesce(p_role, 'anon'), false);
  perform set_config('app.password_expired', case when v_expired then 'on' else 'off' end, false);
end;
$fn$;

revoke all on function auth.begin_session(text, text) from public;
grant execute on function auth.begin_session(text, text) to public;

-- ── 3. auth.uid() honours the flag ──────────────────────────────────────────
--
-- ⚠️ Still a one-line, STABLE, no-table-access function. It reads two session
-- variables instead of one; it does not become a query. Every policy that
-- calls it keeps the same cost.
create or replace function auth.uid()
returns uuid
language sql
stable
as $fn$
  select case
           when current_setting('app.password_expired', true) = 'on' then null
           else nullif(current_setting('app.current_user_id', true), '')::uuid
         end;
$fn$;

-- ── 3b. auth.role() honours it too ──────────────────────────────────────────
--
-- ⚠️ auth.uid() is NOT the only root. 13 policies are written against
-- auth.role() instead -- "Officers can view all packages" is simply
-- `auth.role() = 'authenticated'` -- and that function reads
-- app.current_role, which the flag above does not touch. Verified the hard
-- way: with only auth.uid() gated, a locked session still read all 176
-- packages and all 320 forfeited packages. An expired password has to look
-- like 'anon' to these policies for the lock to mean anything.
create or replace function auth.role()
returns text
language sql
stable
as $fn$
  select case
    when current_setting('app.password_expired', true) = 'on' then 'anon'
    else coalesce(
      nullif(current_setting('app.current_role', true), ''),
      case
        when nullif(current_setting('app.current_user_id', true), '') is null
          then 'anon'
        else 'authenticated'
      end
    )
  end;
$fn$;

-- ── 4. The one action that must still work ──────────────────────────────────
--
-- ⚠️ Also the one hole this opens. auth.change_password takes the user id as
-- an argument and is SECURITY DEFINER, so before this it would change ANY
-- user's password for any caller who knew their id -- and a locked session is
-- exactly a caller with a reason to try. The real identity is
-- app.current_user_id (the flag hides it from auth.uid(), but it is still
-- there), so the function can insist the target is the caller.
-- ⚠️ Order matters: the original body is copied to
-- auth.change_password_unchecked FIRST, then change_password is replaced by a
-- wrapper that calls it. Doing it the other way round would copy the wrapper
-- into the unchecked function and produce infinite recursion.
do $$
declare
  body text;
  src  text;
begin
  -- Already done? The wrapper names the session variable; the original does
  -- not. That is the marker, so re-running changes nothing.
  select pg_get_functiondef(oid) into body
    from pg_proc
   where proname = 'change_password' and pronamespace = 'auth'::regnamespace;

  -- ⚠️ Guarded, not asserted. auth.change_password is not defined in
  -- 01_auth_and_session.sql or anywhere else in postgres/ -- it was added to
  -- the running database by hand, like the views postgres/23 and /32 build.
  -- So on the fresh database 02_schema.sql stands up it does not exist yet,
  -- and failing here would break the one file that has to work. The lock
  -- itself (sections 1-3) is already in place by this point; only the
  -- caller-owns-the-account check on a function that is not there yet is
  -- skipped.
  if body is null then
    raise notice 'auth.change_password not present; skipping its guard';
    return;
  end if;
  if body like '%app.current_user_id%' then
    return;
  end if;

  -- Copy the CURRENT definition under the new name, renaming only the
  -- function itself. The policy check, the "must differ" rule and the bcrypt
  -- cost travel with it verbatim — retyping them is how two copies drift.
  src := replace(body,
                 'FUNCTION auth.change_password(',
                 'FUNCTION auth.change_password_unchecked(');
  if src = body then
    raise exception 'could not rename the body; definition shape changed';
  end if;
  execute src;

  execute 'revoke all on function auth.change_password_unchecked(uuid, text) from public';

  -- Now the guarded front door.
  execute $ddl$
    create or replace function auth.change_password(p_user_id uuid, p_password text)
    returns void
    language plpgsql
    security definer
    set search_path = auth, public
    as $body$
    declare
      v_caller uuid;
    begin
      -- ⚠️ The caller's REAL id, read straight from the session variable
      -- rather than through auth.uid() -- which is null precisely when this
      -- function is most needed, because the password has expired.
      v_caller := nullif(current_setting('app.current_user_id', true), '')::uuid;

      if v_caller is null or v_caller <> p_user_id then
        raise exception 'You may only change your own password.'
          using errcode = '42501';
      end if;

      perform auth.change_password_unchecked(p_user_id, p_password);
    end;
    $body$;
  $ddl$;
end $$;

-- ── 5. Verification ─────────────────────────────────────────────────────────
do $$
declare
  v_uid uuid;
begin
  -- A fresh session with no flag set must behave exactly as before.
  perform set_config('app.current_user_id', '', false);
  perform set_config('app.password_expired', '', false);
  if auth.uid() is not null then
    raise exception 'auth.uid() must be null when signed out';
  end if;

  -- A normal session sees its id.
  perform set_config('app.current_user_id',
                     '11111111-1111-1111-1111-111111111111', false);
  perform set_config('app.password_expired', 'off', false);
  if auth.uid() is null then
    raise exception 'auth.uid() must return the id of a healthy session';
  end if;

  -- An expired one is, to every policy, nobody.
  perform set_config('app.password_expired', 'on', false);
  if auth.uid() is not null then
    raise exception
      'an expired password must make auth.uid() null, or the 132 RLS '
      'policies keep letting the session read';
  end if;

  -- ⚠️ And the OTHER root. Gating auth.uid() alone left a locked session
  -- reading every package in the database, because those policies ask
  -- auth.role() instead.
  perform set_config('app.current_role', 'authenticated', false);
  perform set_config('app.password_expired', 'on', false);
  if auth.role() <> 'anon' then
    raise exception
      'an expired password must read as anon, or the 13 auth.role() '
      'policies keep letting the session read';
  end if;

  perform set_config('app.password_expired', 'off', false);
  if auth.role() <> 'authenticated' then
    raise exception 'a healthy session must keep its role';
  end if;

  -- Leave the session clean.
  perform set_config('app.current_user_id', '', false);
  perform set_config('app.current_role', '', false);
  perform set_config('app.password_expired', 'off', false);
end $$;
