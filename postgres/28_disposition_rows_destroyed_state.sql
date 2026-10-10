-- ============================================================================
--  Destroyed Goods shows a Pending / Destroyed status, and the view could not.
--
--  ⚠️ Destruction is the one disposition with a MIDDLE state. `[FINAL:DESTROY]`
--  (no ED) is the tag `disposeWarehouseItem` writes when a package is marked
--  for destruction, and the item's status becomes 'supposed to be destroyed';
--  only when the yard CONFIRMS does either become the past tense. Both belong
--  on the tab -- one as a row awaiting action, the other as a finished record
--  -- so the tab needs to tell them apart, and `final_tag` alone cannot.
--
--  In this database all 39 destroyed rows come from item statuses: 23 'supposed
--  to be destroyed' and 16 'destroyed'. That split is exactly what the column
--  carries.
--
--  Null for every other page: only DESTROYED has this state, and false would
--  read as "awaiting destruction" on goods that were sold.
--
--  Everything else is migration 22's, sliced out unchanged.
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
       -- ⚠️ Only DESTROYED rows have a middle state. Elsewhere this is NULL,
       -- because false would read as "awaiting destruction" on goods that were
       -- sold or released.
       case when r.final_tag <> 'DESTROYED' then null
            when r.source = 'entry' then
              upper(coalesce(r.note, '')) not like '%DESTROY]%'
              and exists (
                select 1 from public.warehouse_entries wd
                 where wd.id = r.entry_id
                   and upper(trim(coalesce(wd.return_notes, '')))
                       like '[FINAL:DESTROYED]%')
            else exists (
              select 1 from public.package_items pid
               where pid.id = r.item_id
                 and lower(trim(coalesce(pid.status, ''))) = 'destroyed')
       end                                        as is_destroyed,
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
  bad int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'disposition_rows'
                    and column_name = 'is_destroyed') then
    raise exception 'the is_destroyed column was not added';
  end if;

  -- ⚠️ Only DESTROYED rows carry it. On any other page false would read as
  -- "awaiting destruction" on goods that were sold or released.
  select count(*) into bad
    from public.disposition_rows
   where final_tag <> 'DESTROYED' and is_destroyed is not null;
  if bad <> 0 then
    raise exception '% non-destroyed row(s) claim a destruction state', bad;
  end if;

  -- And every DESTROYED row must have an answer, or the tab cannot decide
  -- whether to offer the Mark Destroyed action.
  select count(*) into bad
    from public.disposition_rows
   where final_tag = 'DESTROYED' and is_destroyed is null;
  if bad <> 0 then
    raise exception '% destroyed row(s) have no Pending/Destroyed state', bad;
  end if;

  -- ⚠️ The middle state must actually exist: an item marked 'supposed to be
  -- destroyed' is PENDING, not destroyed. Collapsing the two would silently
  -- present goods awaiting destruction as already gone.
  select count(*) into bad
    from public.disposition_rows d
    join public.package_items pi on pi.id = d.item_id
   where d.final_tag = 'DESTROYED'
     and lower(trim(coalesce(pi.status, ''))) = 'supposed to be destroyed'
     and d.is_destroyed;
  if bad <> 0 then
    raise exception '% package(s) awaiting destruction are shown as destroyed',
      bad;
  end if;

  raise notice 'destroyed rows: % confirmed, % awaiting confirmation',
    (select count(*) from public.disposition_rows
      where final_tag = 'DESTROYED' and is_destroyed),
    (select count(*) from public.disposition_rows
      where final_tag = 'DESTROYED' and not is_destroyed);
  for r in
    select final_tag, count(*) as c from public.disposition_rows
     group by final_tag order by final_tag
  loop
    raise notice '  % -- % row(s)', rpad(r.final_tag, 14), r.c;
  end loop;
end
$verify$;
