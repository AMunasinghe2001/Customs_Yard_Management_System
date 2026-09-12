-- ============================================================================
--  Destruction procedure tables and functions.
--  Mirrors the Tender Sales procedure for "Destruction" items.
-- ============================================================================

-- 1. ── destructions ─────────────────────────────────────────────────────────
create table if not exists public.destructions (
  id               uuid primary key default uuid_generate_v4(),
  sale_number      text,
  sale_date        date,
  serial           int,
  year             int,
  tender_type      text, -- e.g. 'special' | 'general_cargo' | 'motor_vehicle'
  yard             text,
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now(),
  sale_time        text
);

alter table public.destructions enable row level security;

-- Disposal users and admins manage destructions.
drop policy if exists destructions_manage on public.destructions;
create policy destructions_manage on public.destructions
  for all
  using (
    public.auth_user_is_disposal()
    or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  )
  with check (
    public.auth_user_is_disposal()
    or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- 2. ── destruction_items ───────────────────────────────────────────────────
create table if not exists public.destruction_items (
  id                   uuid primary key default uuid_generate_v4(),
  destruction_id       uuid not null references public.destructions(id) on delete cascade,
  forfeited_package_id uuid not null references public.forfeited_packages(id) on delete cascade,
  yard                 text not null,
  destroyed            boolean not null default false,
  destroyed_at         timestamptz,
  notes                text,
  created_at           timestamptz not null default now(),
  unique (forfeited_package_id)
);

create index if not exists idx_destruction_items_sale on public.destruction_items(destruction_id);
create index if not exists idx_destruction_items_forfeited on public.destruction_items(forfeited_package_id);

alter table public.destruction_items enable row level security;

-- Disposal Directorate manages every row; a yard can read its own.
drop policy if exists destruction_items_disposal on public.destruction_items;
create policy destruction_items_disposal on public.destruction_items
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

drop policy if exists destruction_items_yard_read on public.destruction_items;
create policy destruction_items_yard_read on public.destruction_items
  for select
  using (yard = (select yard from public.profiles where id = auth.uid()));

-- 3. ── Mark a destruction item DESTROYED (cross-yard, security definer) ────
create or replace function public.disposal_mark_destruction_item_destroyed(
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
    from public.destruction_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

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

      update public.package_items set status = 'destroyed' where id = r.item_id;

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

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text)
  to authenticated;

-- Done.
