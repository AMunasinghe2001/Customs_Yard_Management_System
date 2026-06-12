-- ============================================================================
--  Move tender management to the Central Disposal Directorate.
--  Tenders + tender_disposals were admin-only for writes; the disposal role now
--  manages them (place tender, record disposal, re-tender) across all yards.
--  (SELECT was already permissive for all authenticated users.)
-- ============================================================================

drop policy if exists disposal_manage_tenders on public.tenders;
create policy disposal_manage_tenders on public.tenders
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

drop policy if exists disposal_manage_tender_disposals on public.tender_disposals;
create policy disposal_manage_tender_disposals on public.tender_disposals
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

-- Done.
