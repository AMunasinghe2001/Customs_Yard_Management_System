-- ============================================================================
--  Dormancy: 90 days → 30.
--
--  An account nobody has signed into for 30 days is disabled. ICT can turn it
--  back on (see reactivate_account, migration 022).
--
--  ⚠️ This is now DECOUPLED from the 90-day password rotation. The two used to
--  share a number, and the comment on the old function said so — but they
--  answer different questions: "has this password gone stale" and "is anyone
--  still using this account". A dormant account is disabled, not merely asked
--  to rotate, so a shorter window is the safer one.
--
--  ⚠️ Expect this to disable accounts on the way through: anything last signed
--  into 31-90 days ago was inside the old window and is outside the new one.
--  The file reports exactly which, rather than leaving it to be discovered
--  when somebody cannot sign in.
--
--  Safe to re-run.
-- ============================================================================

create or replace function public.account_dormant_after_days()
returns integer language sql immutable as $fn$ select 30 $fn$;

comment on function public.account_dormant_after_days() is
  'Days of no sign-in before an account is disabled. Deliberately shorter '
  'than the 90-day password rotation: a stale password is asked to change, '
  'an unused account is switched off.';


-- ── Report what this change catches, before it catches it ───────────────────
do $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select p.full_name, p.role, u.last_sign_in_at::date as last_sign_in
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.is_active
       and coalesce(u.last_sign_in_at, p.created_at)
             < now() - make_interval(days => public.account_dormant_after_days())
     order by p.full_name
  loop
    raise notice 'now dormant: % (%) - last signed in %',
      r.full_name, r.role, coalesce(r.last_sign_in::text, 'never');
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    raise notice 'no active account is dormant under the 30-day rule';
  end if;
end $$;


-- ── Verify the boundary moved ───────────────────────────────────────────────
do $$
declare
  v_id uuid;
  v_was timestamptz;
begin
  select p.id, u.last_sign_in_at into v_id, v_was
    from public.profiles p join auth.users u on u.id = p.id limit 1;
  if v_id is null then
    raise notice 'no accounts to verify with - skipped';
    return;
  end if;

  -- 31 days idle must now be dormant; it was not under the 90-day rule.
  update auth.users set last_sign_in_at = now() - interval '31 days'
   where id = v_id;
  if not public.account_is_dormant(v_id) then
    update auth.users set last_sign_in_at = v_was where id = v_id;
    raise exception '31 days idle is not dormant - the rule is still 90 days';
  end if;

  -- 29 days must NOT be.
  update auth.users set last_sign_in_at = now() - interval '29 days'
   where id = v_id;
  if public.account_is_dormant(v_id) then
    update auth.users set last_sign_in_at = v_was where id = v_id;
    raise exception '29 days idle reads as dormant - the window is too short';
  end if;

  update auth.users set last_sign_in_at = v_was where id = v_id;
  raise notice 'verified: dormant after 30 days, not before';
end $$;
