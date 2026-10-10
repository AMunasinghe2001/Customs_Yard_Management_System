-- ============================================================================
--  Top Management's outcomes existed in the code and barely in the data.
--
--  Five decided packages in the whole database -- auction 1, convert 2,
--  destroy 1, government_use 1 -- and NONE re-exported, NONE delivered. So:
--
--    * Re-exported Goods showed 17 rows, every one of them decided by the YARD.
--      The second route into that page -- Top Management ruling `re_export` on
--      goods that failed every tender -- had no row at all, so the Decided By
--      column that exists to tell the two apart only ever printed one value.
--    * Removed from the Premises had nothing.
--    * The Delivery column added for the four Final Outcome pages had nothing
--      delivered to show, so neither state of the pill could be seen.
--
--  ⚠️ These goods take the FULL route, exactly as the app requires: four
--  tenders exhausted -> a committee appointed -> the ADG submits its figure ->
--  one more tender at that price -> still unsold -> Top Management rules. A
--  proposal written against a package that had not been through that is a row
--  the app's own guard (`getExhaustedUnsoldPackages`) would refuse to list,
--  so it would be invisible however correct it looked in the table.
--
--  Seven packages, chosen because their last tender round is well past. The two
--  whose newest round is TODAY are deliberately left alone: their sale has not
--  closed, so they still have a live chance of selling and nothing may be
--  decided about them yet.
-- ============================================================================

set lock_timeout = '5s';

-- ── The seven, with the outcome each is being given ─────────────────────────
--  ⚠️ Keyed by the FORFEITED ROW's id, not by SR number. Forfeiture is per
--  item, so one SR produces several forfeited rows -- CED/GL1/SR/47/2026 has
--  three, and only ONE of them went to tender. Matching on the SR number
--  picked up the siblings too and tried to appoint a committee for a package
--  with no rounds at all.
--
--  A real table, not a temporary one: it has to outlive a statement.
drop table if exists public._seed_outcomes;
create table public._seed_outcomes(fp_id uuid primary key, proposal text,
                                   note text, deliver boolean);

insert into public._seed_outcomes values
  -- The route that had NO data at all: Top Management ordering a re-export.
  -- CED/GL1/SR/16/2026 Cotton Bed Sheets
  ('87cf8b4e-d0b8-40a1-a3eb-b0dfa989ef3a', 're_export',
   'Consignee arranged carriage back to origin at their own expense.', true),
  -- CED/GL1/SR/42/2026 Rubber Conveyor Belt
  ('93184794-bb1f-421c-bae0-6acd45e27fc2', 're_export',
   'Shipping line accepted return; goods left under Customs supervision.',
   false),
  -- Removed from the Premises, which had none either.
  -- CED/GL1/OA/02/2025 Scrap Steel Bundles
  ('55a4871e-2420-44d8-ba36-35ea0ff2e72e', 'remove_from_premises',
   'Scrap steel removed by the appointed contractor.', true),
  -- One more of each of the existing four, so every page has more than a
  -- single row to sort, filter and page through.
  -- CED/GL1/SR/05/2026 Ceramic Floor Tiles
  ('59e744ec-671a-49e2-8e46-0ab87cd0f9c5', 'government_use',
   'Allocated to the Department of Buildings.', false),
  -- CED/GL1/SR/47/2026 Wrist Watches
  ('98813b7a-4ae2-417a-bfea-3d8ad44ea665', 'auction',
   'Referred to public auction after the committee round failed.', false);

--  ⚠️ Latex Gloves (SR/13/2025) and Industrial Bearings (SR/27/2026) were the
--  obvious next candidates -- four rounds each, no outcome -- and both are
--  WRONG. Each already has a round that SOLD. Goods that sold are finished;
--  giving them a Top Management outcome would say the tender route failed
--  when it succeeded, and the item would appear on a Final Outcome page and
--  on Sold Goods at once. Counting rounds is not enough: a candidate must
--  have four rounds AND none of them sold.

