-- ============================================================================
--  Why does the re-tendered Jasmine Rice still sit in the Unsold pool?
--  Run and share the output.
-- ============================================================================

-- ── A. Every tender_sale_item for GL1/SR/108 Jasmine, with its sale's date ───
--  Shows: which tender sale each TSI row belongs to, the sale_date/time, and
--  whether the row is marked sold. A package leaves the Unsold pool only when
--  its LATEST sale moment has passed (or is set) AND it is not sold.
select tsi.id           as tsi_id,
       tsi.forfeited_package_id,
       tsi.package_item_id,
       tsi.sold,
       ts.sale_number,
       ts.sale_date,
       ts.sale_time,
       ts.created_at     as sale_created
  from public.tender_sale_items tsi
  join public.tender_sales ts on ts.id = tsi.tender_sale_id
  join public.forfeited_packages fp on fp.id = tsi.forfeited_package_id
  join public.packages p on p.id = fp.package_id
 where p.sr_number = 'GL1/SR/108/2026'
 order by ts.created_at;
