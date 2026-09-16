-- 039  perishable_rows stops showing an item after its Final Disposition.
--
-- ⚠️ THE BUG THIS FIXES: an officer opened a perishable item ("Imported
-- Apples", CED/GL1/SR/28/2026) from the Perishable Goods page, recorded a
-- Final Disposition of RELEASE, and got the success toast — but the row never
-- left the Perishable Goods table (its outcome chip stayed "In Yard"), and it
-- never appeared on the Released Goods page either.
--
-- The write itself was correct: `recordFinalDisposition` sets
-- `package_items.status = 'released'` and the row IS in that state:
--
--     select status from package_items where id = '<the item>';
--     -> released
--
-- Two independent things were wrong reading it back:
--
--   1. Released Goods is driven entirely by `warehouse_entries` with
--      `is_returned = true`. `recordFinalDisposition` only inserts that row
--      `if (refEntry != null)` — i.e. only for an item that was admitted to a
--      warehouse at some point. Perishable Goods explicitly SKIPS
--      warehousing (the page's own subtitle: "no warehouse, no appeal
--      window"), so `refEntry` is null, no return row is written, and there
--      is nothing for Released Goods to show.
--
--      This is deliberately NOT "fixed" by inventing a warehouse_entries row
--      for an item that was never admitted: `warehouse_id` and `hold_reason`
--      are NOT NULL on that table, so doing so would mean fabricating a
--      warehouse and a hold reason the goods never actually had. Perishables
--      that skip warehousing are not warehouse discharges, and Released Goods
--      is a warehouse-discharge report.
--
--   2. `perishable_rows` (the view Perishable Goods reads) never filtered on
--      `package_items.status` at all — it is scoped by `nature = 'perishable'`
--      and nothing else. An item stays on this page FOREVER once registered,
--      whatever its status becomes, which is also why the "Awaiting disposal"
--      count at the top of the page was never actually a count of items
--      awaiting anything.
--
-- The fix is entirely on the read side: once an item's Final Disposition is
-- one of the terminal, non-tender outcomes (RELEASED / DESTROYED /
-- RE-EXPORTED / OTHER), it is excluded from `perishable_rows`. SOLD stays —
-- the page already gives it its own outcome chip, by design (see the
-- "Sold is one of the choices HERE and nowhere else" comment in
-- getPerishableRowsPaged) — and 'Perishable', the default, obviously stays.

begin;

create or replace view public.perishable_rows
with (security_invoker = true) as
with agg as (
  select ti.forfeited_package_id as fp_id,
         count(*) as tender_count,
         bool_or(ti.sold) as ever_sold,
         bool_or(ti.unsold) as marked_unsold,
         max(ti.sold_price) as sold_price,
         max(ti.sold_at) as sold_at,
         max(ti.receipt_number) as receipt_number
    from public.tender_sale_items ti
   group by ti.forfeited_package_id
)
select
  pi.id as item_id,
  p.id as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.item_name,
  pi.hs_code,
  pi.quantity,
  pi.unit_value,
  pi.reasons,
  pi.status,
  coalesce(p.entry_date, p.created_at) as effective_date,
  up.id as proposal_id,
  up.proposal,
  up.decided_at,
  up.delivered,
  dri.forfeited_package_id is not null as sent,
  coalesce(a.ever_sold, false) as sold,
  a.sold_price,
  a.sold_at,
  a.receipt_number,
  coalesce(a.marked_unsold, false) as marked_unsold
from public.package_items pi
join public.packages p on p.id = pi.package_id
left join lateral (
  select fp.id
    from public.forfeited_packages fp
   where fp.package_id = p.id and fp.item_id = pi.id and fp.source = 'perishable'
   limit 1
) fpx on true
left join lateral (
  select dri2.forfeited_package_id
    from public.disposal_request_items dri2
   where dri2.forfeited_package_id = fpx.id
   limit 1
) dri on true
left join public.unsold_proposals up on up.forfeited_package_id = fpx.id
left join agg a on a.fp_id = fpx.id
where pi.nature = 'perishable'
  -- ⚠️ The fix. A Final Disposition of RELEASED / DESTROYED / RE-EXPORTED /
  -- OTHER means the goods have left the system through THIS page's own
  -- action — they belong on Released/Destroyed/Re-exported/Other Goods now,
  -- not here. SOLD is excluded from this list on purpose: it already has its
  -- own outcome chip on this page and is meant to stay visible here.
  and lower(pi.status) not in ('released', 'destroyed', 're-exported', 'other');

comment on view public.perishable_rows is
  'Perishable items still tracked on the Perishable Goods page. Excludes '
  'RELEASED / DESTROYED / RE-EXPORTED / OTHER final dispositions -- those '
  'goods have left this page for good. SOLD stays: it is a final outcome '
  'this page shows its own chip for. See migration 039.';

commit;

-- ---------------------------------------------------------------------------
-- Verification.
-- ---------------------------------------------------------------------------

-- 1. The reported item is gone from the view now that it is released.
do $v1$
declare v_status text;
declare v_still_shown boolean;
begin
  select status into v_status from public.package_items
   where id = '2a43b9ca-58ce-42d3-9570-271bf0fd7741';
  if v_status is null then
    raise notice 'SKIP: the reported item is not in this database';
    return;
  end if;
  if lower(v_status) <> 'released' then
    raise notice 'SKIP: the reported item is not currently released (status=%)', v_status;
    return;
  end if;
  select exists (
    select 1 from public.perishable_rows
     where item_id = '2a43b9ca-58ce-42d3-9570-271bf0fd7741'
  ) into v_still_shown;
  if v_still_shown then
    raise exception 'FAIL: the released item is still on Perishable Goods';
  end if;
  raise notice 'PASS: a released perishable item leaves the page';
end $v1$;

-- 2. A row still in the default 'Perishable' status is unaffected.
do $v2$
declare v_cat_id uuid; v_item_id uuid; v_pkg_id uuid;
begin
  insert into public.packages (sr_number, consignee_name, yard)
  values ('M039/TEST/01/2026', 'Migration 039 Test', 'GL1')
  returning id into v_pkg_id;

  insert into public.package_items (package_id, item_name, quantity, status, nature)
  values (v_pkg_id, 'M039 probe item', 1, 'Perishable', 'perishable')
  returning id into v_item_id;

  if not exists (select 1 from public.perishable_rows where item_id = v_item_id) then
    raise exception 'FAIL: an item still awaiting disposal was hidden';
  end if;

  delete from public.package_items where id = v_item_id;
  delete from public.packages where id = v_pkg_id;
  raise notice 'PASS: an item still awaiting disposal stays on the page';
end $v2$;

-- 3. A SOLD item is deliberately still shown (it keeps its own chip).
do $v3$
declare v_item_id uuid; v_pkg_id uuid;
begin
  insert into public.packages (sr_number, consignee_name, yard)
  values ('M039/TEST/02/2026', 'Migration 039 Test 2', 'GL1')
  returning id into v_pkg_id;

  insert into public.package_items (package_id, item_name, quantity, status, nature)
  values (v_pkg_id, 'M039 probe item 2', 1, 'sold', 'perishable')
  returning id into v_item_id;

  if not exists (select 1 from public.perishable_rows where item_id = v_item_id) then
    raise exception 'FAIL: a sold item was hidden -- it should keep its own chip here';
  end if;

  delete from public.package_items where id = v_item_id;
  delete from public.packages where id = v_pkg_id;
  raise notice 'PASS: a sold item is still shown, with its own outcome';
end $v3$;
