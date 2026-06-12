-- ============================================================================
--  Enable Supabase Realtime on tender_sale_items so a delivery toggle / new
--  sale made in one session (e.g. a yard marking a package Delivered) shows up
--  live in the Central Disposal Sold Packages table (and vice-versa), instead
--  of staying stale until the page is reopened.
--  Idempotent — safe to run more than once.
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tender_sale_items'
  ) then
    alter publication supabase_realtime add table public.tender_sale_items;
  end if;
end $$;

-- Done.
