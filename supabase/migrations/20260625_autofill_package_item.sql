-- ============================================================================
--  BULLETPROOF item-scoping for tender / destruction sale rows.
--
--  Problem: tender_sale_items / destruction_items rows sometimes had
--  package_item_id = NULL (e.g. the app build that created them predated the
--  client-side stamping). With a NULL item id the mark-sold / mark-destroyed
--  RPC could not tell which item to process and bulk-processed the whole
--  package — selling Palm Oil alongside Jasmine Rice.
--
--  This migration makes the item id self-healing at the DATABASE layer, so it
--  works regardless of which app build inserts the row:
--
--    1. BEFORE INSERT triggers auto-fill package_item_id from the forfeited
--       package's own item_id whenever the client leaves it NULL.
--    2. A one-time backfill repairs existing rows the same way (skipping any
--       that would collide with an already-stamped sibling row).
--
--  Pair this with 20260625_mark_sold_per_tsi_item.sql /
--  20260625_destruction_per_di_item.sql (the guarded RPCs) for full coverage:
--  if an FP row is genuinely package-level (item_id NULL) the RPC refuses to
--  bulk-process instead of corrupting data.
--
--  Idempotent.
-- ============================================================================

-- 1. ── Auto-fill function (shared shape, one per table for clarity) ──────────
create or replace function public.tsi_autofill_package_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.package_item_id is null then
    select fp.item_id
      into new.package_item_id
      from public.forfeited_packages fp
     where fp.id = new.forfeited_package_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_tsi_autofill_package_item on public.tender_sale_items;
create trigger trg_tsi_autofill_package_item
  before insert on public.tender_sale_items
  for each row execute function public.tsi_autofill_package_item();

create or replace function public.di_autofill_package_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.package_item_id is null then
    select fp.item_id
      into new.package_item_id
      from public.forfeited_packages fp
     where fp.id = new.forfeited_package_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_di_autofill_package_item on public.destruction_items;
create trigger trg_di_autofill_package_item
  before insert on public.destruction_items
  for each row execute function public.di_autofill_package_item();

-- 2. ── Backfill existing rows from the FP's item_id (collision-safe) ─────────
--  Only stamps a row when the FP names a specific item AND no sibling row for
--  the same (forfeited_package_id, item_id) already exists.
update public.tender_sale_items tsi
   set package_item_id = fp.item_id
  from public.forfeited_packages fp
 where tsi.forfeited_package_id = fp.id
   and tsi.package_item_id is null
   and fp.item_id is not null
   and not exists (
     select 1 from public.tender_sale_items x
      where x.forfeited_package_id = tsi.forfeited_package_id
        and x.package_item_id = fp.item_id
        and x.id <> tsi.id
   );

update public.destruction_items di
   set package_item_id = fp.item_id
  from public.forfeited_packages fp
 where di.forfeited_package_id = fp.id
   and di.package_item_id is null
   and fp.item_id is not null
   and not exists (
     select 1 from public.destruction_items x
      where x.forfeited_package_id = di.forfeited_package_id
        and x.package_item_id = fp.item_id
        and x.id <> di.id
   );

-- Done.
