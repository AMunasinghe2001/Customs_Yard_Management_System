-- ============================================================================
--  55 · Re-export delivery is RECORDED, not assumed
--
--  Migration 54 made every re-exported row read `delivered = true`:
--
--      when r.final_tag = 'RE-EXPORTED' then true
--
--  with the stated aim of driving the dashboard's "n/a" count to zero. It did
--  -- by answering the question instead of asking it. All 17 yard-recorded
--  re-exports reported themselves delivered on the day their tag was written,
--  and no officer had said so.
--
--  ⚠️ A figure that cannot be false is not a figure. The Re-exported Goods
--  page showed a green "Delivered" pill on every row with no way to mark one,
--  because there was nothing to mark: the pill was a constant. Goods still
--  standing in the yard awaiting collection were indistinguishable from goods
--  that left the country weeks ago.
--
--  Two things are true of a re-export, and they are not the same event:
--
--    * the yard RULED it -- the [FINAL:RE-EXPORTED] tag, written when the
--      disposition was recorded; and
--    * the goods LEFT -- carriage arranged, collected, gone.
--
--  The tag has always been stored. Departure had nowhere to live, so this adds
--  `warehouse_entries.re_export_delivered` (+ `_at`, + `_by`) and points the
--  view at it. The DG-ruled path is untouched: those goods carry their
--  delivery on `unsold_proposals.delivered`, which the Unsold pages already
--  read and write, and that branch still wins.
--
--  BACKFILL: none. Every existing row becomes "awaiting collection", which is
--  the honest answer -- nobody recorded a departure, so the system knows of
--  none. Officers mark them as the goods actually go. Defaulting them to
--  delivered would repeat 54's mistake with a different spelling.
--
--  ⚠️ The four-source body below is migration 54's, copied verbatim rather
--  than retyped -- only the `delivered` expression above it changes.
-- ============================================================================

set lock_timeout = '5s';

alter table public.warehouse_entries
  add column if not exists re_export_delivered    boolean not null default false,
  add column if not exists re_export_delivered_at timestamptz,
  add column if not exists re_export_delivered_by uuid references public.profiles(id);

-- ⚠️ The same shape `unsold_proposals` uses: a delivery has a date, and a
-- date means a delivery. Without it a row can claim to have been collected on
-- no day at all, and the two halves drift apart.
do $c$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'warehouse_entries_reexport_delivery_consistent') then
    alter table public.warehouse_entries
      add constraint warehouse_entries_reexport_delivery_consistent
      check ((re_export_delivered and re_export_delivered_at is not null)
          or (not re_export_delivered and re_export_delivered_at is null));
  end if;
end $c$;

create index if not exists warehouse_entries_reexport_delivered_idx
  on public.warehouse_entries (re_export_delivered)
  where re_export_delivered;

-- ── The view: read the column, do not assert the answer ──────────────────
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
         -- ⚠️ The DG-ruled path stays FIRST among the re-export branches.
         -- Those goods carry their delivery on the proposal, which the Unsold
         -- pages already read and write; sending them to the entry column
         -- would split one fact across two tables.
         when r.source = 'proposal' then (
           select up2.delivered from public.unsold_proposals up2
            where up2.id = r.proposal_id)
         -- A yard-recorded re-export: read what an officer marked. An item-
         -- status row (source 'item') has no entry to carry it, so it stays
         -- null -- honestly unknown rather than falsely delivered.
         when r.final_tag = 'RE-EXPORTED' and r.source = 'entry' then (
           select we.re_export_delivered
             from public.warehouse_entries we
            where we.id = r.entry_id)
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

grant select on public.disposition_rows to authenticated, anon;

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

-- ── Verify against live data ───────────────────────────────────────
do $verify$
declare
  n_true   int;
  n_false  int;
  n_null   int;
  n_total  int;
  n_prop   int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'warehouse_entries'
                    and column_name = 're_export_delivered') then
    raise exception 'the re_export_delivered column was not added';
  end if;

  select count(*) filter (where delivered),
         count(*) filter (where delivered is false),
         count(*) filter (where delivered is null),
         count(*)
    into n_true, n_false, n_null, n_total
    from public.disposition_rows
   where yard = 'GL1' and final_tag = 'RE-EXPORTED';

  raise notice 'RE-EXPORTED (GL1): % of % delivered, % awaiting, % unknown',
    n_true, n_total, n_false, n_null;

  -- ⚠️ The row COUNT must not move. The body is 54's verbatim, so a
  -- change here means the copy went wrong -- which is exactly how a
  -- hand-retyped source silently drops rows.
  if n_total <> 19 then
    raise exception 'the re-export row count moved: expected 19, got %', n_total;
  end if;

  -- Nothing is delivered until an officer says so. 54 reported 18 of 19 on
  -- the day it ran, with exactly one departure recorded anywhere -- a DG
  -- proposal. After this, that one.
  if n_true <> 1 then
    raise exception 'expected only the 1 recorded proposal delivery, got %',
      n_true;
  end if;

  select count(*) into n_prop
    from public.disposition_rows
   where yard = 'GL1' and final_tag = 'RE-EXPORTED'
     and source = 'proposal' and delivered;
  if n_prop <> 1 then
    raise exception 'the proposal delivery path changed: % delivered', n_prop;
  end if;

  -- Sold and Destroyed must be untouched by all of this.
  if (select count(*) from public.disposition_rows
       where yard = 'GL1' and final_tag = 'SOLD' and delivered) <> 39 then
    raise exception 'the SOLD delivery count moved';
  end if;
  if (select count(*) from public.disposition_rows
       where yard = 'GL1' and final_tag = 'DESTROYED' and is_destroyed) <> 17 then
    raise exception 'the DESTROYED count moved';
  end if;
  if (select count(*) from public.disposition_rows where yard = 'GL1')
     <> (select count(*) from public.disposition_rows where yard = 'GL1') then
    raise exception 'unreachable';
  end if;

  if not exists (select 1 from pg_proc
                  where proname = 'yard_toggle_reexport_delivery') then
    raise exception 'the delivery write was not created';
  end if;

  raise notice 'verified: re-export delivery is recorded, not assumed';
end $verify$;
