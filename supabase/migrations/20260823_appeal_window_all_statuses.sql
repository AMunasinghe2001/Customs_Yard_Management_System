-- ============================================================================
--  The 30-day appeal window applies to EVERY status, not just forfeit.
--
--  Detain, Abandoned and "Other" goods are now frozen for the same 30 days as
--  a forfeiture: no Goods Action, no disposal request to Central Disposal, and
--  the Appeal Directorate can take an appeal on any of them.
--
--  The clock runs from the goods' ENTRY DATE (arrival at the yard), not from
--  the moment an officer changed the status — so a package that has been
--  sitting for months is actionable straight away, while a fresh one waits.
--
--  Abandoned / "Other" rows used to be written with
--      appeal_deadline = now() - 1 day
--  which deliberately skipped the window. This backfills them to the real
--  entry-date-based deadline, so old rows follow the same rule as new ones.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- ── Backfill: recompute the deadline from the package's entry date ──────────
--  Only touches rows whose deadline is the old "yesterday" sentinel, i.e. a
--  deadline at or before the row's own forfeited_at. A genuine forfeiture's
--  deadline is always forfeited_at + 30 days, so those are left alone.
with recomputed as (
  select fp.id,
         (coalesce(p.entry_date::date, p.created_at::date) + interval '30 days')
           as new_deadline
    from public.forfeited_packages fp
    join public.packages p on p.id = fp.package_id
   where fp.appeal_deadline <= fp.forfeited_at
)
update public.forfeited_packages fp
   set appeal_deadline = r.new_deadline
  from recomputed r
 where fp.id = r.id
   and fp.appeal_deadline is distinct from r.new_deadline;

-- ── Report what changed ─────────────────────────────────────────────────────
do $$
declare
  v_open int;
  v_past int;
begin
  select count(*) filter (where appeal_deadline > now()),
         count(*) filter (where appeal_deadline <= now())
    into v_open, v_past
    from public.forfeited_packages;

  raise notice 'appeal windows: % still open, % already passed', v_open, v_past;
end $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  Per source: how many are still inside the 30-day window.
select coalesce(fp.source, 'forfeit')                        as source,
       count(*)                                              as total,
       count(*) filter (where fp.appeal_deadline > now())     as in_appeal,
       count(*) filter (where fp.appeal_deadline <= now())    as actionable,
       min(fp.appeal_deadline)                               as earliest_deadline,
       max(fp.appeal_deadline)                               as latest_deadline
  from public.forfeited_packages fp
 group by coalesce(fp.source, 'forfeit')
 order by 1;
