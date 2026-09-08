-- ============================================================================
--  57 · A release is collected, or it is not
--
--  Released Goods was the last page with no delivery answer. It shows a
--  receipt number and a release date -- the moment an officer RULED the goods
--  released -- and nothing about whether the owner has actually come for them.
--  All 33 rows in this yard carry a receipt; the yard cannot tell from the
--  screen which of them are still standing in a warehouse.
--
--  ⚠️ This is the same two-event shape as a re-export, and it gets the same
--  treatment: `released_delivered` (+ `_at`, + `_by`) on `warehouse_entries`,
--  read by the view, written by an RPC an officer presses.
--
--  ⚠️ Release is NOT re-export, and the columns are separate. One entry
--  cannot be both, but sharing a column would mean a page's filter had to know
--  which kind of ending it was reading before it could trust the value, and
--  the guard in each RPC would have nothing to check against.
--
--  BACKFILL: none, for the reason 55 gave -- nobody recorded a collection, so
--  the system knows of none. Everything starts "awaiting collection".
--
--  ⚠️ The four-source body below is 56's -- itself 55's, itself 54's --
--  copied verbatim. Only the `delivered` and `delivered_at` cases change.
-- ============================================================================

set lock_timeout = '5s';

alter table public.warehouse_entries
  add column if not exists released_delivered    boolean not null default false,
  add column if not exists released_delivered_at timestamptz,
  add column if not exists released_delivered_by uuid references public.profiles(id);

do $c$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'warehouse_entries_released_delivery_consistent') then
    alter table public.warehouse_entries
      add constraint warehouse_entries_released_delivery_consistent
      check ((released_delivered and released_delivered_at is not null)
          or (not released_delivered and released_delivered_at is null));
  end if;
end $c$;

create index if not exists warehouse_entries_released_delivered_idx
  on public.warehouse_entries (released_delivered)
  where released_delivered;

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
         -- A release: has the owner actually come for the goods?
         when r.final_tag = 'RELEASED' then (
           select we.released_delivered
             from public.warehouse_entries we
            where we.id = r.entry_id)
       end                                        as delivered,
       -- ⚠️ The SAME sources in the SAME order as `delivered` above, each
       -- GATED ON ITS OWN FLAG. `tender_sale_items` and `destruction_items`
       -- carry no delivery-consistency check -- only `unsold_proposals` and
       -- the two `warehouse_entries` pairs do -- and the data drifted through
       -- the gap: 20 rows hold a date while reading not-delivered. The FLAG is
       -- the answer; a date beside a false flag is a leftover.
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
         when r.final_tag = 'RELEASED' then (
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
          or v_yard = (select yard from public.profiles where id = auth.uid())) then
    raise exception 'not authorized';
  end if;

  update public.warehouse_entries
     set re_export_delivered    = p_delivered,
         re_export_delivered_at = case when p_delivered then now() end,
         re_export_delivered_by = case when p_delivered then auth.uid() end,
         updated_at             = now()
   where id = p_entry_id;
end;
$fn$;

revoke all on function public.yard_toggle_reexport_delivery(uuid, boolean) from public;
grant execute on function public.yard_toggle_reexport_delivery(uuid, boolean)
  to authenticated;

grant select on public.disposition_rows to authenticated, anon;

-- ── The write: an officer records the collection ────────────────────────────
--
-- The fourth of these, and deliberately identical in shape to
-- `yard_toggle_reexport_delivery`: same guard, same authorisation, and the
-- same refusal to touch the warehouse entry's own closure.
create or replace function public.yard_toggle_released_delivery(
  p_entry_id  uuid,
  p_delivered boolean
) returns void
language plpgsql
security definer
set search_path to 'public'
as $rl$
declare
  v_yard     text;
  v_tag      text;
  v_returned boolean;
