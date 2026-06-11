-- ============================================================================
--  Cross-yard READ access to forfeited_packages for the Central Disposal
--  Directorate. Run after 20260610_disposal_directorate.sql.
--
--  Lets disposal (DC/SDDC) users view forfeited packages across ALL yards
--  (filtered in the UI by a yard dropdown), alongside the strict per-yard
--  `yard_all` policy that keeps everyone else scoped to their own yard.
-- ============================================================================

drop policy if exists disposal_read_all on public.forfeited_packages;
create policy disposal_read_all on public.forfeited_packages
  for select using (public.auth_user_is_disposal());

-- Done.
