-- ============================================================================
--  Per-item delivery tracking for tender_sale_items.
--
--  When a package has multiple items and disposal_mark_sale_item_sold is called,
--  each package_item gets its own [FINAL:SOLD] warehouse entry (with a distinct
--  package_item_id). Previously the delivery flag lived on the single
--  tender_sale_items row for the whole forfeited_package, so toggling delivery
--  for one item showed ALL items of that package as Delivered.
--
--  Fix:
--  1. Add nullable package_item_id to tender_sale_items.
--  2. Drop the unique(forfeited_package_id) constraint and replace it with
--     unique(forfeited_package_id, package_item_id) so we can have one row
--     per sold item when a package has multiple items.
--  3. Replace disposal_mark_sale_item_sold to INSERT one TSI row per item
--     (copying price/taxes from the original package-level TSI row).
--  4. Replace disposal_toggle_delivery_status — unchanged behaviour, but now
--     only the matching TSI row is toggled.
--
--  Idempotent for the schema changes; the function replacements are always safe.
-- ============================================================================

-- 1. ── Add package_item_id column ───────────────────────────────────────────
alter table public.tender_sale_items
  add column if not exists package_item_id uuid
    references public.package_items(id) on delete set null;

create index if not exists idx_tsi_package_item
  on public.tender_sale_items(package_item_id);

-- 2. ── Replace unique constraint ────────────────────────────────────────────
-- Drop old unique(forfeited_package_id) — may have different name depending on
-- when the table was created.
alter table public.tender_sale_items
  drop constraint if exists tender_sale_items_forfeited_package_id_key;

-- Add composite unique with NULLS NOT DISTINCT so (fp_id, NULL) is treated as
-- one slot — without this, every NULL package_item_id is considered distinct
-- and ON CONFLICT can never match the package-level row.
alter table public.tender_sale_items
  drop constraint if exists tender_sale_items_fp_item_unique;
alter table public.tender_sale_items
  add constraint tender_sale_items_fp_item_unique
    unique nulls not distinct (forfeited_package_id, package_item_id);

-- 3. ── Replace disposal_mark_sale_item_sold ──────────────────────────────────
-- Must DROP first because the parameter names changed (p_sold_price → p_price,
-- p_applied_taxes → p_taxes) and PostgreSQL does not allow renaming params with
-- CREATE OR REPLACE.
drop function if exists public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb);

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id   uuid,
  p_receipt   text    default null,
  p_price     numeric default 0,
  p_taxes     jsonb   default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_forfeited    uuid;
  v_package      uuid;
  v_yard         text;
  v_fp_item_id   uuid;   -- FP's specific item_id (null = package-level row)
  v_fp_entry_qty int;    -- FP's actual abandoned/forfeited qty (null = use pi.quantity)
  r              record;
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

  -- Check appeal hold and read the FP's specific item_id and entry_qty.
  select fp.id, fp.package_id, tsi.yard, fp.item_id, fp.entry_qty
    into v_forfeited, v_package, v_yard, v_fp_item_id, v_fp_entry_qty
    from public.tender_sale_items tsi
    join public.forfeited_packages fp on fp.id = tsi.forfeited_package_id
   where tsi.id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  -- Insert a [FINAL:SOLD] warehouse entry for the relevant package item(s).
  -- When the FP row is per-item (v_fp_item_id is not null) only that specific
  -- item is sold.  When the FP row is package-level (v_fp_item_id is null) all
  -- un-finalised items in the package are sold together (legacy behaviour).
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
        coalesce(v_fp_entry_qty, r.qty), v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      -- Upsert a per-item TSI row (copies price/taxes from the package-level row).
      insert into public.tender_sale_items(
        tender_sale_id, forfeited_package_id, package_item_id,
        yard, sold, sold_at, receipt_number,
        sold_price, applied_taxes)
      select
        tsi.tender_sale_id, tsi.forfeited_package_id, r.item_id,
        tsi.yard, true, now(), p_receipt,
        p_price, p_taxes
      from public.tender_sale_items tsi
      where tsi.id = p_item_id
      on conflict (forfeited_package_id, package_item_id)
      do update set
        sold          = true,
        sold_at       = now(),
        receipt_number = p_receipt,
        sold_price    = p_price,
        applied_taxes = p_taxes;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- Fallback: package has no individual items linkable to a warehouse entry.
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

  -- Mark the original package-level TSI row sold too (keeps backward compat).
  update public.tender_sale_items
     set sold = true, sold_at = now(), receipt_number = p_receipt,
         sold_price = p_price, applied_taxes = p_taxes
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

-- Done.
