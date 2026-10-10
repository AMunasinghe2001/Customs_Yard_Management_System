-- ============================================================================
--  Paging in SQL needs the ROWS to exist in SQL.
--
--  The disposition pages (Released / Sold / Destroyed / Re-exported / Other,
--  and the four Final Outcome pages) do not list packages -- they list ITEMS,
--  and a package can produce several rows from two different sources:
--
--    1. a warehouse_entries row whose return_notes carries a [FINAL:...] tag
--    2. an item whose STATUS matches, with no tagged entry (goods that were
--       never warehouse-admitted, so the disposition was recorded on the item)
--
--  The screen merged those two lists in Dart, sorted them by date and then
--  called .skip().take(). That means every row in the yard has to be fetched
--  and built before page 1 can be drawn -- fine at 400 rows, not at 400,000.
--
--  ⚠️ A view, not a table. These rows are a QUESTION asked of the existing
--  data, not a new fact: the moment an officer records a disposition the
--  answer must change, and a table would need a trigger per source to keep up
--  (and would be wrong in between). Nothing is duplicated here.
--
--  The tag sets are the ones the screen already used, kept verbatim:
--    RE-EXPORTED  FINAL:RE-EXPORTED, RE-EXPORTED, RE-EXPORT
--    DESTROYED    FINAL:DESTROYED, FINAL:DESTROY, DESTROYED, DESTROY,
--                 SUPPOSED TO BE DESTROYED
--    SOLD         FINAL:SOLD, SOLD
--    OTHER        FINAL:OTHER, OTHER
--
--  ⚠️ 'FINAL:DESTROY' (no ED) is the PENDING tag disposeWarehouseItem writes --
--  it upper-cases the action name, and the action is "Destroy". Dropping it
--  would hide every package awaiting destruction, which is how they are
--  confirmed.
-- ============================================================================

set lock_timeout = '5s';

create or replace view public.disposition_rows as
-- ── Source 1: a warehouse entry carrying a disposition tag ──────────────────
select
  ('E:' || w.id::text)                       as row_key,
  'entry'::text                              as source,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  w.package_item_id                          as item_id,
  w.id                                       as entry_id,
  null::uuid                                 as proposal_id,
  case
    when tag in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT')
      then 'RE-EXPORTED'
    when tag in ('FINAL:DESTROYED', 'FINAL:DESTROY', 'DESTROYED', 'DESTROY',
                 'SUPPOSED TO BE DESTROYED')
      then 'DESTROYED'
    when tag in ('FINAL:SOLD', 'SOLD')     then 'SOLD'
    when tag in ('FINAL:OTHER', 'OTHER')   then 'OTHER'
  end                                        as final_tag,
  coalesce(pi.item_name,
           (select i2.item_name from public.package_items i2
             where i2.package_id = p.id order by i2.created_at limit 1),
           '—')                              as item_name,
  pi.hs_code,
  coalesce(w.item_count, pi.quantity)        as quantity,
  -- The note the officer typed sits after an em dash inside return_notes.
  nullif(trim(split_part(w.return_notes, '—', 2)), '')  as note,
  -- The officer's name comes from the profile the entry points at; the
  -- entry itself only stores the id.
  coalesce(rp.full_name, rp.badge_number)               as officer,
  -- ⚠️ ONE date column, whatever the source, because the page is sorted by it.
  -- Sorting on a column that is null for half the rows scatters them.
  coalesce(w.returned_at, w.admitted_at, p.updated_at)  as happened_at
from public.warehouse_entries w
join public.packages p            on p.id = w.package_id
left join public.package_items pi on pi.id = w.package_item_id
left join public.profiles rp      on rp.id = w.returned_by
cross join lateral (
  select upper(substring(upper(trim(coalesce(w.return_notes, '')))
                         from '^\[([^\]]+)\]')) as tag) t
where t.tag in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT',
                'FINAL:DESTROYED', 'FINAL:DESTROY', 'DESTROYED', 'DESTROY',
                'SUPPOSED TO BE DESTROYED',
                'FINAL:SOLD', 'SOLD',
                'FINAL:OTHER', 'OTHER')

union all