-- ── 1. Appoint the committee, where one is missing ──────────────────────────
--  A package only reaches Top Management after a committee has priced it and
--  the ADG has submitted that figure. Without this the app would not list the
--  package at all, and the outcome would be invisible.
insert into public.tender_committees
  (forfeited_package_id, members, note, yard, created_by, created_at,
   committee_value, committee_valued_at, committee_note,
   submitted_value, submitted_at, submitted_by)
select fp.id,
       '[{"name": "D. M. Perera", "salary_no": "41207", "designation": "Chairperson"},
         {"name": "S. Fernando", "salary_no": "38915", "designation": "Valuation Directorate"},
         {"name": "A. Jayasinghe", "salary_no": "44160", "designation": "Central Disposal"},
         {"name": "R. Silva", "salary_no": "50338", "designation": "Yard Officer"},
         {"name": "N. Bandara", "salary_no": "36742", "designation": "Finance"}]'::jsonb,
       'Appointed after 4 unsuccessful tenders',
       fp.yard,
       (select id from public.profiles where full_name like '%(DG)%' limit 1),
       lr.moment + interval '3 days',
       -- ⚠️ The committee prices BELOW the last reserve. Four failed tenders
       -- are the market saying the price was too high, and migration 12
       -- already established that a re-tender always lowers it.
       round((lr.reserve * 0.72)::numeric, 2),
       lr.moment + interval '10 days',
       'Committee valuation recorded in writing outside the system.',
       round((lr.reserve * 0.72)::numeric, 2),
       lr.moment + interval '12 days',
       (select id from public.profiles where full_name like '%(ADG)%' limit 1)
  from public.forfeited_packages fp
  join public._seed_outcomes o on o.fp_id = fp.id
  cross join lateral (
    select max(ts.created_at) as moment,
           coalesce(
             -- The newest re-valuation is the price the last round ran at.
             (select tr.valuation_cost
                from public.tender_revaluations tr
               where tr.forfeited_package_id = fp.id
               order by tr.created_at desc limit 1),
             100000) as reserve
      from public.tender_sale_items ti
      join public.tender_sales ts on ts.id = ti.tender_sale_id
     where ti.forfeited_package_id = fp.id) lr
 where not exists (select 1 from public.tender_committees tc
                    where tc.forfeited_package_id = fp.id);

-- ── 1b. Price the committees that were appointed but never valued ──────────
--  ⚠️ Several of these packages ALREADY had a committee row -- appointed, and
--  then nothing: committee_value and submitted_value both null. Step 1 skips
--  them (it only inserts where no row exists), so without this they would
--  reach step 2 with a null submitted_at and the round would be dated nowhere.
--
--  An appointed-but-unpriced committee is also a real state in its own right,
--  which is why those rows exist; this only fills the ones being carried
--  through to a final outcome.
update public.tender_committees tc
   set committee_value     = round((lr.reserve * 0.72)::numeric, 2),
       committee_valued_at = tc.created_at + interval '7 days',
       committee_note      = coalesce(tc.committee_note,
         'Committee valuation recorded in writing outside the system.'),
       submitted_value     = round((lr.reserve * 0.72)::numeric, 2),
       submitted_at        = tc.created_at + interval '9 days',
       submitted_by        = coalesce(tc.submitted_by,
         (select id from public.profiles
           where full_name like '%(ADG)%' limit 1)),
       updated_at          = now()
  from public._seed_outcomes o
  cross join lateral (
    select coalesce(
             (select tr.valuation_cost
                from public.tender_revaluations tr
               where tr.forfeited_package_id = o.fp_id
               order by tr.created_at desc limit 1),
             100000) as reserve) lr
 where tc.forfeited_package_id = o.fp_id
   and tc.submitted_value is null;

-- ── 2. The committee round: tendered once more, and still unsold ────────────
--  ⚠️ The committee's price is TENDERED, not applied. Only if THAT round also
--  fails does the package reach Top Management -- so the round has to exist,
--  and it has to have failed.
--
--  Two plain statements rather than one data-modifying CTE: the sale carries
--  the forfeited row's id in its OWN sale_number, so the second statement can
--  find the sale it just made without depending on a RETURNING clause lining
--  up with the source rows.
insert into public.tender_sales
  (sale_number, sale_date, sale_time, sale_end_time, yard, created_at)
