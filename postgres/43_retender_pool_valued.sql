-- ============================================================================
--  `unsold_retender_pool` gains one column: has this package's NEXT round
--  already been priced?
--
--  ⚠️ The Valuation portal answered that with a second full fetch of the
--  heaviest query in the app. `getValuedCurrentRoundIds()` called
--  `getUnsoldTenderSales()` -- forfeited rows down through packages, their
--  items and their warehouse entries -- purely to learn each package's latest
--  round, then queried tender_revaluations. Opening the tab therefore ran that
--  query TWICE, ~139ms and ~118ms, for one boolean per row.
--
--  The rule is unchanged, and it is subtle enough to be worth stating twice:
--
--      "Valued" means the NEXT round has been priced, which is the row in
--      tender_revaluations with a NULL tender_sale_id. A figure keyed TO a
--      round is that round's own reserve -- every held round has one, so
--      counting those marked every package valued and hid the Set Value
--      button. Packages reach this pool only after their latest round has
--      been held, so "a pending row exists" is the whole test.
--
--  Everything else below is postgres/38's body, verbatim. Only `valued` is
--  new: `create or replace` refuses a non-append column change, so the view is
--  dropped and rebuilt, and its dependants come back with it.
-- ============================================================================

drop view if exists public.unsold_retender_pool cascade;

create view public.unsold_retender_pool as
with rounds as (
  select
    ti.forfeited_package_id as fp_id,
    ti.tender_sale_id,
    ti.sold,
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
  select distinct on (r.fp_id)
    r.fp_id,
    r.tender_sale_id,
    r.sale_moment
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
  l.sale_moment < now() as round_moment_passed,
  exists (select 1 from public.tender_committees tc
           where tc.forfeited_package_id = fp.id) as has_committee,

  -- ⚠️ The NEXT round's price, not this round's reserve. A row keyed to a
  -- tender_sale_id is the reserve OF that round; the pending one -- null
  -- tender_sale_id -- is the figure this directorate is being asked for.
  exists (select 1 from public.tender_revaluations tr
           where tr.forfeited_package_id = fp.id
             and tr.tender_sale_id is null) as valued

from public.forfeited_packages fp
join agg a                        on a.fp_id = fp.id
join latest l                     on l.fp_id = fp.id
left join public.package_items pi on pi.id = fp.item_id
left join public.packages p       on p.id = fp.package_id
where not a.ever_sold
  and coalesce(fp.source, '') <> 'perishable'
  and not exists (select 1 from public.exhausted_unsold e
                   where e.forfeited_package_id = fp.id)
  and (a.round_count <= 4
       or exists (select 1 from public.tender_committees tc
                   where tc.forfeited_package_id = fp.id));

comment on view public.unsold_retender_pool is
  'Unsold, non-perishable, not-yet-exhausted packages that may still be '
  're-tendered: at most four rounds, or any number once a committee has been '
  'appointed. `valued` says whether the next round has already been priced.';


-- ── The rules /38 established must still hold ────────────────────────────
-- ⚠️ Re-asserted here, not assumed. This migration rewrites the whole view to
-- add one column, and a rewrite is exactly when a `where` clause goes missing.
do $verify$
declare
  bad     int;
  n_rows  int;
  n_val   int;
  n_dart  int;
begin
  -- 1. Four rounds is the most Central Disposal can run alone.
  select count(*) into bad
    from public.unsold_retender_pool
   where round_count > 4 and not coalesce(has_committee, false);
  if bad <> 0 then
    raise exception '% package(s) can be re-tendered past four rounds with '
                    'no committee', bad;
  end if;

  -- 2. Nothing sold may be offered again.
  select count(*) into bad
    from public.unsold_retender_pool pool
   where exists (select 1 from public.tender_sale_items ti
                  where ti.forfeited_package_id = pool.forfeited_package_id
                    and ti.sold);
  if bad <> 0 then
    raise exception '% sold package(s) are in the re-tender pool', bad;
  end if;

  -- 3. Perishables have their own route and are never re-tendered here.
  select count(*) into bad
    from public.unsold_retender_pool
   where coalesce(source, '') = 'perishable';
  if bad <> 0 then
    raise exception '% perishable(s) are in the re-tender pool', bad;
  end if;

  -- 4. An exhausted package belongs to Unsold Goods, not here.
  select count(*) into bad
    from public.unsold_retender_pool pool
   where exists (select 1 from public.exhausted_unsold e
                  where e.forfeited_package_id = pool.forfeited_package_id);
  if bad <> 0 then
    raise exception '% exhausted package(s) are in the re-tender pool', bad;
  end if;

  -- 5. And the new column says what the Dart said: a package is valued when a
  --    revaluation with no tender_sale_id exists for it.
  select count(*), count(*) filter (where valued)
    into n_rows, n_val
    from public.unsold_retender_pool;

  select count(distinct tr.forfeited_package_id) into n_dart
    from public.tender_revaluations tr
    join public.unsold_retender_pool pool
      on pool.forfeited_package_id = tr.forfeited_package_id
   where tr.tender_sale_id is null;

  if n_val <> n_dart then
    raise exception 'valued: the view says %, the pending revaluations say %',
      n_val, n_dart;
  end if;

  raise notice 'unsold_retender_pool: % package(s), % already valued', n_rows, n_val;
end
$verify$;
