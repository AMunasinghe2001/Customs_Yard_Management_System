-- ============================================================================
--  Anchor forfeited_packages to the SR-form Entry Date:
--    forfeited_at  = package entry_date
--    appeal_deadline = package entry_date + 30 days
--
--  Both the forfeited date and the 30-day appeal window must count from the
--  SR-form Entry Date, not the moment of forfeiture. New forfeits already do
--  this (createForfeitedPackage), but rows forfeited BEFORE that change still
--  hold (forfeited_at = now, appeal_deadline = now + 30). This backfills them.
--
--  Run in the Supabase SQL Editor.
-- ============================================================================

-- 1. ── PREVIEW: current vs corrected values (nothing changed yet) ────────────
select fp.id,
       fp.sr_number,
       p.entry_date::date              as entry_date,
       fp.forfeited_at::date           as current_forfeited_at,
       fp.appeal_deadline::date        as current_deadline,
       p.entry_date::date              as corrected_forfeited_at,
       (p.entry_date + interval '30 days')::date as corrected_deadline
  from public.forfeited_packages fp
  join public.packages p on p.id = fp.package_id
 where p.entry_date is not null
 order by fp.sr_number;

-- 2. ── UPDATE: anchor both dates to the package entry_date ───────────────────
--    Only rows whose package has an entry_date (leave the rest untouched).
update public.forfeited_packages fp
   set forfeited_at    = p.entry_date,
       appeal_deadline = p.entry_date + interval '30 days'
  from public.packages p
 where p.id = fp.package_id
   and p.entry_date is not null;

-- 3. ── VERIFY: after update, both dates should match entry_date (+30) ────────
select fp.sr_number,
       p.entry_date::date              as entry_date,
       fp.forfeited_at::date           as forfeited_at,
       fp.appeal_deadline::date        as appeal_deadline,
       (fp.forfeited_at::date = p.entry_date::date) as forfeited_ok,
       (fp.appeal_deadline::date = (p.entry_date + interval '30 days')::date) as deadline_ok
  from public.forfeited_packages fp
  join public.packages p on p.id = fp.package_id
 where p.entry_date is not null
 order by fp.sr_number;
