-- ============================================================================
--  Unsold Goods asks a question that cost the whole tender history to answer.
--
--  `getExhaustedUnsoldPackages` calls `getUnsoldTenderSales`, which calls
--  `getTenderSales` -- every sale, every item, every join -- and only THEN
--  narrows to the handful of packages that have run out of road. The result is
--  a page whose cost is the entire tender history of the yard, forever, to
--  show twenty rows.
--
--  This view answers the membership question in SQL. The app still loads the
--  full ReTenderSaleInfo for the packages it names, because the table and the
--  popup genuinely need the rounds -- but for a PAGE of them, not for all.
--
--  ⚠️ The rule is `getExhaustedUnsoldPackages`'s, condition for condition:
--
--    1. Not sold. A sold package is finished, whatever else is true.
--    2. tenderCount > 3 -- the Valuation Tender and Tenders 1-3 all failed.
--    3. The committee valued it AND the ADG SUBMITTED that figure. A recorded
--       committee value with no submission is a price that has not been
--       tendered yet.
--    4. ...and a round RAN AFTER that submission and still did not sell.
--
--  ⚠️ Condition 4 is judged by the round's SCHEDULED MOMENT, never by
--  created_at. That distinction is a live bug this codebase already hit:
--  Central Disposal routinely schedules a round before the ADG submits, and
--  two packages can share one sale row. Keying on created_at stranded Toilet
--  Seat Covers -- submitted 18:31 against a row created 04:25 -- on 5 rounds
--  forever, while Wash Basins in the SAME row moved on. The moment is
--  sale_date + sale_time; the sale has ENDED at sale_date + sale_end_time.
-- ============================================================================

set lock_timeout = '5s';

-- ⚠️ DROP, not `create or replace`: item_name lands mid-list, and Postgres
-- refuses a replacement whose column list is not a pure append. Nothing but
-- the app reads this view.
drop view if exists public.exhausted_unsold;

create view public.exhausted_unsold as
with rounds as (
  -- Every round a forfeited package sat in, with the two moments that matter.
  select ti.forfeited_package_id            as fp_id,
         ts.id                              as sale_id,
         ti.sold,
         -- Scheduled start: the moment the round RAN.
         (ts.sale_date::date
            + coalesce(ts.sale_time, '00:00')::time)      as sale_moment,
         -- And when bidding closed. A round that has not ended cannot have
         -- failed yet -- the package still has a live chance of selling.
         (ts.sale_date::date
            + coalesce(ts.sale_end_time, ts.sale_time, '00:00')::time)
                                                          as end_moment
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
), agg as (
  select fp_id,
         count(*)                       as tender_count,
         bool_or(sold)                  as ever_sold
    from rounds group by fp_id
)
select fp.id                              as forfeited_package_id,
       fp.package_id,
       fp.item_id,
       fp.sr_number,
       fp.consignee_name,
       fp.yard,
       fp.entry_qty,
       fp.forfeited_at,
       -- ⚠️ The search box scans the ITEM NAME as well as the SR number and
       -- consignee, and forfeiture is per item -- so the name is resolved the
       -- way unsoldItemName() does: the forfeited row's own item first,
       -- falling back to the package's first. Without this one column the
       -- search would have stayed in Dart and dragged the whole list back.
       coalesce(pi.item_name,
                (select i2.item_name from public.package_items i2
                  where i2.package_id = fp.package_id
                  order by i2.created_at limit 1))  as item_name,
       a.tender_count,
       tc.submitted_value,
       tc.submitted_at,
       up.id                              as proposal_id,
       up.proposal,
       up.decided_at,
       up.delivered
  from public.forfeited_packages fp
  join agg a                        on a.fp_id = fp.id
  left join public.package_items pi  on pi.id = fp.item_id
  join public.tender_committees tc   on tc.forfeited_package_id = fp.id
  left join public.unsold_proposals up on up.forfeited_package_id = fp.id
 where not a.ever_sold                               -- 1
   and a.tender_count > 3                            -- 2
   and tc.submitted_value is not null                -- 3
   and tc.submitted_at is not null
   and exists (                                      -- 4
     select 1 from rounds r
      where r.fp_id = fp.id
        and r.sale_moment > tc.submitted_at
        and r.end_moment < now());

grant select on public.exhausted_unsold to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  bad int;
  n   int;
begin
  -- ⚠️ Nothing that SOLD may be here. A sold package is finished.
  select count(*) into bad
    from public.exhausted_unsold e
    join public.tender_sale_items ti
      on ti.forfeited_package_id = e.forfeited_package_id
   where ti.sold;
  if bad <> 0 then
    raise exception '% exhausted row(s) actually sold', bad;
  end if;

  -- Nothing may be here on fewer than four rounds.
  select count(*) into bad
    from public.exhausted_unsold where tender_count <= 3;
  if bad <> 0 then
    raise exception '% row(s) have not exhausted the tender route', bad;
  end if;

  -- ⚠️ And every row must have a round that ran AFTER the ADG submitted. This
  -- is the condition whose absence let the DG decide the outcome of a package
  -- that still had a live chance of selling.
  select count(*) into bad
    from public.exhausted_unsold e
   where not exists (
     select 1
       from public.tender_sale_items ti
       join public.tender_sales ts on ts.id = ti.tender_sale_id
      where ti.forfeited_package_id = e.forfeited_package_id
        and (ts.sale_date::date + coalesce(ts.sale_time, '00:00')::time)
            > e.submitted_at);
  if bad <> 0 then
    raise exception '% row(s) reached the DG before their committee round ran',
      bad;
  end if;

  select count(*) into n from public.exhausted_unsold;
  -- Every row must be searchable by name, or the search box quietly stops
  -- matching goods it used to find.
  select count(*) into bad
    from public.exhausted_unsold where item_name is null;
  if bad <> 0 then
    raise exception '% row(s) have no item name to search on', bad;
  end if;

  raise notice '% package(s) have run out of tenders; % already decided',
    n, (select count(*) from public.exhausted_unsold where proposal is not null);
  for r in
    select sr_number, tender_count, coalesce(proposal, '(awaiting)') as outcome
      from public.exhausted_unsold order by sr_number
  loop
    raise notice '  %  % rounds  %',
      rpad(r.sr_number, 22), r.tender_count, r.outcome;
  end loop;
end
$verify$;
