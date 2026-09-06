-- ============================================================================
--  A perishable that SELLS at tender has its final outcome already.
--
--  ⚠️ The bug this fixes, seen on CED/GL1/SR/30/2026 (Butter Blocks 25kg):
--  the item sold for Rs 5,533,000 and appears on Sold Goods, yet the
--  Perishable page still reads "Awaiting Top Management". The two pages
--  disagree about the same goods.
--
--  The cause is that `perishable_rows` only ever looked at `unsold_proposals`.
--  That is the right source for a perishable whose Special Tender Sale FAILED
--  -- one failed sale is the end of the road, and the DG decides what becomes
--  of it. But a perishable that SOLD never reaches the DG at all: selling IS
--  the outcome. With nothing recording that, the row sat waiting for a
--  decision nobody was ever going to make.
--
--  So the view now also reports whether the item sold, at what price, and
--  when. The app shows "Sold" as the final outcome when it did, and falls back
--  to the proposal (or "Awaiting") when it did not.
--
--  ⚠️ Read from tender_sale_items, NOT written into unsold_proposals. A sale
--  is not a proposal: inventing a row there would put sold goods on the DG's
--  Unsold Goods desk, which is the opposite of what should happen, and would
--  double-count them in every report that reads that table.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.perishable_rows;

create view public.perishable_rows as
select
  pi.id                                      as item_id,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.item_name,
  pi.hs_code,
  pi.quantity,
  pi.unit_value,
  -- The Post Status Activity filter reads this verbatim.
  pi.reasons,
  pi.status,
  -- ⚠️ The date the page sorts and filters on. entryDate is nullable and the
  -- app falls back to createdAt, so a row without one does not vanish from a
  -- date filter its neighbours answer.
  coalesce(p.entry_date, p.created_at)       as effective_date,
  -- The final outcome, when Top Management has ruled. Null while it has not.
  up.id                                      as proposal_id,
  up.proposal,
  up.decided_at,
  up.delivered,
  -- Whether it has gone to Central Disposal. Shown as the row's own state.
  (dri.forfeited_package_id is not null)     as sent,
  -- ⚠️ Sold at tender: the outcome for a perishable that found a buyer. This
  -- is a DIFFERENT ending from a proposal, and the app must be able to tell
  -- them apart -- a sale never goes to the DG.
  coalesce(sale.sold, false)                 as sold,
  sale.sold_price,
  sale.sold_at,
  sale.receipt_number
from public.package_items pi
join public.packages p on p.id = pi.package_id
-- The forfeited row a perishable disposal request points at, if any.
left join lateral (
  select fp.id
    from public.forfeited_packages fp
   where fp.package_id = p.id
     and fp.item_id = pi.id
     and fp.source = 'perishable'
   limit 1) fpx on true
left join lateral (
  select dri2.forfeited_package_id
    from public.disposal_request_items dri2
   where dri2.forfeited_package_id = fpx.id
   limit 1) dri on true
left join public.unsold_proposals up
       on up.forfeited_package_id = fpx.id
-- ⚠️ The SOLD round, if there is one. A package can sit in several rounds;
-- only one of them can have sold it, so this picks that row rather than the
-- latest.
left join lateral (
  select ti.sold, ti.sold_price, ti.sold_at, ti.receipt_number
    from public.tender_sale_items ti
   where ti.forfeited_package_id = fpx.id
     and ti.sold
   order by ti.sold_at desc nulls last
   limit 1) sale on true
where pi.nature = 'perishable'
  -- ⚠️ Sent items drop off UNLESS an outcome came back -- a Top Management
  -- proposal, OR a sale. Before this, a perishable that sold simply vanished
  -- from the page that is supposed to show what became of it.
  and (dri.forfeited_package_id is null
       or up.id is not null
       or sale.sold is not null);

grant select on public.perishable_rows to public;

comment on view public.perishable_rows is
  'Perishable package items, with their final outcome: a Top Management '
  'proposal, or a sale at tender. See postgres/36.';

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n_rows int;
  n_sold int;
  bad    int;
begin
  select count(*) into n_rows from public.perishable_rows;
  select count(*) into n_sold from public.perishable_rows where sold;

  -- ⚠️ Nothing may be both sold AND carrying a proposal: selling means the
  -- goods never reached the DG, so a row with both is a contradiction.
  select count(*) into bad
    from public.perishable_rows where sold and proposal is not null;
  if bad <> 0 then
    raise exception '% perishable(s) are both sold and have a proposal', bad;
  end if;

  -- A sold row must carry a price.
  select count(*) into bad
    from public.perishable_rows where sold and sold_price is null;
  if bad <> 0 then
    raise exception '% sold perishable(s) have no price', bad;
  end if;

  -- The case that prompted this: it must now be visible AND marked sold.
  if not exists (select 1 from public.perishable_rows
                  where sr_number = 'CED/GL1/SR/30/2026' and sold) then
    raise warning 'CED/GL1/SR/30/2026 is not showing as sold -- check the '
                  'forfeited row is source=perishable';
  end if;

  raise notice 'perishable_rows: % row(s), % sold at tender', n_rows, n_sold;
  raise notice '  awaiting a decision: %',
    (select count(*) from public.perishable_rows
      where not sold and proposal is null);
  raise notice '  decided by Top Management: %',
    (select count(*) from public.perishable_rows where proposal is not null);
end
$verify$;
