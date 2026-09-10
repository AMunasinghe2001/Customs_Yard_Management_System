-- ============================================================================
-- The base schema's "Admins can manage all profiles" policy survived
-- migration 002, and it is wrong twice over.
--
-- 1. It recurses. It asks whether the caller is an admin by reading profiles
--    INLINE:
--
--      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role='admin')
--
--    That subquery is itself subject to the policies on profiles, so deciding
--    whether profiles may be read requires reading profiles: PostgreSQL error
--    42P17. Every sign-in fails, because the router reads the profile.
--
-- 2. It is a cross-yard bypass. Migration 002 established that every user,
--    "administrators included", sees only their own yard, and it dropped
--    auth_user_is_admin() as "the admin-bypass helper (no longer used)". It
--    replaced admin access with yard_profiles_select/update/insert. It simply
--    never dropped this policy, which grants FOR ALL across every yard.
--
-- So the fix is to remove it, not to rewrite it with a SECURITY DEFINER
-- helper: reviving the helper would re-open the hole 002 closed. Profile
-- access stays governed by the own-row/same-yard policies from 002, plus the
-- directorate read policies. Migration 006 removed the same recursion from
-- yard_staff_boundary; this is the older, second source of it.
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists "Admins can manage all profiles" on public.profiles;

-- The helper 002 dropped must stay dropped: it exists only to bypass the yard
-- boundary, and 007 above is what re-created it in an earlier draft.
drop function if exists public.auth_user_is_admin();

-- Verify no policy on profiles reads profiles inline any more.
do $$
declare
  bad text;
begin
  select string_agg(p.polname, ', ') into bad
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'profiles'
     and (
       pg_get_expr(p.polqual, p.polrelid) ilike '%from profiles%'
       or pg_get_expr(p.polqual, p.polrelid) ilike '%from public.profiles%'
       or pg_get_expr(p.polwithcheck, p.polrelid) ilike '%from profiles%'
       or pg_get_expr(p.polwithcheck, p.polrelid) ilike '%from public.profiles%'
     );

  if bad is not null then
    raise exception 'profiles policies still read profiles inline: %', bad;
  end if;
end $$;
