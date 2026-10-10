-- ============================================================================
--  tender_sale_summary.has_pending must mean "nothing has been decided yet".
--
--  ⚠️ It meant "something is not SOLD", which was the same thing only while
--  unsold was decided by a clock. Now that Central Disposal marks each item
--  Sold or Unsold by hand (postgres/34), an item marked UNSOLD is finished --
--  it has left for the Unsold Tenders pool -- and a sale where every item has
--  been marked one way or the other has nothing left to act on.
--
--  Without this, Central Disposal's worklist keeps showing sales whose every
--  item is already decided, offering an action that has already been taken.
--
--  The yard's own tender page is unaffected: that one is a RECORD and lists
--  every sale, decided or not.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- ⚠️ DROP, not `create or replace`: unsold_count lands mid-list and Postgres
-- refuses a replacement whose column list is not a pure append.
drop view if exists public.tender_sale_summary;

create view public.tender_sale_summary as
with agg as (
  select ti.tender_sale_id                              as sale_id,
         count(*)                                       as item_count,
         count(*) filter (where ti.sold)                as sold_count,
         count(*) filter (where ti.unsold)              as unsold_count,
         -- Anything still awaiting a decision from Central Disposal.
         count(*) filter (where not ti.sold and not ti.unsold) as undecided_count
    from public.tender_sale_items ti
   group by ti.tender_sale_id
)
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
  agg.unsold_count,
  agg.undecided_count,
  -- ⚠️ Pending means UNDECIDED, not unsold. A sale every item of which has
  -- been marked -- some sold, some unsold -- is finished work.
  (agg.undecided_count > 0)                  as has_pending,
  -- ⚠️ Every yard and SR number the sale TOUCHES, not the sale's own yard.
  -- A tender sale can mix items from a multi-directorate yard -- NNR items
  -- filed under CED sitting beside ones filed under PSD -- so the sale-level
  -- yard code cannot tell them apart, and the filter must match any item's.
  --
  -- Pipe-wrapped so an ilike can test membership: '%|GL1|%' matches the whole
  -- code and never a fragment of another.
  (select '|' || string_agg(distinct coalesce(fp.yard, ''), '|') || '|'
     from public.tender_sale_items ti2
     join public.forfeited_packages fp on fp.id = ti2.forfeited_package_id
    where ti2.tender_sale_id = ts.id)        as yards,
  (select '|' || string_agg(distinct coalesce(fp.sr_number, ''), '|') || '|'
     from public.tender_sale_items ti2
     join public.forfeited_packages fp on fp.id = ti2.forfeited_package_id
    where ti2.tender_sale_id = ts.id)        as sr_numbers,
  -- Does this sale re-tender goods that were in an EARLIER one?
  exists (
    select 1
      from public.tender_sale_items a
      join public.forfeited_packages fpa on fpa.id = a.forfeited_package_id
      join public.tender_sale_items b on b.forfeited_package_id <> a.forfeited_package_id
                                      or true
      join public.forfeited_packages fpb on fpb.id = b.forfeited_package_id
      join public.tender_sales earlier on earlier.id = b.tender_sale_id
     where a.tender_sale_id = ts.id
       and earlier.id <> ts.id
       and earlier.created_at < ts.created_at
       and coalesce(fpa.item_id::text, fpa.id::text)
           = coalesce(fpb.item_id::text, fpb.id::text)
  )                                          as is_retender
from public.tender_sales ts
join agg on agg.sale_id = ts.id;

comment on view public.tender_sale_summary is
  'One row per tender sale for Central Disposal''s paged list. has_pending '
  'means UNDECIDED items remain -- see postgres/35.';

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n    int;
  bad  int;
begin
  select count(*) into n from public.tender_sale_summary;

  -- The counts must add up.
  select count(*) into bad
    from public.tender_sale_summary s
   where s.item_count <> s.sold_count + s.unsold_count + s.undecided_count;
  if bad <> 0 then
    raise exception '% sale(s) have counts that do not add up', bad;
  end if;

  -- has_pending is exactly "something is undecided".
  select count(*) into bad
    from public.tender_sale_summary s
   where s.has_pending <> exists (select 1 from public.tender_sale_items ti
                                   where ti.tender_sale_id = s.id
                                     and not ti.sold and not ti.unsold);
  if bad <> 0 then
    raise exception '% sale(s) disagree about having undecided items', bad;
  end if;

  -- ⚠️ And no item is both, which postgres/34's constraint should already
  -- guarantee -- checked here because this view now depends on it.
  select count(*) into bad from public.tender_sale_items
   where sold and unsold;
  if bad <> 0 then
    raise exception '% item(s) are both sold and unsold', bad;
  end if;

  raise notice 'tender_sale_summary: % sale(s)', n;
  raise notice '  with undecided items (Central Disposal''s worklist): %',
    (select count(*) from public.tender_sale_summary where has_pending);
  raise notice '  fully decided (the yard still sees these): %',
    (select count(*) from public.tender_sale_summary where not has_pending);
end
$verify$;
