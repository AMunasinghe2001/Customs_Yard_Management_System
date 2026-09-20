-- ============================================================================
--  70 · A RELEASED item with no warehouse entry was invisible everywhere
--
--  ⚠️ THE BUG THIS FIXES, reported directly: an officer opened a perishable
--  item ("Imported Apples", CED/GL1/SR/28/2026) on the Perishable Goods page
--  and recorded a Final Disposition of RELEASE. The success toast appeared.
--  package_items.status WAS set to 'released' -- confirmed directly:
--
--      select status from package_items where id = '<the item>';
--      -> released
--
--  but the row never left Perishable Goods (its chip stayed "In Yard"), and
--  it never appeared on Released Goods either.
--
--  The cause is the same shape twice over, and Source 2 of this view already
--  carries the fix for the OTHER three dispositions:
--
--    * Released Goods, like every disposition page, is `disposition_rows`
--      filtered to one `final_tag`. Source 4 (the untagged-entry rule) is the
--      ONLY source that can ever produce final_tag = 'RELEASED', and it
--      requires a `warehouse_entries` row (`w.is_returned = true`).
--    * Perishable Goods explicitly SKIPS warehousing -- the page's own
--      subtitle says so: "no warehouse, no appeal window, send them for
--      disposal without waiting". `recordFinalDisposition` in the app only
--      writes a warehouse_entries row `if (refEntry != null)`, and for an
--      item that was never admitted, refEntry is null.
--
--  So an item released straight from Perishable Goods satisfies NEITHER
--  Source 4's requirement NOR Source 2's tag list (Source 2 covers
--  're-exported' / 'destroyed' / 'sold' / 'other' -- 'released' was never in
--  it, because until now every release went through a warehouse entry).
--
--  ⚠️ This is deliberately NOT fixed by making the app fabricate a
--  warehouse_entries row for an item that was never admitted: `warehouse_id`
--  and `hold_reason` are NOT NULL on that table, so doing so would invent a
--  warehouse and a hold reason the goods never actually had. That was already
--  the design given to migration 039 in the app's own `migrations/` folder,
--  which independently reached the same fix from the read side (excluding a
--  finalised item from `perishable_rows`) -- this is that same reasoning
--  applied to `disposition_rows`, so the item actually MOVES to Released
--  Goods instead of merely leaving Perishable Goods.
--
--  Source 5 below is Source 2, copied for exactly one status: 'released'. Two
--  guards, not one: it must have no tagged warehouse_entries row (Source 4's
--  case) AND no return_notes-empty returned row either -- an item that WAS
--  warehoused and released the ordinary way must keep coming from Source 4,
--  or it would count twice.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.disposition_rows;

