-- ============================================================================
--  Item-scope destruction the same way tender sales are item-scoped.
--
--  Bug: when a forfeited_packages row is package-level (item_id IS NULL), the
--  disposal_mark_destruction_item_destroyed RPC destroyed EVERY un-finalised
--  item in the package — destroying e.g. Palm Oil when the yard only meant to
--  destroy Jasmine Rice. This corrupts data at scale.
--
--  Fix:
--    1. Add nullable package_item_id to destruction_items + composite unique
--       (forfeited_package_id, package_item_id) with NULLS NOT DISTINCT.
--    2. createDestruction now stores the covered item's id on each row.
--    3. RPC prefers the destruction_items row's own package_item_id, then the
--       FP's item_id; only when BOTH are null does it fall back to legacy
--       whole-package destruction.
--
--  Idempotent for schema; the function replacement is always safe.
-- ============================================================================

-- 1. ── Add package_item_id column ───────────────────────────────────────────
alter table public.destruction_items
  add column if not exists package_item_id uuid
    references public.package_items(id) on delete set null;

create index if not exists idx_di_package_item
  on public.destruction_items(package_item_id);

-- 2. ── Replace unique constraint ────────────────────────────────────────────
alter table public.destruction_items
  drop constraint if exists destruction_items_forfeited_package_id_key;
alter table public.destruction_items
  drop constraint if exists destruction_items_fp_item_unique;
alter table public.destruction_items
  add constraint destruction_items_fp_item_unique
    unique nulls not distinct (forfeited_package_id, package_item_id);

-- 3. ── Replace the RPC to honour the row's own package_item_id ───────────────
create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_forfeited    uuid;
  v_package      uuid;
  v_yard         text;
  v_fp_item_id   uuid;   -- FP row's item_id (null = package-level row)
  v_fp_entry_qty int;    -- FP row's recorded forfeited/abandoned qty
  v_di_item_id   uuid;   -- the destruction_items row's own package_item_id
  v_target_item  uuid;   -- item we will actually destroy (null = whole package)
  v_target_qty   int;    -- qty to record for a single-item destruction
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

  -- The item to destroy: the DI row's own item wins, then the FP's item;
  -- null = whole package (true legacy package-level destruction only).
  v_target_item := coalesce(v_di_item_id, v_fp_item_id);
  v_target_qty  := v_fp_entry_qty;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
       and (v_target_item is null or pi.id = v_target_item)
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
        coalesce(v_target_qty, r.qty), v_adm, coalesce(v_admat, now()), v_rate,
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
        coalesce(v_target_qty, 1), v_adm, coalesce(v_admat, now()),
        coalesce(v_rate, 0), true, now(), auth.uid(), v_note);
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
