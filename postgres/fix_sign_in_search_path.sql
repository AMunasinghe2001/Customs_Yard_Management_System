-- ============================================================================
--  FIX: `function crypt(text, text) does not exist` at the sign-in screen.
--
--  ⚠️ RUN THIS IN THE SUPABASE SQL EDITOR (Dashboard -> SQL Editor).
--  It cannot be run by the app's `yard_app` account -- changing a function's
--  settings requires its OWNER, and yard_app deliberately owns nothing.
--
--  WHY IT IS NEEDED
--  ----------------
--  pgcrypto lives in the `extensions` schema on Supabase, not in `public`.
--  A function's own `search_path` wins over the session's, so every function
--  that reaches `crypt()` must name `extensions`.
--
--  `sr_auth.sign_in_any_device` and `sr_auth.sign_in_before_flush` are not
--  written as `create function` anywhere -- migrations 032 and 047 RENAME
--  `sr_auth.sign_in` into them. A rename carries the function's stored
--  settings across unchanged, so both inherited the search_path that
--  `sign_in` had ON THE DAY THIS DATABASE WAS BUILT -- which was before
--  `extensions` was added to the source.
--
--  ⚠️ And each rename sits behind an `if not exists` guard, so it runs
--  exactly ONCE, on first build. Re-running the migrations could therefore
--  never correct them: the guard skips, and the stale setting survives.
--  That is why the login kept failing on a database where every .sql file
--  looked correct and a freshly built database tested clean.
--
--  `sign_in` itself was re-created by a later file, so it picked the fix up
--  and looks right -- but it only delegates; the bcrypt compare happens two
--  calls down, in the stale pair.
--
--  Migrations 032 and 047 now re-assert this on every run (outside the
--  guard), so a future install keeps it correct. This file repairs the
--  database that is already in the broken state.
--
--  Safe to run more than once, and safe on the office/local servers: a
--  schema named in search_path that does not exist is simply ignored.
-- ============================================================================

alter function sr_auth.sign_in_any_device(text, text)
  set search_path = sr_auth, public, extensions;

alter function sr_auth.sign_in_before_flush(text, text)
  set search_path = sr_auth, public, extensions;

-- ---------------------------------------------------------------------------
-- Verify: every function in the chain must name `extensions`.
-- ---------------------------------------------------------------------------
do $verify$
declare
  r      record;
  v_bad  text := '';
begin
  for r in
    select p.proname,
           coalesce(array_to_string(p.proconfig, ' | '), '(none)') as cfg
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'sr_auth'
       and p.proname in ('sign_in', 'sign_in_any_device',
                         'sign_in_before_flush', 'sign_up',
                         'change_password')
  loop
    if position('extensions' in r.cfg) = 0 then
      v_bad := v_bad || ' ' || r.proname;
    end if;
    raise notice '  %-22s %s', r.proname, r.cfg;
  end loop;

  if v_bad <> '' then
    raise exception 'still missing `extensions`:%', v_bad;
  end if;
  raise notice 'PASS: the whole sign-in chain can reach pgcrypto';
end $verify$;
