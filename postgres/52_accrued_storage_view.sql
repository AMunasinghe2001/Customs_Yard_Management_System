-- What is still accruing storage charges, per yard.
--
-- ⚠️ The dashboard computed this in Dart from `livePackagesProvider` — every
-- package in the yard with its items and its warehouse entries, 176 rows —
-- and walked them adding up charges. That is the same whole-table fetch the
-- rest of the app has been moved off, on the one figure that changes every
-- single day.
--
-- ⚠️ This is NOT `sr_financials.sr_charges`. That is the whole storage bill
-- ever raised, returned goods included — 368,984,450 on live data. This is
-- what is STILL RUNNING: entries not yet returned, charged from admission to
-- today. 242,304,500, which is the figure the card was showing.
--
-- The two are different questions and both are wanted: the ledger reports what
-- was billed, the dashboard reports what is ticking.
--
-- The rate rule is `calculatePackageCharge`'s, and it is the same one
-- postgres/41 transcribed — rate periods rather than a day-by-day walk, the
-- 50/day default before the first recorded rate, the single-unit repair for
-- old rows, and the no-charge statuses.

drop view if exists public.accrued_storage_by_yard cascade;

create view public.accrued_storage_by_yard as
with rate_period as (
  select (rt.effective_from at time zone 'Asia/Colombo')::date as from_day,
         lead((rt.effective_from at time zone 'Asia/Colombo')::date)
           over (order by rt.effective_from) as next_day,
         rt.rate
    from public.storage_rates rt
  union all
  -- ⚠️ The period BEFORE the first recorded rate, at the model's own default
  -- of 50. Goods admitted before the rate table was filled in are still
  -- accruing; dropping this period would silently zero them.
  select date '1900-01-01',
         (select min((rt2.effective_from at time zone 'Asia/Colombo')::date)
            from public.storage_rates rt2),
         50::numeric
),
running as (
  select
    p.yard,
    p.sr_number,
    we.id as entry_id,
    (we.admitted_at at time zone 'Asia/Colombo')::date as first_day,
    -- ⚠️ To TODAY, not to a return date: these are the entries that have not
    -- been returned, which is what makes the figure a live one.
    (now() at time zone 'Asia/Colombo')::date as last_day,
    case
      when we.item_count = 1
       and we.package_item_id is not null
       and coalesce(we.is_returned, false) = false
       and coalesce(pi.quantity, 0) > 1
      then pi.quantity
      else we.item_count
    end as units
  from public.warehouse_entries we
  join public.packages p on p.id = we.package_id
  left join public.package_items pi on pi.id = we.package_item_id
  where not coalesce(we.is_returned, false)
    and lower(coalesce(p.status, '')) <> 'confiscated'
    and (we.package_item_id is null
         or lower(coalesce(pi.status, '')) not in
            ('confiscated', 'forfeit', 'forfiet', 'forfeited',
             'abandoned', 'destroy', 'destroyed'))
)
select
  r.yard,
  r.sr_number,
  count(distinct r.entry_id) as live_entries,
  sum(rp.rate * r.units
      * (least(r.last_day, coalesce(rp.next_day - 1, date '9999-12-31'))
         - greatest(r.first_day, rp.from_day) + 1)) as accrued
from running r
join rate_period rp
  on greatest(r.first_day, rp.from_day)
     <= least(r.last_day, coalesce(rp.next_day - 1, date '9999-12-31'))
group by r.yard, r.sr_number;

comment on view public.accrued_storage_by_yard is
  'Storage charges still RUNNING — entries not yet returned, charged from '
  'admission to today. Not the same as sr_financials.sr_charges, which is the '
  'whole bill including returned goods.';


-- ── Does it agree with the Dart it replaces? ─────────────────────────────
do $verify$
declare
  v_total   numeric;
  v_ledger  numeric;
  v_utc     numeric;
  v_local   numeric;
begin
  select coalesce(sum(accrued), 0) into v_total
    from public.accrued_storage_by_yard;

  raise notice 'accrued (still running): %', v_total;

  -- The figure the dashboard was showing, computed in Dart from every package
  -- in the yard. Read off the running app before this view existed.
  if round(v_total) <> 242304500 then
    raise exception 'accrued: got %, the dashboard showed 242,304,500', v_total;
  end if;

  -- ⚠️ And it must NOT equal the ledger's total, or one of the two is
  -- answering the wrong question. The ledger bills returned goods too.
  select coalesce(sum(sr_charges), 0) into v_ledger from public.sr_financials;
  if round(v_total) = round(v_ledger) then
    raise exception 'accrued equals the ledger total (%) -- one of them is '
                    'counting the wrong entries', v_ledger;
  end if;

  -- ⚠️ The same answer whoever asks. The app connects as UTC and psql here
  -- inherits Asia/Colombo; a date that follows the session gives the two
  -- different day counts, and this figure grows by a day every day.
  set local timezone to 'UTC';
  select coalesce(sum(accrued), 0) into v_utc from public.accrued_storage_by_yard;
  set local timezone to 'Asia/Colombo';
  select coalesce(sum(accrued), 0) into v_local from public.accrued_storage_by_yard;
  if round(v_utc) <> round(v_local) then
    raise exception 'accrued depends on the reader: UTC %, Colombo %',
      v_utc, v_local;
  end if;

  raise notice 'accrued agrees with the dashboard, differs from the ledger '
               '(%), and reads the same under UTC.', v_ledger;
end
$verify$;
