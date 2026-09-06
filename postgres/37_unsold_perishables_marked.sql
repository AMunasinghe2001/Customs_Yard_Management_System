-- ============================================================================
--  unsold_perishables: a package is unsold when an OFFICER says so.
--
--  ⚠️ postgres/32 selected "the sale has ended and it did not sell", which was
--  the rule the whole app used at the time. That rule has since gone: a clock
--  should not decide an outcome, and Central Disposal now marks every item
--  Sold or Unsold by hand (postgres/34).
--
--  This view was left behind, and the two portals disagreed because of it.
--  CED/GL1/SR/17/2026 sits in TS/GL1/2026/SP05 with sold=false AND
--  unsold=false -- nobody has decided yet -- so Central Disposal's worklist
--  still offers it, while the DG's Unsold Perishables tab was already
--  presenting it for a final decision. The DG could rule on goods the
--  directorate had not finished with.
--
--  So membership is now the mark: the item was MARKED unsold. Everything else
--  about the view is unchanged -- perishables get one round, and a failed
--  Special Tender Sale is still the end of the road.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.unsold_perishables;

create view public.unsold_perishables as
with agg as (
  select ti.forfeited_package_id            as fp_id,
         count(*)                           as tender_count,
         bool_or(ti.sold)                   as ever_sold,
         -- ⚠️ The mark, not a moment. An officer decided this.
         bool_or(ti.unsold)                 as marked_unsold,
         max(ts.sale_date::date
             + coalesce(ts.sale_time, '00:00')::time) as last_sale_moment
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
   group by ti.forfeited_package_id
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
       -- first, falling back to the package's first.
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
   and a.marked_unsold;

comment on view public.unsold_perishables is
  'Perishable forfeits an officer has MARKED unsold. One failed sale is the '
  'end of the road for goods that spoil -- see postgres/32 and /37.';

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n_view    int;
  bad       int;
begin
  select count(*) into n_view from public.unsold_perishables;

  -- Nothing that sold may appear.
  select count(*) into bad
    from public.unsold_perishables v
   where exists (select 1 from public.tender_sale_items ti
                  where ti.forfeited_package_id = v.forfeited_package_id
                    and ti.sold);
  if bad <> 0 then
    raise exception 'unsold_perishables contains % SOLD package(s)', bad;
  end if;

  -- Nothing that is not a perishable may appear.
  select count(*) into bad
    from public.unsold_perishables v
    join public.forfeited_packages fp on fp.id = v.forfeited_package_id
   where fp.source <> 'perishable';
  if bad <> 0 then
    raise exception 'unsold_perishables contains % non-perishable(s)', bad;
  end if;

  -- ⚠️ And nothing UNDECIDED. This is the fix: a package Central Disposal has
  -- not finished with must not be on the DG's desk.
  select count(*) into bad
    from public.unsold_perishables v
   where not exists (select 1 from public.tender_sale_items ti
                      where ti.forfeited_package_id = v.forfeited_package_id
                        and ti.unsold);
  if bad <> 0 then
    raise exception '% perishable(s) reached the DG without being marked '
                    'unsold', bad;
  end if;

  raise notice 'unsold_perishables = % row(s), every one marked unsold',
    n_view;
  raise notice '  perishable forfeits in total : %',
    (select count(*) from public.forfeited_packages where source = 'perishable');
  raise notice '  still undecided at Central Disposal: %',
    (select count(*) from public.forfeited_packages fp
      join public.tender_sale_items ti on ti.forfeited_package_id = fp.id
     where fp.source = 'perishable' and not ti.sold and not ti.unsold);
end
$verify$;
