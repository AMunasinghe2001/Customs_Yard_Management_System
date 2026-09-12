-- ============================================================================
--  Fix disposal_mark_sale_item_sold so it sells exactly ONE item when the
--  tender_sale_items row identifies one — never the whole package.
--
--  Bug: when a forfeited_packages row is package-level (item_id IS NULL) the
--  function looped over EVERY un-finalised item in the package and marked them
--  all SOLD (e.g. selling Palm Oil when the yard only sold Jasmine Rice), each
--  copying the same sold_price. This produced bogus extra Sold rows.
--
--  Fix: prefer the TSI row's own package_item_id (per-item sale rows carry it);
--  fall back to the FP's item_id; only when BOTH are null do we keep the legacy
--  whole-package behaviour. The qty uses the FP's recorded entry_qty.
--
--  Always-safe replacement (same signature).
-- ============================================================================

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
  v_forfeited     uuid;
  v_package       uuid;
  v_yard          text;
  v_fp_item_id    uuid;   -- FP's specific item_id (null = package-level row)
  v_fp_entry_qty  int;    -- FP's actual abandoned/forfeited qty
  v_tsi_item_id   uuid;   -- the TSI row's own package_item_id (per-item sales)
  v_target_item   uuid;   -- the item we will actually sell
  v_target_qty    int;    -- qty to record for a single-item sale
  v_unfinalised   int;    -- count of un-finalised items in the package
  v_only_item     uuid;   -- the sole un-finalised item id (when count = 1)
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

  -- Read FP item/qty AND the TSI row's own package_item_id (per-item sales).
  select fp.id, fp.package_id, tsi.yard, fp.item_id, fp.entry_qty,
         tsi.package_item_id
    into v_forfeited, v_package, v_yard, v_fp_item_id, v_fp_entry_qty,
         v_tsi_item_id
    from public.tender_sale_items tsi
    join public.forfeited_packages fp on fp.id = tsi.forfeited_package_id
   where tsi.id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  -- The item to sell: the TSI row's own item wins, then the FP's item.
  v_target_item := coalesce(v_tsi_item_id, v_fp_item_id);
  -- The qty to record for a single-item sale: the FP's recorded entry_qty.
  v_target_qty  := v_fp_entry_qty;

  -- Safety net: if we couldn't resolve a specific item AND the package has more
  -- than one un-finalised item, refuse rather than bulk-selling every item
  -- (which is the bug that sold Palm Oil alongside Jasmine Rice). Auto-pick the
  -- item only when the package has exactly one un-finalised item.
  if v_target_item is null then
    select count(*), min(pi.id)
      into strict v_unfinalised, v_only_item
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other');
    if v_unfinalised > 1 then
      raise exception 'ambiguous_sale_item: tender_sale_item % covers a package '
        'with % un-finalised items but names no package_item_id', p_item_id,
        v_unfinalised;
    end if;
    v_target_item := v_only_item;  -- the single item (or null when none left)
  end if;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  -- At this point v_target_item is a single resolved item id (or null only when
  -- the package genuinely has no un-finalised items). Record EXACTLY ONE
  -- [FINAL:SOLD] entry for it — directly, not via a loop over package_items, so
  -- that:
  --   • we never bulk-sell sibling items (the Palm-Oil bug), and
  --   • partial sales of the SAME item still record (no status gate that would
  --     otherwise force a bogus NULL-item fallback entry on the 2nd partial).
  if v_target_item is not null then
    -- Warehouse context: prefer an entry already on this item, else any on the
    -- package, else any warehouse.
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

    -- Qty: the disposition's recorded qty, else the item's registered quantity.
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

    update public.package_items set status = 'sold' where id = v_target_item;

    -- Clear any lingering ACTIVE (un-returned) entry for this item so it leaves
    -- the live warehouse view; the [FINAL:SOLD] row above is the record of sale.
    delete from public.warehouse_entries
     where package_item_id = v_target_item and is_returned = false;
  end if;

  -- Mark this tender_sale_item row sold (price/taxes/receipt recorded on it).
  update public.tender_sale_items
     set sold = true, sold_at = now(), receipt_number = p_receipt,
         sold_price = p_price, applied_taxes = p_taxes
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

-- Done.
