-- ============================================================================
--  Allow yard officers to read tender_sales that contain their yard's packages.
--
--  Previously tender_sales had no read policy for officers/admins — only
--  disposal-directorate users could query it. The yard Tender Sale screen
--  (tender_disposal_screen.dart) watches tenderSalesProvider which calls
--  getTenderSales(), so without this policy the screen always returned empty.
-- ============================================================================

-- Officers & admins can read a tender_sale when at least one of its items
-- belongs to their yard (profiles.yard match).
drop policy if exists tender_sales_yard_read on public.tender_sales;
create policy tender_sales_yard_read on public.tender_sales
  for select
  using (
    exists (
      select 1
        from public.tender_sale_items tsi
        join public.profiles p on p.id = auth.uid()
       where tsi.tender_sale_id = tender_sales.id
         and tsi.yard = p.yard
    )
  );
