-- ============================================================================
--  Fix disposal_mark_destruction_item_destroyed to respect per-item forfeited
--  package rows (forfeited_packages.item_id != null).
--
--  Previously the function destroyed ALL package_items when called, regardless
--  of which specific item the destruction_item was linked to via its
--  forfeited_package. Now when the forfeited_package has item_id set (i.e. a
--  per-item FP row created by the new disposal-request flow), only that single
--  item is destroyed. Legacy package-level FP rows (item_id is null) continue
--  to destroy all un-finalised items as before.
-- ============================================================================

create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_forfeited   uuid;
  v_package     uuid;
  v_yard        text;
  v_fp_item_id  uuid;   -- item_id on the forfeited_package row (may be null)
  r             record;
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
    from public.destruction_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  -- Appeal hold: block the destruction outright.
  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  select package_id, item_id
    into v_package, v_fp_item_id
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  -- When the forfeited_package has a specific item_id (per-item FP row created
  -- by the new disposal-request flow), destroy only that item. Otherwise fall
  -- back to destroying all un-finalised items on the package (legacy behaviour).
  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
       and (v_fp_item_id is null or pi.id = v_fp_item_id)
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

      update public.package_items set status = 'destroyed' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- Nothing item-level was written (no items, or none linkable). Still surface
  -- the destruction with one package-level [FINAL:DESTROYED] entry.
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

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text)
  to authenticated;

-- Done.
