-- ============================================================================
-- Profiles are the source of auth_user_yard(), so they cannot carry the
-- generic yard_staff_boundary policy: evaluating it would read profiles to
-- decide whether profiles may be read, producing PostgreSQL error 42P17.
--
-- Operational tables keep the restrictive policy from migration 005. Profile
-- access remains governed by its dedicated own-row/same-yard policies.
-- Safe to re-run.
-- ============================================================================

drop policy if exists yard_staff_boundary on public.profiles;

-- Verify the migration repaired the recursive policy without weakening the
-- operational-table boundary.
do $$
begin
  if exists (
    select 1 from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'profiles'
     and p.polname = 'yard_staff_boundary'
  ) then
    raise exception 'profiles must not have yard_staff_boundary';
  end if;
end $$;
