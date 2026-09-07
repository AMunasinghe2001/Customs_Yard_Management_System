-- The Valuation Directorate's two feed tabs, as a view.
--
-- ⚠️ The Valuation portal had NO paging at all -- not SQL paging, not even a
-- client-side pager. `ListView.separated(itemCount: list.length)` rendered
-- every request awaiting valuation, and the query behind it went SIX levels
-- deep: requests -> items -> forfeited_packages -> packages -> package_items,
-- and separately -> warehouse_entries -> warehouses. All three tabs fired
-- their own such query on open.
--
-- Two rules decided membership, and BOTH ran in Dart after the whole feed had
-- been fetched -- which is why a page could not be asked for by number:
--
--   * A request stays in the feed while ANY of its items is not yet
--     FORWARDED. Forwarded items have moved on to Central Disposal.
--
--   * A request belongs to the Perishable tab when EVERY one of its pending
--     items is perishable. Perishables arrive as their own request, so a
--     mixed one is not a perishable batch -- and `perishable` is a real
--     forfeited_packages source (postgres/07), so the row says what the goods
--     are rather than the screen inferring it.
--
-- Both rules live here now. The two tabs still split the SAME membership, so
-- a request can never appear on both or fall between them.

drop view if exists public.valuation_rows cascade;

create view public.valuation_rows as
with pending_item as (
  -- The items still awaiting a cost, with what the row needs to be found by.
  select
    dri.request_id,
    dri.id as item_id,
    fp.source,
    fp.sr_number,
    fp.consignee_name,
    fp.yard as item_yard
  from public.disposal_request_items dri
  join public.forfeited_packages fp
    on fp.id = dri.forfeited_package_id
  where not dri.forwarded
),
agg as (
  select
    request_id,
    count(*) as pending_count,
    -- ⚠️ EVERY pending item, not any. A request holding one perishable among
    -- ordinary goods is not a perishable batch, and putting it on that tab
    -- would tell the officer it is on the Special Tender clock when it is not.
    bool_and(source = 'perishable') as all_perishable,
    -- Pipe-wrapped, so a search matches a whole value rather than a substring
    -- of one -- the same shape disposal_request_summary uses.
    '|' || coalesce(string_agg(distinct sr_number, '|'), '') || '|'
      as sr_numbers,
    '|' || coalesce(string_agg(distinct consignee_name, '|'), '') || '|'
      as consignees,
    '|' || coalesce(string_agg(distinct item_yard, '|'), '') || '|'
      as item_yards
  from pending_item
  group by request_id
)
select
  dr.id,
  dr.yard,
  dr.request_date,
  dr.status,
  dr.created_at,
  dr.valuation_status,
  agg.pending_count,
  agg.all_perishable as is_perishable,
  agg.sr_numbers,
  agg.consignees,
  agg.item_yards,
  -- The name shown on the card, joined here rather than embedded per row.
  pr.full_name as created_by_name
from public.disposal_requests dr
join agg on agg.request_id = dr.id
left join public.profiles pr on pr.id = dr.created_by;

comment on view public.valuation_rows is
  'One row per disposal request still awaiting valuation: the request, how '
  'many of its items are pending, and whether every one of them is '
  'perishable. The Valuation portal pages and filters on this.';


-- ── Does it hold the same requests the Dart held? ────────────────────────
-- ⚠️ Asserted against the live data. A view that admits a different set of
-- requests is a wrong view, however clean its SQL reads: a request that falls
-- out of this feed is one the directorate never gets to cost.
do $verify$
declare
  n_rows        int;
  n_expected    int;
  n_perishable  int;
  n_ordinary    int;
  n_items       int;
  n_items_view  int;
begin
  select count(*) into n_rows from public.valuation_rows;

  -- The same membership the service computed in Dart: a request with at least
  -- one not-yet-forwarded item.
  select count(distinct request_id) into n_expected
    from public.disposal_request_items where not forwarded;

  if n_rows <> n_expected then
    raise exception 'valuation_rows holds % requests, % have pending items',
      n_rows, n_expected;
  end if;

  -- The two tabs must partition the feed, never overlap it and never lose a
  -- request between them.
  select count(*) filter (where is_perishable),
         count(*) filter (where not is_perishable)
    into n_perishable, n_ordinary
    from public.valuation_rows;

  if n_perishable + n_ordinary <> n_rows then
    raise exception 'the two tabs hold % + % of % requests',
      n_perishable, n_ordinary, n_rows;
  end if;

  -- And the pending counts add up to the pending items themselves.
  select count(*) into n_items
    from public.disposal_request_items where not forwarded;
  select coalesce(sum(pending_count), 0) into n_items_view
    from public.valuation_rows;

  if n_items <> n_items_view then
    raise exception 'pending items: % in the table, % counted by the view',
      n_items, n_items_view;
  end if;

  raise notice 'valuation_rows: % requests (% perishable, % ordinary), % pending items',
    n_rows, n_perishable, n_ordinary, n_items;
end
$verify$;
