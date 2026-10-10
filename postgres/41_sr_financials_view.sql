-- The Financials ledger as a VIEW, one row per SR.
--
-- ⚠️ The page loaded EVERY SR, then filtered and totalled them in Dart.
-- 176 SRs, 395 items, 333 warehouse entries and 82 tender sales, all decoded
-- into Dart objects on the UI isolate so a header strip could add up ten
-- numbers -- which is why the page took a second or two to appear.
--
-- Every figure below is the same one buildSrFinancials computes; the rules are
-- transcribed from it, not reinvented:
--
--   sr_charges     storage, billed per warehouse ENTRY, day by day at the
--                  rate in force on each day
--   sale_proceeds  what the goods fetched at tender
--   taxes          the taxes STORED on the sale item, which are the ones that
--                  were enabled at the moment of sale
--   deposit        lodged once for the whole SR
--   the five expense kinds, and the refund derived per SR from them
--
-- Two seams are deliberate:
--
--   * A sale whose forfeited row names no item counts towards the SR rather
--     than a goods item; both are collected here, so the SR total is exact
--     either way. The per-ITEM split the table dialog shows still needs
--     buildSrFinancials -- this view answers the page and its totals.
--
--   * A refund is deposit minus spent, per SR, floored at zero, and must be
--     summed per SR rather than derived from the totals: an SR that overspent
--     its deposit refunds nothing, it does not refund a negative.

-- ⚠️ Every date below is taken in ASIA/COLOMBO, never in the session's own
-- timezone.
--
-- `admitted_at::date` on a timestamptz uses whatever timezone the connection
-- happens to be set to. psql here inherits Asia/Colombo; the app's driver
-- connects as UTC. The same entry therefore lands on a different DAY for each
-- of them, and a storage charge counted day by day came out 88,100 higher
-- read through the app than read through psql -- the same view, the same
-- database, two answers.
--
-- Dart's own figure is the one to match: parseDbDate calls .toLocal(), so
-- calculatePackageCharge has always counted days in the yard's local time.
-- `at time zone 'Asia/Colombo'` makes that explicit here and independent of
-- who is asking.

drop view if exists public.sr_financials cascade;

create view public.sr_financials as
with

-- ── Storage, per warehouse entry ─────────────────────────────────────────
-- ⚠️ Counted by RATE PERIOD, not day by day.
--
-- calculatePackageCharge walks one day at a time and looks up the rate in
-- force on each, which is the clearest way to say the rule and the slowest
-- way to compute it: generate_series over every entry's whole stay, with a
-- correlated lookup per day, took 89ms. A rate holds until the next one
-- starts, so the same figure is the rate times the days of overlap between
-- the entry's stay and that period -- 14.7ms, and identical to the cent.
rate_period as (
  -- Each rate runs until the next one begins.
  select (rt.effective_from at time zone 'Asia/Colombo')::date as from_day,
         lead((rt.effective_from at time zone 'Asia/Colombo')::date)
           over (order by rt.effective_from) as next_day,
         rt.rate
    from public.storage_rates rt
  union all
  -- ⚠️ And the implicit period BEFORE the first rate was ever recorded, at
  -- the model's own default of 50. Goods admitted before the rate table was
  -- filled in are still charged; dropping this period would silently zero
  -- them.
  select date '1900-01-01',
         (select min((rt2.effective_from at time zone 'Asia/Colombo')::date)
            from public.storage_rates rt2),
         50::numeric
),
chargeable_entry as (
  select
    we.id,
    p.sr_number,
    (we.admitted_at at time zone 'Asia/Colombo')::date as first_day,
    coalesce((we.returned_at at time zone 'Asia/Colombo')::date,
             (now() at time zone 'Asia/Colombo')::date) as last_day,
    -- The entry's own unit count, with the same repair the model makes: an
    -- old row saying 1 unit for an item that holds more, still in the yard,
    -- is charged for the item's quantity.
    case
      when we.item_count = 1
       and we.package_item_id is not null
       and coalesce(we.is_returned, false) = false
       and coalesce(pi_one.quantity, 0) > 1
      then pi_one.quantity
      else we.item_count
    end as units
  from public.warehouse_entries we
  join public.packages p on p.id = we.package_id
  left join public.package_items pi_one on pi_one.id = we.package_item_id
  where
    -- No charge when the package is confiscated, or when the item this entry
    -- bills is confiscated / forfeited / abandoned / destroyed.
    lower(coalesce(p.status, '')) <> 'confiscated'
    and (
      we.package_item_id is null
      or lower(coalesce(pi_one.status, '')) not in
         ('confiscated', 'forfeit', 'forfiet', 'forfeited',
          'abandoned', 'destroy', 'destroyed')
    )
    -- An entry naming no item charges nothing when EVERY item of its package
    -- is in one of those states.
    and (
      we.package_item_id is not null
      or not exists (select 1 from public.package_items pi2
                      where pi2.package_id = p.id)
      or exists (
        select 1 from public.package_items pi3
         where pi3.package_id = p.id
           and lower(coalesce(pi3.status, '')) not in
               ('confiscated', 'forfeit', 'forfiet', 'forfeited',
                'abandoned', 'destroy', 'destroyed'))
    )
),
sr_storage as (
  select
    ce.sr_number,
    sum(rp.rate * ce.units
        * (least(ce.last_day, coalesce(rp.next_day - 1, date '9999-12-31'))
           - greatest(ce.first_day, rp.from_day) + 1)) as sr_charges
  from chargeable_entry ce
  join rate_period rp
    -- Only the periods this stay actually overlaps.
    on greatest(ce.first_day, rp.from_day)
       <= least(ce.last_day, coalesce(rp.next_day - 1, date '9999-12-31'))
  group by ce.sr_number
),

