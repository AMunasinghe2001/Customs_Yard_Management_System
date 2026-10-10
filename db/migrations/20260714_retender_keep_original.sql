-- ============================================================================
--  Re-tender / re-destruction must KEEP the original sale row.
--
--  Before: tender_sale_items / destruction_items had a unique constraint on
--  (forfeited_package_id, package_item_id). Re-tendering an unsold item reused
--  the same forfeited_package_id, so the ON CONFLICT upsert UPDATED (moved) the
--  existing row into the new sale — the item vanished from the original sale.
--
--  The yard needs the item to stay in the ORIGINAL sale as Unsold AND appear in
--  the re-tender sale as Pending (same item, two sales, different status). So
--  scope uniqueness PER SALE by adding the sale id to the unique key. Then a
--  re-tender into a new sale INSERTS a fresh row and the original is untouched.
--
--  This is strictly more permissive than before (an extra column in the key),
--  so no existing row can violate it.
-- ============================================================================

-- 1. ── tender_sale_items ─────────────────────────────────────────────────────
alter table public.tender_sale_items
  drop constraint if exists tender_sale_items_fp_item_unique;
alter table public.tender_sale_items
  add constraint tender_sale_items_fp_item_unique
    unique nulls not distinct
      (tender_sale_id, forfeited_package_id, package_item_id);

-- 2. ── destruction_items ─────────────────────────────────────────────────────
alter table public.destruction_items
  drop constraint if exists destruction_items_fp_item_unique;
alter table public.destruction_items
  add constraint destruction_items_fp_item_unique
    unique nulls not distinct
      (destruction_id, forfeited_package_id, package_item_id);
