-- ============================================================================
--  Forfeited-package SOURCE: add 'other'
--  Run after 20260613_forfeited_source.sql.
--
--  Packages registered with an "Other" item status (a custom disposition set on
--  the SR form — e.g. court-held / pending-decision) can now be routed through
--  the same disposal-request → tender-sale / destruction pipeline as forfeited
--  and abandoned goods, with NO appeal period. They get a real
--  forfeited_packages row (source='other') only when requested; `source` lets
--  the Central Disposal "Disposal Requests" page badge them and lets the yard's
--  "true forfeits only" lists filter the synthetic rows out.
-- ============================================================================

alter table public.forfeited_packages
  drop constraint if exists forfeited_packages_source_check;

alter table public.forfeited_packages
  add constraint forfeited_packages_source_check
    check (source in ('forfeit', 'abandoned', 'other'));
