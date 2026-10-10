-- ============================================================================
--  Index the appeal window's filter column.
--
--  The Appeal Directorate's "goods still open to appeal" query used to pull
--  EVERY package in the system — with its items, warehouse entries and profile
--  joins — and then discard the out-of-window ones in Dart. The portal sat
--  loading for about a minute.
--
--  It now asks the database for the window instead:
--
--      entry_date >= now() - 30 days
--      OR (entry_date IS NULL AND created_at >= now() - 30 days)
--
--  These indexes are what make that filter cheap. Without them the planner
--  still scans the whole table; the win is only in the smaller result set
--  travelling over the wire.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

create index if not exists packages_entry_date_idx
  on public.packages(entry_date desc);

-- Covers the fallback arm: rows that never had an entry_date recorded.
create index if not exists packages_created_at_idx
  on public.packages(created_at desc);

-- The Appeal portal also loads the real rows behind Detain / Abandoned /
-- "Other" appeals, keyed by (package_id, item_id) and filtered on source.
create index if not exists forfeited_packages_source_idx
  on public.forfeited_packages(source);

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select count(*)                                                as packages,
       count(*) filter (
         where coalesce(entry_date, created_at) >= now() - interval '30 days')
                                                                as in_window
  from public.packages;
