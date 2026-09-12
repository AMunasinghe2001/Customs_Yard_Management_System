-- ============================================================================
--  Why does the Destroyed Packages table show "—" for Notes/Financials/Delivery
--  for GL1/SR/108/2026 Jasmine Rice? Run and share.
-- ============================================================================

-- A. The destroyed warehouse entry (drives the row) + its package_item_id.
select 'destroyed entry' as kind, we.id, we.package_item_id, pi.item_name,
       we.return_notes
  from public.warehouse_entries we
  join public.packages p on p.id = we.package_id
  left join public.package_items pi on pi.id = we.package_item_id
 where p.sr_number = 'GL1/SR/108/2026'
   and upper(coalesce(we.return_notes, '')) like '[FINAL:DESTROYED]%';

-- B. The destruction_items rows for this SR + their FP's item_id + valuation.
select di.id as di_id, di.forfeited_package_id, di.destroyed, di.delivered,
       fp.item_id as fp_item_id,
       pi.item_name as fp_item_name,
       (select dri.valuation_cost
          from public.disposal_request_items dri
         where dri.forfeited_package_id = fp.id
         limit 1) as valuation_cost
  from public.destruction_items di
  join public.forfeited_packages fp on fp.id = di.forfeited_package_id
  join public.packages p on p.id = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
 where p.sr_number = 'GL1/SR/108/2026';
