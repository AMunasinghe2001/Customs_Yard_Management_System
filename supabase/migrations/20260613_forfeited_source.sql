-- ============================================================================
--  Forfeited-package SOURCE tag (Forfeit vs Abandoned)
--  Run after 20260528_add_forfeited_packages_and_tenders.sql.
--
--  Yards can now route ABANDONED packages through the same disposal-request →
--  tender-sale / destruction pipeline as forfeited ones. To reuse that pipeline
--  unchanged, an abandoned package gets a real forfeited_packages row when it is
--  requested; `source` records where it came from so the Central Disposal
--  "Disposal Requests" page can badge each item Forfeit vs Abandoned, and so the
--  yard's "true forfeits only" lists can filter the synthetic rows out.
-- ============================================================================

alter table public.forfeited_packages
  add column if not exists source text not null default 'forfeit'
    check (source in ('forfeit', 'abandoned'));

-- Existing rows are all genuine forfeits — the default already covers them, but
-- be explicit for any row that somehow has a NULL.
update public.forfeited_packages set source = 'forfeit' where source is null;

create index if not exists idx_forfeited_packages_source
  on public.forfeited_packages(source);
