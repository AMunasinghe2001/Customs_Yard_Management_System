-- ============================================================================
--  Fix GL1/SR/108/2026 — revert the wrongly-recorded SOLD entries and clear
--  the corrupted tender_sale_items so the sale can be created fresh.
--
--  Root cause: tender_sale_items rows had no package_item_id, and the package's
--  forfeited_packages row was package-level (item_id IS NULL). So
--  disposal_mark_sale_item_sold marked EVERY item SOLD (Jasmine Rice AND Palm
--  Oil), each copying the same sold_price.
--
--  This script:
--    1. Deletes the bogus [FINAL:SOLD] warehouse entries.
--    2. Resets the affected package_items back to 'Detain'.
--    3. DELETES all tender_sale_items for the SR (both the original rows and the
--       per-item rows the buggy SOLD run inserted) — clean slate.
--
--  After running this, RE-CREATE the tender sale from the app. The new code
--  stamps each row's package_item_id, so Mark Sold then sells exactly one item.
--
--  ⚠ Review the SELECT in step 1, then COMMIT.
-- ============================================================================

begin;

-- ── 1. INSPECT what will be reverted (review before committing) ─────────────
select 'FINAL:SOLD entries' as kind, we.id, we.package_item_id, we.item_count,
       we.return_notes, we.returned_at
  from public.warehouse_entries we
  join public.packages p on p.id = we.package_id
 where p.sr_number = 'GL1/SR/108/2026'
   and upper(coalesce(we.return_notes, '')) like '[FINAL:SOLD]%';

-- ── 2. DELETE the [FINAL:SOLD] warehouse entries for this package ───────────
delete from public.warehouse_entries we
 using public.packages p
 where we.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026'
   and upper(coalesce(we.return_notes, '')) like '[FINAL:SOLD]%';

-- ── 3. Reset the items that were flipped to 'sold' back to 'Detain' ─────────
update public.package_items pi
   set status = 'Detain'
  from public.packages p
 where pi.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026'
   and lower(pi.status) = 'sold';

-- ── 4. DELETE all tender_sale_items for this SR (clean slate) ───────────────
--  Removes both the original package-level rows AND the per-item rows the buggy
--  SOLD run inserted. Re-create the tender sale from the app afterwards; the
--  new rows will carry package_item_id and sell correctly.
delete from public.tender_sale_items tsi
 using public.forfeited_packages fp,
       public.packages p
 where tsi.forfeited_package_id = fp.id
   and fp.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026';

-- (Optional) Remove now-empty tender_sales headers for this SR's sales. Leave
-- commented unless you also want to delete the empty CDU/TS/... shell.
-- delete from public.tender_sales ts
--  where not exists (
--    select 1 from public.tender_sale_items tsi where tsi.tender_sale_id = ts.id
--  );

-- Review the row counts above. If correct:
commit;
-- Otherwise: rollback;
