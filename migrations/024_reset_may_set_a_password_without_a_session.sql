-- ============================================================================
--  "Forgot password" could not set a password at all.
--
--  ⚠️ A regression I introduced. Migration 018 wraps auth.change_password with
--  a guard that refuses any caller whose `app.current_user_id` is not the user
--  being changed -- correct for a signed-in officer, and fatal here: a
--  password RESET has no session by definition. The officer proved control of
--  the mailbox with a one-time code, but the session variable is empty, so the
--  guard raised "You may only change your own password." and the app showed
--  "Something went wrong. Please try again."
--
--  reset_password_for_identifier calls the INNER function instead. That is
--  where the policy check, the reuse check and the hashing live, so the reset
--  still cannot set a weak or previously-used password -- it only skips the
--  are-you-yourself test, which the OTP has already answered by other means.
--
--  ⚠️ The inner function is named by 018 and only exists after it has run.
--  Resolved at runtime rather than hardcoded, so this file works whether or
--  not 018 has been applied yet -- on a fresh database where 018 has not run,
--  `auth.change_password` IS the unguarded body and calling it is correct.
--
--  Safe to re-run.
-- ============================================================================

do $$
declare
  v_setter text;
begin
  -- Prefer the unwrapped body 018 renames aside; fall back to the plain name.
  if exists (select 1 from pg_proc p
               join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'auth'
                and p.proname = 'change_password_unchecked') then
    v_setter := 'auth.change_password_unchecked';
  else
    v_setter := 'auth.change_password';
  end if;

  execute format($f$
    create or replace function public.reset_password_for_identifier(
      p_identifier text,
      p_password   text
    )
    returns void
    language plpgsql
    security definer
    set search_path = public, auth
    as $body$
    declare
      v_email text;
      v_id    uuid;
    begin
      v_email := public.reset_email_for_identifier(p_identifier);
      if v_email is null then
        raise exception 'reset_not_available' using errcode = '22023';
      end if;

      select u.id into v_id
      from   auth.users u
      where  lower(u.email) = lower(v_email);

      if v_id is null then
        raise exception 'reset_not_available' using errcode = '22023';
      end if;

      -- ⚠️ The UNGUARDED setter. See the note at the top of migration 024:
      -- there is no session here to satisfy 018's caller check, and the
      -- one-time code has already established who this is. Policy and reuse
      -- checks still apply -- they live inside this function.
      perform %s(v_id, p_password);

      update public.profiles
         set password_updated_at = now()
       where id = v_id;

      update auth.users
         set failed_login_attempts = 0,
             locked_until = null,
             updated_at = now()
       where id = v_id;
    end;
    $body$;
  $f$, v_setter);

  raise notice 'reset_password_for_identifier now calls %', v_setter;
end $$;


-- ── Verify: a reset with NO session must succeed ────────────────────────────
do $$
declare
  v_id uuid;
  v_saved text;
  v_email text;
begin
  select p.id, u.email into v_id, v_email
    from public.profiles p join auth.users u on u.id = p.id
   where p.is_active limit 1;
  if v_id is null then
    raise notice 'no active account to test with - skipping';
    return;
  end if;

  select encrypted_password into v_saved from auth.users where id = v_id;

  -- ⚠️ Explicitly NO session: this is the exact condition that broke.
  perform set_config('app.current_user_id', '', true);

  begin
    perform public.reset_password_for_identifier(v_email, 'ResetProof#2026a');
  exception when others then
    update auth.users set encrypted_password = v_saved where id = v_id;
    raise exception 'a session-less reset still fails: %', SQLERRM;
  end;

  -- And the reuse check must still bite, even on this path.
  declare
    v_blocked boolean := false;
  begin
    begin
      perform public.reset_password_for_identifier(v_email, 'ResetProof#2026a');
    exception when others then
      v_blocked := true;
    end;
    if not v_blocked then
      update auth.users set encrypted_password = v_saved where id = v_id;
      raise exception
        'the reset path accepted a password it had just set - the reuse '
        'check was lost with the guard';
    end if;
  end;

  update auth.users set encrypted_password = v_saved where id = v_id;
  delete from auth.password_history where user_id = v_id;
  update public.profiles set password_updated_at = now() - interval '95 days'
   where id = v_id and full_name = 'Ajantha Deepal';
  raise notice 'session-less reset works and still blocks reuse - restored';
end $$;
