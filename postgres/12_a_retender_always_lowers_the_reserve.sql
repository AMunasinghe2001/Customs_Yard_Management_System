-- ============================================================================
--  A re-tender LOWERS the reserve. It never raises it.
--
--  That is the whole point of the chain: the bids came in below the reserve,
--  Valuation reads them, and sets a lower figure so the next round has a
--  chance of clearing. A round priced ABOVE the one that already failed is
--  asking more for goods that nobody would pay less for.
--
--  ⚠️ Migration 11 filled the gaps by stepping down from each package's
--  ORIGINAL valuation (original x 0.86^(n-1)). That is right when the earlier
--  rounds were also derived from the original -- and wrong wherever a round
--  already carried a hand-seeded figure well below that curve, because the
--  filled-in round then landed above its own predecessor. 15 rounds came out
--  that way.
--
--  Fixed by walking each package's rounds in order and pulling any figure that
--  is not below the previous one down to 86% of it. Only the offending rows
--  move; every figure that already descends is left exactly as it was.
-- ============================================================================

set lock_timeout = '5s';

do $fix$
declare
  r         record;
  prev_fp   uuid := null;
  prev_cost numeric := null;
  target    numeric;
  moved     int := 0;
begin
  for r in
    select v.id,
           v.forfeited_package_id as fp,
           v.valuation_cost       as cost,
           ts.created_at
      from public.tender_revaluations v
      join public.tender_sales ts on ts.id = v.tender_sale_id
     order by v.forfeited_package_id, ts.created_at
  loop
    if prev_fp is distinct from r.fp then
      -- First round of a package: whatever it says stands.
      prev_fp := r.fp;
      prev_cost := r.cost;
      continue;
    end if;

    if r.cost >= prev_cost then
      target := round((prev_cost * 0.86)::numeric, 0);
      update public.tender_revaluations
         set valuation_cost = target
       where id = r.id;
      moved := moved + 1;
      prev_cost := target;
    else
      prev_cost := r.cost;
    end if;
  end loop;

  raise notice 'pulled % round(s) back below their predecessor', moved;
end
$fix$;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  ascending int;
  nonpositive int;
begin
  -- ⚠️ Every round must be strictly cheaper than the one before it.
  select count(*) into ascending
    from (
      select v.forfeited_package_id fp, v.valuation_cost cost,
             row_number() over (partition by v.forfeited_package_id
                                order by ts.created_at) rn
        from public.tender_revaluations v
        join public.tender_sales ts on ts.id = v.tender_sale_id
    ) a
    join (
      select v.forfeited_package_id fp, v.valuation_cost cost,
             row_number() over (partition by v.forfeited_package_id
                                order by ts.created_at) rn
        from public.tender_revaluations v
        join public.tender_sales ts on ts.id = v.tender_sale_id
    ) b on b.fp = a.fp and b.rn = a.rn + 1
   where b.cost >= a.cost;
  if ascending <> 0 then
    raise exception '% round(s) are still priced at or above the round '
                    'before them', ascending;
  end if;

  -- And nothing was driven to zero or below on the way down.
  select count(*) into nonpositive
    from public.tender_revaluations where valuation_cost <= 0;
  if nonpositive <> 0 then
    raise exception '% valuation(s) fell to zero or below', nonpositive;
  end if;

  raise notice 'every re-tender is priced below the round it follows';
end
$verify$;
