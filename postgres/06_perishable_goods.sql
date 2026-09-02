-- ============================================================================
--  Perishable goods
--
--  Some seized goods cannot wait. Food, chemicals and the like spoil, so they
--  never reach a warehouse and never sit out the 30-day appeal window that
--  forfeited goods do -- by the time it expired there would be nothing left to
--  dispose of. They go straight to a disposal request instead, and from there
--  the ordinary process runs unchanged.
--
--  `nature` records which kind an item is. It is asked once, on the SR form,
--  and everything downstream reads it:
--
--    'normal'      -- warehouse, appeal window, the existing flow
--    'perishable'  -- neither; listed on its own page, disposed of at once
--
--  ⚠️ Defaulting to 'normal' is what leaves every existing item and every
--  existing query behaving exactly as before.
--
--  Idempotent -- safe to re-run.
-- ============================================================================

set client_min_messages = warning;

alter table public.package_items
  add column if not exists nature text not null default 'normal';

-- Only the two the app knows. A typo here would quietly create a third kind
-- that no screen lists and no query filters on.
alter table public.package_items
  drop constraint if exists package_items_nature_check;
alter table public.package_items
  add constraint package_items_nature_check
  check (nature in ('normal', 'perishable'));

-- The perishable pages filter on this and nothing else, so it earns an index.
create index if not exists package_items_nature_idx
  on public.package_items (nature)
  where nature <> 'normal';

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  v_pkg  uuid;
  v_item uuid;
  v_n    int;
begin
  insert into public.packages (sr_number, consignee_name, created_at)
  values ('VERIFY/NATURE/99/2099', 'Nature Probe', now())
  returning id into v_pkg;

  -- Existing rows and new ones without a nature are 'normal': that is what
  -- keeps every current screen behaving as it did.
  insert into public.package_items (package_id, item_name, quantity)
  values (v_pkg, 'Probe Item', 1)
  returning id into v_item;

  select count(*) into v_n
  from public.package_items
  where id = v_item and nature = 'normal';
  if v_n <> 1 then
    raise exception 'VERIFY FAILED: nature did not default to normal';
  end if;

  -- Perishable is accepted.
  update public.package_items set nature = 'perishable' where id = v_item;

  -- Anything else is not.
  begin
    update public.package_items set nature = 'frozen' where id = v_item;
    raise exception 'VERIFY FAILED: an unknown nature was accepted';
  exception when check_violation then
    null; -- expected
  end;

  delete from public.packages where id = v_pkg;
  raise notice 'perishable goods VERIFY passed';
end
$verify$;
