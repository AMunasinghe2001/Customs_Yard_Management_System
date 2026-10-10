-- ============================================================================
--  Tender Sales is the heaviest query in the app.
--
--  `getTenderSales` fetches EVERY sale with:
--      tender_sale_items
--        -> forfeited_packages
--             -> disposal_request_items (valuation_cost)
--             -> packages
--                  -> package_items
--                  -> warehouse_entries -> warehouses
--
--  ...and three screens read it. On one yard that is 81 sales and 188 items.
--  Central Disposal shows ALL TWENTY-EIGHT yards, so the same query is heading
--  for thousands of sales and tens of thousands of joined rows — every one of
--  them fetched to render twenty cards.
--
--  This view carries the SALE-LEVEL facts the list needs to choose and order
--  its page, so the heavy per-item fetch happens for one page of sales only.
--
--  ⚠️ What it deliberately does NOT decide: whether the SELL WINDOW HAS CLOSED.
--  That comes from `unsoldDeadline` -> `workingDeadline`, which rolls forward
--  past weekends AND Sri Lankan public holidays fetched from an external API
--  at runtime. There is no holiday table here, so a SQL version would silently
--  disagree with the app on exactly the days that matter. The app keeps that
--  test, applied to one page.
--
--  What SQL can settle: has anything sold, is anything still pending, which
--  yards and SR numbers the sale touches (for the search and yard filters),
--  and whether the sale RE-TENDERS goods from an earlier one.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.tender_sale_summary;

create view public.tender_sale_summary as
select
  ts.id,
  ts.sale_number,
  ts.sale_date,
  ts.sale_time,
  ts.sale_end_time,
  ts.tender_type,
  ts.yard,
  ts.created_at,
  agg.item_count,
  agg.sold_count,
  -- The list hides a sale with nothing left to act on.
  (agg.item_count > agg.sold_count)          as has_pending,
  -- ⚠️ Every yard and SR number the sale TOUCHES, not the sale's own yard.
  -- A tender sale can mix items from a multi-directorate yard -- NNR items
  -- filed under CED sitting beside ones filed under PSD -- so the sale-level
  -- yard code cannot tell them apart, and the filter must match any item's.
  -- ⚠️ Joined into ONE text column each, not a text[]. The search and yard
  -- filters run as `ilike`, which arrays cannot serve -- and the Dart driver
  -- hands array columns back as UndecodedBytes anyway, so a row would arrive
  -- unreadable. Wrapped in separators so a filter cannot match across two
  -- neighbouring values.
  agg.item_yards,
  agg.sr_numbers,
  agg.consignees,
  -- ⚠️ A RE-TENDER: this sale shares goods with an EARLIER-created sale, so
  -- the items went unsold there and are being offered again. Matched on the
  -- forfeited row's ITEM where it has one, falling back to the forfeited id,
  -- exactly as `_tenderItemKey` does.
  exists (
    select 1
      from public.tender_sale_items a
      join public.tender_sale_items b
        on coalesce(
             (select fpa.item_id from public.forfeited_packages fpa
               where fpa.id = a.forfeited_package_id)::text,
             a.forfeited_package_id::text)
         = coalesce(
             (select fpb.item_id from public.forfeited_packages fpb
               where fpb.id = b.forfeited_package_id)::text,
             b.forfeited_package_id::text)
      join public.tender_sales earlier on earlier.id = b.tender_sale_id
     where a.tender_sale_id = ts.id
       and earlier.id <> ts.id
       and earlier.created_at < ts.created_at)  as is_retender
from public.tender_sales ts
cross join lateral (
  select
    count(*)                                        as item_count,
    count(*) filter (where ti.sold)                 as sold_count,
    '|' || coalesce(string_agg(distinct ti.yard, '|'), '') || '|'
                                                    as item_yards,
    '|' || coalesce(string_agg(distinct fp.sr_number, '|'), '') || '|'
                                                    as sr_numbers,
    '|' || coalesce(string_agg(distinct fp.consignee_name, '|'), '') || '|'
                                                    as consignees
    from public.tender_sale_items ti
    left join public.forfeited_packages fp on fp.id = ti.forfeited_package_id
   where ti.tender_sale_id = ts.id) agg;

grant select on public.tender_sale_summary to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  bad int;
  n   int;
begin
  -- One row per sale, no more and no fewer.
  select count(*) into n from public.tender_sale_summary;
  if n <> (select count(*) from public.tender_sales) then
    raise exception 'the summary has % row(s) for % sale(s)',
      n, (select count(*) from public.tender_sales);
  end if;

  -- The counts must match the items they summarise.
  select count(*) into bad
    from public.tender_sale_summary s
   where s.item_count <> (select count(*) from public.tender_sale_items ti
                           where ti.tender_sale_id = s.id)
      or s.sold_count <> (select count(*) from public.tender_sale_items ti
                           where ti.tender_sale_id = s.id and ti.sold);
  if bad <> 0 then
    raise exception '% sale(s) have counts that disagree with their items', bad;
  end if;

  -- has_pending is exactly "something is not sold".
  select count(*) into bad
    from public.tender_sale_summary s
   where s.has_pending <> exists (select 1 from public.tender_sale_items ti
                                   where ti.tender_sale_id = s.id
                                     and not ti.sold);
  if bad <> 0 then
    raise exception '% sale(s) disagree about having pending items', bad;
  end if;

  -- ⚠️ A re-tender must have an EARLIER sale sharing its goods, and the very
  -- first sale of a package can never be one.
  select count(*) into bad
    from public.tender_sale_summary s
   where s.is_retender
     and not exists (
       select 1 from public.tender_sale_items a
         join public.tender_sale_items b
           on b.forfeited_package_id = a.forfeited_package_id
         join public.tender_sales e on e.id = b.tender_sale_id
        where a.tender_sale_id = s.id
          and e.created_at < s.created_at);
  if bad <> 0 then
    raise exception '% sale(s) claim to be re-tenders with nothing before them',
      bad;
  end if;

  -- The text columns must actually carry their values, or every search
  -- silently matches nothing.
  select count(*) into bad
    from public.tender_sale_summary s
   where s.item_count > 0 and s.sr_numbers = '||';
  if bad <> 0 then
    raise exception '% sale(s) have items but no SR numbers to search', bad;
  end if;

  raise notice 'tender_sale_summary: % sale(s), % with pending items, % re-tenders',
    n,
    (select count(*) from public.tender_sale_summary where has_pending),
    (select count(*) from public.tender_sale_summary where is_retender);
  for r in
    select sale_number, item_count, sold_count, is_retender
      from public.tender_sale_summary
     order by created_at desc limit 4
  loop
    raise notice '  %  %/% sold%',
      rpad(coalesce(r.sale_number, '(no number)'), 24),
      r.sold_count, r.item_count,
      case when r.is_retender then '  [re-tender]' else '' end;
  end loop;
end
$verify$;
