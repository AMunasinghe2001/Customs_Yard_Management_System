-- ============================================================================
--  Reissue a directorate username and password as one database transaction.
--
--  The old client path changed the password and username in two separate
--  requests. If either request failed, the credentials in the email could
--  describe a different state from the account in the database.
-- ============================================================================

create or replace function public.reset_directorate_credentials(
  p_profile_id uuid,
  p_username   text,
  p_password   text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $fn$
declare
  v_email text;
  v_role  text;
begin
  if not public.auth_user_is_ict() then
    raise exception 'Only the ICT Directorate may reissue directorate credentials.'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_username), '') is null then
    raise exception 'A username is required.' using errcode = '22023';
  end if;

  select u.email, p.role
    into v_email, v_role
    from public.profiles p
    join sr_auth.users u on u.id = p.id
   where p.id = p_profile_id
   for update of p;

  if v_email is null then
    raise exception 'Directorate account was not found.' using errcode = 'P0002';
  end if;

  if v_role not in ('disposal', 'appeal', 'valuation', 'executive', 'ict') then
    raise exception 'This is not a directorate account.' using errcode = '22023';
  end if;

  -- Reuse the established reset setter so password policy and password
  -- history remain in one place. The profile update below is in this same
  -- transaction, so the emailed pair can never be half-applied.
  perform public.reset_password_for_identifier(v_email, p_password);

  update public.profiles
     set username = btrim(p_username)
   where id = p_profile_id;
end;
$fn$;

grant execute on function public.reset_directorate_credentials(uuid, text, text)
  to authenticated;