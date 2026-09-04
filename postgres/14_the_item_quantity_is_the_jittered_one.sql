-- ============================================================================
--  The ITEM's quantity was the wrong number, not the forfeit's.
--
--  Migration 13 pulled down the 120 forfeited rows that claimed MORE units
--  than their item held, and left the 121 that claimed fewer -- because a
--  partial forfeit is a real thing and flattening one would destroy it.
--
--  ⚠️ But the warehouse settles it. For these rows the warehouse entry agrees
--  with entry_qty, not with the item:
--
--      Truck Tyres              item 51   forfeit 40   warehouse 40
--      Galvanised Steel Sheets  item 93   forfeit 85   warehouse 85
--      Cast Iron Pipes          item 73   forfeit 70   warehouse 70
--
--  Two independent records say 40 and one says 51. The odd one out is the
--  item, and the reason is in the seeder: the item row was inserted with a
--  jitter (`base + rng(30) - 15`) while the forfeited row and the warehouse
--  placement were both given the un-jittered base. So this was never a partial
--  forfeit -- the whole consignment was forfeited and stored, and only the
--  item's own count drifted.
--
--  114 of the 121 are backed that way. The other 7 have no warehouse entry to
--  arbitrate, so they are LEFT ALONE: without a second record there is nothing
--  to distinguish an accident from a deliberate partial forfeit, and guessing
--  would destroy the real ones to tidy up seed noise.
-- ============================================================================

set lock_timeout = '5s';

update public.package_items pi
   set quantity = fp.entry_qty
  from public.forfeited_packages fp
 where fp.item_id = pi.id
   and fp.entry_qty < pi.quantity
   and exists (
     select 1 from public.warehouse_entries w
      where w.package_item_id = pi.id
        and w.item_count = fp.entry_qty);

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  disagreeing int;
  unarbitrated int;
begin
  -- ⚠️ Where the warehouse has spoken, all three records must now agree.
  select count(*) into disagreeing
    from public.forfeited_packages fp
    join public.package_items pi on pi.id = fp.item_id
    join public.warehouse_entries w on w.package_item_id = pi.id
   where w.item_count = fp.entry_qty
     and pi.quantity <> fp.entry_qty;
  if disagreeing <> 0 then
    raise exception '% item(s) still disagree with their forfeit AND their '
                    'warehouse', disagreeing;
  end if;

  -- Nothing may forfeit more than the item holds (migration 13's rule).
  if exists (select 1 from public.forfeited_packages fp
               join public.package_items pi on pi.id = fp.item_id
              where fp.entry_qty > pi.quantity) then
    raise exception 'a forfeit claims more units than its item holds';
  end if;

  select count(*) into unarbitrated
    from public.forfeited_packages fp
    join public.package_items pi on pi.id = fp.item_id
   where fp.entry_qty < pi.quantity;
  raise notice
    '% row(s) still read as partial forfeits -- no warehouse entry to '
    'arbitrate, so they are left as recorded.', unarbitrated;
end
$verify$;
