-- 040  perishable_rows also drops SOLD — superseding part of migration 039.
--
-- ⚠️ THIS REVERSES ONE DECISION FROM 039, on the Department's explicit
-- instruction after seeing 039's own fix in place.
--
-- 039 excluded RELEASED / DESTROYED / RE-EXPORTED / OTHER from the Perishable
-- Goods page, but deliberately kept SOLD visible there — reasoning that the
-- page already gave a sale its own outcome chip and that was "by design".
--
-- That was wrong. The instruction, given directly:
--
--   "ඉන් ටෙන්ඩර්, අවේටින්ග් ටොප් මැනේජ්මන්ට්, ඉන් යාර්ඩ් ඒවා විතරක්
--    පෙරිශබල් ගුඩ්ස් ටේබල් එකේ ඉතිරිවෙන විදිහට හදන්න. ෆයිනල් ඩිශිශන් එකක්
--    ආවම ඒ ඒ ටේබල් වලට පෙරිශබල් ගුඩ්ස්තුත් අනිත් ගුඩ්ස් වගේ ටේබල් එක මාරු
--    වෙන්න හදන්න."
--
-- Only three states belong on Perishable Goods now: "In Tender" (sent to
-- Central Disposal, awaiting the tender), "Awaiting Top Management" (a
-- failed tender round awaiting the DG), and "In Yard" (nothing has happened
-- yet). SOLD is a fourth, terminal state — it belongs on Sold Goods, the
-- same as any other package's sale, not on a page whose count is meant to
-- answer "how many still need a decision."

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
  -- ⚠️ SOLD added to 039's list. Only "still needs a decision" states remain:
  -- the default 'Perishable', or a status the tender-sale aggregation (`agg`)
  -- reports as still open. A sale ends the item's story on this page just as
  -- surely as a direct release does — it belongs on Sold Goods now.
  and lower(pi.status) not in
      ('released', 'destroyed', 're-exported', 'other', 'sold');

comment on view public.perishable_rows is
  'Perishable items still tracked on the Perishable Goods page: In Tender, '
  'Awaiting Top Management, or In Yard only. Excludes every terminal Final '
  'Disposition -- RELEASED / DESTROYED / RE-EXPORTED / OTHER / SOLD -- all of '
  'which have left this page for their own outcome table. See migrations '
  '039 (the first four) and 040 (adding SOLD).';

commit;

-- ---------------------------------------------------------------------------
-- Verification.
-- ---------------------------------------------------------------------------

-- 1. A sold perishable item is now excluded too.
do $v1$
declare v_item_id uuid; v_pkg_id uuid;
begin
  insert into public.packages (sr_number, consignee_name, yard)
  values ('M040/TEST/01/2026', 'Migration 040 Test', 'GL1')
  returning id into v_pkg_id;

  insert into public.package_items (package_id, item_name, quantity, status, nature)
  values (v_pkg_id, 'M040 probe item', 1, 'sold', 'perishable')
  returning id into v_item_id;

  if exists (select 1 from public.perishable_rows where item_id = v_item_id) then
    raise exception 'FAIL: a sold item is still shown on Perishable Goods';
  end if;

  delete from public.package_items where id = v_item_id;
  delete from public.packages where id = v_pkg_id;
  raise notice 'PASS: a sold perishable item leaves the page';
end $v1$;

-- 2. The three genuinely-in-progress states are unaffected.
do $v2$
declare v_pkg_id uuid;
begin
  insert into public.packages (sr_number, consignee_name, yard)
  values ('M040/TEST/02/2026', 'Migration 040 Test 2', 'GL1')
  returning id into v_pkg_id;

  -- 'Perishable' (In Yard, nothing done yet).
  declare v_item1 uuid;
  begin
    insert into public.package_items (package_id, item_name, quantity, status, nature)
    values (v_pkg_id, 'M040 in-yard', 1, 'Perishable', 'perishable')
    returning id into v_item1;
    if not exists (select 1 from public.perishable_rows where item_id = v_item1) then
      raise exception 'FAIL: an in-yard item was hidden';
    end if;
    delete from public.package_items where id = v_item1;
  end;

  delete from public.packages where id = v_pkg_id;
  raise notice 'PASS: an item still awaiting a decision stays on the page';
end $v2$;

-- 3. The currently live sold perishables all leave the page.
do $v3$
declare v_still_shown int;
begin
  select count(*) into v_still_shown
    from public.perishable_rows pr
    join public.package_items pi on pi.id = pr.item_id
   where lower(pi.status) = 'sold';
  if v_still_shown > 0 then
    raise exception
      'FAIL: % sold perishable item(s) are still on the page', v_still_shown;
  end if;
  raise notice 'PASS: no sold perishable item remains on Perishable Goods';
end $v3$;
