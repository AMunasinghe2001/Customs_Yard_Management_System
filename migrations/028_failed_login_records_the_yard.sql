-- ============================================================================
--  A failed sign-in should say WHICH yard the account belongs to.
--
--  ⚠️ `record_failed_login` inserted no `yard` at all, so every "Login failed"
--  row showed an em-dash in the Activity Log — including attempts against
--  yard officers and yard administrators, who very much do belong to a yard.
--  ICT reading the trail could not tell which office an attempt was aimed at.
--
--  The yard is knowable here: it is the yard on the PROFILE being attempted.
--  Not the attacker's — there is no session yet — but the target's, which is
--  the useful fact ("someone is guessing at Grey Line 2 passwords").
--
--  ⚠️ A DIRECTORATE account still records no yard, because it has none
--  (migration 027). The column is left null rather than filled with a
--  default, which is the whole point of 027.
--
--  Safe to re-run.
-- ============================================================================

create or replace function public.record_failed_login(p_identifier text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $fn$
declare
  v_email   text;
  v_user_id uuid;
  v_attempts int;
  v_locked  timestamptz;
  v_has_profile boolean;
  v_yard    text;
begin
  v_email := public.email_for_login(p_identifier);
  if v_email is null then
    v_email := lower(trim(p_identifier));
  end if;

  select u.id, u.failed_login_attempts, u.locked_until
    into v_user_id, v_attempts, v_locked
    from sr_auth.users u
   where lower(u.email) = lower(v_email);

  v_has_profile := v_user_id is not null
    and exists (select 1 from public.profiles p where p.id = v_user_id);

  -- ⚠️ The TARGET's yard, and only for an account that has one. A directorate
  -- profile carries null (migration 027) and must keep carrying null here.
  if v_has_profile then
    select p.yard into v_yard
      from public.profiles p
     where p.id = v_user_id
       and p.role in ('officer', 'admin');
  end if;

  insert into public.audit_logs (user_id, yard, action, entity_type, entity_id,
                                 details)
  values (case when v_has_profile then v_user_id else null end,
          v_yard,
          case when v_locked is not null
               then 'Login failed — account locked'
               else 'Login failed' end,
          'auth',
          coalesce(v_user_id::text, 'unknown'),
          jsonb_build_object(
            'attempts', coalesce(v_attempts, 0),
            'locked_until', v_locked,
            'account_exists', v_user_id is not null,
            'profile_exists', v_has_profile));
end;
$fn$;


-- ── Verify ──────────────────────────────────────────────────────────────────
--
-- ⚠️ Rows are matched by ENTITY_ID, not by "the newest row". Both inserts land
-- in the same transaction with the same clock, so `order by created_at desc
-- limit 1` read the officer's row back for the directorate check and reported
-- a failure that was not real.
do $$
declare
  v_officer_email text;
  v_officer_id    uuid;
  v_officer_yard  text;
  v_dir_email     text;
  v_dir_id        uuid;
  v_logged_yard   text;
begin
  select u.email, p.id, p.yard into v_officer_email, v_officer_id, v_officer_yard
    from public.profiles p join sr_auth.users u on u.id = p.id
   where p.role in ('officer','admin') and p.yard is not null limit 1;
  select u.email, p.id into v_dir_email, v_dir_id
    from public.profiles p join sr_auth.users u on u.id = p.id
   where p.role in ('ict','valuation','appeal','disposal','executive') limit 1;

  if v_officer_email is null then
    raise notice 'no yard account to verify with - skipped';
    return;
  end if;

  -- A yard account's failure records its yard.
  perform public.record_failed_login(v_officer_email);
  select yard into v_logged_yard
    from public.audit_logs
   where action like 'Login failed%'
     and entity_id = v_officer_id::text
   order by created_at desc limit 1;
  if v_logged_yard is distinct from v_officer_yard then
    raise exception
      'a yard officer''s failed login recorded yard %, expected %',
      coalesce(v_logged_yard,'NULL'), v_officer_yard;
  end if;

  -- A directorate account's failure records none.
  if v_dir_email is not null then
    perform public.record_failed_login(v_dir_email);
    select yard into v_logged_yard
      from public.audit_logs
     where action like 'Login failed%'
       and entity_id = v_dir_id::text
     order by created_at desc limit 1;
    if v_logged_yard is not null then
      raise exception
        'a directorate failed login recorded yard % - it has none',
        v_logged_yard;
    end if;
  end if;

  -- ⚠️ These two rows STAY in the trail. audit_logs is append-only by
  -- trigger, so the check cannot tidy up after itself — and a verification
  -- that could delete audit rows would be a worse thing to own than two
  -- self-explanatory entries. They are marked so nobody reads them as real
  -- attempts.
  insert into public.audit_logs (user_id, action, entity_type, entity_id,
                                 details)
  values (null, 'Migration 028 self-check', 'auth', 'migration',
          jsonb_build_object(
            'note', 'The two Login failed rows at this timestamp were written '
                    'by migration 028 verifying itself, not by a real '
                    'sign-in attempt.'));

  raise notice
    'verified: a yard account''s failure records its yard, a directorate''s '
    'records none (2 self-check rows left in the trail, marked)';
end $$;
