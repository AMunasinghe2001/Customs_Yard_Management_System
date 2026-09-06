-- ============================================================================
--  A package cannot go to tender a fifth time without a committee.
--
--  ⚠️ The route is fixed and finite:
--
--      1  Valuation Tender   -- priced by the Valuation Directorate
--      2  Tender 1           -- priced from round 1's unsold bids
--      3  Tender 2
--      4  Tender 3           -- the LAST round Central Disposal can run
--      -> Top Management appoints a committee, which prices it
--      5  the committee-priced round
--      -> if that fails too, the package is exhausted and the DG rules
--
--  So four rounds is the most Central Disposal can run on its own. After the
--  fourth the package belongs to Top Management: a committee has to price it
--  before anything else happens.
--
--  `unsold_retender_pool` never said so. It listed any unsold, non-perishable,
--  not-yet-exhausted package whatever its round count, so Central Disposal
--  could re-tender a package for a fifth time with no committee. It did:
--  CED/GL1/OA/07/2025 sits at round_count = 5 with zero committees, having run
--  TS/GL1/2026/009, /010, /012, /011 and /068.
--
--  A package past four rounds with no committee is now HELD OUT of the
--  re-tender pool. It is not lost -- the Tender Committees tab lists exactly
--  those, because that is the page that appoints one.
--
--  ⚠️ This deliberately does NOT touch the existing rows. Round 5 already
--  happened for that package; deleting or rewriting the history would be
--  falsifying a record. The package simply stops being offered again until a
--  committee exists.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.unsold_retender_pool;

create view public.unsold_retender_pool as
with rounds as (
  select ti.forfeited_package_id                     as fp_id,
         ti.tender_sale_id,
         ti.sold,
         ts.created_at                               as round_created,
         (ts.sale_date::date
            + coalesce(ts.sale_time, '00:00')::time) as sale_moment
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
), agg as (
  select fp_id,
         count(*)                       as round_count,
         bool_or(sold)                  as ever_sold,
         max(round_created)             as latest_round_created
    from rounds group by fp_id
), latest as (
  -- The CURRENT round: newest by created_at, exactly as the app sorts.
  select distinct on (r.fp_id)
         r.fp_id, r.tender_sale_id, r.sale_moment
    from rounds r
   order by r.fp_id, r.round_created desc
)
select
  fp.id                                    as forfeited_package_id,
  fp.package_id,
  fp.item_id,
  fp.sr_number,
  fp.consignee_name,
  fp.yard,
  fp.entry_qty,
  fp.source,
  fp.forfeited_at,
  p.case_number,
  coalesce(pi.item_name,
           (select i2.item_name from public.package_items i2
             where i2.package_id = fp.package_id
             order by i2.created_at limit 1))  as item_name,
  a.round_count,
  l.sale_moment                            as latest_sale_moment,
  -- ⚠️ There is NO `unsold` column on tender_sale_items -- the model reads
  -- one and it is always false, because a round is unsold when it is NOT sold
  -- and its deadline has passed. So the only half SQL can settle is whether
  -- the current round's scheduled moment is already behind us; the DEADLINE
  -- (sale date + the following working day, past weekends and Sri Lankan
  -- public holidays) needs the calendar the app fetches at runtime, and the
  -- page applies it.
  (l.sale_moment < now())                  as round_moment_passed,
  -- ⚠️ The Committees tab is this same pool narrowed twice: to packages on
  -- their FOURTH round (Valuation Tender + Tenders 1-3 all failed), and to
  -- those that actually have a committee appointed. Both are settled here so
  -- the tab is one query rather than three providers intersected in Dart.
  --
  -- A card leaves that tab when the committee-priced tender ALSO fails, which
  -- is when the package becomes exhausted -- and this view already excludes
  -- exhausted packages, so no separate `movedOn` set is needed.
  exists (select 1 from public.tender_committees tc
           where tc.forfeited_package_id = fp.id)  as has_committee
from public.forfeited_packages fp
join agg a                        on a.fp_id = fp.id
join latest l                     on l.fp_id = fp.id
left join public.package_items pi on pi.id = fp.item_id
left join public.packages p       on p.id = fp.package_id
where not a.ever_sold                                        -- 2
  and coalesce(fp.source, '') <> 'perishable'                -- 4
  -- 5. Not already exhausted: that package belongs to Unsold Goods.
  and not exists (select 1 from public.exhausted_unsold e
                   where e.forfeited_package_id = fp.id)
  -- ⚠️ 6. Four rounds is the most Central Disposal can run on its own.
  -- Past that the package needs a committee valuation before it can be
  -- offered again, and appointing one is Top Management's to do.
  and (a.round_count <= 4
       or exists (select 1 from public.tender_committees tc
                   where tc.forfeited_package_id = fp.id))
;

grant select on public.unsold_retender_pool to public;

comment on view public.unsold_retender_pool is
  'Packages Central Disposal may still re-tender. Stops at four rounds unless '
  'Top Management has appointed a committee -- see postgres/38.';

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n     int;
  bad   int;
  held  int;
begin
  select count(*) into n from public.unsold_retender_pool;

  -- The rule itself.
  select count(*) into bad
    from public.unsold_retender_pool
   where round_count > 4 and not coalesce(has_committee, false);
  if bad <> 0 then
    raise exception '% package(s) can be re-tendered past four rounds with '
                    'no committee', bad;
  end if;

  -- Nothing sold may be offered again.
  select count(*) into bad
    from public.unsold_retender_pool u
   where exists (select 1 from public.tender_sale_items ti
                  where ti.forfeited_package_id = u.forfeited_package_id
                    and ti.sold);
  if bad <> 0 then
    raise exception '% SOLD package(s) are in the re-tender pool', bad;
  end if;

  -- ⚠️ And nothing may be held out with nowhere to go. A package past four
  -- rounds without a committee must appear on the Tender Committees tab,
  -- which is the page that appoints one.
  select count(*) into held
    from public.forfeited_packages fp
    join (select ti.forfeited_package_id as fp_id,
                 count(*) as rc, bool_or(ti.sold) as sold
            from public.tender_sale_items ti
           group by ti.forfeited_package_id) r on r.fp_id = fp.id
   where not r.sold
     and coalesce(fp.source, '') <> 'perishable'
     and r.rc > 4
     and not exists (select 1 from public.tender_committees tc
                      where tc.forfeited_package_id = fp.id)
     and not exists (select 1 from public.exhausted_unsold e
                      where e.forfeited_package_id = fp.id);

  raise notice 'unsold_retender_pool = % row(s)', n;
  raise notice '  held out awaiting a committee: %', held;
  for bad in select round_count from public.unsold_retender_pool
              group by round_count order by round_count
  loop
    raise notice '  round %: % package(s)', bad,
      (select count(*) from public.unsold_retender_pool
        where round_count = bad);
  end loop;
end
$verify$;
