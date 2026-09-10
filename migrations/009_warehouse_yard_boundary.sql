-- ============================================================================
-- Migration 008 gave `warehouses` a yard, but left it protected only by
-- PERMISSIVE policies. PostgreSQL OR-s permissive policies together, so
-- `warehouses_disposal_read` and `executive_read_all` widen the result set
-- past `warehouses_yard_select` — correct for those national roles, but it
-- means a yard officer/admin has no policy that can never be widened.
--
-- Migration 005 already solved this for every operational table by adding a
-- RESTRICTIVE policy, which is AND-ed with all permissive ones. It applies
-- itself to every BASE TABLE carrying a `yard` column — but it ran BEFORE 008
-- existed, so `warehouses` was not a candidate at the time, and re-running it
-- is not part of a normal upgrade. `warehouse_zones` has no `yard` column at
-- all (it inherits through warehouse_id), so 005 can never cover it.
--
-- This closes both, using the same helpers so the rule stays one rule:
--   * yard staff (officer/admin) are pinned to their own yard
--   * directorate roles keep their intentional cross-yard reads
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists yard_staff_boundary on public.warehouses;
create policy yard_staff_boundary on public.warehouses
  as restrictive
  for all
  using (
    (not public.auth_user_is_yard_staff())
    or yard = public.auth_user_yard()
  );

-- Zones carry no yard of their own; the boundary follows the parent warehouse
-- through the SECURITY DEFINER helper added in 008, so evaluating it does not
-- re-enter the warehouses policies.
drop policy if exists yard_staff_boundary on public.warehouse_zones;
create policy yard_staff_boundary on public.warehouse_zones
  as restrictive
  for all
  using (
    (not public.auth_user_is_yard_staff())
    or public.warehouse_yard(warehouse_id) = public.auth_user_yard()
  );

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  missing text;
begin
  select string_agg(t, ', ') into missing
    from unnest(array['warehouses', 'warehouse_zones']) as t
   where not exists (
     select 1 from pg_policy p
       join pg_class c on c.oid = p.polrelid
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = t
        and p.polname = 'yard_staff_boundary'
        and not p.polpermissive
   );
  if missing is not null then
    raise exception 'restrictive yard boundary missing on: %', missing;
  end if;
end $$;
