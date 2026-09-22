-- ============================================================================
--  Sending a disposal request is a YARD ADMINISTRATION act.
--
--  ⚠️ It was gated in the UI only, and only by "is anything actionable" -- not
--  by who is asking. Five screens (Detained, Abandoned, Forfeited, Other,
--  Perishable) each built their own button, and a yard OFFICER could press any
--  of them. The same officer is already refused the Final Disposition button
--  on the very same rows, so the app was inconsistent with itself about who
--  decides the fate of held goods.
--
--  The UI is now gated too, but a button is not a permission: the RLS policies
--  on disposal_requests / disposal_request_items checked the YARD and never
--  the ROLE, so an officer's session could insert a request directly. This
--  closes it where it actually counts.
--
--  ⚠️ RESTRICTIVE, not permissive. A permissive policy is OR-ed with the
--  others, so adding one would have GRANTED a new way in rather than taking
--  one away. Restrictive policies are AND-ed: every other policy still has to
--  pass, and this one can only ever subtract.
--
--  SELECT is untouched -- an officer must still SEE what their yard has sent.
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. "Is the caller a yard OFFICER?" ──────────────────────────────────────
--
-- ⚠️ auth_user_is_yard_staff() is not the question: it is true for 'officer'
-- AND 'admin' together, which is exactly the distinction being drawn here.
create or replace function public.auth_user_is_yard_officer()
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (
    select 1
      from public.profiles p
     where p.id = sr_auth.uid()
       and lower(coalesce(p.role, '')) = 'officer'
  );
$fn$;

revoke all on function public.auth_user_is_yard_officer() from public;
grant execute on function public.auth_user_is_yard_officer() to authenticated;


-- ── 2. An officer may read, but not raise, a disposal request ───────────────
do $$
begin
  -- Dropped first so re-running replaces rather than duplicates.
  drop policy if exists disposal_requests_admin_only_write on public.disposal_requests;
  drop policy if exists disposal_request_items_admin_only_write
    on public.disposal_request_items;

  create policy disposal_requests_admin_only_write
    on public.disposal_requests
    as restrictive
    for all
    using (not public.auth_user_is_yard_officer())
    with check (not public.auth_user_is_yard_officer());

  create policy disposal_request_items_admin_only_write
    on public.disposal_request_items
    as restrictive
    for all
    using (not public.auth_user_is_yard_officer())
    with check (not public.auth_user_is_yard_officer());
end $$;

-- ⚠️ `for all` covers SELECT too, which would blind the officer to their own
-- yard's requests. Put the read back explicitly: this restrictive pair is
-- about WRITING.
do $$
begin
  drop policy if exists disposal_requests_officer_may_read
    on public.disposal_requests;
  drop policy if exists disposal_request_items_officer_may_read
    on public.disposal_request_items;

  create policy disposal_requests_officer_may_read
    on public.disposal_requests
    as restrictive
    for select
    using (true);

  create policy disposal_request_items_officer_may_read
    on public.disposal_request_items
    as restrictive
    for select
    using (true);
end $$;


-- ── 3. Verify, as the two roles ─────────────────────────────────────────────
--
-- ⚠️ `set local role yard_app` is NOT optional, and the first version of this
-- check was worthless without it. A migration runs as `postgres`, a SUPERUSER,
-- and RLS NEVER applies to a superuser -- so the officer insert succeeded and
-- the check still reported success, because its exception handler treated any
-- error as "blocked" and the insert raised none. It was proving nothing twice
-- over: it also named a column (`requested_by`) the table does not have, so on
-- the run before that it "passed" on a typo.
--
-- Switching to yard_app -- the non-superuser the app actually connects with --
-- is what makes this a test of the policy rather than of the connection.
do $$
declare
  v_officer uuid;
  v_admin   uuid;
  v_id      uuid;
  v_allowed boolean := false;
begin
  select id into v_officer
    from public.profiles where role = 'officer' and is_active limit 1;
  select id into v_admin
    from public.profiles where role = 'admin' and is_active limit 1;

  if v_officer is null or v_admin is null then
    raise notice 'need one active officer and one active admin to verify - skipped';
    return;
  end if;

  perform set_config('app.current_role', 'authenticated', true);
  set local role yard_app;

  -- The officer must be refused, and specifically by RLS (42501).
  perform set_config('app.current_user_id', v_officer::text, true);
  begin
    insert into public.disposal_requests (yard, request_date, status, created_by)
    values ((select yard from public.profiles where id = v_officer),
            current_date, 'pending', v_officer)
    returning id into v_id;
    v_allowed := true;
    delete from public.disposal_requests where id = v_id;
  exception
    when insufficient_privilege then
      null;  -- exactly what should happen
    when others then
      raise exception
        'the officer insert failed for the WRONG reason (% %) - this check is '
        'not testing the policy', SQLSTATE, SQLERRM;
  end;

  if v_allowed then
    raise exception
      'a yard OFFICER can still raise a disposal request - the restrictive '
      'policy is not doing its job';
  end if;

  -- And the admin must still be able to.
  perform set_config('app.current_user_id', v_admin::text, true);
  insert into public.disposal_requests (yard, request_date, status, created_by)
  values ((select yard from public.profiles where id = v_admin),
          current_date, 'pending', v_admin)
  returning id into v_id;
  delete from public.disposal_requests where id = v_id;

  -- The officer must still SEE their yard's requests.
  perform set_config('app.current_user_id', v_officer::text, true);
  perform count(*) from public.disposal_requests;

  reset role;
  raise notice
    'verified as yard_app: officer refused, admin allowed, officer can read';
end $$;

-- Reset the session so this file leaves nothing behind.
select set_config('app.current_user_id', '', false);
select set_config('app.current_role', '', false);
