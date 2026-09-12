-- ============================================================================
--  Tender Sale line items + "mark sold" for the Central Disposal Directorate.
--  Run after 20260611_disposal_requests.sql.
--
--  A Tender Sale now carries the actual packages being sold (only packages a
--  yard tagged "sale" in a disposal request can be added). The Disposal
--  Directorate can later mark each package SOLD; that writes a [FINAL:SOLD]
--  warehouse entry IN THE PACKAGE'S OWN YARD (via a SECURITY DEFINER RPC) so it
--  surfaces in that yard's Warehouses view and the cross-yard Sold Packages tab.
-- ============================================================================

-- 1. ── Line items ───────────────────────────────────────────────────────────
create table if not exists public.tender_sale_items (
  id                   uuid primary key default uuid_generate_v4(),
  tender_sale_id       uuid not null references public.tender_sales(id) on delete cascade,
  forfeited_package_id uuid not null references public.forfeited_packages(id) on delete cascade,
  yard                 text not null,
  sold                 boolean not null default false,
  sold_at              timestamptz,
  receipt_number       text,
  created_at           timestamptz not null default now(),
  unique (forfeited_package_id)
);

create index if not exists idx_tender_sale_items_sale on public.tender_sale_items(tender_sale_id);
create index if not exists idx_tender_sale_items_forfeited on public.tender_sale_items(forfeited_package_id);

alter table public.tender_sale_items enable row level security;

-- Disposal Directorate manages every row; a yard can read its own.
drop policy if exists tender_sale_items_disposal on public.tender_sale_items;
create policy tender_sale_items_disposal on public.tender_sale_items
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

drop policy if exists tender_sale_items_yard_read on public.tender_sale_items;
create policy tender_sale_items_yard_read on public.tender_sale_items
  for select
  using (yard = (select yard from public.profiles where id = auth.uid()));

-- 2. ── Mark a tender-sale package SOLD (cross-yard, security definer) ────────
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

  -- For each not-yet-finalised item write a [FINAL:SOLD] entry. The warehouse
  -- context prefers the item's own latest entry but falls back to ANY entry on
  -- the package (entries are often admitted package-level, with no item link).
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

  -- Nothing item-level was written (no items, or none linkable). Still surface
  -- the sale with one package-level [FINAL:SOLD] entry. Use any package entry;
  -- as a last resort anchor it to any warehouse so it appears in the lists.
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
