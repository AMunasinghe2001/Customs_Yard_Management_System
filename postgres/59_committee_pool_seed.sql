-- ============================================================================
--  59 · The two packages waiting on a committee actually get one
--
--  `committee_pool` holds packages that failed four or more tenders and need a
--  five-member committee appointed. Two sit there with none:
--
--    CED/GL1/OA/07/2025  Ceramic Floor Tiles   5 rounds
--    CED/GL1/SR/08/2026  Rubber Conveyor Belt  4 rounds
--
--  ⚠️ The DATA was right all along. The "5×" that looked wrong is Valuation
--  Tender + Tenders 1-3 + Committee Tender 1 -- exactly the process. And the
--  23 forfeited packages carrying both a sold and an unsold row are a package
--  that failed and later sold: every unsold round predates its sale, checked,
--  none after. A package that fails twice and then sells has three rows and
--  one outcome.
--
--  ⚠️ What IS out of order: OA/07/2025 already ran a Committee Tender with no
--  committee behind it to price it. This appoints one for both, so the
--  Committees tab has rows to exercise.
--
--  ⚠️ Seed data only -- `tender_committees` is officer-entered, never ICT
--  reference data, so nothing here touches directorates, yards or accounts.
-- ============================================================================

set lock_timeout = '5s';

insert into public.tender_committees
  (forfeited_package_id, yard, members, note, committee_value, committee_valued_at)
select
  cp.forfeited_package_id,
  cp.yard,
  -- The same five posts every other committee in this database carries: a
  -- chairperson, the two directorates with a stake, the yard, and finance.
  '[{"name": "D. M. Perera",  "salary_no": "41207", "designation": "Chairperson"},
    {"name": "S. Fernando",   "salary_no": "38915", "designation": "Valuation Directorate"},
    {"name": "A. Jayasinghe", "salary_no": "44160", "designation": "Central Disposal"},
    {"name": "R. Silva",      "salary_no": "50338", "designation": "Yard Officer"},
    {"name": "N. Bandara",    "salary_no": "36742", "designation": "Finance"}]'::jsonb,
  'Appointed after ' || cp.round_count || ' unsuccessful tenders',
  null,      -- the committee has not priced it yet; that is the tab's job
  null
from public.committee_pool cp
where not exists (select 1 from public.tender_committees tc
                   where tc.forfeited_package_id = cp.forfeited_package_id);

-- ── Verify against live data ────────────────────────────────────────────────
do $verify$
declare
  n_pool      int;
  n_without   int;
  n_members   int;
  n_bad       int;
begin
  select count(*) into n_pool from public.committee_pool where yard = 'GL1';

  select count(*) into n_without
    from public.committee_pool cp
   where not exists (select 1 from public.tender_committees tc
                      where tc.forfeited_package_id = cp.forfeited_package_id);
  if n_without > 0 then
    raise exception '% packages in the committee pool still have no committee',
      n_without;
  end if;

  -- ⚠️ FIVE members, every time. A committee short of one is not a committee,
  -- and the popup renders whatever the array holds -- it would simply show
  -- four names and say nothing was wrong.
  select count(*) into n_bad
    from public.tender_committees
   where jsonb_array_length(members) <> 5;
  if n_bad > 0 then
    raise exception '% committees do not have five members', n_bad;
  end if;

  select count(*) into n_members from public.tender_committees;
  raise notice 'committee pool: % packages, all with a committee (% total)',
    n_pool, n_members;

  -- ⚠️ A committee must never be appointed for goods that SOLD. The pool
  -- filters on `not ever_sold`, so this only fails if something wrote one
  -- directly.
  if exists (
    select 1 from public.tender_committees tc
     where exists (select 1 from public.tender_sale_items ti
                    where ti.forfeited_package_id = tc.forfeited_package_id
                      and ti.sold)) then
    raise exception 'a committee is appointed for goods that already sold';
  end if;

  raise notice 'verified: every package awaiting a committee has one';
end $verify$;
