-- ============================================================================
--  Apply migrations 021 → 023 to a server that has 001 … 020.
--
--  ⚠️ THE ORDER MATTERS, and 018 at the end is not a typo.
--
--    021  dormancy: disable an account nobody has signed into
--    022  corrects 021 -- it read the WRONG COLUMN (see below)
--    023  password history: a password may not be reused
--    018  RE-APPLIED, because 023 overwrites the guard it installs
--    024  lets "forgot password" work again -- 018's guard broke it
--    025  only a yard SDDC/DDC may raise a disposal request
--    026  dormancy after 30 days, not 90
--    027  a directorate account carries no yard
--    028  a failed sign-in records the yard it targeted
--    029  a log row keeps the role its actor held that day
--    030  the committee round takes no bids
--    031  one committee round, only after the value is submitted
--
--  ⚠️ Why 018 must come last. Migration 018 wraps sr_auth.change_password so a
--  session may only change ITS OWN password: it renames the real body to
--  change_password_unchecked and puts a caller check in front. 023 does a
--  plain `create or replace function sr_auth.change_password`, which replaces
--  that wrapper and takes the check with it. Re-applying 018 re-wraps the new
--  body. Verified on the development database: after 023 alone the caller
--  guard was gone; after 018 both guards are present and layered.
--
--  ⚠️ 021 IS INCLUDED EVEN THOUGH 022 CORRECTS IT. 022 only replaces the two
--  functions that read the clock; 021 is what CREATES deactivated_reason,
--  deactivated_at and the depth function. Skipping it leaves 022 with nothing
--  to correct.
--
--  ⚠️ Expect 021 to disable accounts on the way through. That is 021's own
--  bug -- it reads profiles.last_seen_at, a PRESENCE heartbeat that signOut()
--  deliberately NULLs, so any account that signed out tidily looks unused.
--  022 runs next and re-enables every account 021 switched off whose real
--  clock (sr_auth.users.last_sign_in_at) says it is not dormant. Accounts ICT
--  disabled BY HAND are left alone: their reason is 'manual'.
--
--  Run as an administrator (the `postgres` role), NOT as yard_app:
--
--      psql -h 10.10.71.15 -U postgres -d Customs_SR_DB \
--           -v ON_ERROR_STOP=1 -f postgres/69_apply_021_to_023.sql
--
--  Every file is idempotent; running this twice is safe.
-- ============================================================================

\set ON_ERROR_STOP on
\echo ''
\echo '=== 021 dormancy ==================================================='
\i migrations/021_dormant_accounts_are_disabled.sql
\echo ''
\echo '=== 022 dormancy reads the right clock ============================='
\i migrations/022_dormancy_reads_the_right_clock.sql
\echo ''
\echo '=== 023 password history =========================================='
\i migrations/023_password_history_blocks_reuse.sql
\echo ''
\echo '=== 018 RE-APPLIED (023 overwrote its wrapper) ====================='
\i migrations/018_expired_password_locks_the_session.sql
\echo ''
\echo '=== 024 forgot-password works without a session ===================='
-- ⚠️ AFTER 018, because it looks for the change_password_unchecked that 018
-- creates. Run before it and the reset would be wired to the guarded
-- function it is trying to avoid.
\i migrations/024_reset_may_set_a_password_without_a_session.sql
\echo ''
\echo '=== 025 only yard admin sends disposal requests ================='
\i migrations/025_only_yard_admin_sends_disposal_requests.sql
\echo ''
\echo '=== 026 dormancy after 30 days =================================='
\i migrations/026_dormancy_after_30_days.sql
\echo ''
\echo '=== 027 directorates carry no yard ==============================='
\i migrations/027_directorates_do_not_belong_to_a_yard.sql
\echo ''
\echo '=== 028 failed sign-in records the target yard =================='
\i migrations/028_failed_login_records_the_yard.sql
\echo ''
\echo '=== 029 log rows keep the role of the day ========================'
\i migrations/029_audit_rows_keep_the_role_of_the_day.sql
\echo ''
\echo '=== 030 the committee round takes no bids ========================'
\i migrations/030_the_committee_round_takes_no_bids.sql
\echo ''
\echo '=== 031 one committee round, value first ========================='
\i migrations/031_one_committee_round_and_a_value_before_it.sql
\echo ''

-- ── Prove the end state, rather than trusting the order ─────────────────────
\echo '=== verification ==================================================='
do $$
declare
  v_wrapper  boolean;
  v_inner    boolean;
  v_clock    boolean;
  v_history  boolean;
begin
  -- The caller guard must be on the OUTER function...
  select position('app.current_user_id' in prosrc) > 0 into v_wrapper
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'sr_auth' and p.proname = 'change_password';

  -- ...and the reuse check on the inner one 018 renamed.
  select position('password_history' in prosrc) > 0 into v_inner
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'sr_auth' and p.proname = 'change_password_unchecked';

  -- Dormancy must read the sign-in clock, not the heartbeat.
  select position('last_sign_in_at' in prosrc) > 0 into v_clock
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'disable_dormant_accounts';

  select exists (select 1 from pg_tables
                  where schemaname = 'sr_auth' and tablename = 'password_history')
    into v_history;

  if not v_wrapper then
    raise exception
      'change_password has NO caller guard -- 018 was not re-applied after 023';
  end if;
  if not v_inner then
    raise exception
      'change_password_unchecked has no reuse check -- 023 did not survive';
  end if;
  if not v_clock then
    raise exception
      'dormancy still reads the heartbeat column -- 022 did not apply';
  end if;
  if not v_history then
    raise exception 'sr_auth.password_history is missing -- 023 did not apply';
  end if;

  -- ⚠️ And the reset must NOT be wired to the guarded function: it has no
  -- session to satisfy it. This is the check that would have caught the
  -- forgot-password regression.
  if not exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname = 'reset_password_for_identifier'
           and position('change_password_unchecked' in p.prosrc) > 0) then
    raise exception
      'the password reset calls the GUARDED setter -- forgot-password will '
      'fail with "You may only change your own password" (024 not applied)';
  end if;

  -- ⚠️ And a yard officer must not be able to raise a disposal request.
  if not exists (select 1 from pg_policies
                  where tablename = 'disposal_requests'
                    and policyname = 'disposal_requests_admin_only_write'
                    and permissive = 'RESTRICTIVE') then
    raise exception
      'disposal_requests has no RESTRICTIVE admin-only write policy -- a yard '
      'officer can still send a disposal request (025 not applied)';
  end if;

  -- ⚠️ And dormancy must be the 30-day rule, not the old 90.
  if public.account_dormant_after_days() <> 30 then
    raise exception
      'dormancy is still % days -- 026 was not applied',
      public.account_dormant_after_days();
  end if;

  -- ⚠️ And no directorate account may claim a yard.
  if exists (select 1 from public.profiles
              where role in ('ict','valuation','appeal','disposal','executive')
                and yard is not null) then
    raise exception
      'directorate accounts still carry a yard -- 027 was not applied';
  end if;

  raise notice 'OK: caller guard + reuse check layered, dormancy on the '
               'sign-in clock, history table present, disposal requests '
               'admin-only';
end $$;

-- What the dormancy rule would do right now, so nobody is surprised.
\echo ''
\echo '--- accounts currently inactive ------------------------------------'
select p.full_name, p.deactivated_reason, u.last_sign_in_at::date as last_sign_in
  from public.profiles p
  join sr_auth.users u on u.id = p.id
 where not p.is_active
 order by p.full_name;