-- ── Source 2: an item whose STATUS says so, with no tagged entry ────────────
--  Goods that were never warehouse-admitted: the Final Disposition was
--  recorded straight onto the item, so there is no entry to carry a tag.
select
  ('I:' || pi.id::text)                      as row_key,
  'item'::text                               as source,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.id                                      as item_id,
  null::uuid                                 as entry_id,
  null::uuid                                 as proposal_id,
  case lower(pi.status)
    when 're-exported'               then 'RE-EXPORTED'
    when 'destroyed'                 then 'DESTROYED'
    when 'supposed to be destroyed'  then 'DESTROYED'
    when 'destroy'                   then 'DESTROYED'
    when 'sold'                      then 'SOLD'
    when 'other'                     then 'OTHER'
  end                                        as final_tag,
  pi.item_name,
  pi.hs_code,
  pi.quantity,
  null::text                                 as note,
  null::text                                 as officer,
  p.updated_at                               as happened_at
from public.package_items pi
join public.packages p on p.id = pi.package_id
where lower(coalesce(pi.status, '')) in
      ('re-exported', 'destroyed', 'supposed to be destroyed', 'destroy',
       'sold', 'other')
  -- ⚠️ Only where NO tagged entry already covers this item, or the same goods
  -- appear twice -- once from each source. This is the `coveredItemIds` guard
  -- the screen applies in Dart.
  and not exists (
    select 1
      from public.warehouse_entries w2
     cross join lateral (
       select upper(substring(upper(trim(coalesce(w2.return_notes, '')))
                              from '^\[([^\]]+)\]')) as tag) t2
     where w2.package_item_id = pi.id
       and t2.tag in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT',
                      'FINAL:DESTROYED', 'FINAL:DESTROY', 'DESTROYED',
                      'DESTROY', 'SUPPOSED TO BE DESTROYED',
                      'FINAL:SOLD', 'SOLD',
                      'FINAL:OTHER', 'OTHER'))

union all

-- ── Source 3: Top Management ruled re-export after every tender failed ──────
--  The second route onto the Re-exported page. These goods have no [FINAL:]
--  entry and their item status is unchanged -- the decision lives in
--  unsold_proposals -- so without this they appear on no page in the app.
select
  ('P:' || up.id::text)                      as row_key,
  'proposal'::text                           as source,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  fp.yard,
  fp.item_id,
  null::uuid                                 as entry_id,
  up.id                                      as proposal_id,
  'RE-EXPORTED'::text                        as final_tag,
  coalesce(pi.item_name, '—')                as item_name,
  pi.hs_code,
  coalesce(fp.entry_qty, pi.quantity)        as quantity,
  nullif(trim(coalesce(up.note, '')), '')    as note,
  null::text                                 as officer,
  up.decided_at                              as happened_at
from public.unsold_proposals up
join public.forfeited_packages fp on fp.id = up.forfeited_package_id
join public.packages p            on p.id = fp.package_id
left join public.package_items pi on pi.id = fp.item_id
where up.proposal = 're_export';

grant select on public.disposition_rows to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  dupes int;
  untagged int;
begin
  -- ⚠️ Every row must have a final_tag. A null one is a row the CASE did not
  -- cover, and it would sit in the view matching no page at all.
  select count(*) into untagged
    from public.disposition_rows where final_tag is null;
  if untagged <> 0 then
    raise exception '% row(s) carry no final_tag', untagged;
  end if;

  -- The row_key must be unique, or a page could show the same goods twice.
  select count(*) into dupes from (
    select row_key from public.disposition_rows
     group by row_key having count(*) > 1) d;
  if dupes <> 0 then
    raise exception '% duplicated row_key(s)', dupes;
  end if;

  -- No item may appear from BOTH the entry and the item source -- that is the
  -- coveredItemIds guard, and it is the whole reason source 2 has a NOT
  -- EXISTS.
  select count(*) into dupes from (
    select item_id from public.disposition_rows
     where item_id is not null and source in ('entry', 'item')
     group by item_id having count(distinct source) > 1) d;
  if dupes <> 0 then
    raise exception '% item(s) appear from both the entry and item source',
      dupes;
  end if;

  -- And nothing may be dateless: the pages sort on happened_at.
  if exists (select 1 from public.disposition_rows where happened_at is null)
  then
    raise exception 'a disposition row has no date to sort by';
  end if;

  raise notice 'disposition_rows:';
  for r in
    select final_tag, source, count(*) as n
      from public.disposition_rows
     group by final_tag, source order by final_tag, source
  loop
    raise notice '  % / % -- % row(s)', rpad(r.final_tag, 12), rpad(r.source, 9), r.n;
  end loop;
end
$verify$;
