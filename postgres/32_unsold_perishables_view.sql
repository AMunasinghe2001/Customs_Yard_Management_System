-- ============================================================================
--  unsold_perishables -- the Top Management Directorate's Unsold Perishables
--  tab, decided in SQL.
--
--  ⚠️ Perishables do NOT go round again, and never reach a tender committee.
--  Normal goods run the Valuation Tender plus Tenders 1-3, get a committee
--  valuation and one more round -- five chances over months. Goods that spoil
--  do not have months: ONE failed sale is the end of the road, and Top
--  Management decides their outcome straight away.
--
--  So this deliberately does NOT test tender_count, a committee, or an ADG
--  submission the way `exhausted_unsold` (postgres/23) does. The condition is:
--  the package is a perishable, it went to a sale, that sale has ENDED, and it
--  did not sell.
--
--  ⚠️ "Has ended" is judged by the scheduled end moment
--  (sale_date + sale_end_time), never by created_at -- the same rule
--  postgres/23 documents. A round that has not closed cannot have failed yet:
--  the goods still have a live chance of selling, and putting them on the DG's
--  desk while bidding is open would be deciding their fate early.
--
--  Replaces `getUnsoldPerishables()`, which fetched EVERY unsold tender sale
--  with its items, forfeited rows, packages, package items and warehouse
--  entries, then filtered to `source = 'perishable'` in Dart -- so the tab paid
--  for the whole tender history of every yard to show twenty rows.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.unsold_perishables;

create view public.unsold_perishables as
with rounds as (
  select ti.forfeited_package_id            as fp_id,
         ti.sold,
         (ts.sale_date::date
            + coalesce(ts.sale_time, '00:00')::time)      as sale_moment,
         (ts.sale_date::date
            + coalesce(ts.sale_end_time, ts.sale_time, '00:00')::time)
                                                          as end_moment
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
), agg as (
  select fp_id,
         count(*)                       as tender_count,
         bool_or(sold)                  as ever_sold,
         max(sale_moment)               as last_sale_moment,
         -- Has any round actually closed? One still open means the goods
         -- have not failed yet.
         bool_or(end_moment <= now())   as any_round_ended
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
       -- Resolved the way unsoldItemName() does: the forfeited row's own item
       -- first, falling back to the package's first. Without it the search
       -- box would have kept the whole list in Dart.
       coalesce(pi.item_name,
                (select i2.item_name from public.package_items i2
                  where i2.package_id = fp.package_id
                  order by i2.created_at limit 1))  as item_name,
       p.case_number,
       a.tender_count,
       a.last_sale_moment,
       up.id                              as proposal_id,
       up.proposal,
       up.decided_at,
       up.delivered
  from public.forfeited_packages fp
  join agg a                         on a.fp_id = fp.id
  left join public.package_items pi   on pi.id = fp.item_id
  left join public.packages p         on p.id = fp.package_id
  left join public.unsold_proposals up on up.forfeited_package_id = fp.id
 where fp.source = 'perishable'
   and not a.ever_sold
   and a.any_round_ended;

comment on view public.unsold_perishables is
  'Perishable forfeits whose one tender sale has ended without selling. '
  'One failed sale is the end of the road for goods that spoil -- see '
  'postgres/32.';

-- ── Verify ────────────────────────────────────────────────────────────────
-- Claims checked against live data, so a migration that "ran fine" but
-- selects the wrong set fails loudly here rather than quietly on screen.
do $verify$
declare
  n_view       int;
  n_perishable int;
  n_sold       int;
  n_open       int;
begin
  select count(*) into n_view from public.unsold_perishables;

  -- Nothing that sold may appear.
  select count(*) into n_sold
    from public.unsold_perishables v
   where exists (select 1 from public.tender_sale_items ti
                  where ti.forfeited_package_id = v.forfeited_package_id
                    and ti.sold);
  if n_sold <> 0 then
    raise exception 'unsold_perishables contains % SOLD package(s)', n_sold;
  end if;

  -- Nothing that is not a perishable may appear.
  select count(*) into n_perishable
    from public.unsold_perishables v
    join public.forfeited_packages fp
      on fp.id = v.forfeited_package_id
   where fp.source <> 'perishable';
  if n_perishable <> 0 then
    raise exception 'unsold_perishables contains % non-perishable(s)',
      n_perishable;
  end if;

  -- Nothing whose every round is still open may appear.
  select count(*) into n_open
    from public.unsold_perishables v
   where not exists (
     select 1 from public.tender_sale_items ti
       join public.tender_sales ts on ts.id = ti.tender_sale_id
      where ti.forfeited_package_id = v.forfeited_package_id
        and (ts.sale_date::date
             + coalesce(ts.sale_end_time, ts.sale_time, '00:00')::time)
            <= now());
  if n_open <> 0 then
    raise exception 'unsold_perishables contains % package(s) whose sale is '
                    'still open', n_open;
  end if;

  raise notice 'OK: unsold_perishables = % row(s)', n_view;
  raise notice '    perishable forfeits in total : %',
    (select count(*) from public.forfeited_packages
      where source = 'perishable');
end
$verify$;