select 'TS/' || fp.yard || '/CMT/' || replace(fp.id::text, '-', ''),
       (tc.submitted_at + interval '20 days')::date,
       '09:00', '15:00', fp.yard,
       tc.submitted_at + interval '20 days'
  from public.forfeited_packages fp
  join public._seed_outcomes o on o.fp_id = fp.id
  join public.tender_committees tc on tc.forfeited_package_id = fp.id
 where not exists (
   select 1 from public.tender_sale_items ti
     join public.tender_sales ts on ts.id = ti.tender_sale_id
    where ti.forfeited_package_id = fp.id
      and ts.created_at > tc.submitted_at)
   and not exists (
   select 1 from public.tender_sales ts2
    where ts2.sale_number =
          'TS/' || fp.yard || '/CMT/' || replace(fp.id::text, '-', ''));

-- ⚠️ There is no `unsold` column: a round is unsold when it is NOT sold and
-- its deadline has passed. `sold = false` on a sale whose date is long past is
-- exactly what an unsold round looks like everywhere else in this database.
insert into public.tender_sale_items
  (tender_sale_id, forfeited_package_id, yard, sold, created_at)
select ts.id, fp.id, fp.yard, false, ts.created_at
  from public.forfeited_packages fp
  join public._seed_outcomes o on o.fp_id = fp.id
  join public.tender_sales ts
    on ts.sale_number = 'TS/' || fp.yard || '/CMT/' || replace(fp.id::text, '-', '')
 where not exists (select 1 from public.tender_sale_items ti
                    where ti.tender_sale_id = ts.id
                      and ti.forfeited_package_id = fp.id);

-- ── 3. The decision itself ──────────────────────────────────────────────────
insert into public.unsold_proposals
  (forfeited_package_id, proposal, note, yard, decided_by, decided_at,
   delivered, delivered_at)
select fp.id, o.proposal, o.note, fp.yard,
       (select id from public.profiles where full_name like '%(DG)%' limit 1),
       tc.submitted_at + interval '35 days',
       o.deliver,
       -- Delivered a fortnight after the ruling, or not at all. Both states
       -- have to exist or the Delivery column can only ever be seen one way.
       case when o.deliver then tc.submitted_at + interval '49 days' end
  from public.forfeited_packages fp
  join public._seed_outcomes o on o.fp_id = fp.id
  join public.tender_committees tc on tc.forfeited_package_id = fp.id
 where not exists (select 1 from public.unsold_proposals up
                    where up.forfeited_package_id = fp.id);

-- ── 3b. Nothing may be dated in the future ──────────────────────────────────
--  ⚠️ The dates above are derived from each package's own committee timeline
--  (+35 days to rule, +14 more to hand over), and for the packages whose last
--  round was recent that lands AFTER today. A decision recorded before it
--  happened is not a decision, and the yard would be reading a hand-over that
--  has not occurred.
--
--  Pulled back so the sequence still reads correctly -- ruled first, handed
--  over after -- but inside the past.
update public.unsold_proposals up
   set decided_at   = now() - interval '9 days',
       delivered_at = case when up.delivered then now() - interval '2 days' end,
       updated_at   = now()
 where up.decided_at > now()
    or up.delivered_at > now();

-- ── 4. Delivered goods have LEFT the warehouse ──────────────────────────────
--  The same close the toggle performs, so a seeded hand-over and a real one
--  are indistinguishable -- and zone capacity does not go on counting goods
--  that are gone.
update public.warehouse_entries w
   set is_returned  = true,
       returned_at  = up.delivered_at,
       return_notes = '[FINAL:' || upper(up.proposal) || ']',
       updated_at   = now()
  from public.unsold_proposals up
  join public.forfeited_packages fp on fp.id = up.forfeited_package_id
 where w.package_item_id = fp.item_id
   and up.delivered
   and coalesce(w.is_returned, false) = false;

drop table if exists public._seed_outcomes;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  delivered_n int;
  undelivered_n int;
  bad int;
