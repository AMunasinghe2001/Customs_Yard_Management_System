-- ============================================================================
--  Clear ONLY the old Tender Sales & Destruction Sales that came back with the
--  restore snapshot, so you can continue the disposal flow from a clean state.
--
--  WHY: the restore snapshot re-inserted tender_sales / destructions rows that
--  were created in an earlier session. After forwarding a valuation, those old
--  rows resurfaced in the Central "Tender Sales" / "Destructions" tabs even
--  though you never created a new sale — because valuation forwarding makes the
--  forfeited items valid again, and the stale sale rows were still in the DB.
--
--  This removes those sale rows and their items. It does NOT touch:
--    • forfeited_packages   (your forfeited data stays)
--    • disposal_requests / _items  (your 7 requested items + valuations stay)
--    • packages / package_items / warehouse_entries
--  After running, the Central Tender Sales & Destructions tabs are empty and
--  you can create fresh sales from the forwarded disposal requests.
--
--  ⚠ DESTRUCTIVE for sale rows only. Run in the Supabase SQL Editor.
--  ⚠ CLOSE THE RUNNING APP FIRST (avoids realtime read-lock contention).
--
--  Wrapped in a transaction — inspect the NOTICE counts, then COMMIT (or
--  change the final `commit;` to `rollback;` to abort).
-- ============================================================================

begin;

do $$
declare
  n_ts_items  bigint := 0;
  n_ts        bigint := 0;
  n_di_items  bigint := 0;
  n_dest      bigint := 0;
begin
  -- Children first (FK: *_items → parent sale).
  if to_regclass('public.tender_sale_items') is not null then
    delete from public.tender_sale_items;
    get diagnostics n_ts_items = row_count;
  end if;
  if to_regclass('public.tender_sales') is not null then
    delete from public.tender_sales;
    get diagnostics n_ts = row_count;
  end if;

  if to_regclass('public.destruction_items') is not null then
    delete from public.destruction_items;
    get diagnostics n_di_items = row_count;
  end if;
  if to_regclass('public.destructions') is not null then
    delete from public.destructions;
    get diagnostics n_dest = row_count;
  end if;

  raise notice 'Deleted tender_sale_items = %', n_ts_items;
  raise notice 'Deleted tender_sales      = %', n_ts;
  raise notice 'Deleted destruction_items = %', n_di_items;
  raise notice 'Deleted destructions      = %', n_dest;
end $$;

-- The forwarded disposal requests remain 'forwarded', so they reappear in the
-- Central Disposal "Disposal Requests" tab, ready to be placed into a NEW
-- tender / destruction sale. Nothing else was touched.

-- Review the NOTICE counts above, then keep it:
commit;
-- Otherwise: rollback;
