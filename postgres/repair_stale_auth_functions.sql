-- ==========================================================================
--  REPAIR: rewrite the 17 function bodies that still call `auth.uid()`.
--
--      psql -U postgres -d Customs_SR_DB_backup_20260914_1543 --           -f postgres/repair_stale_auth_functions.sql
--
--  WHY THESE ARE STALE
--  -------------------
--  After the schema rename, 17 functions in `public` still named the old
--  `auth` schema. It no longer exists, so every one of them fails the
--  moment the app calls it -- which is most of the Disposal, Valuation and
--  Appeal actions, plus the yard helpers every RLS policy depends on.
--
--  The SOURCE is correct: `postgres/02_schema.sql` says `sr_auth.uid()`
--  throughout. They are stale only because that file ABORTS partway down on
--  a populated database, so the statements after the failure never run.
--
--  ⚠️ AND RE-RUNNING 02_schema.sql IS NOT THE ANSWER. It carries a
--  `20260620_seed_data.sql` block that begins:
--
--      DELETE FROM public.packages;
--      DELETE FROM public.warehouse_entries;
--      DELETE FROM public.audit_logs;
--      ...
--
--  On this database that is 176 packages, 395 warehouse entries, 318
--  forfeited packages and 1388 audit rows -- the real data. That block is
--  written for an EMPTY database. Several of the stale functions are
--  defined AFTER it, so there is no way to reach them by re-running the
--  file without passing through the delete.
--
--  So this file carries just those functions, copied verbatim from the LAST
--  definition of each in 02_schema.sql (a few are restated there as the
--  system grew; the last one is the current one). Nothing else is touched:
--  no table, no policy, no row.
--
--  Safe to re-run -- every statement is `create or replace`.
-- ==========================================================================

-- ⚠️ pgcrypto lives in `extensions` on Supabase and in `public` locally. A
-- schema named here that does not exist is simply ignored, so this one line
-- is correct on every deployment.
set search_path = public, sr_auth, extensions;

-- auth_user_is_appeal   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.auth_user_is_appeal()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'appeal'
  );
$$;

-- auth_user_is_disposal   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.auth_user_is_disposal()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'disposal'
  );
$$;

-- auth_user_is_executive   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.auth_user_is_executive()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'executive'
  );
$$;

-- auth_user_is_ict   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.auth_user_is_ict()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $fn$
  select exists (
    select 1 from public.profiles p
     where p.id = sr_auth.uid()
       and p.role = 'ict'
       and p.is_active
  );
$fn$;

-- auth_user_is_valuation   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.auth_user_is_valuation()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'valuation'
  );
$$;

-- auth_user_yard   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.auth_user_yard()
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$
  select yard from public.profiles where id = sr_auth.uid();
$$;

-- disposal_mark_destruction_item_destroyed   (last of 5 definition(s) in 02_schema.sql)
create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text    default null,
  p_price   numeric default 0,
  p_taxes   jsonb   default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
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
      coalesce(v_rate, 0), true, now(), sr_auth.uid(), v_note);

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

-- disposal_mark_forfeited_sold   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.disposal_mark_forfeited_sold(
  p_forfeited_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_package uuid;
  v_yard    text;
  r         record;
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

  select package_id, yard into v_package, v_yard
    from public.forfeited_packages where id = p_forfeited_id;
  if v_package is null then
    raise exception 'forfeited package not found';
  end if;

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
        true, now(), sr_auth.uid(), v_note);

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
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;
end;
$$;

-- disposal_mark_sale_item_sold   (last of 7 definition(s) in 02_schema.sql)
create or replace function public.disposal_mark_sale_item_sold(
  p_item_id   uuid,
  p_receipt   text    default null,
  p_price     numeric default 0,
  p_taxes     jsonb   default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
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
      coalesce(v_rate, 0), true, now(), sr_auth.uid(), v_note);

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