begin
  -- ⚠️ Every proposal must sit on a package that genuinely exhausted the
  -- route: a committee figure submitted, and a tender round AFTER it that did
  -- not sell. Otherwise the app's own guard will not list it, and the row is
  -- data nobody can see.
  select count(*) into bad
    from public.unsold_proposals up
    join public.forfeited_packages fp on fp.id = up.forfeited_package_id
    join public.package_items pi on pi.id = fp.item_id
   -- ⚠️ PERISHABLES ARE EXEMPT, and correctly so. Goods that spoil never go
   -- to tender at all -- no warehouse, no appeal window, decided at once --
   -- so demanding an exhausted tender route of them would fail two outcomes
   -- that are exactly right.
   where lower(coalesce(pi.reasons, '')) not like '%perishable%'
     and lower(coalesce(pi.status, '')) <> 'perishable'
     and (not exists (
     select 1 from public.tender_committees tc
      where tc.forfeited_package_id = fp.id
        and tc.submitted_value is not null)
      or not exists (
     select 1 from public.tender_sale_items ti
       join public.tender_sales ts on ts.id = ti.tender_sale_id
       join public.tender_committees tc on tc.forfeited_package_id = fp.id
      where ti.forfeited_package_id = fp.id
        and ts.created_at > tc.submitted_at));
  if bad <> 0 then
    raise exception '% non-perishable outcome(s) sit on a package that did '
                    'not exhaust the tender route', bad;
  end if;

  -- The committee round must have FAILED. An outcome on goods that sold is a
  -- contradiction.
  select count(*) into bad
    from public.unsold_proposals up
    join public.tender_sale_items ti
      on ti.forfeited_package_id = up.forfeited_package_id
   where ti.sold;
  if bad <> 0 then
    for r in
      select fp.sr_number, up.proposal, ti.sold_price
        from public.unsold_proposals up
        join public.forfeited_packages fp on fp.id = up.forfeited_package_id
        join public.tender_sale_items ti
          on ti.forfeited_package_id = up.forfeited_package_id
       where ti.sold
    loop
      raise notice 'SOLD-AND-DECIDED: % / % / %',
        r.sr_number, r.proposal, r.sold_price;
    end loop;
    raise exception '% outcome(s) sit on goods that actually sold', bad;
  end if;

  -- Nothing delivered may still hold an open warehouse row.
  select count(*) into bad
    from public.unsold_proposals up
    join public.forfeited_packages fp on fp.id = up.forfeited_package_id
    join public.warehouse_entries w on w.package_item_id = fp.item_id
   where up.delivered and coalesce(w.is_returned, false) = false;
  if bad <> 0 then
    raise exception '% delivered package(s) still hold an open warehouse row',
      bad;
  end if;

  -- Both delivery states must exist, or the column can only be seen one way.
  select count(*) into delivered_n
    from public.unsold_proposals where delivered;
  select count(*) into undelivered_n
    from public.unsold_proposals where not delivered;
  if delivered_n = 0 or undelivered_n = 0 then
    raise exception 'need both delivered and undelivered rows; got % / %',
      delivered_n, undelivered_n;
  end if;

  -- Nothing may be dated ahead of today.
  select count(*) into bad
    from public.unsold_proposals
   where decided_at > now() or delivered_at > now();
  if bad <> 0 then
    raise exception '% outcome(s) are dated in the future', bad;
  end if;

  -- And a hand-over cannot precede the ruling that ordered it.
  select count(*) into bad
    from public.unsold_proposals
   where delivered and delivered_at < decided_at;
  if bad <> 0 then
    raise exception '% package(s) were handed over before being decided', bad;
  end if;

  raise notice 'Final outcomes now recorded:';
  for r in
    select proposal, count(*) as n,
           sum(case when delivered then 1 else 0 end) as handed_over
      from public.unsold_proposals group by proposal order by proposal
  loop
    raise notice '  % -- % package(s), % handed over',
      rpad(r.proposal, 22), r.n, r.handed_over;
  end loop;
end
$verify$;
