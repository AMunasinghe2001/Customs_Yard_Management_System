-- ============================================================================
--  56 · A delivery has a DATE, and the popup says it
--
--  Migration 55 gave every ending a delivery FLAG. The popup wants the day:
--  the Top Management panel has always read "Delivered on 03 Sep 2026", and
--  the yard's own panel beside it could only say "Delivered" -- the same fact,
--  told with less of it, on the same page.
--
--  ⚠️ The dates already existed. `tender_sale_items.delivered_at`,
--  `destruction_items.delivered_at` and `unsold_proposals.delivered_at` were
--  all being read for their boolean and their date thrown away one column
--  short. This adds `delivered_at` beside `delivered`, resolved from the same
--  four sources in the same order, so the two can never disagree about which
--  hand-over they describe.
--
--  ⚠️ The four-source body below is 55's -- itself 54's -- copied verbatim.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.disposition_rows;

create view public.disposition_rows as
select r.*,
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
         when r.final_tag = 'RE-EXPORTED' and r.source = 'entry' then (
           select we.re_export_delivered
             from public.warehouse_entries we
            where we.id = r.entry_id)
       end                                        as delivered,
       -- ⚠️ The SAME four sources in the SAME order as `delivered`,
       -- and each GATED ON ITS OWN FLAG. A date resolved differently from its
       -- flag is worse than no date: it would name the day of some other
       -- hand-over entirely.
       --
       -- ⚠️ The gate is not belt-and-braces. `tender_sale_items` and
       -- `destruction_items` carry NO delivery-consistency check -- only
       -- `unsold_proposals` has one -- and the data drifted through the gap:
       -- 13 sold rows and 7 destruction rows hold a `delivered_at` while
       -- reading not-delivered, and 18 sold and 2 destruction rows are
       -- delivered with no date at all. The FLAG is the answer; a date beside
       -- a false flag is a leftover, not a hand-over.
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
) r;

-- ── The write: an officer records the departure ─────────────────────────────
--
-- Mirrors `disposal_toggle_delivery_status` (sales) and
-- `disposal_toggle_outcome_delivery` (DG rulings), so all three hand-overs are
-- authorised and audited the same way.
--
-- ⚠️ Unlike the DG-ruling version, this does NOT close the warehouse
-- entry. It is already closed: writing [FINAL:RE-EXPORTED] sets is_returned in
-- the same action -- all 17 in this yard are closed and were on the day their
-- tag was written. Re-closing would overwrite `returned_at` with today's date
-- and lose the day the disposition was actually recorded.
create or replace function public.yard_toggle_reexport_delivery(
  p_entry_id  uuid,
  p_delivered boolean
) returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_yard text;
  v_tag  text;
begin
  select p.yard,
         upper(substring(upper(trim(coalesce(w.return_notes, '')))
                         from '^\[([^\]]+)\]'))
    into v_yard, v_tag
    from public.warehouse_entries w
    join public.packages p on p.id = w.package_id
   where w.id = p_entry_id;

  if v_yard is null then
    raise exception 'no warehouse_entry with id %', p_entry_id;
  end if;

  -- ⚠️ Only a RE-EXPORT entry. Without this the function would flip the
  -- flag on a sold or destroyed entry, where it means nothing and where the
  -- real delivery lives on another table entirely.
  if v_tag is null or v_tag not in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT') then
    raise exception 'entry % is not a re-export (tag %)', p_entry_id, coalesce(v_tag, 'none');
  end if;

  -- The yard that holds the goods, or Central Disposal. The same rule the
  -- other two delivery writes use.
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;

  update public.warehouse_entries
     set re_export_delivered    = p_delivered,
         re_export_delivered_at = case when p_delivered then now() end,
         re_export_delivered_by = case when p_delivered then sr_auth.uid() end,
         updated_at             = now()
   where id = p_entry_id;
end;
$fn$;

revoke all on function public.yard_toggle_reexport_delivery(uuid, boolean) from public;
grant execute on function public.yard_toggle_reexport_delivery(uuid, boolean)
  to authenticated;

grant select on public.disposition_rows to authenticated, anon;

-- ── Verify against live data ───────────────────────────────────────
do $verify$
declare
  n_total     int;
  n_delivered int;
  n_dated     int;
  n_orphan    int;
  n_undated   int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'disposition_rows'
                    and column_name = 'delivered_at') then
    raise exception 'the delivered_at column was not added';
  end if;

  select count(*) into n_total from public.disposition_rows where yard = 'GL1';
  -- ⚠️ The row count must not move. The body is 55's verbatim, so any
  -- change here means the copy went wrong.
  if n_total <> 228 then
    raise exception 'the row count moved: expected 228, got %', n_total;
  end if;

  -- ⚠️ A date without a delivery is a contradiction, and the gates
  -- above exist because two of the source tables allow one -- 20 rows in this
  -- database hold a `delivered_at` while reading not-delivered. This asserts
  -- the gates hold.
  select count(*) into n_orphan
    from public.disposition_rows
   where delivered_at is not null and coalesce(delivered, false) = false;
  if n_orphan > 0 then
    raise exception '% rows carry a delivery date but are not delivered', n_orphan;
  end if;

  -- The reverse is legal and expected: 18 sold and 2 destruction rows were
  -- marked delivered before anything asked for a date. The popup says
  -- "Delivered" for those and names no day, which is exactly what is known.
  select count(*) into n_undated
    from public.disposition_rows
   where delivered and delivered_at is null;
  raise notice '% delivered rows have no date recorded', n_undated;

  select count(*) filter (where delivered),
         count(*) filter (where delivered and delivered_at is not null)
    into n_delivered, n_dated
    from public.disposition_rows where yard = 'GL1';

  raise notice 'GL1: % delivered, % of them dated', n_delivered, n_dated;

  -- ⚠️ Assert the RULE, not the tally. 55 pinned re-export deliveries
  -- at exactly 1 because that was the count on the day it ran -- and officers
  -- have marked two more since, so re-running it would now fail on a system
  -- working exactly as intended. What must hold is that every re-export
  -- delivery came from somewhere an officer wrote, never from a constant.
  if exists (select 1 from public.disposition_rows r
              where r.final_tag = 'RE-EXPORTED' and r.delivered
                and r.source = 'entry'
                and not exists (select 1 from public.warehouse_entries we
                                 where we.id = r.entry_id
                                   and we.re_export_delivered)) then
    raise exception 'a re-export reports delivered with nothing recorded behind it';
  end if;

  -- Sold and Destroyed must be untouched by all of this. These ARE fixed:
  -- nothing in this migration or in 55 writes to either table.
  if (select count(*) from public.disposition_rows
       where yard = 'GL1' and final_tag = 'SOLD' and delivered) <> 39 then
    raise exception 'the SOLD delivery count moved';
  end if;
  if (select count(*) from public.disposition_rows
       where yard = 'GL1' and final_tag = 'DESTROYED' and is_destroyed) <> 17 then
    raise exception 'the DESTROYED count moved';
  end if;

  raise notice 'verified: every delivery carries its own date';
end $verify$;
