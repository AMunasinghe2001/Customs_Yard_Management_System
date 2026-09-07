-- ============================================================================
--  A package enters the re-tender pool when an officer MARKS its latest round
--  unsold — never when a clock says the round is over.
--
--  ⚠️ `unsold_retender_pool` never said so. It admitted any unsold,
--  non-perishable, not-yet-exhausted package whose rounds numbered four or
--  fewer, whatever had actually been recorded about the latest round. It
--  carried a `round_moment_passed` column, computed from `sale_moment <
--  now()`, that nothing ever read.
--
--  The Dart had the rule and the view did not, so the two disagreed:
--  getUnsoldTenderSales() found 9 packages, the view listed 15. The six extra
--  are packages whose latest round has simply not been marked yet — a sale
--  Central Disposal has still to record the outcome of.
--
--  Marking, not the calendar, is deliberate and was asked for directly. A
--  package used to enter this pool once a working-day grace window closed, so
--  the outcome was decided by the calendar: a public holiday moved the
--  deadline and the package moved with it. Worse, it left Central Disposal no
--  way to record what actually happened, because the sale had already gone
--  from their tab. Now an officer marks it, and until they do the package
--  stays where it is.
--
--  Everything else below is postgres/43's body, verbatim; only the latest
--  round's `unsold` mark is new. `round_moment_passed` stays as a column --
--  the tab shows when a round was held -- but it decides nothing.
-- ============================================================================

drop view if exists public.unsold_retender_pool cascade;

create view public.unsold_retender_pool as
with rounds as (
  select
    ti.forfeited_package_id as fp_id,
    ti.tender_sale_id,
    ti.sold,
    ti.unsold,
    ts.created_at as round_created,
    ts.sale_date + coalesce(ts.sale_time, '00:00')::time as sale_moment
  from public.tender_sale_items ti
  join public.tender_sales ts on ts.id = ti.tender_sale_id
),
agg as (
  select
    fp_id,
    count(*) as round_count,
    bool_or(sold) as ever_sold,
    max(round_created) as latest_round_created
  from rounds
  group by fp_id
),
latest as (
  -- ⚠️ The most recently CREATED round, not the one with the latest sale
  -- date. created_at always increases; a re-tender placed with no date yet
  -- must still count as the current round, or a package would be judged on a
  -- round that has been superseded.
  select distinct on (r.fp_id)
    r.fp_id,
    r.tender_sale_id,
    r.sale_moment,
    r.unsold as latest_unsold
  from rounds r
  order by r.fp_id, r.round_created desc
)
select
  fp.id as forfeited_package_id,
  fp.package_id,
  fp.item_id,
  fp.sr_number,
  fp.consignee_name,
  fp.yard,
  fp.entry_qty,
  fp.source,
  fp.forfeited_at,
  p.case_number,
  coalesce(pi.item_name, (
    select i2.item_name
      from public.package_items i2
     where i2.package_id = fp.package_id
     order by i2.created_at
     limit 1)) as item_name,
  a.round_count,
  l.sale_moment as latest_sale_moment,
  -- Kept as INFORMATION -- when the round was held -- and read by nothing as
  -- a rule. See the header: the calendar does not decide an outcome.
  l.sale_moment < now() as round_moment_passed,
  exists (select 1 from public.tender_committees tc
           where tc.forfeited_package_id = fp.id) as has_committee,

  -- The NEXT round's price, not this round's reserve. A row keyed to a
  -- tender_sale_id is the reserve OF that round; the pending one -- null
  -- tender_sale_id -- is the figure the Valuation Directorate is being asked
  -- for.
  exists (select 1 from public.tender_revaluations tr
           where tr.forfeited_package_id = fp.id
             and tr.tender_sale_id is null) as valued

from public.forfeited_packages fp
join agg a                        on a.fp_id = fp.id
join latest l                     on l.fp_id = fp.id
left join public.package_items pi on pi.id = fp.item_id
left join public.packages p       on p.id = fp.package_id
where not a.ever_sold
  -- ⚠️ MARKED unsold. The rule this migration exists for.
  and l.latest_unsold
  and coalesce(fp.source, '') <> 'perishable'
  and not exists (select 1 from public.exhausted_unsold e
                   where e.forfeited_package_id = fp.id)
  and (a.round_count <= 4
       or exists (select 1 from public.tender_committees tc
                   where tc.forfeited_package_id = fp.id));

