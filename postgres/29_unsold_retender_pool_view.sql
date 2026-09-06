-- ============================================================================
--  Unsold Tenders layers THREE whole-table computations on top of each other.
--
--  The tab reads:
--      unsoldTenderSalesProvider  -> getUnsoldTenderSales()
--      reTenderEligibleProvider   -> getReTenderEligibleIds()
--      exhaustedUnsoldProvider    -> getExhaustedUnsoldPackages()
--
--  ...and every one of those begins by fetching EVERY tender sale with its
--  items, forfeited rows, packages, package items and warehouse entries. Three
--  passes over the whole yard to draw twenty cards, and Central Disposal shows
--  all twenty-eight yards.
--
--  This view answers the pool's membership question once, in SQL.
--
--  The rule, from getUnsoldTenderSales:
--    1. The package is in at least one tender sale.
--    2. It has NOT sold in any of them.
--    3. Its CURRENT round (the newest by created_at) is over -- either the row
--       is explicitly marked unsold, or the sale's deadline has passed.
--    4. It is not PERISHABLE. ⚠️ Goods that spoil get no second round: one
--       failed Special Tender Sale and they go straight to Top Management.
--       Offering them again would offer goods that will not last the wait, and
--       would hide them from the DG, who is the only one who can act.
--  ...and then, from the tab itself:
--    5. It has not EXHAUSTED the route -- a package whose committee-priced
--       tender also failed belongs to Unsold Goods, where the DG rules on it,
--       not to this re-tender pool.
--
--  ⚠️ Condition 3's DEADLINE half stays in Dart, for the same reason the
--  Tender Sales view leaves it there: `unsoldDeadline` -> `workingDeadline`
--  rolls past weekends and Sri Lankan public holidays fetched from an API at
--  runtime, and there is no holiday table here. What SQL can settle is the
--  scheduled SALE MOMENT; a row whose deadline falls in the grace window is
--  included here and filtered by the page, the same split the Tender Sales tab
--  uses.
--
--  ⚠️ There is also no "unsold" COLUMN to read: the model has the field and it
--  is always false. A round is unsold when it is not sold and its deadline has
--  passed, which is why condition 3 needs the calendar at all.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.unsold_retender_pool;

create view public.unsold_retender_pool as
with rounds as (
  select ti.forfeited_package_id                     as fp_id,
         ti.tender_sale_id,
         ti.sold,
         ts.created_at                               as round_created,
         (ts.sale_date::date
            + coalesce(ts.sale_time, '00:00')::time) as sale_moment
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
), agg as (
  select fp_id,
         count(*)                       as round_count,
         bool_or(sold)                  as ever_sold,
         max(round_created)             as latest_round_created
    from rounds group by fp_id
), latest as (
  -- The CURRENT round: newest by created_at, exactly as the app sorts.
  select distinct on (r.fp_id)
         r.fp_id, r.tender_sale_id, r.sale_moment
    from rounds r
   order by r.fp_id, r.round_created desc
)
select
  fp.id                                    as forfeited_package_id,
  fp.package_id,
  fp.item_id,
  fp.sr_number,
  fp.consignee_name,
  fp.yard,
  fp.entry_qty,
  fp.source,
  fp.forfeited_at,
  p.case_number,
  coalesce(pi.item_name,
           (select i2.item_name from public.package_items i2
             where i2.package_id = fp.package_id
             order by i2.created_at limit 1))  as item_name,
  a.round_count,
  l.sale_moment                            as latest_sale_moment,
  -- ⚠️ There is NO `unsold` column on tender_sale_items -- the model reads
  -- one and it is always false, because a round is unsold when it is NOT sold
  -- and its deadline has passed. So the only half SQL can settle is whether
  -- the current round's scheduled moment is already behind us; the DEADLINE
  -- (sale date + the following working day, past weekends and Sri Lankan
  -- public holidays) needs the calendar the app fetches at runtime, and the
  -- page applies it.
  (l.sale_moment < now())                  as round_moment_passed,
  -- ⚠️ The Committees tab is this same pool narrowed twice: to packages on
  -- their FOURTH round (Valuation Tender + Tenders 1-3 all failed), and to
  -- those that actually have a committee appointed. Both are settled here so
  -- the tab is one query rather than three providers intersected in Dart.
  --
  -- A card leaves that tab when the committee-priced tender ALSO fails, which
  -- is when the package becomes exhausted -- and this view already excludes
  -- exhausted packages, so no separate `movedOn` set is needed.
  exists (select 1 from public.tender_committees tc
           where tc.forfeited_package_id = fp.id)  as has_committee
