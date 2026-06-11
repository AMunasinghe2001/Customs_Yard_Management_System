-- ============================================================================
--  Tender Sale: sold price + applied taxes + delivery tracking.
--  Run after 20260611_tender_sale_items.sql (and the mark-sold fix).
--
--  The Mark Package Sold dialog now captures a Sold Price and the taxes applied
--  (VAT/PAL…), and packages can be flagged Delivered. This adds the columns and
--  REPLACES disposal_mark_sale_item_sold with a 4-arg version, plus a new
--  disposal_toggle_delivery_status RPC.
-- ============================================================================

-- 1. ── New columns ──────────────────────────────────────────────────────────
alter table public.tender_sale_items
  add column if not exists sold_price    numeric(14,2) not null default 0,
  add column if not exists applied_taxes jsonb         not null default '[]'::jsonb,
  add column if not exists is_delivered  boolean       not null default false,
  add column if not exists delivered_at  timestamptz;

-- 2. ── Mark sold (now also stores sold_price + applied_taxes) ────────────────
drop function if exists public.disposal_mark_sale_item_sold(uuid, text);

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id      uuid,
  p_receipt      text default null,
  p_sold_price   numeric default 0,
  p_applied_taxes jsonb default '[]'::jsonb
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
     set sold = true,
         sold_at = now(),
         receipt_number = p_receipt,
         sold_price = coalesce(p_sold_price, 0),
         applied_taxes = coalesce(p_applied_taxes, '[]'::jsonb)
   where id = p_item_id;
end;
$$;

grant execute on function
  public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

-- 3. ── Toggle delivery ──────────────────────────────────────────────────────
create or replace function public.disposal_toggle_delivery_status(
  p_item_id uuid,
  p_is_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;
  update public.tender_sale_items
     set is_delivered = p_is_delivered,
         delivered_at = case when p_is_delivered then now() else null end
   where id = p_item_id;
end;
$$;

grant execute on function
  public.disposal_toggle_delivery_status(uuid, boolean)
  to authenticated;

-- Done.
