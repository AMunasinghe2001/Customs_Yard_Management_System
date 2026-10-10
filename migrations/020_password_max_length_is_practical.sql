-- ============================================================================
-- The password maximum becomes 24, from 128.
--
-- ⚠️ 128 was a ceiling on what the ALGORITHM can hash, not on what a person
-- can type. bcrypt stops at 72 bytes and the rule was set above even that, so
-- it could never fire: an officer would have had to enter 129 characters
-- correctly, twice, at a shared desk. A limit nobody can reach is not a
-- limit — it only made the requirement line read as noise beside the rules
-- that do matter.
--
-- 24 rather than 20 so a three-word passphrase still fits. Passphrases are
-- the easiest strong passwords to remember, and a 20-character cap quietly
-- rules them out while doing nothing for security.
--
-- ⚠️ Must move together with PasswordPolicy.maxLength in
-- lib/core/security_policy.dart. Those two numbers are the same rule written
-- twice; when they drift, the form promises what the server refuses — which
-- is exactly what the "Minimum 8 characters" hint was doing against this
-- function's 12.
--
-- ⚠️ No existing account is affected. Passwords are stored as bcrypt hashes
-- ($2a$), so their original length is unknowable and unchecked at sign-in —
-- this rule applies only when a NEW password is set. Nobody is locked out by
-- it; someone whose current password is longer than 24 simply cannot re-enter
-- that same one on their next rotation.
--
-- Safe to re-run.
-- ============================================================================

create or replace function public.password_policy_violation(p_password text)
returns text
language plpgsql
immutable
as $function$
begin
  if p_password is null or length(p_password) < 12 then
    return 'Password must be at least 12 characters.';
  end if;
  if length(p_password) > 24 then
    -- A practical ceiling, not bcrypt's. See the header: the old 128 sat
    -- above even bcrypt's 72-byte limit and could never be reached.
    return 'Password must be at most 24 characters.';
  end if;
  if p_password !~ '[A-Z]' then
    return 'Password must contain an uppercase letter.';
  end if;
  if p_password !~ '[a-z]' then
    return 'Password must contain a lowercase letter.';
  end if;
  if p_password !~ '[0-9]' then
    return 'Password must contain a number.';
  end if;
  if p_password !~ '[^A-Za-z0-9]' then
    return 'Password must contain a special character.';
  end if;
  -- The handful that a dictionary attack tries first. Not a substitute for a
  -- real breach list, but it costs nothing and stops the obvious ones.
  if lower(p_password) ~ '(password|passw0rd|welcome|customs|qwerty|admin123|letmein|12345678)' then
    return 'Password contains a commonly used word.';
  end if;
  return null;
end;
$function$;

-- ── Verification ────────────────────────────────────────────────────────────
do $$
begin
  -- The boundary itself is accepted.
  if public.password_policy_violation('Redwood#Harbor47x12345aA') is not null then
    raise exception '24 characters must be accepted, got: %',
      public.password_policy_violation('Redwood#Harbor47x12345aA');
  end if;

  -- One over is not.
  if public.password_policy_violation('Redwood#Harbor47x12345aAb') is null then
    raise exception '25 characters must be rejected';
  end if;

  -- And the message says which end was wrong, so the app can show the same
  -- thing the officer sees in the checklist.
  if public.password_policy_violation('Redwood#Harbor47x12345aAb')
       not like '%at most 24%' then
    raise exception 'the message must name the maximum';
  end if;

  -- The lower bound and the character classes are untouched.
  if public.password_policy_violation('Short1!') is null then
    raise exception 'the 12-character minimum was lost';
  end if;
  if public.password_policy_violation('alllowercase123!') is null then
    raise exception 'the uppercase rule was lost';
  end if;
  if public.password_policy_violation('Password1234!') is null then
    raise exception 'the common-word rule was lost';
  end if;
end $$;
