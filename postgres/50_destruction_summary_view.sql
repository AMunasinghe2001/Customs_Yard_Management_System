-- One row per destruction, with the SR numbers, yards and consignees it
-- touches.
--
-- ⚠️ The yard's Destruction page loaded EVERY destruction with its items,
-- their forfeited rows, packages, package items and warehouse entries, then
-- filtered by yard, search, date range and year in Dart and paged the result
-- with `pageSlice`. Client-side paging still loads everything; it only renders
-- less.
--
-- The same shape as `tender_sale_summary`, and for the same reasons:
--
-- ⚠️ The yard match is on the yards a destruction's ITEMS carry, not on the
--    `destructions.yard` column. A destruction can mix items from a
--    multi-directorate yard, and the sale-level code cannot tell them apart.
--    Older rows leave `destruction_items.yard` empty, so the forfeited row's
--    yard stands in — the screen's `effectiveYard` rule.
--
-- ⚠️ Every list is pipe-wrapped, so `ilike '%|GL1|%'` matches a whole value
--    and cannot run across two neighbouring entries.

drop view if exists public.destruction_summary cascade;

create view public.destruction_summary as
with agg as (
  select
    di.destruction_id,
    count(*) as item_count,
    count(*) filter (where di.destroyed) as destroyed_count,
    count(*) filter (where not di.destroyed) as pending_count
  from public.destruction_items di
  group by di.destruction_id
)
select
  d.id,
  d.sale_number,
  d.sale_date,
  d.sale_time,
  d.sale_end_time,
  d.tender_type,
  d.yard,
  d.created_at,
  agg.item_count,
  agg.destroyed_count,
  agg.pending_count,
  agg.pending_count > 0 as has_pending,

  -- The yards the ITEMS carry, with the forfeited row standing in for an
  -- empty destruction_items.yard.
  (select '|' || string_agg(distinct
            coalesce(nullif(trim(di2.yard), ''), fp.yard, ''), '|') || '|'
     from public.destruction_items di2
     left join public.forfeited_packages fp on fp.id = di2.forfeited_package_id
    where di2.destruction_id = d.id) as item_yards,

  (select '|' || string_agg(distinct coalesce(fp.sr_number, ''), '|') || '|'
     from public.destruction_items di2
     join public.forfeited_packages fp on fp.id = di2.forfeited_package_id
    where di2.destruction_id = d.id) as sr_numbers,

  (select '|' || string_agg(distinct coalesce(fp.consignee_name, ''), '|') || '|'
     from public.destruction_items di2
     join public.forfeited_packages fp on fp.id = di2.forfeited_package_id
    where di2.destruction_id = d.id) as consignees,

  -- A destruction RE-DESTROYS goods when an earlier one already held the same
  -- item. Keyed on the item where there is one, else the forfeited row.
  exists (
    select 1
      from public.destruction_items a
      join public.forfeited_packages fpa on fpa.id = a.forfeited_package_id
      join public.destruction_items b on true
      join public.forfeited_packages fpb on fpb.id = b.forfeited_package_id
      join public.destructions earlier on earlier.id = b.destruction_id
     where a.destruction_id = d.id
       and earlier.id <> d.id
       and earlier.created_at < d.created_at
       and coalesce(fpa.item_id::text, fpa.id::text)
           = coalesce(fpb.item_id::text, fpb.id::text)) as is_redestruction

from public.destructions d
join agg on agg.destruction_id = d.id;

comment on view public.destruction_summary is
  'One row per destruction with its item counts and the SR numbers, yards and '
  'consignees it touches, each pipe-wrapped for whole-value matching.';


-- ── Does it hold every destruction, and can the filters answer? ──────────
do $verify$
declare
  n_rows      int;
  n_dest      int;
  n_yard      int;
  n_items     int;
  n_counted   int;
  bad         int;
begin
  select count(*) into n_rows from public.destruction_summary;
  -- ⚠️ A destruction with no items is not on this list, and that is the
  -- screen's own behaviour: the card is a list of goods.
  select count(distinct destruction_id) into n_dest
    from public.destruction_items;
  if n_rows <> n_dest then
    raise exception 'destruction_summary holds % of % destructions with items',
      n_rows, n_dest;
  end if;

  -- The columns whose absence broke both filters on the tender page.
  select count(*) into n_yard
    from public.destruction_summary where item_yards ilike '%|GL1|%';
  if n_yard = 0 then
    raise exception 'no destruction touches yard GL1 -- item_yards is not '
                    'being filled in';
  end if;

  select count(*) into bad
    from public.destruction_summary where consignees is null;
  if bad <> 0 then
    raise exception 'consignees is null on % destruction(s)', bad;
  end if;

  -- Every value pipe-wrapped.
  select count(*) into bad
    from public.destruction_summary
   where consignees not like '|%|' or item_yards not like '|%|'
      or sr_numbers not like '|%|';
  if bad <> 0 then
    raise exception '% row(s) are not pipe-wrapped', bad;
  end if;

  -- The counts add up to the items themselves.
  select count(*) into n_items from public.destruction_items;
  select coalesce(sum(item_count), 0) into n_counted
    from public.destruction_summary;
  if n_items <> n_counted then
    raise exception 'items: % in the table, % counted by the view',
      n_items, n_counted;
  end if;

  raise notice 'destruction_summary: % destruction(s), % item(s); GL1 touches %',
    n_rows, n_items, n_yard;
end
$verify$;
