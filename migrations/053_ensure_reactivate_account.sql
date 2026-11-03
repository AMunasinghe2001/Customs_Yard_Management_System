-- ============================================================================
--  053 · Ensure reactivate_account resets the 30-day dormancy clock
--
--  When an account is reactivated by ICT:
--    1. is_active is set to true
--    2. deactivated_reason and deactivated_at are cleared to NULL
--    3. sr_auth.users.last_sign_in_at is set to now() (restarting the 30-day window)
--
--  This ensures that when any user signs in and triggers disable_dormant_accounts(),
--  the reactivated account is NOT immediately deactivated back to DORMANT.
-- ============================================================================

create or replace function public.reactivate_account(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
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

  update sr_auth.users
     set last_sign_in_at = now()
   where id = p_id;
end;
$fn$;

revoke all on function public.reactivate_account(uuid) from public;
grant execute on function public.reactivate_account(uuid) to authenticated;

