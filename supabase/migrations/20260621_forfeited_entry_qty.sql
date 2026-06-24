-- ============================================================================
--  Add entry_qty to forfeited_packages so per-entry abandoned disposal-request
--  rows carry the EXACT quantity abandoned in that warehouse entry event.
--
--  Before: a synthetic per-entry abandoned row (one [ABANDONED] warehouse entry
--  = one row, e.g. qty 15 and qty 19 for the same item) created a
--  forfeited_packages row with no quantity. When the Valuation / Central
--  Disposal screens reloaded the row from the DB, the in-memory entryQty was
--  lost and totalQuantity fell back to the FULL PackageItem.quantity (e.g. 200),
--  so both rows wrongly showed 200 and the cost × qty totalled against 200.
--
--  Now: createDisposalRequest() stores the originating warehouse entry's
--  item_count in entry_qty. DisposalRequestItemModel.totalQuantity prefers
--  forfeited.entryQty when present, so each row shows + prices its own qty.
--  Idempotent — safe to re-run.
-- ============================================================================

alter table public.forfeited_packages
  add column if not exists entry_qty integer;

-- Done.
