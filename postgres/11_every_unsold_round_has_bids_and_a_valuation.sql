-- ============================================================================
--  Every unsold round needs BIDS, and every round after the first needs a
--  VALUATION. The seed left many with neither.
--
--  The two rules, in the officers' own words:
--
--    * "A tender only records bids when the goods DON'T sell." So an unsold
--      round without bids is not a round that nobody bid on -- it is a round
--      whose bids were never written. And it is the bids that justify the next
--      round: Valuation reads them, then sets a lower reserve. Without them
--      the chain "bid too low -> re-value -> re-tender" has a hole in it, and
--      the screen says so: Tender 3 sat there gold, "Awaiting Valuation
--      Directorate", with no bids for Valuation to read.
--
--    * Round one runs at the Valuation Directorate's original figure. EVERY
--      round after it runs at a fresh one -- that is what re-tendering means.
--      A later round with no `tender_revaluations` row has no reserve price of
--      its own, so the popup showed it bare while its neighbours carried
--      figures.
--
--  ⚠️ SOLD rounds are left completely alone. Bidding stops the moment goods
--  sell, so a sold round having no bids is correct -- adding any would assert
--  something that did not happen. Same for the committee round: it is priced
--  by the committee, not by bidding.
--
--  What is written here is derived from the row itself, never invented from
--  nothing: each missing valuation steps DOWN from the previous round's
--  reserve (a re-tender lowers the price), and each missing bid sits BELOW
--  that round's reserve (which is why the goods did not sell).
-- ============================================================================

set lock_timeout = '5s';

-- ── 1. A reserve price for every round after the first ──────────────────────
with rounds as (
  select ti.forfeited_package_id as fp,
         ts.id                   as sid,
         ts.created_at,
         ti.sold,
         ti.yard,
         row_number() over (partition by ti.forfeited_package_id
                            order by ts.created_at) as rn
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
),
-- The figure each package started from: its original valuation.
base as (
  select r.fp,
         coalesce(
           (select dri.valuation_cost
              from public.disposal_request_items dri
             where dri.forfeited_package_id = r.fp
               and dri.valuation_cost is not null
             limit 1),
           100000) as original
    from (select distinct fp from rounds) r
),
missing as (
  select r.*, b.original
    from rounds r
    join base b on b.fp = r.fp
   where r.rn > 1
     and not r.sold
     and not exists (select 1 from public.tender_revaluations v
                      where v.forfeited_package_id = r.fp
                        and v.tender_sale_id = r.sid)
     -- The committee round prices itself; it is not a Valuation re-valuation.
     and not exists (select 1 from public.tender_committees tc
                      where tc.forfeited_package_id = r.fp
                        and tc.submitted_value is not null
                        and r.rn = (select max(rn) from rounds r2
                                     where r2.fp = r.fp))
)
insert into public.tender_revaluations
       (forfeited_package_id, tender_sale_id, valuation_cost, note, yard,
        created_at)
select m.fp,
       m.sid,
       -- ⚠️ Each round is ~14% below the one before it, which is the shape the
       -- rest of the data already has: a re-tender lowers the reserve until
       -- the goods clear. Rounded to a whole rupee.
       round((m.original * power(0.86, m.rn - 1))::numeric, 0),
       'Re-valued by the Valuation Directorate for this round',
       m.yard,
       m.created_at - interval '1 day'
  from missing m;

-- ── 2. Bids for every unsold round that has none ────────────────────────────
with rounds as (
  select ti.forfeited_package_id as fp,
         ts.id                   as sid,
         ts.created_at,
         ti.sold,
         ti.yard,
         row_number() over (partition by ti.forfeited_package_id
                            order by ts.created_at) as rn,
         count(*) over (partition by ti.forfeited_package_id) as total
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
),
reserve as (
  select r.*,
         coalesce(
           (select v.valuation_cost from public.tender_revaluations v
             where v.forfeited_package_id = r.fp and v.tender_sale_id = r.sid),
           (select dri.valuation_cost from public.disposal_request_items dri
             where dri.forfeited_package_id = r.fp
               and dri.valuation_cost is not null limit 1),
           100000) as unit
    from rounds r
),
needy as (
  select * from reserve r
   where not r.sold
     and not exists (select 1 from public.tender_bids b
                      where b.forfeited_package_id = r.fp
                        and b.tender_sale_id = r.sid)
     -- ⚠️ The committee round is priced, not bid on.
     and not exists (select 1 from public.tender_committees tc
                      where tc.forfeited_package_id = r.fp
                        and tc.submitted_value is not null
                        and r.rn = r.total)
)
insert into public.tender_bids
       (forfeited_package_id, tender_sale_id, amount, yard, created_at)
select n.fp, n.sid,
       -- ⚠️ BELOW the round's reserve -- that is why the goods went unsold.
       -- Two bids, at roughly 55% and 68% of it, which is the spread the
       -- rounds that do have bids already show.
       round((n.unit * f.frac)::numeric, 0),
       n.yard,
       n.created_at + interval '1 hour'
  from needy n
  cross join (values (0.55), (0.68)) as f(frac);

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  no_bids   int;
  no_reval  int;
  sold_bids int;
begin
  -- Every unsold, non-committee round now has bids.
  select count(*) into no_bids
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
   where not ti.sold
     and not exists (select 1 from public.tender_bids b
                      where b.forfeited_package_id = ti.forfeited_package_id
                        and b.tender_sale_id = ts.id)
     and not exists (select 1 from public.tender_committees tc
                      where tc.forfeited_package_id = ti.forfeited_package_id
                        and tc.submitted_value is not null);
  if no_bids <> 0 then
    raise exception '% unsold round(s) still have no bids', no_bids;
  end if;

  -- Every round after the first now has a reserve of its own.
  select count(*) into no_reval
    from (
      select ti.forfeited_package_id fp, ts.id sid, ti.sold,
             row_number() over (partition by ti.forfeited_package_id
                                order by ts.created_at) rn,
             count(*) over (partition by ti.forfeited_package_id) total
        from public.tender_sale_items ti
        join public.tender_sales ts on ts.id = ti.tender_sale_id
    ) r
   where r.rn > 1 and not r.sold
     and not exists (select 1 from public.tender_revaluations v
                      where v.forfeited_package_id = r.fp
                        and v.tender_sale_id = r.sid)
     and not exists (select 1 from public.tender_committees tc
                      where tc.forfeited_package_id = r.fp
                        and tc.submitted_value is not null
                        and r.rn = r.total);
  if no_reval <> 0 then
    raise exception '% later round(s) still have no valuation', no_reval;
  end if;

  -- ⚠️ And nothing was added to a round that SOLD: bidding stops when the
  -- goods go, so a bid there would assert something that never happened.
  select count(*) into sold_bids
    from public.tender_sale_items ti
   where ti.sold
     and exists (select 1 from public.tender_bids b
                  where b.forfeited_package_id = ti.forfeited_package_id
                    and b.tender_sale_id = ti.tender_sale_id);
  if sold_bids <> 0 then
    raise exception '% sold round(s) carry bids', sold_bids;
  end if;

  raise notice 'every unsold round has bids and every later round a valuation';
end
$verify$;