-- disposal_toggle_destruction_delivery   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.disposal_toggle_destruction_delivery(
  p_item_id uuid,
  p_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_yard text;
begin
  select yard into v_yard from public.destruction_items where id = p_item_id;
  if v_yard is null then
    raise exception 'destruction item not found';
  end if;
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;
  update public.destruction_items
     set delivered = p_delivered,
         delivered_at = case when p_delivered then now() else null end
   where id = p_item_id;
end;
$$;

-- release_appeal_with_decision   (last of 2 definition(s) in 02_schema.sql)
create or replace function public.release_appeal_with_decision(
  p_forfeited_id uuid,
  p_decision     text,
  p_note         text default null,
  p_item_id      uuid default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_item_ids uuid[];
  v_new_ids  uuid[];
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select coalesce(held_item_ids, '{}') into v_item_ids
    from public.forfeited_packages
   where id = p_forfeited_id;
  if v_item_ids is null then
    raise exception 'forfeited package not found';
  end if;

  if p_item_id is not null then
    -- Remove ONLY this item from the held set (siblings keep their holds).
    select coalesce(array_agg(x), '{}') into v_new_ids
      from unnest(v_item_ids) x
     where x <> p_item_id;

    update public.forfeited_packages
       set item_appeal_decisions = coalesce(item_appeal_decisions, '{}'::jsonb)
             || jsonb_build_object(
                  p_item_id::text,
                  jsonb_build_object(
                    'decision',    p_decision,
                    'note',        p_note,
                    'decided_at',  now(),
                    'decided_by',  sr_auth.uid()
                  )),
           held_item_ids = v_new_ids,
           appeal_hold   = (cardinality(v_new_ids) > 0),
           appeal_hold_note = case
             when cardinality(v_new_ids) > 0 then appeal_hold_note else null end,
           appeal_held_at = case
             when cardinality(v_new_ids) > 0 then appeal_held_at else null end,
           appeal_held_by = case
             when cardinality(v_new_ids) > 0 then appeal_held_by else null end
     where id = p_forfeited_id;
  else
    -- Legacy package-level decision (single-item / no item id supplied).
    update public.forfeited_packages
       set appeal_hold      = false,
           held_item_ids    = '{}',
           appeal_hold_note  = null,
           appeal_held_at    = null,
           appeal_held_by    = null,
           appeal_decision   = p_decision,
           appeal_decision_note = p_note,
           appeal_decided_at = now(),
           appeal_decided_by = sr_auth.uid()
     where id = p_forfeited_id;
  end if;
end;
$$;

-- set_appeal_hold   (last of 3 definition(s) in 02_schema.sql)
create or replace function public.set_appeal_hold(
  p_forfeited_id uuid,
  p_hold         boolean,
  p_note         text    default null,
  p_item_id      uuid    default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_deadline    timestamptz;
  v_item_ids    uuid[];
  v_new_ids     uuid[];
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select appeal_deadline, held_item_ids
    into v_deadline, v_item_ids
    from public.forfeited_packages
   where id = p_forfeited_id;

  if v_deadline is null then
    raise exception 'forfeited package not found';
  end if;

  if p_hold and v_deadline < now() then
    raise exception 'appeal_window_passed';
  end if;

  v_item_ids := coalesce(v_item_ids, '{}');

  if p_hold then
    if p_item_id is not null then
      -- Add item to held set (avoid duplicates).
      if not (v_item_ids @> array[p_item_id]) then
        v_new_ids := v_item_ids || array[p_item_id];
      else
        v_new_ids := v_item_ids;
      end if;
    else
      -- p_item_id null → not used in new flow, keep existing.
      v_new_ids := v_item_ids;
    end if;
  else
    if p_item_id is not null then
      -- Remove specific item from held set.
      select array_agg(x) into v_new_ids
        from unnest(v_item_ids) x
       where x <> p_item_id;
      if v_new_ids is null then v_new_ids := '{}'; end if;
    else
      -- Release all.
      v_new_ids := '{}';
    end if;
  end if;

  update public.forfeited_packages
     set held_item_ids  = v_new_ids,
         -- cardinality() → 0 (not NULL) for '{}', so the flag is never NULL.
         appeal_hold    = (cardinality(v_new_ids) > 0),
         appeal_hold_note = case
           when cardinality(v_new_ids) > 0 then p_note
           else null
         end,
         appeal_held_at = case
           when cardinality(v_new_ids) > 0 then coalesce(appeal_held_at, now())
           else null
         end,
         appeal_held_by = case
           when cardinality(v_new_ids) > 0 then coalesce(appeal_held_by, sr_auth.uid())
           else null
         end
   where id = p_forfeited_id;
end;
$$;

-- valuation_forward_all   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.valuation_forward_all(
  p_request_id uuid
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_missing int;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  select count(*) into v_missing
    from public.disposal_request_items
   where request_id = p_request_id
     and valuation_cost is null;
  if v_missing > 0 then
    raise exception 'valuation_incomplete';
  end if;

  update public.disposal_request_items
     set forwarded = true
   where request_id = p_request_id;

  update public.disposal_requests
     set valuation_status = 'forwarded',
         valued_at = coalesce(valued_at, now()),
         valued_by = coalesce(valued_by, sr_auth.uid())
   where id = p_request_id;
end;
$$;

-- valuation_forward_item   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.valuation_forward_item(
  p_item_id uuid
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_request uuid;
  v_cost    numeric;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  select request_id, valuation_cost into v_request, v_cost
    from public.disposal_request_items
   where id = p_item_id;

  if v_request is null then
    raise exception 'item not found';
  end if;
  if v_cost is null then
    raise exception 'valuation_incomplete';  -- this item still needs a cost
  end if;

  update public.disposal_request_items
     set forwarded = true
   where id = p_item_id;

  -- Keep the request-level status coherent: forwarded once any item is; and
  -- record who/when valued it (first forward wins for the timestamp).
  update public.disposal_requests
     set valuation_status = 'forwarded',
         valued_at = coalesce(valued_at, now()),
         valued_by = coalesce(valued_by, sr_auth.uid())
   where id = v_request;
end;
$$;

-- valuation_set_costs   (last of 1 definition(s) in 02_schema.sql)
create or replace function public.valuation_set_costs(
  p_request_id uuid,
  p_costs      jsonb default '{}'::jsonb,
  p_forward    boolean default false
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  k text;
  v_missing int;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  if not exists (select 1 from public.disposal_requests where id = p_request_id) then
    raise exception 'disposal request not found';
  end if;

  -- Apply the per-item costs (only rows belonging to this request).
  for k in select jsonb_object_keys(coalesce(p_costs, '{}'::jsonb))
  loop
    update public.disposal_request_items
       set valuation_cost = (p_costs ->> k)::numeric
     where id = k::uuid
       and request_id = p_request_id;
  end loop;

  if p_forward then
    -- Every line item must have a cost before the request can be forwarded.
    select count(*) into v_missing
      from public.disposal_request_items
     where request_id = p_request_id
       and valuation_cost is null;
    if v_missing > 0 then
      raise exception 'valuation_incomplete';
    end if;

    update public.disposal_requests
       set valuation_status = 'forwarded',
           valued_at = now(),
           valued_by = sr_auth.uid()
     where id = p_request_id;
  end if;
end;
$$;


-- --------------------------------------------------------------------------
--  Two superseded 3-argument overloads.
--
--  ⚠️ These are NOT the versions the app calls. `set_appeal_hold` and
--  `release_appeal_with_decision` were later given a `p_item_id` argument
--  so an appeal can be held or released for ONE item rather than the whole
--  package, and services.dart always passes it:
--
--      supabase.rpc('set_appeal_hold', params: {
--        'p_forfeited_id': realId, 'p_hold': hold,
--        'p_note': note, 'p_item_id': itemId });
--
--  The 3-arg originals were left behind by `create or replace`, which
--  cannot replace a function whose argument LIST differs -- it just adds a
--  second one. They still name the pre-rename `auth` schema, so they are
--  both dead and broken: nothing calls them, and anything that did would
--  fail. Dropping them is what makes the verification below honest.
-- --------------------------------------------------------------------------
drop function if exists public.set_appeal_hold(uuid, boolean, text);
drop function if exists public.release_appeal_with_decision(uuid, text, text);

-- --------------------------------------------------------------------------
--  Verify: nothing in public may still name the old schema.
-- --------------------------------------------------------------------------
do $verify$
declare
  r      record;
  v_bad  text := '';
  n      int := 0;
begin
  for r in
    select p.proname
      from pg_proc p
      join pg_namespace n2 on n2.oid = p.pronamespace
     where n2.nspname = 'public'
       and p.prosrc ~ '(^|[^_a-zA-Z0-9.])auth[.]'
     order by 1
  loop
    v_bad := v_bad || ' ' || r.proname;
    n := n + 1;
  end loop;

  if n > 0 then
    raise exception '% function body(ies) still name the old auth schema:%',
      n, v_bad;
  end if;
  raise notice 'PASS: no function in public names the old auth schema';
end $verify$;