create view public.disposition_rows
with (security_invoker = true) as
select r.*,
       public.item_is_perishable(r.item_id)       as is_perishable,
       case when r.final_tag <> 'DESTROYED' then null
            when r.source = 'entry' then
              upper(coalesce(r.note, '')) not like '%DESTROY]%'
              and exists (
                select 1 from public.warehouse_entries wd
                 where wd.id = r.entry_id
                   and upper(trim(coalesce(wd.return_notes, '')))
                       like '[FINAL:DESTROYED]%')
            -- ⚠️ The destruction RECORD, not the item's status. The status
            -- is what a Final Disposition of Destroy SETS in order to route
            -- the item onto this page at all (migration 039), so asking it
            -- here answers "yes" for every row on the page by construction
            -- -- which is exactly how a perishable destroyed straight out of
            -- the yard arrived already marked Destroyed, with no Mark
            -- Destroyed button left to press. destruction_items is the
            -- record of the ACT.
            else exists (
              select 1
                from public.destruction_items di
                join public.forfeited_packages fpd
                  on fpd.id = di.forfeited_package_id
               where coalesce(di.package_item_id, fpd.item_id) = r.item_id
                 and di.destroyed)
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
         when r.final_tag = 'RE-EXPORTED' and r.source = 'entry' then (
           select we.re_export_delivered
             from public.warehouse_entries we
            where we.id = r.entry_id)
         when r.final_tag = 'RELEASED' and r.source = 'release' then (
           select we.released_delivered
             from public.warehouse_entries we
            where we.id = r.entry_id)
         -- ⚠️ Source 5 now carries the item's OPEN warehouse entry (see the
         -- entry_id subselect below), so its hand-over flag lives in the same
         -- place every other release's does. Reading it from the entry is
         -- what lets the officer press Mark Delivered on a perishable and
         -- have the answer stick.
         --
         -- The entry is never `is_returned` for these -- releasing a
         -- perishable records the disposition on the ITEM and leaves the
         -- entry open -- so `released_delivered` is the only flag that can
         -- speak for them. Null when the item was genuinely never admitted.
         when r.final_tag = 'RELEASED' and r.source = 'item' then (
           select we.released_delivered
             from public.warehouse_entries we
            where we.id = r.entry_id)
       end                                        as delivered,
       case
         when r.final_tag = 'SOLD' then (
           select case when ti.is_delivered then ti.delivered_at end
             from public.tender_sale_items ti
             join public.forfeited_packages fp2
               on fp2.id = ti.forfeited_package_id
            where ti.sold
              and coalesce(ti.package_item_id, fp2.item_id) = r.item_id
            order by ti.sold_at desc nulls last, ti.created_at desc
            limit 1)
         when r.final_tag = 'DESTROYED' then (
           select case when di.delivered then di.delivered_at end
             from public.destruction_items di
             join public.forfeited_packages fp3
               on fp3.id = di.forfeited_package_id
            where di.destroyed
              and coalesce(di.package_item_id, fp3.item_id) = r.item_id
            order by di.destroyed_at desc nulls last
            limit 1)
         when r.source = 'proposal' then (
           select case when up2.delivered then up2.delivered_at end
             from public.unsold_proposals up2
            where up2.id = r.proposal_id)
         when r.final_tag = 'RE-EXPORTED' and r.source = 'entry' then (
           select case when we.re_export_delivered
                       then we.re_export_delivered_at end
             from public.warehouse_entries we
            where we.id = r.entry_id)
         when r.final_tag = 'RELEASED'
              and r.source in ('release', 'item') then (
           select case when we.released_delivered
                       then we.released_delivered_at end
             from public.warehouse_entries we
            where we.id = r.entry_id)
       end                                        as delivered_at
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
  nullif(trim(split_part(w.return_notes, '—', 2)), '')  as note,
  coalesce(rp.full_name, rp.badge_number)               as officer,
  coalesce(w.returned_at, w.admitted_at, p.updated_at)  as happened_at,
  w.hold_reason                              as hold_reason,
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
--  ⚠️ 'released' is NOT in this list -- it is Source 5, below, because a
--  release also has to avoid double-counting against Source 4 (an item that
--  WAS warehoused and released the ordinary way), which none of these four
--  other statuses need to worry about.
select
  ('I:' || pi.id::text)                      as row_key,
  'item'::text                               as source,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.id                                      as item_id,
  -- ⚠️ The item's warehouse entry, for the same reason Source 5 carries one:
  -- a disposition recorded on the ITEM leaves the entry open, but the goods
  -- were still stored and the yard is still owed for the space. With null
  -- here the Sold and Destroyed tables printed "—" in their charge columns
  -- for 8 perishables, exactly as Released did.
  (select w2b.id
     from public.warehouse_entries w2b
    where w2b.package_item_id = pi.id
    order by w2b.admitted_at desc
    limit 1)                                 as entry_id,
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

