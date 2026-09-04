-- ============================================================================
--  Goods that have gone are not in a warehouse.
--
--  Two SOLD items still held an open `warehouse_entries` row -- no
--  `returned_at`, so every page that asks "where is this now" answered with a
--  warehouse for goods that had already been sold:
--
--      CED/GL1/OA/07/2025   Truck Tyres   sold   still in Open Area 01
--      CED/GL1/OA/11/2025   Truck Tyres   sold   still in Open Area 01
--
--  The seed's own `_recordSaleInWarehouse` closes the entry and writes a
--  `[FINAL:SOLD]` row in its place; these two took a path that never called
--  it. 67 sold items, 65 closed correctly, 2 left open.
--
--  ⚠️ The UI no longer trusts the entry for this -- an item whose STATUS says
--  it has left shows "Left the warehouse" whatever its rows say -- but the
--  rows themselves are still wrong, and every OTHER reader of them (zone
--  capacity, storage charges, the stock report) would still be counting these
--  goods as present.
--
--  Closed out the way the sale would have: the open row is marked returned at
--  the sale's own moment and tagged [FINAL:SOLD], so the item's history reads
--  as it does for the 65 that went through properly.
-- ============================================================================

set lock_timeout = '5s';

update public.warehouse_entries w
   set is_returned  = true,
       returned_at  = coalesce(
         -- The moment the sale actually happened, where one is recorded.
         (select ts.created_at
            from public.tender_sale_items ti
            join public.tender_sales ts on ts.id = ti.tender_sale_id
            join public.forfeited_packages fp
              on fp.id = ti.forfeited_package_id
           where fp.item_id = w.package_item_id
             and ti.sold
           order by ts.created_at desc
           limit 1),
         w.admitted_at),
       return_notes = '[FINAL:SOLD]',
       updated_at   = now()
  from public.package_items pi
 where pi.id = w.package_item_id
   and pi.status = 'sold'
   and coalesce(w.is_returned, false) = false;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  still_held int;
  any_gone   int;
begin
  -- ⚠️ Nothing that has left may hold an open warehouse row.
  select count(*) into any_gone
    from public.warehouse_entries w
    join public.package_items pi on pi.id = w.package_item_id
   where coalesce(w.is_returned, false) = false
     and lower(pi.status) in
         ('sold', 'destroyed', 're-exported', 'returned', 'released');
  if any_gone <> 0 then
    raise exception '% disposed item(s) still hold an open warehouse row',
      any_gone;
  end if;

  -- And a closed row must carry the moment it closed, or the storage charge
  -- it implies runs to today.
  if exists (select 1 from public.warehouse_entries
              where is_returned and returned_at is null) then
    raise exception 'a closed warehouse row has no returned_at';
  end if;

  select count(*) into still_held
    from public.warehouse_entries
   where coalesce(is_returned, false) = false;
  raise notice '% warehouse row(s) remain open, all for goods still held',
    still_held;
end
$verify$;
