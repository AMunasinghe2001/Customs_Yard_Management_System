-- ============================================================================
--  Disposal Expenses: the last Central Disposal tab fetching the whole yard.
--
--  It reads `srFinancialsProvider`, which calls getAllPackages() AND
--  getTenderSales() and then rolls the whole yard up in Dart -- per item, per
--  tax name, with an SR-keyed fallback for sales that name no item. That was
--  measured and deliberately left alone once (3.6ms and 0.2ms on ONE yard);
--  Central Disposal shows twenty-eight, and this tab needs a page.
--
--  ⚠️ This view answers only what the EXPENSES tab needs, which is a much
--  smaller question than the whole of SrFinancials: which SRs have money to
--  account for, and what has been spent against each. The sale proceeds, the
--  per-tax breakdown and the storage charges stay where they are -- the
--  Financials tab still uses them, and reproducing that shape here would mean
--  two definitions of the same figures.
--
--  The tab lists an SR when it "carries a deposit or already has a cost", so
--  both halves are computed here:
--    destroying_deposit  -- lodged on the SR form, per package
--    the five expense kinds, from financial_expenses
--
--  ⚠️ An expense keys EITHER to a package item OR to the SR number alone
--  (16 rows by item, 55 by SR in this database). Matching only one way would
--  silently drop most of the money.
--
--  ⚠️ A ZERO deposit is real -- it means none was lodged, or none was recorded
--  on the SR form. It must not be replaced with an invented figure, which is
--  a mistake this codebase has already made once.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.sr_expense_summary;

create view public.sr_expense_summary as
with per_sr as (
  select
    fe.sr_number,
    sum(fe.amount) filter (where fe.kind = 'destruction_expense')  as destruction,
    sum(fe.amount) filter (where fe.kind = 'advertising_expense')  as advertising,
    sum(fe.amount) filter (where fe.kind = 'labour_expense')       as labour,
    sum(fe.amount) filter (where fe.kind = 'transport_expense')    as transport,
    sum(fe.amount) filter (where fe.kind = 'auction_expense')      as auction,
    max(fe.incurred_on)                                           as last_spent_on
  from public.financial_expenses fe
  -- ⚠️ Grouped by SR NUMBER, so a row keyed only to the SR counts alongside
  -- one keyed to a package item. Both are real and both belong to the SR.
  where coalesce(trim(fe.sr_number), '') <> ''
  group by fe.sr_number
)
select
  p.id                                     as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  p.entry_date,
  p.created_at,
  -- ⚠️ Zero, never invented. A deposit of 0 means none was lodged.
  coalesce(p.destroying_deposit, 0)        as destroying_deposit,
  coalesce(s.destruction, 0)               as destruction_expense,
  coalesce(s.advertising, 0)               as advertising_expense,
  coalesce(s.labour, 0)                    as labour_expense,
  coalesce(s.transport, 0)                 as transport_expense,
  coalesce(s.auction, 0)                   as auction_expense,
  (coalesce(s.destruction, 0) + coalesce(s.advertising, 0)
   + coalesce(s.labour, 0) + coalesce(s.transport, 0)
   + coalesce(s.auction, 0))               as deposit_spent,
  -- What is left of the deposit, and what was overspent. Only one can be
  -- positive, which is why they are separate figures rather than a signed one.
  greatest(coalesce(p.destroying_deposit, 0)
           - (coalesce(s.destruction, 0) + coalesce(s.advertising, 0)
              + coalesce(s.labour, 0) + coalesce(s.transport, 0)
              + coalesce(s.auction, 0)), 0)  as refund,
  greatest((coalesce(s.destruction, 0) + coalesce(s.advertising, 0)
            + coalesce(s.labour, 0) + coalesce(s.transport, 0)
            + coalesce(s.auction, 0))
           - coalesce(p.destroying_deposit, 0), 0)  as deficit,
  -- The date the tab's range filter reads, falling back the way
  -- `_matchesDateRange` did:
  --   when money was last spent, then the SR's entry date, then created_at,
  --   and finally ⚠️ THE YEAR IN THE SR NUMBER.
  --
  -- That last one matters: a legacy SR can carry no usable date at all, and
  -- the app matched it on its number's year rather than dropping it from
  -- every date filter. Losing that would hide those SRs entirely whenever a
  -- range was set.
  coalesce(
    s.last_spent_on::timestamptz,
    p.entry_date,
    p.created_at,
    (substring(p.sr_number from '(20[0-9]{2})') || '-01-01')::timestamptz
  )                                        as activity_date
from public.packages p
left join per_sr s on s.sr_number = p.sr_number
-- ⚠️ The tab's own rule: only SRs with something to account for. An SR with
-- neither a deposit nor a cost has nothing to show and would be a blank row.
where coalesce(p.destroying_deposit, 0) > 0
   or coalesce(s.destruction, 0) + coalesce(s.advertising, 0)
      + coalesce(s.labour, 0) + coalesce(s.transport, 0)
      + coalesce(s.auction, 0) > 0;

grant select on public.sr_expense_summary to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  bad int;
  n   int;
begin
  -- ⚠️ Every listed SR must have something to account for, or the tab shows a
  -- row with nothing in it.
  select count(*) into bad
    from public.sr_expense_summary
   where destroying_deposit <= 0 and deposit_spent <= 0;
  if bad <> 0 then
    raise exception '% SR(s) are listed with nothing to account for', bad;
  end if;

  -- The parts must add up to the total spent.
  select count(*) into bad
    from public.sr_expense_summary
   where round(deposit_spent, 2) <> round(destruction_expense
         + advertising_expense + labour_expense + transport_expense
         + auction_expense, 2);
  if bad <> 0 then
    raise exception '% SR(s) have a spend that disagrees with its parts', bad;
  end if;

  -- ⚠️ A refund and a deficit cannot both be positive: either the deposit
  -- covered the spend or it did not.
  select count(*) into bad
    from public.sr_expense_summary where refund > 0 and deficit > 0;
  if bad <> 0 then
    raise exception '% SR(s) claim a refund AND a deficit', bad;
  end if;

  -- ⚠️ No money may be lost. Every expense row that names an SR must be
  -- counted against it -- matching only by package item would drop the 55
  -- rows keyed to the SR alone.
  select count(*) into bad
    from public.financial_expenses fe
   where coalesce(trim(fe.sr_number), '') <> ''
     and not exists (select 1 from public.sr_expense_summary s
                      where s.sr_number = fe.sr_number);
  if bad <> 0 then
    raise exception '% expense row(s) belong to no listed SR', bad;
  end if;

  -- ⚠️ Every row needs a date or a date filter silently hides it. The SR
  -- number's year is the last resort, exactly as the app had it.
  select count(*) into bad
    from public.sr_expense_summary where activity_date is null;
  if bad <> 0 then
    raise exception '% SR(s) have no date, so a range filter would hide them',
      bad;
  end if;

  select count(*) into n from public.sr_expense_summary;
  raise notice
    '% SR(s) with money to account for: % lodged, % spent, % refundable',
    n,
    (select round(sum(destroying_deposit), 2) from public.sr_expense_summary),
    (select round(sum(deposit_spent), 2) from public.sr_expense_summary),
    (select round(sum(refund), 2) from public.sr_expense_summary);
  for r in
    select sr_number, destroying_deposit, deposit_spent
      from public.sr_expense_summary
     order by deposit_spent desc limit 3
  loop
    raise notice '  %  deposit %  spent %',
      rpad(r.sr_number, 22), r.destroying_deposit, r.deposit_spent;
  end loop;
end
$verify$;