-- ── What the goods fetched, and the tax stored with the sale ─────────────
-- ⚠️ applied_taxes is a JSON array of name/amount written AT THE MOMENT OF
-- SALE. Re-reading today's tax table would restate a past sale whenever a
-- rate is enabled or disabled, so the stored amounts are the only correct
-- source.
sale_tax as (
  -- One row per (SR, tax name): the table has a COLUMN per tax, and which
  -- taxes exist is data, not a fixed list -- Cess, PAL, Stamp Duty and VAT
  -- appear on today's sales, and a tax added tomorrow must reach the table
  -- without a migration.
  select
    coalesce(fp.sr_number, '') as sr_number,
    coalesce(nullif(trim(t ->> 'name'), ''), 'Tax') as tax_name,
    sum(coalesce((t ->> 'amount')::numeric, 0)) as amount
  from public.tender_sale_items tsi
  join public.forfeited_packages fp
    on fp.id = tsi.forfeited_package_id
  cross join lateral jsonb_array_elements(
    case jsonb_typeof(tsi.applied_taxes)
      when 'array' then tsi.applied_taxes
      else '[]'::jsonb
    end) as t
  where tsi.sold
  group by 1, 2
),
sr_sale as (
  select
    coalesce(fp.sr_number, '') as sr_number,
    sum(coalesce(tsi.sold_price, 0)) as sale_proceeds,
    sum((select coalesce(sum(coalesce((t ->> 'amount')::numeric, 0)), 0)
           from jsonb_array_elements(
                  case jsonb_typeof(tsi.applied_taxes)
                    when 'array' then tsi.applied_taxes
                    else '[]'::jsonb
                  end) as t)) as taxes
  from public.tender_sale_items tsi
  join public.forfeited_packages fp
    on fp.id = tsi.forfeited_package_id
  where tsi.sold
  group by 1
  having coalesce(fp.sr_number, '') <> ''
),
sr_tax_map as (
  select sr_number,
         jsonb_object_agg(tax_name, amount) as taxes_by_name
    from sale_tax
   where sr_number <> ''
   group by sr_number
),

-- ── Recorded costs, per SR ───────────────────────────────────────────────
sr_expense as (
  select
    fe.sr_number,
    coalesce(sum(fe.amount) filter (where fe.kind = 'destruction_expense'), 0)
      as destruction_expense,
    coalesce(sum(fe.amount) filter (where fe.kind = 'advertising_expense'), 0)
      as advertising_expense,
    coalesce(sum(fe.amount) filter (where fe.kind = 'labour_expense'), 0)
      as labour_expense,
    coalesce(sum(fe.amount) filter (where fe.kind = 'transport_expense'), 0)
      as transport_expense,
    coalesce(sum(fe.amount) filter (where fe.kind = 'auction_expense'), 0)
      as auction_expense
  from public.financial_expenses fe
  where coalesce(trim(fe.sr_number), '') <> ''
  group by fe.sr_number
),

