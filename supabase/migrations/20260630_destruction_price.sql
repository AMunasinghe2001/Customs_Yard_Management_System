-- ============================================================================
--  Add a destruction price + taxes to destruction_items, and let the
--  Mark-Destroyed RPC store them — mirroring the tender-sale flow so the
--  Destroyed Packages table / popup can show the destruction price.
-- ============================================================================

alter table public.destruction_items
  add column if not exists destroyed_price numeric(14,2) not null default 0,
  add column if not exists applied_taxes  jsonb        not null default '[]'::jsonb;

-- Replace the RPC to accept + store the price/taxes (extra optional params, so
-- existing callers keep working). The function otherwise matches
-- 20260625_destruction_per_di_item.sql.
drop function if exists public.disposal_mark_destruction_item_destroyed(uuid, text);
drop function if exists public.disposal_mark_destruction_item_destroyed(uuid, text, numeric, jsonb);

create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text    default null,
  p_price   numeric default 0,
  p_taxes   jsonb   default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_forfeited    uuid;
  v_package      uuid;
  v_yard         text;
  v_fp_item_id   uuid;
  v_fp_entry_qty int;
  v_di_item_id   uuid;
  v_target_item  uuid;
  v_target_qty   int;
  v_unfinalised  int;
  v_only_item    uuid;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select di.forfeited_package_id, di.yard, di.package_item_id
    into v_forfeited, v_yard, v_di_item_id
    from public.destruction_items di
   where di.id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  select package_id, item_id, entry_qty
    into v_package, v_fp_item_id, v_fp_entry_qty
    from public.forfeited_packages
   where id = v_forfeited;

  v_target_item := coalesce(v_di_item_id, v_fp_item_id);
  v_target_qty  := v_fp_entry_qty;

  if v_target_item is null then
    select count(*), min(pi.id)
      into strict v_unfinalised, v_only_item
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other');
    if v_unfinalised > 1 then
      raise exception 'ambiguous_destruction_item: destruction_item % covers a '
        'package with % un-finalised items but names no package_item_id',
        p_item_id, v_unfinalised;
    end if;
    v_target_item := v_only_item;
  end if;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  if v_target_item is not null then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = v_target_item) desc nulls last, admitted_at desc
     limit 1;
    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_target_qty is null then
      select pi.quantity into v_target_qty
        from public.package_items pi where pi.id = v_target_item;
    end if;

    insert into public.warehouse_entries(
      package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
      item_count, admitted_by, admitted_at, daily_rate,
      is_returned, returned_at, returned_by, return_notes)
    values (
      v_package, v_yard, v_target_item, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
      coalesce(v_target_qty, 1), v_adm, coalesce(v_admat, now()),
      coalesce(v_rate, 0), true, now(), auth.uid(), v_note);

    update public.package_items set status = 'destroyed' where id = v_target_item;

    delete from public.warehouse_entries
     where package_item_id = v_target_item and is_returned = false;
  end if;

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt,
         destroyed_price = p_price, applied_taxes = p_taxes
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text, numeric, jsonb)
  to authenticated;

-- Done.
