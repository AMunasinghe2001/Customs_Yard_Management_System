-- ============================================================================
--  61 · A sold lot pays its storage too
--
--  Release and re-export collect the storage charge before the goods leave.
--  A SALE did not: the button set `is_delivered` and the buyer walked out with
--  goods the yard had been storing, sometimes for years, with the charge shown
--  on no form and collected on no receipt.
--
--  ⚠️ The same shape as migration 60, deliberately. Three hand-overs, one
--  procedure for each, all taking (receipt, charge, handed-at) and all writing
--  them in the SAME statement as the flag -- two writes leave a window where
--  the goods are gone with no record of the money.
--
--  ⚠️ And the same trap: `create or replace function` matches on the ARGUMENT
--  LIST, so adding parameters creates an OVERLOAD and leaves the 2-argument
--  version resolvable. Migration 60's verify block caught that on its first
--  run; this drops the old signature outright.
-- ============================================================================

set lock_timeout = '5s';

alter table public.tender_sale_items
  add column if not exists handover_receipt_no text,
  add column if not exists handover_charge     numeric;

do $c$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'tender_sale_items_handover_receipt_consistent') then
    alter table public.tender_sale_items
      add constraint tender_sale_items_handover_receipt_consistent
      check (handover_receipt_no is null or is_delivered);
  end if;
end $c$;

drop function if exists public.disposal_toggle_delivery_status(uuid, boolean);

create or replace function public.disposal_toggle_delivery_status(
  p_item_id      uuid,
  p_is_delivered boolean,
  p_receipt_no   text default null,
  p_charge       numeric default null,
  p_handed_at    timestamptz default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_yard text;
begin
  select ti.yard into v_yard
    from public.tender_sale_items ti
   where ti.id = p_item_id;

  if v_yard is null then
    raise exception 'no tender_sale_item with id %', p_item_id;
  end if;

  -- The Central Disposal Directorate OR the package's own yard may update it:
  -- the same rule the other two hand-overs use.
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = auth.uid())) then
    raise exception 'not authorized';
  end if;

  update public.tender_sale_items
     set is_delivered        = p_is_delivered,
         delivered_at        =
           case when p_is_delivered then coalesce(p_handed_at, now()) end,
         handover_receipt_no = case when p_is_delivered then p_receipt_no end,
         handover_charge     = case when p_is_delivered then p_charge end
   where id = p_item_id;
end;
$fn$;

revoke all on function public.disposal_toggle_delivery_status(uuid, boolean, text, numeric, timestamptz) from public;
grant execute on function public.disposal_toggle_delivery_status(uuid, boolean, text, numeric, timestamptz) to authenticated;

-- ── Verify against live data ────────────────────────────────────────────────
do $verify$
declare
  n_fn   int;
  n_bad  int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'tender_sale_items'
                    and column_name = 'handover_receipt_no') then
    raise exception 'the receipt column was not added';
  end if;

  -- ⚠️ ONE function, not two. An old 2-argument overload left behind stays
  -- resolvable, and a caller that forgot the receipt would silently take it.
  select count(*) into n_fn
    from pg_proc where proname = 'disposal_toggle_delivery_status';
  if n_fn <> 1 then
    raise exception 'expected exactly 1 delivery function, found % (an overload survives)',
      n_fn;
  end if;

  select count(*) into n_bad
    from public.tender_sale_items
   where handover_receipt_no is not null and not is_delivered;
  if n_bad > 0 then
    raise exception '% sold lots carry a receipt but are not delivered', n_bad;
  end if;

  -- ⚠️ Assert the RULE, not the tally. Migration 55 pinned a count that
  -- officers then changed through the very button it had created, and
  -- re-running it failed on a system working exactly as intended. This one
  -- failed the same way on its first run -- 39 had become 40 -- so it asks
  -- the question that must always hold instead.
  --
  -- Nothing here backfills a receipt: those hand-overs happened before the
  -- form existed, and inventing a receipt number for them would put a
  -- fiction in the record. So a delivered row with no receipt is EXPECTED,
  -- and only the reverse is impossible.
  if exists (select 1 from public.tender_sale_items
              where is_delivered and delivered_at is null
                and handover_receipt_no is not null) then
    raise exception 'a receipt was recorded with no hand-over date';
  end if;

  -- Delivery only ever applies to goods that SOLD.
  if exists (select 1 from public.tender_sale_items
              where is_delivered and not sold) then
    raise exception 'a lot is delivered without having been sold';
  end if;

  raise notice 'verified: a sold lot pays its storage too';
end $verify$;
