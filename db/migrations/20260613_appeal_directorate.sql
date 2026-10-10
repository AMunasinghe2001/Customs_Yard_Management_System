-- ============================================================================
--  Appeal Directorate role + appeal-hold on forfeited packages
--  Run after the disposal migrations (esp. 20260610_disposal_directorate.sql,
--  20260611_tender_sale_sold_price.sql, 20260612_destructions.sql).
--
--  Adds a fourth institutional role, `appeal` (Appeal Directorate), modelled on
--  the disposal (DC/SDDC) role: cross-yard READ of forfeited packages, OTP login,
--  two positions (AD / ADD). The Appeal Directorate can place an "appeal hold" on
--  a forfeited package whose 30-day appeal window has NOT yet expired; a held
--  package CANNOT be sold or destroyed (the finalize RPCs hard-block on it) and
--  the owning yard sees a warning.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

-- 1. ── Allow the new role ───────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'officer', 'disposal', 'appeal'));

-- 2. ── Helper: is the caller an Appeal Directorate user? ────────────────────
create or replace function public.auth_user_is_appeal()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'appeal'
  );
$$;

-- 3. ── Cross-yard READ access for appeal users (SELECT only) ────────────────
do $$
declare t text;
begin
  foreach t in array array['packages', 'package_items', 'warehouse_entries', 'forfeited_packages']
  loop
    execute format('drop policy if exists appeal_read_all on public.%I;', t);
    execute format(
      'create policy appeal_read_all on public.%I for select using (public.auth_user_is_appeal());',
      t);
  end loop;
end $$;

-- Appeal users can also read profiles across yards (so the dashboard resolves names).
drop policy if exists appeal_read_profiles on public.profiles;
create policy appeal_read_profiles on public.profiles
  for select using (public.auth_user_is_appeal());

-- 4. ── Appeal-hold columns on forfeited_packages ────────────────────────────
alter table public.forfeited_packages
  add column if not exists appeal_hold      boolean not null default false,
  add column if not exists appeal_hold_note text,
  add column if not exists appeal_held_at   timestamptz,
  add column if not exists appeal_held_by   uuid references public.profiles(id);

create index if not exists idx_forfeited_packages_appeal_hold
  on public.forfeited_packages(appeal_hold) where appeal_hold;

-- 5. ── Limit to one AD and one ADD account ──────────────────────────────────
create or replace function public.appeal_position_available(code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'appeal' and lower(username) = lower(code)
  );
$$;

grant execute on function public.appeal_position_available(text) to anon, authenticated;

-- 6. ── Set / clear an appeal hold (Appeal Directorate only) ─────────────────
--    Refuses to hold a package whose appeal window has already passed. Clearing
--    (p_hold = false) is always allowed so a resolved/rejected appeal can be
--    released. SECURITY DEFINER → the appeal role needs no broad UPDATE grant.
create or replace function public.set_appeal_hold(
  p_forfeited_id uuid,
  p_hold         boolean,
  p_note         text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deadline timestamptz;
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select appeal_deadline into v_deadline
    from public.forfeited_packages where id = p_forfeited_id;
  if v_deadline is null then
    raise exception 'forfeited package not found';
  end if;

  if p_hold and v_deadline < now() then
    raise exception 'appeal_window_passed';
  end if;

  update public.forfeited_packages
     set appeal_hold      = p_hold,
         appeal_hold_note = case when p_hold then p_note else null end,
         appeal_held_at   = case when p_hold then now() else null end,
         appeal_held_by   = case when p_hold then auth.uid() else null end
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.set_appeal_hold(uuid, boolean, text) to authenticated;

-- 7. ── Hard block: a held package cannot be sold or destroyed ────────────────
--    Re-create the two finalize RPCs with an appeal-hold guard added right after
--    the forfeited-package id is resolved. Bodies are otherwise identical to
--    20260611_tender_sale_sold_price.sql / 20260612_destructions.sql.

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

  -- Appeal hold: block the sale outright.
  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
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

  -- Appeal hold: block the destruction outright.
  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
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
