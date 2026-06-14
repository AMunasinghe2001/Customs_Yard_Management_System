-- ============================================================================
--  Enable Supabase Realtime on the remaining disposal-pipeline tables so data
--  moving between tables (request → tender sale / destruction → sold/destroyed)
--  updates every open view live, instead of needing a page reload:
--    • disposal_requests / disposal_request_items  (the requests feed)
--    • destructions / destruction_items            (the destructions + undestroyed views)
--  (tender_sale_items is already published — see 20260611_tender_sale_items_realtime.sql.)
--  Idempotent — safe to run more than once.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'disposal_requests',
    'disposal_request_items',
    'destructions',
    'destruction_items'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Done.
