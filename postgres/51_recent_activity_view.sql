-- The packages a yard has touched TODAY, most recently first.
--
-- ⚠️ The dashboards fetched EVERY package in the yard — 176 rows at 159ms,
-- each with its items and warehouse entries — to keep the twenty that were
-- touched today and throw the rest away.
--
-- "Touched today" is three things, and the third is why the whole table was
-- being read: a package counts when its own row was updated or created today,
-- OR when any of its warehouse entries was admitted or returned today. That
-- last one covers Release, Re-export and Forfeit, which write only to
-- `warehouse_entries` and never touch the package row — so a package's own
-- timestamps cannot answer the question alone.
--
-- `touched_at` is the latest of those moments across the package and its
-- entries, which is the order the dashboard reads in.
--
-- ⚠️ TODAY means today, not "today or later". The Dart tested
-- `isAfter(startOfDay)` with no upper bound, so a warehouse entry whose
-- returned_at is next week counted as activity now -- two rows on the live
-- data, both future returns from seeding. A dashboard headed "Recent
-- Activity" reporting something that has not happened yet is worse than a
-- short list.

drop view if exists public.recent_package_activity cascade;

create view public.recent_package_activity as
with entry_touch as (
  select
    we.package_id,
    max(greatest(we.admitted_at, coalesce(we.returned_at, we.admitted_at)))
      as last_entry_touch
  from public.warehouse_entries we
  group by we.package_id
)
select
  p.id as package_id,
  p.sr_number,
  p.yard,
  p.status,
  -- ⚠️ The latest touch across the package AND its entries, not the package's
  -- own updated_at: a forfeit writes only to warehouse_entries, so ordering by
  -- the package row alone would bury today's work under last week's edits.
  greatest(p.updated_at, p.created_at,
           coalesce(et.last_entry_touch, p.created_at)) as touched_at
from public.packages p
left join entry_touch et on et.package_id = p.id
where
  -- ⚠️ Today in ASIA/COLOMBO, not in the reader's timezone. The app's driver
  -- connects as UTC and psql here inherits Asia/Colombo, so a bare
  -- `::date = current_date` would disagree between them -- and near midnight
  -- that means a yard's own day's work vanishing from its dashboard.
  (p.updated_at at time zone 'Asia/Colombo')::date
      = (now() at time zone 'Asia/Colombo')::date
  or (p.created_at at time zone 'Asia/Colombo')::date
      = (now() at time zone 'Asia/Colombo')::date
  or exists (
    select 1 from public.warehouse_entries we
     where we.package_id = p.id
       and ((we.admitted_at at time zone 'Asia/Colombo')::date
              = (now() at time zone 'Asia/Colombo')::date
         or (we.returned_at at time zone 'Asia/Colombo')::date
              = (now() at time zone 'Asia/Colombo')::date));

comment on view public.recent_package_activity is
  'Packages touched today — the package row updated or created, or any of its '
  'warehouse entries admitted or returned. `touched_at` is the latest of '
  'those across the package and its entries.';


-- ── Does it find what the Dart found? ────────────────────────────────────
do $verify$
declare
  n_rows   int;
  n_dart   int;
  n_utc    int;
  n_local  int;
  bad      int;
begin
  select count(*) into n_rows from public.recent_package_activity;

  -- The same membership, stated independently.
  select count(*) into n_dart
    from public.packages p
   where (p.updated_at at time zone 'Asia/Colombo')::date
           = (now() at time zone 'Asia/Colombo')::date
      or (p.created_at at time zone 'Asia/Colombo')::date
           = (now() at time zone 'Asia/Colombo')::date
      or exists (
        select 1 from public.warehouse_entries we
         where we.package_id = p.id
           and ((we.admitted_at at time zone 'Asia/Colombo')::date
                  = (now() at time zone 'Asia/Colombo')::date
             or (we.returned_at at time zone 'Asia/Colombo')::date
                  = (now() at time zone 'Asia/Colombo')::date));
  if n_rows <> n_dart then
    raise exception 'recent_package_activity holds %, the rule finds %',
      n_rows, n_dart;
  end if;

  -- ⚠️ And the same answer whoever asks. The app connects as UTC; psql here
  -- inherits Asia/Colombo. A date comparison that follows the session would
  -- give the two different days near midnight -- the exact trap postgres/41
  -- was caught by.
  set local timezone to 'UTC';
  select count(*) into n_utc from public.recent_package_activity;
  set local timezone to 'Asia/Colombo';
  select count(*) into n_local from public.recent_package_activity;
  if n_utc <> n_local then
    raise exception 'today depends on the reader: UTC sees %, Colombo sees %',
      n_utc, n_local;
  end if;

  -- touched_at is never before the package was created.
  select count(*) into bad
    from public.recent_package_activity r
    join public.packages p on p.id = r.package_id
   where r.touched_at < p.created_at;
  if bad <> 0 then
    raise exception '% row(s) claim a touch before the package existed', bad;
  end if;

  raise notice 'recent_package_activity: % package(s) touched today', n_rows;
end
$verify$;
