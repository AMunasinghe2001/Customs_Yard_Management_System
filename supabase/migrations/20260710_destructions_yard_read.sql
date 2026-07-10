-- ============================================================================
--  Allow yard officers to read `destructions` that contain their yard's items.
--
--  BUG: the yard Destruction Sale screen (destruction_disposal_screen.dart)
--  watches destructionsProvider → getDestructions(), which selects from the
--  `destructions` header table with `destruction_items` nested. But the only
--  read policy on `destructions` was `destructions_manage`, restricted to
--  disposal users + admins. Officers therefore got ZERO destruction rows
--  (the header is RLS-blocked, so the nested items never surface either),
--  and the page always showed "No destruction sales for this yard yet" even
--  after an item was destroyed.
--
--  `destruction_items` already has a yard-read policy (destruction_items_yard_read),
--  so this mirrors 20260624_tender_sales_yard_read.sql for the header table:
--  an officer/admin may READ a destruction when at least one of its items
--  belongs to their yard.
-- ============================================================================

drop policy if exists destructions_yard_read on public.destructions;
create policy destructions_yard_read on public.destructions
  for select
  using (
    exists (
      select 1
        from public.destruction_items di
        join public.profiles p on p.id = auth.uid()
       where di.destruction_id = destructions.id
         and di.yard = p.yard
    )
  );
