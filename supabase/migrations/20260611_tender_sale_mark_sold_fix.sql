-- ============================================================================
--  FIX: make disposal_mark_sale_item_sold robust.
--  Run this if you already ran 20260611_tender_sale_items.sql (it only
--  REPLACES the function). The earlier version keyed the warehouse context
--  strictly on package_item_id, so packages whose entries are admitted at
--  PACKAGE level (no item link) — or have none — wrote no [FINAL:SOLD] row and
--  never showed up in the Sold Packages / Warehouses views.
--
--  New behaviour: per item, take the item's own latest entry, else ANY entry on
--  the package; if the package has no entries at all, anchor a single
--  package-level SOLD entry to any warehouse so the sale still surfaces.
-- ============================================================================

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.tender_sale_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), auth.uid(), v_note);
    end if;
  end if;

  update public.tender_sale_items
     set sold = true, sold_at = now(), receipt_number = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text)
  to authenticated;

-- Done.
