-- ============================================================================
--  Executive Office (DG / ADG) read access for the valuation reports.
--
--  The Director General's Office reports ("List of Goods for Valuation" and
--  "List of Goods Valued") read the full valuation chain of a package:
--    * initial valuation → disposal_request_items.valuation_cost
--    * 2nd / 3rd / final → tender_revaluations rows, oldest first
--
--  `20260714_executive_directorate.sql` already granted executive SELECT on
--  disposal_request_items, but `tender_revaluations` was created afterwards
--  (20260716) and only granted to valuation / disposal / appeal. Without this
--  policy the DG's report silently shows blank 2nd/3rd/Final columns instead
--  of the real re-valuations.
--
--  The High Panel ALSO writes here: once a package is still unsold after the
--  Valuation Tender plus Tender 1-3, it goes to the Tender Committees tab and
--  the ADG sets that committee round's valuation. That write lands in the same
--  `tender_revaluations` table (keyed by tender_sale_id), so the valuation
--  chain — and every report built on it — stays a single continuous series.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

--  (tender_sales / tender_sale_items already carry `executive_read_all` from
--   20260718_tender_committees.sql, so only this table is missing.)

drop policy if exists tender_reval_executive_read on public.tender_revaluations;
create policy tender_reval_executive_read on public.tender_revaluations
  for select using (public.auth_user_is_executive());

-- Committee valuations set by the ADG (saveTenderRevaluation deletes the old
-- row for the round, then inserts the new one — so INSERT *and* DELETE).
drop policy if exists tender_reval_executive_write on public.tender_revaluations;
create policy tender_reval_executive_write on public.tender_revaluations
  for all
  using (public.auth_user_is_executive())
  with check (public.auth_user_is_executive());

reset lock_timeout;
