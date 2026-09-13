-- ============================================================================
--  Dormancy must read auth.users.last_sign_in_at, not profiles.last_seen_at.
--
--  ⚠️ Migration 021 got this WRONG, and the error disabled live accounts that
--  were in daily use.
--
--  `profiles.last_seen_at` is a PRESENCE heartbeat, not a record of last use.
--  signOut() and setUserOffline() both set it to NULL on purpose -- the online
--  list is judged by a fresh heartbeat, so leaving a recent value there would
--  keep somebody showing as "online" for ~90s after they left. Nulling it is
--  instant-offline, and it is the correct behaviour for what that column is
--  for.
--
--  The consequence for 021 was that ANY account whose holder had signed out
--  cleanly -- the normal way to leave the app -- had a null last_seen_at, fell
--  back to `created_at`, and was disabled the moment the account was more than
--  90 days old. Observed directly: an SDDC account signed into minutes earlier
--  read as dormant, because it was created in March and its heartbeat was
--  nulled on the way out.
--
--  `auth.users.last_sign_in_at` is the right clock. auth.sign_in sets it on
--  every successful sign-in and nothing clears it, so it means exactly what
--  the rule needs: when did this account last actually get used.
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. Read the sign-in clock ───────────────────────────────────────────────
--
-- ⚠️ Still coalesced to created_at, and that part was right: an account that
-- has been provisioned but NEVER signed in has a null last_sign_in_at, and
-- that is dormancy too -- it is the unused-account case the rule exists for.
-- The difference is that a null now means "never used", not "signed out
-- tidily".
create or replace function public.account_is_dormant(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(u.last_sign_in_at, p.created_at)
           < now() - make_interval(days => public.account_dormant_after_days())
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.id = p_id;
$fn$;


-- ── 2. The sweep, on the same clock ─────────────────────────────────────────
create or replace function public.disable_dormant_accounts()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_count integer;
begin
  with disabled as (
    update public.profiles p
       set is_active = false,
           deactivated_reason = 'dormant',
           deactivated_at = now(),
           updated_at = now()
      from auth.users u
     where u.id = p.id
       and p.is_active
       and coalesce(u.last_sign_in_at, p.created_at)
             < now() - make_interval(days => public.account_dormant_after_days())
    returning 1
  )
  select count(*) into v_count from disabled;
  return v_count;
end;
$fn$;


-- ── 3. Reactivation resets the clock that is actually read ──────────────────
--
-- ⚠️ 021 reset last_seen_at, which is no longer the column the rule consults
-- -- so waking an account would NOT have stopped the next sweep disabling it
-- again. Reset last_sign_in_at instead: the account has been deliberately
-- restored, and the 90 days start from that decision.
create or replace function public.reactivate_account(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not public.auth_user_is_ict() then
    raise exception 'Only the ICT Directorate can reactivate an account'
      using errcode = 'insufficient_privilege';
  end if;

  update public.profiles
     set is_active = true,
         deactivated_reason = null,
         deactivated_at = null,
         updated_at = now()
   where id = p_id;

  update auth.users
     set last_sign_in_at = now()
   where id = p_id;
end;
$fn$;

revoke all on function public.reactivate_account(uuid) from public;
grant execute on function public.reactivate_account(uuid) to authenticated;


-- ── 4. Undo 021's false positives ───────────────────────────────────────────
--
-- Every account 021 switched off is re-enabled if the real clock says it is
-- not dormant. An account ICT disabled BY HAND is left alone -- its reason is
-- 'manual', and that was somebody's decision, not this bug.
do $$
declare
  r record;
begin
  for r in select p.id, p.full_name
             from public.profiles p
             join auth.users u on u.id = p.id
            where not p.is_active
              and p.deactivated_reason = 'dormant'
              and coalesce(u.last_sign_in_at, p.created_at)
                    >= now() - make_interval(
                         days => public.account_dormant_after_days())
  loop
    update public.profiles
       set is_active = true, deactivated_reason = null, deactivated_at = null,
           updated_at = now()
     where id = r.id;
    raise notice 'restored % (021 disabled it on the heartbeat column)',
      r.full_name;
  end loop;
end $$;


-- ── 5. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_id uuid;
begin
  -- ⚠️ The exact case 021 got wrong: signed in just now, heartbeat nulled by
  -- a clean sign-out, account older than the dormancy window.
  select p.id into v_id
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.created_at < now() - interval '91 days'
   limit 1;

  if v_id is null then
    raise notice 'no account old enough to test with - skipping';
    return;
  end if;

  update auth.users set last_sign_in_at = now() where id = v_id;
  update public.profiles set last_seen_at = null where id = v_id;

  if public.account_is_dormant(v_id) then
    raise exception
      'an account signed into just now still reads as dormant - the rule is '
      'back on the heartbeat column';
  end if;

  -- And a genuinely unused one is still caught.
  update auth.users set last_sign_in_at = now() - interval '91 days'
   where id = v_id;
  if not public.account_is_dormant(v_id) then
    raise exception 'an account unused for 91 days is not caught';
  end if;

  update auth.users set last_sign_in_at = now() where id = v_id;
  raise notice 'dormancy now reads last_sign_in_at - verified';
end $$;
