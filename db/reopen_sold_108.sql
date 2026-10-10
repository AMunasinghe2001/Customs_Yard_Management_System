-- ============================================================================
--  Re-open the SOLD packages of GL1/SR/108/2026 so they rejoin the tender.
--
--  Reverts every recorded sale for the SR:
--    1. Delete the [FINAL:SOLD] warehouse entries (incl. the bogus NULL-item
--       ones that showed as "—" / "Palm Oil").
--    2. Reset the items flipped to 'sold' back to 'Detain'.
--    3. Reset every tender_sale_item for the SR back to UNSOLD (clears the sold
--       flag / price / taxes / receipt / delivery).
--
--  The existing tender sale then shows all its rows as "Mark Sold" again, and
--  every item can be sold afresh — now one item at a time (new RPC + trigger).
--
--  ⚠ Review the SELECT in step 0, then COMMIT.
-- ============================================================================

begin;

-- ── 0. INSPECT the sale records that will be reverted ───────────────────────
select 'FINAL:SOLD entry' as kind, we.id, we.package_item_id, we.item_count,
       we.return_notes, we.returned_at
  from public.warehouse_entries we
  join public.packages p on p.id = we.package_id
 where p.sr_number = 'GL1/SR/108/2026'
   and upper(coalesce(we.return_notes, '')) like '[FINAL:SOLD]%';

-- ── 1. Delete the [FINAL:SOLD] warehouse entries ────────────────────────────
delete from public.warehouse_entries we
 using public.packages p
 where we.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026'
   and upper(coalesce(we.return_notes, '')) like '[FINAL:SOLD]%';

-- ── 2. Reset the items that were flipped to 'sold' back to 'Detain' ─────────
update public.package_items pi
   set status = 'Detain'
  from public.packages p
 where pi.package_id = p.id
   and p.sr_number = 'GL1/SR/108/2026'
   and lower(pi.status) = 'sold';

-- ── 3. Reset every tender_sale_item for this SR back to UNSOLD ──────────────
update public.tender_sale_items tsi
   set sold = false,
       sold_at = null,
       receipt_number = null,
       sold_price = 0,
       applied_taxes = '[]'::jsonb,
       is_delivered = false,
       delivered_at = null
  from public.forfeited_packages fp
  join public.packages p on p.id = fp.package_id
 where tsi.forfeited_package_id = fp.id
   and p.sr_number = 'GL1/SR/108/2026';

-- Review the row counts above. If correct:
commit;
-- Otherwise: rollback;
