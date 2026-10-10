-- ============================================================================
--  Disposal Requests: four queries, then the filtering in Dart.
--
--  `getDisposalRequests` runs THREE lookups just to build the "already
--  consumed" set -- every tender's forfeited_package_ids array, every
--  tender_sale_item, every destruction_item -- and then fetches EVERY
--  forwarded request with:
--      disposal_request_items
--        -> forfeited_packages
--             -> packages -> package_items
--                         -> warehouse_entries -> warehouses
--
--  ...and finally drops, in Dart, the items that are not forwarded or are
--  already consumed, plus any request left with nothing. On one yard that is
--  53 requests. Central Disposal shows all twenty-eight.
--
--  ⚠️ The awkward part is that a REQUEST is only visible because of its ITEMS:
--  a request whose every item has been tendered must not appear at all, and
--  the item count shown on the card is the count that SURVIVES both gates.
--  Doing that in Dart means fetching every request in full to discover which
--  ones to throw away.
--
--  This view answers it per request, so a page can be chosen before the heavy
--  fetch runs.
--
--  The two gates, kept exactly as the app has them:
--    1. The request's valuation_status is 'forwarded'  (Central Disposal only
--       sees what the Valuation Directorate has sent on)
--    2. The ITEM's own `forwarded` flag                (a per-item gate: a
--       request can be forwarded with only some of its items released)
--  ...and then the item must not already be in a tender, a tender sale or a
--  destruction.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.disposal_request_summary;

create view public.disposal_request_summary as
with consumed as (
  -- ⚠️ Everything that has moved on. Three sources, exactly as the app's three
  -- lookups: a tender's id array, a tender sale's items, a destruction's items.
  select unnest(t.forfeited_package_ids)::uuid as fp_id
    from public.tenders t
   where t.forfeited_package_ids is not null
  union
  select ti.forfeited_package_id from public.tender_sale_items ti
  union
  select di.forfeited_package_id from public.destruction_items di
), live_items as (
  -- The items that survive BOTH gates and are not consumed.
  select dri.request_id,
         dri.forfeited_package_id,
         fp.sr_number,
         fp.consignee_name,
         fp.yard as item_yard
    from public.disposal_request_items dri
    join public.forfeited_packages fp on fp.id = dri.forfeited_package_id
   where dri.forwarded
     and dri.forfeited_package_id not in (select fp_id from consumed
                                           where fp_id is not null)
)
select
  dr.id,
  dr.yard,
  dr.request_date,
  dr.status,
  dr.created_at,
  dr.valuation_status,
  dr.valued_at,
  agg.live_count,
  -- ⚠️ Text, not text[]: the search runs as `ilike`, which an array cannot
  -- serve, and the Dart driver hands array columns back as UndecodedBytes.
  -- Pipe-wrapped so a filter cannot match across two neighbouring values.
  agg.sr_numbers,
  agg.consignees,
  agg.item_yards
from public.disposal_requests dr
cross join lateral (
  select
    count(*)                                                   as live_count,
    '|' || coalesce(string_agg(distinct li.sr_number, '|'), '') || '|'
                                                               as sr_numbers,
    '|' || coalesce(string_agg(distinct li.consignee_name, '|'), '') || '|'
                                                               as consignees,
    '|' || coalesce(string_agg(distinct li.item_yard, '|'), '') || '|'
                                                               as item_yards
    from live_items li
   where li.request_id = dr.id) agg
where dr.valuation_status = 'forwarded'
  -- ⚠️ A request with nothing left is not shown at all. This is the rule that
  -- forced the old code to fetch everything before it could decide.
  and agg.live_count > 0;

grant select on public.disposal_request_summary to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  bad int;
  n   int;
begin
  -- Nothing unforwarded may appear.
  select count(*) into bad
    from public.disposal_request_summary s
   where s.valuation_status <> 'forwarded';
  if bad <> 0 then
    raise exception '% request(s) are not forwarded but are listed', bad;
  end if;

  -- ⚠️ Every listed request must have at least one live item, or the card
  -- would show "0 packages requested" and there would be nothing to act on.
  select count(*) into bad
    from public.disposal_request_summary where live_count < 1;
  if bad <> 0 then
    raise exception '% request(s) are listed with no live items', bad;
  end if;

  -- ⚠️ And nothing already tendered, sold or destroyed may be counted. This
  -- is the whole of the consumed gate: get it wrong and Central Disposal is
  -- offered goods that have already moved on.
  select count(*) into bad
    from public.disposal_request_summary s
    join public.disposal_request_items dri on dri.request_id = s.id
   where dri.forwarded
     and (exists (select 1 from public.tender_sale_items ti
                   where ti.forfeited_package_id = dri.forfeited_package_id)
       or exists (select 1 from public.destruction_items di
                   where di.forfeited_package_id = dri.forfeited_package_id))
     and s.live_count > (
       select count(*) from public.disposal_request_items d2
         join public.forfeited_packages f2 on f2.id = d2.forfeited_package_id
        where d2.request_id = s.id and d2.forwarded
          and not exists (select 1 from public.tender_sale_items ti2
                           where ti2.forfeited_package_id = d2.forfeited_package_id)
          and not exists (select 1 from public.destruction_items di2
                           where di2.forfeited_package_id = d2.forfeited_package_id));
  if bad <> 0 then
    raise exception '% request(s) count goods that have already moved on', bad;
  end if;

  -- The searchable columns must carry their values.
  select count(*) into bad
    from public.disposal_request_summary where sr_numbers = '||';
  if bad <> 0 then
    raise exception '% request(s) have no SR numbers to search', bad;
  end if;

  select count(*) into n from public.disposal_request_summary;
  raise notice
    '% forwarded request(s) with live items, out of % request(s) in all',
    n, (select count(*) from public.disposal_requests);
  for r in
    select yard, request_date::date as d, live_count
      from public.disposal_request_summary
     order by created_at desc limit 4
  loop
    raise notice '  %  %  % package(s)', rpad(r.yard, 8), r.d, r.live_count;
  end loop;
end
$verify$;