-- ── Source 3: a Top Management ruling that names a final outcome ───────────
--
-- ⚠️ `destroy` joins `re_export` here, reported directly: a perishable ruled
-- DESTROY stayed on Perishable Goods and reached Destroyed Goods never. The
-- ruling IS the decision -- what is still outstanding is the ACT -- so the
-- row has to move the moment it is made and then sit on the Destroyed page
-- as awaiting, exactly as a re-export ruling already does.
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
  case up.proposal
    when 'destroy' then 'DESTROYED'
    else 'RE-EXPORTED'
  end                                        as final_tag,
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
where up.proposal in ('re_export', 'destroy')
  -- ⚠️ Not when the item already reaches this page another way. A ruling is
  -- one route to Destroyed Goods; a Final Disposition recorded on the item
  -- (Source 2) is another, and an item that has both would otherwise be
  -- listed twice.
  and not exists (
    select 1 from public.package_items pi2
     where pi2.id = fp.item_id
       and lower(coalesce(pi2.status, '')) in
           ('re-exported', 'destroyed', 'supposed to be destroyed',
            'destroy', 'sold', 'other'))

union all

-- ── Source 4: a RELEASE that WAS warehoused, which is the disposition with
--    no tag ───────────────────────────────────────────────────────────────
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
  nullif(trim(coalesce(w.return_notes, '')), '')        as note,
  coalesce(rp.full_name, rp.badge_number)               as officer,
  coalesce(w.returned_at, w.admitted_at, p.updated_at)  as happened_at,
  w.hold_reason                              as hold_reason,
  nullif(trim(substring(w.return_notes from '(?i)Receipt No:\s*([^|]*)')), '')
                                             as receipt_no
from public.warehouse_entries w
join public.packages p            on p.id = w.package_id
left join public.package_items pi on pi.id = w.package_item_id
left join public.profiles rp      on rp.id = w.returned_by
where w.is_returned = true
  and not exists (
    select 1
      from (select upper(substring(upper(trim(coalesce(w.return_notes, '')))
                                   from '^\[([^\]]+)\]')) as tag) t
     where t.tag in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT',
                    'FINAL:DESTROYED', 'FINAL:DESTROY', 'DESTROYED',
                    'DESTROY', 'SUPPOSED TO BE DESTROYED',
                    'FINAL:SOLD', 'SOLD',
                    'FINAL:OTHER', 'OTHER')
  )

union all

-- ── Source 5: a RELEASE recorded straight onto the item, with no warehouse
--    entry at all ─────────────────────────────────────────────────────────
--  THE FIX. An item Perishable Goods (or any other page that skips
--  warehousing) released directly through recordFinalDisposition: its status
--  is 'released' and no warehouse_entries row exists for it because it was
--  never admitted. Source 4 cannot see it -- there is no entry to be
--  "returned" -- so without this source such an item appears on no page at
--  all, exactly as reported.
select
  ('IR:' || pi.id::text)                     as row_key,
  'item'::text                               as source,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.id                                      as item_id,
  -- ⚠️ The item's OPEN warehouse entry, when it has one.
  --
  -- This was `null`, on the assumption that goods released straight out of
  -- Perishable Goods were never warehoused. They ARE: the page skips the
  -- APPEAL window and the disposal wait, not storage -- every perishable in
  -- this database has an admitted entry. With no entry_id the Released Goods
  -- table could not find one, so its Warehouse Charge cell printed "—" and
  -- the yard lost the storage it was owed on every perishable release.
  --
  -- Still not `is_returned`: releasing a perishable records the disposition
  -- on the ITEM and never closes the entry, which is exactly why Source 4
  -- cannot see these rows and Source 5 exists at all.
  (select w5.id
     from public.warehouse_entries w5
    where w5.package_item_id = pi.id
    order by w5.admitted_at desc
    limit 1)                                 as entry_id,
  null::uuid                                 as proposal_id,
  'RELEASED'::text                           as final_tag,
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
where lower(coalesce(pi.status, '')) = 'released'
  -- ⚠️ Guard 1: no tagged warehouse entry (Source 1's case — irrelevant to
  -- 'released' but kept for the same shape as Source 2).
  and not exists (
    select 1
      from public.warehouse_entries w3
     cross join lateral (
       select upper(substring(upper(trim(coalesce(w3.return_notes, '')))
                              from '^\[([^\]]+)\]')) as tag) t3
     where w3.package_item_id = pi.id
       and t3.tag in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT',
                      'FINAL:DESTROYED', 'FINAL:DESTROY', 'DESTROYED',
                      'DESTROY', 'SUPPOSED TO BE DESTROYED',
                      'FINAL:SOLD', 'SOLD',
                      'FINAL:OTHER', 'OTHER'))
  -- ⚠️ Guard 2: no RETURNED warehouse entry either, tagged or not — an item
  -- that WAS warehoused and released the ordinary way already comes from
  -- Source 4, and counting it again here would put it on Released Goods
  -- twice.
  and not exists (
    select 1 from public.warehouse_entries w4
     where w4.package_item_id = pi.id and w4.is_returned = true)
) r;

