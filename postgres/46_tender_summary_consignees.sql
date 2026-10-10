-- ============================================================================
--  `tender_sale_summary` gains a `consignees` column, and its yard list keeps
--  the name the app already asks for.
--
--  ⚠️ Top Management's Tender Sales tab pages against this view, and BOTH its
--  filters were throwing:
--
--      column "item_yards" does not exist
--      column "consignees" does not exist
--
--  The service asks for `item_yards`; the view calls it `yards`. And nothing
--  ever carried the consignee names the search claims to match. Neither
--  failure was visible on the page -- picking a yard or typing a search simply
--  errored the tab, and the "all sales" case that nobody filters kept working,
--  so it looked fine.
--
--  Fixing the view rather than the caller: `sr_numbers` and `yards` are the
--  established shape here, `consignees` completes the trio the search names,
--  and the caller's `item_yards` is the clearer name for what it holds -- the
--  yards of the ITEMS in a sale, not the sale's own `yard` column. Both names
--  are provided so neither side has to guess.
--
--  Everything else is postgres/35's body, verbatim.
-- ============================================================================

drop view if exists public.tender_sale_summary cascade;

create view public.tender_sale_summary as
with agg as (
  select
    ti.tender_sale_id as sale_id,
    count(*) as item_count,
    count(*) filter (where ti.sold) as sold_count,
    count(*) filter (where ti.unsold) as unsold_count,
    -- ⚠️ UNDECIDED, not "not sold". An item marked unsold has been decided;
    -- counting it as pending kept a finished sale on the worklist.
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
  agg.undecided_count > 0 as has_pending,

  -- ⚠️ Pipe-wrapped, every one of them, so an `ilike '%|GL1|%'` matches a
  -- whole value and cannot run across two neighbouring entries.
  (select '|' || string_agg(distinct coalesce(fp.yard, ''), '|') || '|'
     from public.tender_sale_items ti2
     join public.forfeited_packages fp on fp.id = ti2.forfeited_package_id
    where ti2.tender_sale_id = ts.id) as yards,

  -- The same list under the name the app asks for: these are the yards of the
  -- ITEMS in the sale, which is the distinction that matters -- a sale can mix
  -- items from a multi-directorate yard, and `ts.yard` cannot tell them apart.
  (select '|' || string_agg(distinct coalesce(fp.yard, ''), '|') || '|'
     from public.tender_sale_items ti2
     join public.forfeited_packages fp on fp.id = ti2.forfeited_package_id
    where ti2.tender_sale_id = ts.id) as item_yards,

  (select '|' || string_agg(distinct coalesce(fp.sr_number, ''), '|') || '|'
     from public.tender_sale_items ti2
     join public.forfeited_packages fp on fp.id = ti2.forfeited_package_id
    where ti2.tender_sale_id = ts.id) as sr_numbers,

  -- New: the consignees a sale touches, which the search has always claimed
  -- to match and never could.
  (select '|' || string_agg(distinct coalesce(fp.consignee_name, ''), '|') || '|'
     from public.tender_sale_items ti2
     join public.forfeited_packages fp on fp.id = ti2.forfeited_package_id
    where ti2.tender_sale_id = ts.id) as consignees,

  -- A sale RE-TENDERS goods when an earlier sale already offered the same
  -- item. Keyed on the item where there is one, else the forfeited row.
  exists (
    select 1
      from public.tender_sale_items a
      join public.forfeited_packages fpa on fpa.id = a.forfeited_package_id
      join public.tender_sale_items b on true
      join public.forfeited_packages fpb on fpb.id = b.forfeited_package_id
      join public.tender_sales earlier on earlier.id = b.tender_sale_id
     where a.tender_sale_id = ts.id
       and earlier.id <> ts.id
       and earlier.created_at < ts.created_at
       and coalesce(fpa.item_id::text, fpa.id::text)
           = coalesce(fpb.item_id::text, fpb.id::text)) as is_retender

from public.tender_sales ts
join agg on agg.sale_id = ts.id;

comment on view public.tender_sale_summary is
  'One row per tender sale with its item counts and the SR numbers, yards and '
  'consignees it touches, each pipe-wrapped for whole-value matching. '
  '`has_pending` means UNDECIDED items remain.';


-- ── The filters that were throwing must now answer ───────────────────────
do $verify$
declare
  n_sales    int;
  n_yard     int;
  n_cons     int;
  n_pending  int;
  bad        int;
begin
  select count(*) into n_sales from public.tender_sale_summary;

  -- ⚠️ The two columns whose absence broke both filters. Selecting them is
  -- the test: a missing column raises 42703 right here rather than in the app.
  select count(*) into n_yard
    from public.tender_sale_summary where item_yards ilike '%|GL1|%';
  select count(*) into n_cons
    from public.tender_sale_summary where consignees is not null;

  if n_yard = 0 then
    raise exception 'no sale touches yard GL1 -- item_yards is not being '
                    'filled in';
  end if;
  if n_cons <> n_sales then
    raise exception 'consignees is null on % of % sales',
      n_sales - n_cons, n_sales;
  end if;

  -- Both names for the yard list must agree, or a caller picks the wrong one
  -- and gets a different answer.
  select count(*) into bad
    from public.tender_sale_summary
   where coalesce(yards, '') <> coalesce(item_yards, '');
  if bad <> 0 then
    raise exception '% sale(s) have yards and item_yards disagreeing', bad;
  end if;

  -- Every value pipe-wrapped, so a search cannot match across two entries.
  select count(*) into bad
    from public.tender_sale_summary
   where consignees not like '|%|' or item_yards not like '|%|'
      or sr_numbers not like '|%|';
  if bad <> 0 then
    raise exception '% row(s) are not pipe-wrapped', bad;
  end if;

  -- /35's rule: pending means UNDECIDED.
  select count(*) into n_pending
    from public.tender_sale_summary where has_pending;
  select count(*) into bad
    from public.tender_sale_summary
   where has_pending <> (undecided_count > 0);
  if bad <> 0 then
    raise exception '% sale(s) report has_pending against their own '
                    'undecided count', bad;
  end if;

  raise notice 'tender_sale_summary: % sale(s), % with work outstanding; '
               'GL1 touches %', n_sales, n_pending, n_yard;
end
$verify$;
