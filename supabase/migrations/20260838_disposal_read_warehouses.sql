-- ============================================================================
--  Central Disposal can read `warehouses` and `warehouse_zones`.
--
--  Their Report Generator carries the same Warehouse filter every other portal
--  has, but `warehouses` had SELECT policies for the executive role only — so
--  the list came back empty and the dropdown had to be hidden for them.
--
--  Read-only: creating and editing a warehouse stays with the yard admin.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

drop policy if exists warehouses_disposal_read on public.warehouses;
create policy warehouses_disposal_read on public.warehouses
  for select using (public.auth_user_is_disposal());

-- The zone list is read alongside it (capacity views, the SR form's picker).
drop policy if exists warehouse_zones_disposal_read on public.warehouse_zones;
create policy warehouse_zones_disposal_read on public.warehouse_zones
  for select using (public.auth_user_is_disposal());

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('warehouses', 'warehouse_zones')
 order by tablename, policyname;
