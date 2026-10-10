-- ============================================================================
--  Perishable Goods is the last yard page fetching the whole yard.
--
--  `perishableRowsProvider` awaits `livePackagesProvider` -- every package with
--  every item, warehouse entry and join -- then walks it looking for the 47
--  items registered as perishable. Same shape as every page fixed before it:
--  the cost is the yard, the output is twenty rows.
--
--  ⚠️ Two rules decide membership, and the second is the subtle one:
--
--    1. The item's nature is 'perishable'.
--    2. It has NOT been sent for disposal yet -- UNLESS a final outcome has
--       come back for it.
--
--  That exception matters. An item the DG has ruled on has been sent, so the
--  "already sent" set holds it; dropping it there would mean the yard and
--  Central Disposal never see the decision at all, because this is the ONLY
--  page that lists perishable goods. They never reach a warehouse and never
--  sit out the appeal window, so no disposition page can show them. The row
--  stays, carrying its outcome.
--
--  Sent is recorded as a disposal_request_items row pointing at a
--  forfeited_packages row whose source is 'perishable' -- the app matches on
--  (package_id, item_id), not on the forfeited id, because a request stores a
--  synthetic per-item row.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.perishable_rows;

create view public.perishable_rows as
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
  -- The Post Status Activity filter reads this verbatim.
  pi.reasons,
  pi.status,
  -- ⚠️ The date the page sorts and filters on. entryDate is nullable and the
  -- app falls back to createdAt, so a row without one does not vanish from a
  -- date filter its neighbours answer.
  coalesce(p.entry_date, p.created_at)       as effective_date,
  -- The final outcome, when Top Management has ruled. Null while it has not.
  up.id                                      as proposal_id,
  up.proposal,
  up.decided_at,
  up.delivered,
  -- Whether it has gone to Central Disposal. Shown as the row's own state.
  (dri.forfeited_package_id is not null)     as sent
from public.package_items pi
join public.packages p on p.id = pi.package_id
-- The forfeited row a perishable disposal request points at, if any.
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
where pi.nature = 'perishable'
  -- ⚠️ Sent items drop off UNLESS a decision came back — see the header.
  and (dri.forfeited_package_id is null or up.id is not null);

grant select on public.perishable_rows to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  bad int;
  n   int;
begin
  -- Nothing but perishable goods may be here.
  select count(*) into bad
    from public.perishable_rows pr
    join public.package_items pi on pi.id = pr.item_id
   where pi.nature <> 'perishable';
  if bad <> 0 then
    raise exception '% non-perishable row(s) leaked in', bad;
  end if;

  -- ⚠️ A sent item may only remain if it carries a decision. Without this the
  -- page would list goods that already belong to a disposal request.
  select count(*) into bad
    from public.perishable_rows where sent and proposal is null;
  if bad <> 0 then
    raise exception '% sent row(s) remain with no decision to show', bad;
  end if;

  -- One row per item, or the page shows the same goods twice.
  select count(*) into bad from (
    select item_id from public.perishable_rows
     group by item_id having count(*) > 1) d;
  if bad <> 0 then
    raise exception '% item(s) appear more than once', bad;
  end if;

  -- Every row needs a date, since the page sorts on it.
  if exists (select 1 from public.perishable_rows
              where effective_date is null) then
    raise exception 'a perishable row has no date to sort by';
  end if;

  select count(*) into n from public.perishable_rows;
  raise notice '% perishable row(s): % awaiting disposal, % decided',
    n,
    (select count(*) from public.perishable_rows where not sent),
    (select count(*) from public.perishable_rows where proposal is not null);
  for r in
    select coalesce(proposal, '(awaiting)') as outcome, count(*) as c
      from public.perishable_rows group by 1 order by 1
  loop
    raise notice '  % -- % row(s)', rpad(r.outcome, 22), r.c;
  end loop;
end
$verify$;
