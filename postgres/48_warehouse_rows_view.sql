-- One row per live warehouse entry, with everything its table filters on.
--
-- ⚠️ The Warehouses page loaded a whole facility's entries and filtered them
-- in Dart — six filters, one of which needed the PACKAGE ITEM behind each
-- entry, so it read `packageDataProvider(e.packageId)` per row: a
-- getPackageById per entry, each pulling the package with its items, its
-- warehouse entries, those entries' warehouses and the returning officer's
-- profile. Then it paged the result with `pageSlice`, which still loads
-- everything and only renders less.
--
-- The rules, transcribed from the screen:
--
--   * RETURNED entries never appear. This page is what the facility holds.
--
--   * ⚠️ Nor do goods that have LEFT the yard under a final disposition —
--     released, returned, sold, re-exported, destroyed, other. The entry is
--     still open because nobody closed it, but the goods are gone, and
--     listing them tells an officer to go and find something that is not
--     there.
--
--   * item_status is the status of the item this entry bills, with 'Forfiet'
--     folded into 'Forfeit' — a typo that reached the data and would
--     otherwise split one filter choice into two.
--
--   * The year filter matches EITHER the SR number's year segment or the
--     admission year: an SR filed in one year can be admitted in the next,
--     and an officer looking for either should find it.

drop view if exists public.warehouse_rows cascade;

create view public.warehouse_rows as
select
  we.id as entry_id,
  we.warehouse_id,
  we.package_id,
  we.package_item_id,
  p.sr_number,
  p.consignee_name,
  we.hold_reason,
  we.item_count,
  we.admitted_at,

  -- The goods on this row.
  pi.item_name,

  -- ⚠️ Normalised. 'Forfiet' is a typo that reached the data; folding it here
  -- keeps the filter's one choice from matching only half its rows.
  case
    when lower(trim(coalesce(pi.status, ''))) = 'forfiet' then 'Forfeit'
    else pi.status
  end as item_status,

  -- The package-level status the 'confiscated' filter reads.
  p.status as package_status,
  lower(coalesce(p.status, '')) = 'confiscated' as is_package_confiscated,

  -- Both of the year filter's answers, so it can match either.
  extract(year from we.admitted_at at time zone 'Asia/Colombo')::text
    as admitted_year,
  substring(p.sr_number, '(20[0-9]{2})') as sr_year

from public.warehouse_entries we
join public.packages p on p.id = we.package_id
left join public.package_items pi on pi.id = we.package_item_id
where
  not coalesce(we.is_returned, false)
  -- Goods with a final disposition have left the yard.
  and lower(trim(coalesce(pi.status, ''))) not in
      ('released', 'returned', 'sold', 're-export', 're-exported',
       'destroy', 'destroyed', 'other');

comment on view public.warehouse_rows is
  'Live warehouse entries — not returned, and not goods that have left the '
  'yard under a final disposition — with the item status, hold reason and '
  'both year values the Warehouses page filters on.';


-- ── Against the Dart it replaces ─────────────────────────────────────────
do $verify$
declare
  n_rows      int;
  n_entries   int;
  n_returned  int;
  n_left      int;
  bad         int;
begin
  select count(*) into n_rows from public.warehouse_rows;
  select count(*) into n_entries from public.warehouse_entries;
  select count(*) into n_returned
    from public.warehouse_entries where coalesce(is_returned, false);

  -- The rows dropped for having left the yard.
  select count(*) into n_left
    from public.warehouse_entries we
    left join public.package_items pi on pi.id = we.package_item_id
   where not coalesce(we.is_returned, false)
     and lower(trim(coalesce(pi.status, ''))) in
         ('released', 'returned', 'sold', 're-export', 're-exported',
          'destroy', 'destroyed', 'other');

  if n_rows <> n_entries - n_returned - n_left then
    raise exception 'warehouse_rows holds %, expected % - % returned - % '
                    'departed', n_rows, n_entries, n_returned, n_left;
  end if;

  -- No returned entry may appear.
  select count(*) into bad
    from public.warehouse_rows r
    join public.warehouse_entries we on we.id = r.entry_id
   where coalesce(we.is_returned, false);
  if bad <> 0 then
    raise exception '% returned entr(ies) are on the live list', bad;
  end if;

  -- ⚠️ Nor any goods that have left. This is the rule an officer notices
  -- when it breaks: they are sent to find something that is not there.
  select count(*) into bad
    from public.warehouse_rows
   where lower(trim(coalesce(item_status, ''))) in
         ('released', 'returned', 'sold', 're-export', 're-exported',
          'destroy', 'destroyed', 'other');
  if bad <> 0 then
    raise exception '% departed item(s) are still listed as held', bad;
  end if;

  -- The typo is folded, not merely lowercased.
  select count(*) into bad
    from public.warehouse_rows where item_status = 'Forfiet';
  if bad <> 0 then
    raise exception '% row(s) still carry the Forfiet spelling', bad;
  end if;

  raise notice 'warehouse_rows: % live row(s) of % entries (% returned, % departed)',
    n_rows, n_entries, n_returned, n_left;
end
$verify$;
