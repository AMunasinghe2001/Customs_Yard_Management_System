-- ============================================================================
-- Database-wide yard boundary for every operational table with a `yard`.
--
-- Older schema policies include permissive rules such as
-- `sr_auth.role() = 'authenticated'`. PostgreSQL combines permissive policies
-- with OR, so that old rule could override `yard_all` and leak a GL1 row to a
-- GL2 officer. This migration adds a RESTRICTIVE policy instead: restrictive
-- policies are AND-ed with every permissive policy, so no old or future broad
-- policy can widen a yard officer/admin's result set.
--
-- Directorate roles (ICT, Disposal, Appeal, Valuation, Executive) are not
-- yard staff and retain their intentional national workflows. Every officer
-- and yard admin is bound to exactly profiles.yard, including ICT-added yards.
-- Safe to re-run.
-- ============================================================================

create or replace function public.auth_user_is_yard_staff()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
      from public.profiles p
     where p.id = sr_auth.uid()
       and lower(coalesce(p.role, '')) in ('officer', 'admin')
  );
$$;

grant execute on function public.auth_user_is_yard_staff() to authenticated;

do $$
declare
  t text;
begin
  -- No hard-coded yard codes: this covers GL1, GL2 and every yard ICT creates.
  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name
     where c.table_schema = 'public'
       and c.column_name = 'yard'
       and tb.table_type = 'BASE TABLE'
       -- auth_user_yard() reads profiles itself. Applying this policy to
       -- profiles would make that lookup recursively invoke its own policy.
       and c.table_name <> 'profiles'
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('drop policy if exists yard_staff_boundary on public.%I', t);
    execute format($policy$
      create policy yard_staff_boundary on public.%I
        as restrictive
        for all
        using (
          not public.auth_user_is_yard_staff()
          or yard = public.auth_user_yard()
        )
        with check (
          not public.auth_user_is_yard_staff()
          or yard = public.auth_user_yard()
        )
    $policy$, t);
  end loop;
end $$;

-- Fail deployment rather than leaving even one yard-bearing data table open.
do $$
declare
  missing text;
begin
  select string_agg(c.table_name, ', ' order by c.table_name) into missing
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
   where c.table_schema = 'public'
     and c.column_name = 'yard'
     and tb.table_type = 'BASE TABLE'
     and c.table_name <> 'profiles'
     and not exists (
       select 1 from pg_policy p
       join pg_class pc on pc.oid = p.polrelid
       join pg_namespace pn on pn.oid = pc.relnamespace
       where pn.nspname = 'public'
         and pc.relname = c.table_name
         and p.polname = 'yard_staff_boundary'
         and p.polpermissive = false
     );
  if missing is not null then
    raise exception 'yard-staff boundary missing from: %', missing;
  end if;
end $$;
