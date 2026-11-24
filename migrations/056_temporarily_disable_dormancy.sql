-- ============================================================================
--  056_temporarily_disable_dormancy.sql
--
--  Temporarily disable automatic dormancy and inactivity deactivation per admin request.
--  Accounts will no longer be marked dormant or deactivated regardless of how long
--  they have not logged in.
--
--  Safe to re-run and easily reversible.
-- ============================================================================

-- Set dormant window to a very large number of days (e.g., 100 years / ~36500 days)
create or replace function public.account_dormant_after_days()
returns integer language sql immutable as $fn$ select 36500 $fn$;

comment on function public.account_dormant_after_days() is
  'Temporarily disabled: set to 36500 days (~100 years) so accounts do not auto-deactivate due to inactivity.';

-- account_is_dormant returns false while feature is disabled
create or replace function public.account_is_dormant(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $fn$
  select false;
$fn$;

comment on function public.account_is_dormant(uuid) is
  'Temporarily disabled: always returns false so no account is treated as dormant.';

-- disable_dormant_accounts becomes a safe no-op
create or replace function public.disable_dormant_accounts()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  -- Dormancy sweeps are temporarily disabled.
  return 0;
end;
$fn$;

comment on function public.disable_dormant_accounts() is
  'Temporarily disabled: returns 0 without deactivating any accounts.';

-- Reactivate any accounts that were previously deactivated with reason 'dormant'
update public.profiles
   set is_active = true,
       deactivated_reason = null,
       deactivated_at = null,
       updated_at = now()
 where deactivated_reason = 'dormant';