comment on view public.unsold_retender_pool is
  'Packages whose LATEST tender round an officer has marked unsold and which '
  'may still be re-tendered: at most four rounds, or any number once a '
  'committee has been appointed. `valued` says whether the next round has '
  'already been priced. Membership follows the mark, never a clock.';


-- ── Against the Dart it now has to match ─────────────────────────────────
do $verify$
declare
  bad      int;
  n_rows   int;
  n_dart   int;
  n_val    int;
  n_pend   int;
begin
  -- 1. The new rule: every row's latest round is marked unsold.
  select count(*) into bad
    from public.unsold_retender_pool pool
   where not exists (
     select 1
       from public.tender_sale_items ti
       join public.tender_sales ts on ts.id = ti.tender_sale_id
      where ti.forfeited_package_id = pool.forfeited_package_id
        and ti.unsold
        and ts.created_at = (
          select max(ts2.created_at)
            from public.tender_sale_items ti2
            join public.tender_sales ts2 on ts2.id = ti2.tender_sale_id
           where ti2.forfeited_package_id = pool.forfeited_package_id));
  if bad <> 0 then
    raise exception '% package(s) are in the pool whose latest round nobody '
                    'has marked unsold', bad;
  end if;

  -- 2. And the same membership getUnsoldTenderSales() computes in Dart:
  --    not sold, latest round marked unsold, not perishable, not exhausted.
  select count(*) into n_dart
    from public.forfeited_packages fp
   where coalesce(fp.source, '') <> 'perishable'
     and exists (select 1 from public.tender_sale_items ti
                  where ti.forfeited_package_id = fp.id)
     and not exists (select 1 from public.tender_sale_items ti
                      where ti.forfeited_package_id = fp.id and ti.sold)
     and not exists (select 1 from public.exhausted_unsold e
                      where e.forfeited_package_id = fp.id)
     and exists (
       select 1 from public.tender_sale_items ti
         join public.tender_sales ts on ts.id = ti.tender_sale_id
        where ti.forfeited_package_id = fp.id
          and ti.unsold
          and ts.created_at = (
            select max(ts2.created_at)
              from public.tender_sale_items ti2
              join public.tender_sales ts2 on ts2.id = ti2.tender_sale_id
             where ti2.forfeited_package_id = fp.id));

  select count(*) into n_rows from public.unsold_retender_pool;
  -- The view also drops packages past four rounds with no committee, which
  -- the Dart did not know about (postgres/38), so it may hold FEWER -- never
  -- more.
  if n_rows > n_dart then
    raise exception 'the pool holds % packages, the Dart rule finds %',
      n_rows, n_dart;
  end if;

  -- 3. The rules /38 established still hold after this rewrite.
  select count(*) into bad
    from public.unsold_retender_pool
   where round_count > 4 and not coalesce(has_committee, false);
  if bad <> 0 then
    raise exception '% package(s) can be re-tendered past four rounds with '
                    'no committee', bad;
  end if;

  select count(*) into bad
    from public.unsold_retender_pool pool
   where exists (select 1 from public.tender_sale_items ti
                  where ti.forfeited_package_id = pool.forfeited_package_id
                    and ti.sold);
  if bad <> 0 then
    raise exception '% sold package(s) are in the re-tender pool', bad;
  end if;

  select count(*) into bad
    from public.unsold_retender_pool where coalesce(source, '') = 'perishable';
  if bad <> 0 then
    raise exception '% perishable(s) are in the re-tender pool', bad;
  end if;

  select count(*) into bad
    from public.unsold_retender_pool pool
   where exists (select 1 from public.exhausted_unsold e
                  where e.forfeited_package_id = pool.forfeited_package_id);
  if bad <> 0 then
    raise exception '% exhausted package(s) are in the re-tender pool', bad;
  end if;

  -- 4. The Valuation tab's own numbers: at most three rounds is its work.
  select count(*) filter (where round_count <= 3),
         count(*) filter (where round_count <= 3 and not valued)
    into n_val, n_pend
    from public.unsold_retender_pool;

  raise notice 'unsold_retender_pool: % package(s); Valuation sees % (% pending)',
    n_rows, n_val, n_pend;
end
$verify$;
