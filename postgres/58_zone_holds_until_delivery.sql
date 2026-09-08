-- ============================================================================
--  58 · A zone is occupied until the goods actually leave
--
--  Zone capacity counts `is_returned = false`, which is the moment an officer
--  RECORDED the disposition -- not the moment the goods left. A release or a
--  re-export closes its warehouse entry the day it is written, so 31 released
--  and 17 re-exported lots in this yard vanished from their zones while still
--  physically standing in them. An officer looking for space was told there
--  was room that a pallet was sitting in.
--
--  ⚠️ The STORAGE CHARGE deliberately does NOT change. Charging stops when the
--  yard rules -- the bill is issued and closed at that point, and the goods
--  wait on their owner, not on the yard. Capacity is a physical question and
--  billing is a contractual one, and they end on different days.
--
--  ⚠️ Only the two endings with a recorded hand-over hold their space. Sold
--  and destroyed goods have their own delivery flags on other tables, and
--  wiring those in here would mean this view could not answer from
--  `warehouse_entries` alone. They already leave the zone when their entry
--  closes, which is what the yard has always seen; changing that is a separate
--  decision with its own numbers.
-- ============================================================================

set lock_timeout = '5s';

create or replace view public.zone_occupancy_entries as
select
  we.id            as entry_id,
  we.package_id,
  we.package_item_id,
  we.item_count,
  we.zone,
  we.warehouse_id,
  p.yard,
  -- Which of the three reasons this entry is still taking up space, so a
  -- caller can say so rather than the figure being unexplained.
  case
    when not coalesce(we.is_returned, false)              then 'held'
    when we.re_export_delivered is false
     and upper(trim(coalesce(we.return_notes, '')))
         like '[FINAL:RE-EXPORTED]%'                      then 'awaiting_shipment'
    else 'awaiting_collection'
  end              as occupancy_reason
from public.warehouse_entries we
join public.packages p on p.id = we.package_id
where
  -- Still held: never returned at all.
  not coalesce(we.is_returned, false)
  -- Or ruled, but not yet handed over. `<kind>_delivered` is NOT NULL DEFAULT
  -- false, so `is false` is the whole of "not yet" -- there is no third state
  -- to leak through.
  or (upper(trim(coalesce(we.return_notes, ''))) like '[FINAL:RE-EXPORTED]%'
      and we.re_export_delivered is false)
  or (coalesce(we.return_notes, '') !~ '^\[' and we.released_delivered is false);

grant select on public.zone_occupancy_entries to authenticated, anon;

-- ── Verify against live data ────────────────────────────────────────────────
do $verify$
declare
  n_old        int;
  n_new        int;
  n_ship       int;
  n_collect    int;
  n_charging   int;
begin
  -- What the zone view used to count.
  select count(*) into n_old
    from public.warehouse_entries we
    join public.packages p on p.id = we.package_id
   where p.yard = 'GL1' and not coalesce(we.is_returned, false);

  select count(*) into n_new
    from public.zone_occupancy_entries where yard = 'GL1';

  select count(*) filter (where occupancy_reason = 'awaiting_shipment'),
         count(*) filter (where occupancy_reason = 'awaiting_collection')
    into n_ship, n_collect
    from public.zone_occupancy_entries where yard = 'GL1';

  raise notice 'zones held: % -> % (% awaiting shipment, % awaiting collection)',
    n_old, n_new, n_ship, n_collect;

  -- ⚠️ The new figure must be LARGER, never smaller: this only ever adds the
  -- goods that are still physically present. A smaller number would mean the
  -- filter had dropped something genuinely held.
  if n_new < n_old then
    raise exception 'zone occupancy SHRANK: % -> %', n_old, n_new;
  end if;

  -- Every goods still awaiting a hand-over must be in here.
  if exists (
    select 1 from public.warehouse_entries we
     join public.packages p on p.id = we.package_id
    where p.yard = 'GL1'
      and ((upper(trim(coalesce(we.return_notes, ''))) like '[FINAL:RE-EXPORTED]%'
            and we.re_export_delivered is false)
        or (coalesce(we.return_notes, '') !~ '^\[' and we.is_returned
            and we.released_delivered is false))
      and not exists (select 1 from public.zone_occupancy_entries z
                       where z.entry_id = we.id)) then
    raise exception 'goods awaiting hand-over are missing from zone occupancy';
  end if;

  -- ⚠️ And a hand-over that HAS happened must be gone from the zone. This is
  -- the whole point: the two marked shipped must not still hold space.
  if exists (
    select 1 from public.zone_occupancy_entries z
     join public.warehouse_entries we on we.id = z.entry_id
    where we.re_export_delivered or we.released_delivered) then
    raise exception 'goods that have been handed over still occupy a zone';
  end if;

  -- ⚠️ The STORAGE CHARGE is untouched. Billing ends when the yard rules; only
  -- the physical space runs on.
  select count(*) into n_charging
    from public.accrued_storage_by_yard where yard = 'GL1';
  raise notice 'storage-charge rows for this yard: % (untouched by this view)',
    n_charging;

  raise notice 'verified: a zone is occupied until the goods actually leave';
end $verify$;
