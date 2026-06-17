-- ============================================================================
--  DIAGNOSTIC: does a package have warehouse_entries?
--  The Central Disposal / Valuation details popup shows "Warehouse Summary"
--  from packages.warehouse_entries. If it only shows the Yard row, the package
--  has no warehouse entries (or none for the shown item). Run this to confirm.
--  Replace the SR number if needed.
-- ============================================================================

-- 1. The package + its items.
select p.id as package_id, p.sr_number, p.consignee_name,
       pi.id as item_id, pi.item_name, pi.quantity, pi.hs_code
  from public.packages p
  left join public.package_items pi on pi.package_id = p.id
 where p.sr_number = 'GL1/SR/102/2026';

-- 2. Warehouse entries for that package (the popup's Warehouse Summary source).
--    If this returns 0 rows, the package was never admitted to a warehouse, so
--    there is nothing to show beyond the Yard.
select we.id, we.package_id, we.package_item_id, we.warehouse_id,
       w.name as warehouse_name, we.zone, we.item_count,
       we.is_returned, we.admitted_at
  from public.warehouse_entries we
  left join public.warehouses w on w.id = we.warehouse_id
 where we.package_id = (
   select id from public.packages where sr_number = 'GL1/SR/102/2026' limit 1
 )
 order by we.admitted_at;

-- Done.