-- ── One row per SR ───────────────────────────────────────────────────────
-- ⚠️ Grouped from packages, because the deposit is lodged once for the SR and
-- an SR can span more than one package row.
sr as (
  select
    p.sr_number,
    min(p.yard)           as yard,
    min(p.consignee_name) as consignee_name,
    sum(coalesce(p.destroying_deposit, 0)) as destroying_deposit,
    min(p.entry_date)     as entry_date,
    min(p.created_at)     as created_at,
    count(*)              as package_count
  from public.packages p
  where coalesce(trim(p.sr_number), '') <> ''
  group by p.sr_number
)

select
  sr.sr_number,
  sr.yard,
  sr.consignee_name,
  sr.package_count,

  -- The goods name and quantity the row shows.
  (select string_agg(distinct pi4.item_name, ', ')
     from public.package_items pi4
     join public.packages p4 on p4.id = pi4.package_id
    where p4.sr_number = sr.sr_number
      and coalesce(trim(pi4.item_name), '') <> '') as goods_name,
  (select coalesce(sum(pi5.quantity), 0)
     from public.package_items pi5
     join public.packages p5 on p5.id = pi5.package_id
    where p5.sr_number = sr.sr_number) as quantity,

  coalesce(st.sr_charges, 0)          as sr_charges,
  sr.destroying_deposit,
  coalesce(sl.sale_proceeds, 0)       as sale_proceeds,
  coalesce(sl.taxes, 0)               as taxes,
  -- The per-tax breakdown the table shows as one column per tax.
  coalesce(tm.taxes_by_name, '{}'::jsonb) as taxes_by_name,

  coalesce(ex.destruction_expense, 0) as destruction_expense,
  coalesce(ex.advertising_expense, 0) as advertising_expense,
  coalesce(ex.labour_expense, 0)      as labour_expense,
  coalesce(ex.transport_expense, 0)   as transport_expense,
  coalesce(ex.auction_expense, 0)     as auction_expense,

  (coalesce(ex.destruction_expense, 0) + coalesce(ex.advertising_expense, 0)
   + coalesce(ex.labour_expense, 0) + coalesce(ex.transport_expense, 0)
   + coalesce(ex.auction_expense, 0)) as deposit_spent,

  -- ⚠️ Floored at zero PER SR. An SR that overspent its deposit refunds
  -- nothing; summing a negative would understate the total refunds.
  greatest(
    sr.destroying_deposit
    - (coalesce(ex.destruction_expense, 0) + coalesce(ex.advertising_expense, 0)
       + coalesce(ex.labour_expense, 0) + coalesce(ex.transport_expense, 0)
       + coalesce(ex.auction_expense, 0)),
    0) as refund,

  -- The date the page filters and orders on, with the same fallback chain the
  -- Dart row applies: the SR's first warehouse admission, else its entry date,
  -- else the year in the SR number.
  coalesce(
    (select min(we2.admitted_at)
       from public.warehouse_entries we2
       join public.packages p6 on p6.id = we2.package_id
      where p6.sr_number = sr.sr_number),
    sr.entry_date,
    sr.created_at,
    (substring(sr.sr_number, '(20[0-9]{2})') || '-01-01')::timestamptz
  ) as activity_date

from sr
left join sr_storage st on st.sr_number = sr.sr_number
left join sr_sale    sl on sl.sr_number = sr.sr_number
left join sr_tax_map tm on tm.sr_number = sr.sr_number
left join sr_expense ex on ex.sr_number = sr.sr_number;

comment on view public.sr_financials is
  'One row per SR for the Financials page: storage, deposit, sale proceeds, '
  'stored taxes, the five expense kinds and the refund. Transcribed from '
  'buildSrFinancials so the page can filter, page and total in SQL.';