grant select on public.disposition_rows to authenticated, anon, public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  n_dup    int;
  n_null   int;
  n_shown  boolean;
  v_status text;
begin
  -- 1. The specific reported item, if this database has it: RELEASED, and
  --    visible on Released Goods.
  select status into v_status from public.package_items
   where id = '2a43b9ca-58ce-42d3-9570-271bf0fd7741';
  if v_status is not null and lower(v_status) = 'released' then
    select exists (
      select 1 from public.disposition_rows
       where item_id = '2a43b9ca-58ce-42d3-9570-271bf0fd7741'
         and final_tag = 'RELEASED'
    ) into n_shown;
    if not n_shown then
      raise exception 'FAIL: the reported item is still missing from Released Goods';
    end if;
    raise notice 'PASS: the reported item now appears as RELEASED';
  else
    raise notice 'SKIP: the reported item is not in this database, or not released';
  end if;

  -- 2. No item is counted by BOTH Source 5 (this migration's addition) and
  --    any other source. This is the guard that is actually new here.
  --
  --    ⚠️ NOT a blanket "no item ever appears twice" check. Two OLDER,
  --    unrelated duplications already exist in this view (a package proposed
  --    for re-export by Top Management that was ALSO separately released
  --    through a warehouse entry, and the same shape for an OTHER-tagged
  --    item) -- confirmed present before this migration touched anything, by
  --    re-running 57_released_delivery.sql's own unmodified view and finding
  --    the same three item_ids duplicated. Asserting the general rule here
  --    would fail this migration for a pre-existing defect it did not cause
  --    and was not asked to fix.
  select count(*) into n_dup
    from (select item_id
            from public.disposition_rows
           where item_id is not null
           group by item_id
          having count(*) filter (where row_key like 'IR:%') > 0
             and count(*) > count(*) filter (where row_key like 'IR:%')
         ) dupes;
  if n_dup > 0 then
    raise exception
      'FAIL: % item(s) are double-counted because of the NEW released-status source',
      n_dup;
  end if;

  -- 3. Every row still has a final_tag.
  select count(*) into n_null from public.disposition_rows where final_tag is null;
  if n_null > 0 then
    raise exception 'FAIL: % row(s) lost their final_tag', n_null;
  end if;

  raise notice 'disposition_rows RELEASED sources: % from warehouse entries, % from item status',
    (select count(*) from public.disposition_rows
      where final_tag = 'RELEASED' and source = 'release'),
    (select count(*) from public.disposition_rows
      where final_tag = 'RELEASED' and row_key like 'IR:%');
end
$verify$;

-- 4. A round-trip proof, independent of live data: an item released with NO
--    warehouse entry now appears, exactly once, as RELEASED.
do $rt$
declare v_pkg uuid; v_item uuid; v_count int;
begin
  insert into public.packages (sr_number, consignee_name, yard)
  values ('M070/TEST/01/2026', 'Migration 70 Test', 'GL1')
  returning id into v_pkg;

  insert into public.package_items (package_id, item_name, quantity, status, nature)
  values (v_pkg, 'M070 probe item', 1, 'released', 'perishable')
  returning id into v_item;

  select count(*) into v_count
    from public.disposition_rows
   where item_id = v_item and final_tag = 'RELEASED';
  if v_count <> 1 then
    raise exception 'FAIL: a released item with no warehouse entry shows % times, expected 1', v_count;
  end if;

  delete from public.package_items where id = v_item;
  delete from public.packages where id = v_pkg;
  raise notice 'PASS: a released item with no warehouse entry appears exactly once';
end
$rt$;
