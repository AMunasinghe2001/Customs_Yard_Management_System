-- ============================================================================
-- A yard cannot see the staff who used to serve in it.
--
-- `yard_profiles_select` returns a profile only when `profiles.yard` equals
-- the caller's yard. `profiles.yard` holds ONE value — where a person is NOW
-- — so the moment an officer is transferred GL1 → GL2 their row leaves GL1's
-- result set, taking with it the record that they ever worked there.
--
-- The Admin Panel's staff table asks "who has served in this yard, and
-- when". It reads the service dates from `audit_logs`, which is already
-- scoped per yard and already readable — but the NAME beside each date lives
-- in `profiles`, and that row was invisible. The page could therefore show
-- a service span for nobody.
--
-- ⚠️ Narrow on purpose. This does NOT open profiles across yards: it grants
-- SELECT only on rows the caller's OWN yard has a recorded history with, and
-- only ever on the caller's own yard's log. A yard sees the people who
-- passed through it and nobody else.
--
-- Safe to re-run.
-- ============================================================================

-- Whether this yard's audit log has any profile event for that person.
--
-- SECURITY DEFINER because it is consulted BY a profiles policy: reading
-- audit_logs here must not re-enter the caller's own policies, and a plain
-- subquery against a table that itself joins profiles would risk the 42P17
-- recursion that migrations 006 and 007 removed.
create or replace function public.profile_served_in_my_yard(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $function$
  select exists (
    select 1
      from public.audit_logs l
     where l.entity_type = 'profile'
       and l.entity_id = p_profile_id::text
       and l.yard is not null
       and l.yard = public.auth_user_yard()
  );
$function$;

revoke all on function public.profile_served_in_my_yard(uuid) from public;
grant execute on function public.profile_served_in_my_yard(uuid) to authenticated;

drop policy if exists yard_profiles_select on public.profiles;
create policy yard_profiles_select on public.profiles
  for select using (
    id = (select sr_auth.uid())
    or yard = (select public.auth_user_yard())
    -- Someone who has since moved on, but whose service here is recorded.
    or (select public.profile_served_in_my_yard(id))
  );

-- ⚠️ The restrictive boundary must widen with it, or it AND-s the new rows
-- straight back out again. Same shape as the permissive rule above.
drop policy if exists yard_staff_boundary on public.profiles;

do $$
begin
  if exists (
    select 1 from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'profiles'
       and p.polname = 'yard_profiles_select'
       and pg_get_expr(p.polqual, p.polrelid) not like '%profile_served_in_my_yard%'
  ) then
    raise exception 'yard_profiles_select does not admit past staff';
  end if;
end $$;