from public.forfeited_packages fp
join agg a                        on a.fp_id = fp.id
join latest l                     on l.fp_id = fp.id
left join public.package_items pi on pi.id = fp.item_id
left join public.packages p       on p.id = fp.package_id
where not a.ever_sold                                        -- 2
  and coalesce(fp.source, '') <> 'perishable'                -- 4
  -- 5. Not already exhausted: that package belongs to Unsold Goods.
  and not exists (select 1 from public.exhausted_unsold e
                   where e.forfeited_package_id = fp.id);

grant select on public.unsold_retender_pool to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  bad int;
  n   int;
begin
  -- ⚠️ Nothing that SOLD may be offered again.
  select count(*) into bad
    from public.unsold_retender_pool u
    join public.tender_sale_items ti
      on ti.forfeited_package_id = u.forfeited_package_id
   where ti.sold;
  if bad <> 0 then
    raise exception '% sold package(s) are in the re-tender pool', bad;
  end if;

  -- ⚠️ No PERISHABLE. One failed Special Tender Sale and they go to Top
  -- Management; offering them again would hide them from the only person who
  -- can act on goods that will not last the wait.
  select count(*) into bad
    from public.unsold_retender_pool where source = 'perishable';
  if bad <> 0 then
    raise exception '% perishable package(s) are in the re-tender pool', bad;
  end if;

  -- ⚠️ Nothing that has run out of rounds: those belong to Unsold Goods,
  -- where the DG rules on them. A package in BOTH lists would be offered for
  -- re-tender and decided on at the same time.
  select count(*) into bad
    from public.unsold_retender_pool u
    join public.exhausted_unsold e
      on e.forfeited_package_id = u.forfeited_package_id;
  if bad <> 0 then
    raise exception '% exhausted package(s) are also in the re-tender pool',
      bad;
  end if;

  -- Every row must name its current round, or the page cannot tell whether
  -- the window has closed.
  if exists (select 1 from public.unsold_retender_pool
              where latest_sale_moment is null) then
    raise exception 'a pool row has no current round to judge';
  end if;

  -- ⚠️ A committee card must have a committee. The flag has to agree with the
  -- table it is derived from, or the tab shows a card it cannot render.
  select count(*) into bad
    from public.unsold_retender_pool u
   where u.has_committee <> exists (select 1 from public.tender_committees tc
                                     where tc.forfeited_package_id
                                           = u.forfeited_package_id);
  if bad <> 0 then
    raise exception '% row(s) disagree about having a committee', bad;
  end if;

  select count(*) into n from public.unsold_retender_pool;
  raise notice
    '% package(s) in the re-tender pool (% past their round moment); '
    '% exhausted, held back for Top Management',
    n,
    (select count(*) from public.unsold_retender_pool
      where round_moment_passed),
    (select count(*) from public.exhausted_unsold);
  for r in
    select sr_number, round_count, round_moment_passed
      from public.unsold_retender_pool
     order by round_count desc, sr_number limit 4
  loop
    raise notice '  %  % round(s)%',
      rpad(r.sr_number, 22), r.round_count,
      case when r.round_moment_passed then '  [round over]' else '' end;
  end loop;
end
$verify$;
