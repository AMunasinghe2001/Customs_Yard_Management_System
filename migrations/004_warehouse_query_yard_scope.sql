-- ============================================================================
-- Warehouse view: expose the owning yard for mandatory SQL-side filtering.
-- A physical warehouse is shared; its entries are not. Safe to re-run.
-- ============================================================================

create or replace view public.warehouse_rows as
select
  we.id as entry_id,
  we.warehouse_id,
  we.package_id,
  we.package_item_id,
  p.sr_number,
  p.consignee_name,
  we.hold_reason,
  we.item_count,
  we.admitted_at,
  pi.item_name,
  case
    when lower(trim(coalesce(pi.status, ''))) = 'forfiet' then 'Forfeit'
    else pi.status
  end as item_status,
  p.status as package_status,
  lower(coalesce(p.status, '')) = 'confiscated' as is_package_confiscated,
  extract(year from we.admitted_at at time zone 'Asia/Colombo')::text
    as admitted_year,
  substring(p.sr_number, '(20[0-9]{2})') as sr_year,
  p.yard
from public.warehouse_entries we
join public.packages p on p.id = we.package_id
left join public.package_items pi on pi.id = we.package_item_id
where not coalesce(we.is_returned, false)
  and lower(trim(coalesce(pi.status, ''))) not in
      ('released', 'returned', 'sold', 're-export', 're-exported',
       'destroy', 'destroyed', 'other');

alter view public.warehouse_rows set (security_invoker = true);

create index if not exists warehouse_entries_yard_warehouse_live_idx
  on public.warehouse_entries (yard, warehouse_id, admitted_at desc)
  where not coalesce(is_returned, false);

analyze public.warehouse_entries;
