-- ============================================================================
--  committee_pool -- every package waiting on Top Management for a committee.
--
--  ⚠️ postgres/38 stopped Central Disposal re-tendering a package past four
--  rounds without a committee, and that created an orphan. The Committees tab
--  read `unsold_retender_pool`, and the new rule holds exactly those packages
--  OUT of it -- so CED/GL1/OA/07/2025 (five rounds, no committee) appeared on
--  no page at all:
--
--    * not in the re-tender pool  -- held out by the four-round rule
--    * not on the DG's Unsold Goods -- its committee round has not failed,
--      because it never had a committee
--    * not on Tender Committees   -- that tab read the pool it was held out of
--
--  A package with nowhere to go is worse than one in the wrong place: nobody
--  can act on it and nothing says so.
--
--  So the Committees tab gets its own view. It answers ONE question -- has
--  this package finished the rounds Central Disposal can run, and is it still
--  unsold? -- without the re-tender pool's fifth condition, which exists to
--  stop a different portal doing a different thing.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.committee_pool;

create view public.committee_pool as
with rounds as (
  select ti.forfeited_package_id            as fp_id,
         ti.sold,
         ts.created_at                      as round_created,
         (ts.sale_date::date
            + coalesce(ts.sale_time, '00:00')::time) as sale_moment
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
), agg as (
  select fp_id,
         count(*)                       as round_count,
         bool_or(sold)                  as ever_sold
    from rounds group by fp_id
), latest as (
  select distinct on (r.fp_id) r.fp_id, r.sale_moment
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
  (l.sale_moment < now())                  as round_moment_passed,
  exists (select 1 from public.tender_committees tc
           where tc.forfeited_package_id = fp.id)  as has_committee
from public.forfeited_packages fp
join agg a                        on a.fp_id = fp.id
join latest l                     on l.fp_id = fp.id
left join public.package_items pi on pi.id = fp.item_id
left join public.packages p       on p.id = fp.package_id
where not a.ever_sold
  and coalesce(fp.source, '') <> 'perishable'
  -- ⚠️ Perishables never reach a committee. One failed Special Tender Sale is
  -- the end of the road for goods that spoil; they go straight to the DG.
  --
  -- Not exhausted: once the committee-priced round has failed too, the
  -- package belongs to Unsold Goods and the DG rules on it.
  and not exists (select 1 from public.exhausted_unsold e
                   where e.forfeited_package_id = fp.id)
  -- Finished the rounds Central Disposal can run on its own.
  and a.round_count >= 4;

grant select on public.committee_pool to public;

comment on view public.committee_pool is
  'Packages that have finished Central Disposal''s four rounds and are with '
  'Top Management -- awaiting a committee, or already priced by one. See '
  'postgres/39.';

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n       int;
  bad     int;
  orphans int;
begin
  select count(*) into n from public.committee_pool;

  -- Nothing sold, nothing perishable.
  select count(*) into bad
    from public.committee_pool c
   where exists (select 1 from public.tender_sale_items ti
                  where ti.forfeited_package_id = c.forfeited_package_id
                    and ti.sold);
  if bad <> 0 then
    raise exception '% SOLD package(s) in the committee pool', bad;
  end if;

  select count(*) into bad from public.committee_pool
   where coalesce(source, '') = 'perishable';
  if bad <> 0 then
    raise exception '% perishable(s) in the committee pool', bad;
  end if;

  -- ⚠️ THE POINT OF THIS VIEW: no package may be invisible everywhere. Any
  -- unsold, non-perishable package past four rounds must be reachable on
  -- SOME page.
  select count(*) into orphans
    from public.forfeited_packages fp
    join (select ti.forfeited_package_id as fp_id,
                 count(*) as rc, bool_or(ti.sold) as sold
            from public.tender_sale_items ti
           group by ti.forfeited_package_id) r on r.fp_id = fp.id
   where not r.sold
     and coalesce(fp.source, '') <> 'perishable'
     and r.rc >= 4
     and not exists (select 1 from public.committee_pool c
                      where c.forfeited_package_id = fp.id)
     and not exists (select 1 from public.exhausted_unsold e
                      where e.forfeited_package_id = fp.id);
  if orphans <> 0 then
    raise exception '% package(s) past four rounds appear on NO page', orphans;
  end if;

  raise notice 'committee_pool = % row(s)', n;
  raise notice '  awaiting a committee : %',
    (select count(*) from public.committee_pool where not has_committee);
  raise notice '  committee appointed  : %',
    (select count(*) from public.committee_pool where has_committee);
end
$verify$;
