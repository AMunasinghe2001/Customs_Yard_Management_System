-- ============================================================================
--  Released Goods filters on two things no other page does.
--
--  ⚠️ `hold_reason` -- the Reason dropdown on that page -- and the RECEIPT
--  NUMBER, which the search box scans alongside the SR number and item name.
--  Neither is on the view yet, so those two filters would have stayed in Dart
--  and dragged the whole table back into memory to answer them.
--
--  The receipt number is not a column: it is one field of a pipe-separated
--  note, "Receipt No: 4410 | Date: 2025-01-03". Rather than make the app parse
--  it (which is what forced the fetch-everything), the view splits it out the
--  same way the screen did, so it can be searched in SQL.
--
--  Everything else is migration 21's, sliced out unchanged.
-- ============================================================================

set lock_timeout = '5s';

-- ⚠️ DROP, not `create or replace`. Postgres refuses to replace a view when
-- the new column list is not a pure append -- these two columns land inside
-- the subquery, so `delivered` (added by the wrapper) shifts position and it
-- errors with "cannot change name of view column". Nothing depends on this
-- view but the app, which re-queries, so dropping is safe.
drop view if exists public.disposition_rows;

create view public.disposition_rows as
select r.*,
       case
         when r.final_tag = 'SOLD' then (
           select ti.is_delivered
             from public.tender_sale_items ti
             join public.forfeited_packages fp2
               on fp2.id = ti.forfeited_package_id
            where ti.sold
              and coalesce(ti.package_item_id, fp2.item_id) = r.item_id
            order by ti.sold_at desc nulls last, ti.created_at desc
            limit 1)
         when r.final_tag = 'DESTROYED' then (
           select di.delivered
             from public.destruction_items di
             join public.forfeited_packages fp3
               on fp3.id = di.forfeited_package_id
            where di.destroyed
              and coalesce(di.package_item_id, fp3.item_id) = r.item_id
            order by di.destroyed_at desc nulls last
            limit 1)
         when r.source = 'proposal' then (
           select up2.delivered from public.unsold_proposals up2
            where up2.id = r.proposal_id)
       end as delivered
  from (
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
  coalesce(w.returned_at, w.admitted_at, p.updated_at)  as happened_at,
  w.hold_reason                              as hold_reason,
  -- One field of a pipe-separated note: "Receipt No: 4410 | Date: ...".
  -- Split here so the search box can match it in SQL.
  nullif(trim(substring(w.return_notes from '(?i)Receipt No:\s*([^|]*)')), '')
                                             as receipt_no
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
  p.updated_at                               as happened_at,
  null::text                                 as hold_reason,
  null::text                                 as receipt_no
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
  up.decided_at                              as happened_at,
  null::text                                 as hold_reason,
  null::text                                 as receipt_no
from public.unsold_proposals up
join public.forfeited_packages fp on fp.id = up.forfeited_package_id
join public.packages p            on p.id = fp.package_id
left join public.package_items pi on pi.id = fp.item_id
where up.proposal = 're_export'

union all

-- ── Source 4: a RELEASE, which is the disposition with no tag ───────────────
--  Goods handed back to their owner. The entry is returned and either carries
--  no note, a free-text receipt note, or an explicit [FINAL:RELEASED] /
--  [RELEASE...] tag.
select
  ('R:' || w.id::text)                       as row_key,
  'release'::text                            as source,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  w.package_item_id                          as item_id,
  w.id                                       as entry_id,
  null::uuid                                 as proposal_id,
  'RELEASED'::text                           as final_tag,
  coalesce(pi.item_name,
           (select i2.item_name from public.package_items i2
             where i2.package_id = p.id order by i2.created_at limit 1),
           '-')                              as item_name,
  pi.hs_code,
  coalesce(w.item_count, pi.quantity)        as quantity,
  -- A release note is the whole thing, not the half after an em dash: there
  -- is no tag in front of it to strip.
  nullif(trim(coalesce(w.return_notes, '')), '')        as note,
  coalesce(rp.full_name, rp.badge_number)               as officer,
  coalesce(w.returned_at, w.admitted_at, p.updated_at)  as happened_at,
  w.hold_reason                              as hold_reason,
  -- One field of a pipe-separated note: "Receipt No: 4410 | Date: ...".
  -- Split here so the search box can match it in SQL.
  nullif(trim(substring(w.return_notes from '(?i)Receipt No:\s*([^|]*)')), '')
                                             as receipt_no
from public.warehouse_entries w
join public.packages p            on p.id = w.package_id
left join public.package_items pi on pi.id = w.package_item_id
left join public.profiles rp      on rp.id = w.returned_by
where w.is_returned
  and (
    -- ⚠️ The three cases the screen accepted, in the same order.
    coalesce(trim(w.return_notes), '') = ''
    or trim(w.return_notes) not like '[%'
    or upper(trim(w.return_notes)) like '[FINAL:RELEASED]%'
    or upper(trim(w.return_notes)) like '[RELEASE%')
) r;

grant select on public.disposition_rows to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  n int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'disposition_rows'
                    and column_name = 'hold_reason') then
    raise exception 'hold_reason is missing';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_name = 'disposition_rows'
                    and column_name = 'receipt_no') then
    raise exception 'receipt_no is missing';
  end if;

  -- ⚠️ The receipt number must actually be EXTRACTED, not left as the whole
  -- note. If the split is wrong every receipt search silently matches nothing.
  select count(*) into n
    from public.disposition_rows
   where receipt_no is not null and receipt_no like '%|%';
  if n <> 0 then
    raise exception '% receipt number(s) still carry the rest of the note', n;
  end if;

  select count(*) into n
    from public.disposition_rows where receipt_no is not null;
  raise notice '% row(s) carry a parsed receipt number', n;

  for r in
    select final_tag, count(*) as c,
           count(*) filter (where hold_reason is not null) as with_reason
      from public.disposition_rows group by final_tag order by final_tag
  loop
    raise notice '  % -- % row(s), % with a hold reason',
      rpad(r.final_tag, 14), r.c, r.with_reason;
  end loop;
end
$verify$;
