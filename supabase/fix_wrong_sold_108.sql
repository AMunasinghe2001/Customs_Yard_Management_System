-- ============================================================================
--  Fix GL1/SR/108/2026 — revert the wrongly-recorded SOLD / DESTROYED entries
--  and clear the corrupted tender_sale_items + destruction_items so the sale
--  can be created fresh.
--
--  Root cause: tender_sale_items / destruction_items rows had no
--  package_item_id, and the package's forfeited_packages row was package-level
--  (item_id IS NULL). So disposal_mark_sale_item_sold / _destroyed processed
--  EVERY item (Jasmine Rice AND Palm Oil), each copying the same price.
--
--  This script:
--    1. Deletes the bogus [FINAL:SOLD] / [FINAL:DESTROYED] warehouse entries.
--    2. Resets the affected package_items back to 'Detain'.
--    3. DELETES all tender_sale_items AND destruction_items for the SR — clean
--       slate. Re-create the sale from the app; the new rows carry
--       package_item_id and process exactly one item.
--
--  ⚠ Review the SELECT in step 1, then COMMIT.
-- ============================================================================

begin;

-- ── 1. INSPECT what will be reverted (review before committing) ─────────────
select 'FINAL entries' as kind, we.id, we.package_item_id, we.item_count,
       we.return_notes, we.returned_at
  from public.warehouse_entries we
  join public.packages p on p.id = we.package_id
 where p.sr_number = 'GL1/SR/108/2026'
   and (upper(coalesce(we.return_notes, '')) like '[FINAL:SOLD]%'
        or upper(coalesce(we.return_notes, '')) like '[FINAL:DESTROYED]%');

-- ── 2. DELETE the [FINAL:SOLD] / [FINAL:DESTROYED] warehouse entries ────────
delete from public.warehouse_entries we
 using public.packages p
 where we.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026'
   and (upper(coalesce(we.return_notes, '')) like '[FINAL:SOLD]%'
        or upper(coalesce(we.return_notes, '')) like '[FINAL:DESTROYED]%');

-- ── 3. Reset the items flipped to sold/destroyed back to 'Detain' ──────────
update public.package_items pi
   set status = 'Detain'
  from public.packages p
 where pi.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026'
   and lower(pi.status) in ('sold', 'destroyed');

-- ── 4a. DELETE all tender_sale_items for this SR (clean slate) ──────────────
delete from public.tender_sale_items tsi
 using public.forfeited_packages fp,
       public.packages p
 where tsi.forfeited_package_id = fp.id
   and fp.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026';

-- ── 4b. DELETE all destruction_items for this SR (clean slate) ──────────────
delete from public.destruction_items di
 using public.forfeited_packages fp,
       public.packages p
 where di.forfeited_package_id = fp.id
   and fp.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026';

-- (Optional) Remove now-empty tender_sales / destructions headers. Leave
-- commented unless you also want to delete the empty CDU/TS/... shells.
-- delete from public.tender_sales ts
--  where not exists (
--    select 1 from public.tender_sale_items tsi where tsi.tender_sale_id = ts.id
--  );
-- delete from public.destructions d
--  where not exists (
--    select 1 from public.destruction_items di where di.destruction_id = d.id
--  );

-- Review the row counts above. If correct:
commit;
-- Otherwise: rollback;
