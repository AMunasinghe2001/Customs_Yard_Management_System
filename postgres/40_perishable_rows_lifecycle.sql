-- ============================================================================
--  40 · perishable_rows lifecycle states and marked_unsold tracking
--
--  Fixes the mismatch between Central Disposal Directorate's Perishable tab
--  and Top Management Directorate's Unsold Perishables tab.
--
--  Previously:
--  1. `perishable_rows` excluded items sent in disposal requests if they were
--     awaiting DG decision (dri is not null, up.id is null, sold is false).
--     This dropped the 6 genuine unsold perishable items from the view.
--  2. Unsent yard items defaulted to showing "Awaiting Top Management" in the
--     UI because proposal == null and soldPrice == null.
--
--  Now:
--  `perishable_rows` includes all perishable items with their complete
--  lifecycle flags: sent, marked_unsold, sold, and proposal.
-- ============================================================================

set client_min_messages = warning;
set lock_timeout = '5s';

drop view if exists public.perishable_rows;

create view public.perishable_rows as
with agg as (
  select ti.forfeited_package_id            as fp_id,
         count(*)                           as tender_count,
         bool_or(ti.sold)                   as ever_sold,
         bool_or(ti.unsold)                 as marked_unsold,
         max(ti.sold_price)                 as sold_price,
         max(ti.sold_at)                    as sold_at,
         max(ti.receipt_number)             as receipt_number
    from public.tender_sale_items ti
   group by ti.forfeited_package_id
)
select
  pi.id                                      as item_id,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.item_name,
  pi.hs_code,
  pi.quantity,
  pi.unit_value,
  pi.reasons,
  pi.status,
  coalesce(p.entry_date, p.created_at)       as effective_date,
  up.id                                      as proposal_id,
  up.proposal,
  up.decided_at,
  up.delivered,
  (dri.forfeited_package_id is not null)     as sent,
  coalesce(a.ever_sold, false)               as sold,
  a.sold_price,
  a.sold_at,
  a.receipt_number,
  coalesce(a.marked_unsold, false)           as marked_unsold
from public.package_items pi
join public.packages p on p.id = pi.package_id
left join lateral (
  select fp.id
    from public.forfeited_packages fp
   where fp.package_id = p.id
     and fp.item_id = pi.id
     and fp.source = 'perishable'
   limit 1) fpx on true
left join lateral (
  select dri2.forfeited_package_id
    from public.disposal_request_items dri2
   where dri2.forfeited_package_id = fpx.id
   limit 1) dri on true
left join public.unsold_proposals up
       on up.forfeited_package_id = fpx.id
left join agg a on a.fp_id = fpx.id
where pi.nature = 'perishable';

grant select on public.perishable_rows to public;

comment on view public.perishable_rows is
  'Perishable package items with full lifecycle tracking: sent, marked_unsold, sold, and proposal. See postgres/40.';