begin
  select p.yard, w.is_returned,
         upper(substring(upper(trim(coalesce(w.return_notes, '')))
                         from '^\[([^\]]+)\]'))
    into v_yard, v_returned, v_tag
    from public.warehouse_entries w
    join public.packages p on p.id = w.package_id
   where w.id = p_entry_id;

  if v_yard is null then
    raise exception 'no warehouse_entry with id %', p_entry_id;
  end if;

  -- ⚠️ A RELEASE is the entry with no disposition tag -- exactly the rule
  -- source 4 of the view uses. Without this the function would flip the flag
  -- on a sold, destroyed or re-exported entry, where the real delivery lives
  -- on another column or another table entirely.
  if not coalesce(v_returned, false) then
    raise exception 'entry % has not been released', p_entry_id;
  end if;
  if v_tag in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT',
               'FINAL:DESTROYED', 'FINAL:DESTROY', 'DESTROYED', 'DESTROY',
               'SUPPOSED TO BE DESTROYED', 'FINAL:SOLD', 'SOLD',
               'FINAL:OTHER', 'OTHER') then
    raise exception 'entry % is not a release (tag %)', p_entry_id, v_tag;
  end if;

  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = auth.uid())) then
    raise exception 'not authorized';
  end if;

  update public.warehouse_entries
     set released_delivered    = p_delivered,
         released_delivered_at = case when p_delivered then now() end,
         released_delivered_by = case when p_delivered then auth.uid() end,
         updated_at            = now()
   where id = p_entry_id;
end;
$rl$;

revoke all on function public.yard_toggle_released_delivery(uuid, boolean) from public;
grant execute on function public.yard_toggle_released_delivery(uuid, boolean)
  to authenticated;

grant select on public.disposition_rows to authenticated, anon;

-- ── Verify against live data ───────────────────────────────────────
do $verify$
declare
  n_total   int;
  n_rel     int;
  n_rel_d   int;
  n_orphan  int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'warehouse_entries'
                    and column_name = 'released_delivered') then
    raise exception 'the released_delivered column was not added';
  end if;

  select count(*) into n_total from public.disposition_rows where yard = 'GL1';
  if n_total <> 228 then
    raise exception 'the row count moved: expected 228, got %', n_total;
  end if;

  -- ⚠️ RELEASED used to answer NULL for every row -- no hand-over step
  -- existed. Now every one of them answers, and none of them answers true,
  -- because nobody has recorded a collection yet.
  select count(*),
         count(*) filter (where delivered is null)
    into n_rel, n_orphan
    from public.disposition_rows
   where yard = 'GL1' and final_tag = 'RELEASED';
  if n_rel <> 33 then
    raise exception 'the RELEASED row count moved: expected 33, got %', n_rel;
  end if;
  if n_orphan > 0 then
    raise exception '% released rows still have no delivery answer', n_orphan;
  end if;

  select count(*) into n_rel_d
    from public.disposition_rows
   where yard = 'GL1' and final_tag = 'RELEASED' and delivered;
  raise notice 'RELEASED (GL1): % of % collected', n_rel_d, n_rel;

  -- A date without a delivery is a contradiction; the gates above exist
  -- because two source tables allow one.
  select count(*) into n_orphan
    from public.disposition_rows
   where delivered_at is not null and coalesce(delivered, false) = false;
  if n_orphan > 0 then
    raise exception '% rows carry a delivery date but are not delivered', n_orphan;
  end if;

  -- ⚠️ Assert the RULE, not the tally: officers mark deliveries between
  -- runs, so a fixed count fails on a system working exactly as intended.
  if exists (select 1 from public.disposition_rows r
              where r.delivered and r.entry_id is not null
                and r.final_tag in ('RELEASED', 'RE-EXPORTED')
                and r.source in ('entry', 'release')
                and not exists (select 1 from public.warehouse_entries we
                                 where we.id = r.entry_id
                                   and (we.released_delivered
                                        or we.re_export_delivered))) then
    raise exception 'a hand-over reports delivered with nothing recorded behind it';
  end if;

  -- Sold and Destroyed are untouched: nothing here writes to either table.
  if (select count(*) from public.disposition_rows
       where yard = 'GL1' and final_tag = 'SOLD' and delivered) <> 39 then
    raise exception 'the SOLD delivery count moved';
  end if;
  if (select count(*) from public.disposition_rows
       where yard = 'GL1' and final_tag = 'DESTROYED' and is_destroyed) <> 17 then
    raise exception 'the DESTROYED count moved';
  end if;

  raise notice 'verified: a release is collected, or it is not';
end $verify$;
