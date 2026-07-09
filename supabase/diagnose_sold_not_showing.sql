-- ============================================================================
--  Diagnose: a Tender-Sale item shows "Sold" but the Sold Packages page is empty.
--
--  The Sold page lists an item when EITHER:
--    (a) it has a warehouse_entries row whose return_notes starts with
--        '[FINAL:SOLD]' or '[SOLD]', OR
--    (b) the package_items.status = 'sold'.
--  This checks whether marking sold actually wrote those.
--
--  Run in the Supabase SQL Editor. Look at each result set.
-- ============================================================================

-- 1. Tender-sale items marked sold (the source of truth for "1/2 sold").
select tsi.id            as tsi_id,
       tsi.sold,
       tsi.package_item_id,
       tsi.sale_id
  from public.tender_sale_items tsi
 where tsi.sold = true
 order by tsi.package_item_id;

-- 2. For those sold TSI, is the linked package_items.status = 'sold'?
select pi.id       as item_id,
       pi.item_name,
       pi.status,
       (pi.status = 'sold') as status_ok
  from public.tender_sale_items tsi
  join public.package_items pi
    on pi.id = tsi.package_item_id
 where tsi.sold = true
 order by pi.item_name;

-- 3. Is there a [FINAL:SOLD] warehouse_entries row for those items?
select we.package_item_id,
       we.return_notes,
       (we.return_notes like '[FINAL:SOLD]%' or we.return_notes like '[SOLD]%')
         as has_sold_tag
  from public.warehouse_entries we
 where we.package_item_id in (
   select package_item_id from public.tender_sale_items where sold = true
 )
 order by we.package_item_id;

-- 4. Cross-check: which sold TSI have NEITHER status='sold' NOR a [FINAL:SOLD]
--    entry? These are the ones the Sold page can't see.
select tsi.package_item_id,
       pi.item_name,
       pi.status,
       exists (
         select 1 from public.warehouse_entries we
          where we.package_item_id = tsi.package_item_id
            and (we.return_notes like '[FINAL:SOLD]%'
                 or we.return_notes like '[SOLD]%')
       ) as has_sold_tag
  from public.tender_sale_items tsi
  left join public.package_items pi on pi.id = tsi.package_item_id
 where tsi.sold = true
   and pi.status is distinct from 'sold'
   and not exists (
     select 1 from public.warehouse_entries we
      where we.package_item_id = tsi.package_item_id
        and (we.return_notes like '[FINAL:SOLD]%'
             or we.return_notes like '[SOLD]%')
   );