-- ── Does it agree with the Dart it replaces? ─────────────────────────────
-- ⚠️ Asserted against the LIVE data, not a fixture. The figures on the right
-- are what the page showed before this view existed, read off the running
-- app; a view that computes different money is a wrong view, however clean
-- its SQL reads.
do $verify$
declare
  n_rows      int;
  v_charges   numeric;
  v_deposits  numeric;
  v_proceeds  numeric;
  v_taxes     numeric;
  v_destroy   numeric;
  v_advert    numeric;
  v_labour    numeric;
  v_transport numeric;
  v_auction   numeric;
  v_refund    numeric;
  v_utc       numeric;
  v_local     numeric;
begin
  select count(*),
         sum(sr_charges), sum(destroying_deposit), sum(sale_proceeds),
         sum(taxes), sum(destruction_expense), sum(advertising_expense),
         sum(labour_expense), sum(transport_expense), sum(auction_expense),
         sum(refund)
    into n_rows, v_charges, v_deposits, v_proceeds, v_taxes, v_destroy,
         v_advert, v_labour, v_transport, v_auction, v_refund
    from public.sr_financials;

  raise notice 'sr_financials: % rows', n_rows;
  raise notice '  income      charges=% deposits=% proceeds=% taxes=%',
    v_charges, v_deposits, v_proceeds, v_taxes;
  raise notice '  expenditure destroy=% advert=% labour=% transport=% auction=% refund=%',
    v_destroy, v_advert, v_labour, v_transport, v_auction, v_refund;

  -- One row per SR, and every SR in the system.
  if n_rows <> (select count(distinct sr_number) from public.packages
                 where coalesce(trim(sr_number), '') <> '') then
    raise exception 'sr_financials has % rows for % SRs', n_rows,
      (select count(distinct sr_number) from public.packages
        where coalesce(trim(sr_number), '') <> '');
  end if;

  -- The four income figures the page's header strip adds up, as the running
  -- app reported them.
  if round(v_charges) <> 369383700 then
    raise exception 'SR charges: got %, the page shows 369,383,700', v_charges;
  end if;
  if round(v_deposits) <> 3776645 then
    raise exception 'deposits: got %, the page shows 3,776,645', v_deposits;
  end if;
  if round(v_proceeds) <> 308692662 then
    raise exception 'sale proceeds: got %, the page shows 308,692,662', v_proceeds;
  end if;
  if round(v_taxes) <> 85181352 then
    raise exception 'taxes: got %, the page shows 85,181,352', v_taxes;
  end if;

  -- And the six on the expenditure side.
  if round(v_destroy) <> 423384 then
    raise exception 'destruction: got %, the page shows 423,384', v_destroy;
  end if;
  if round(v_advert) <> 189664 then
    raise exception 'advertising: got %, the page shows 189,664', v_advert;
  end if;
  if round(v_labour) <> 338536 then
    raise exception 'labour: got %, the page shows 338,536', v_labour;
  end if;
  if round(v_transport) <> 294632 then
    raise exception 'transport: got %, the page shows 294,632', v_transport;
  end if;
  if round(v_auction) <> 341859 then
    raise exception 'auction: got %, the page shows 341,859', v_auction;
  end if;
  if round(v_refund) <> 3148317 then
    raise exception 'refunds: got %, the page shows 3,148,317', v_refund;
  end if;

  -- ⚠️ And the same answer whoever asks. The charge is counted day by day,
  -- so a date cast that follows the session's timezone gives the app and psql
  -- different money for the same entry -- which is how the 88,100 discrepancy
  -- above was found. Reading the view under UTC must not move a figure.
  set local timezone to 'UTC';
  select sum(sr_charges) into v_utc from public.sr_financials;
  set local timezone to 'Asia/Colombo';
  select sum(sr_charges) into v_local from public.sr_financials;
  if round(v_utc) <> round(v_local) then
    raise exception 'sr_charges depends on the reader''s timezone: '
      'UTC gives %, Asia/Colombo gives %', v_utc, v_local;
  end if;

  raise notice 'sr_financials agrees with the page it replaces, all ten figures, '
    'and reads the same under UTC.';
end
$verify$;
