-- ============================================================================
--  The Tender History popup reads three tables per round. Each had its own RLS,
--  and the gaps showed up as MISSING PARTS of the same history depending on who
--  was looking:
--
--      tender_sales / tender_sale_items → the round order   (already granted)
--      tender_revaluations              → each round's PRICE
--      tender_committees                → the committee round's members
--
--  `tender_revaluations` had SELECT policies for Valuation, Central Disposal,
--  Appeal and the High Panel — but NOT for the yards. So in a yard's Unsold
--  popup, Tender 1/2/3 rendered with no price and no "re-valued" mark, while
--  Central Disposal saw all of them.
--
--  This grants the owning yard read access to the re-valuations for its own
--  packages, and re-asserts the committee read so every portal lists the
--  appointed members. Read-only throughout: setting a re-valuation stays with
--  the Valuation Directorate, appointing a committee stays with the DG/ADG.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── The owning yard: re-valuations for its own packages ──────────────────
--    Matched on the re-valuation's own `yard` column where it is stamped, and
--    otherwise through the forfeited package it belongs to (older rows were
--    written before that column was populated).
drop policy if exists tender_reval_yard_read on public.tender_revaluations;
create policy tender_reval_yard_read on public.tender_revaluations
  for select
  using (
    yard = (select p.yard from public.profiles p where p.id = auth.uid())
    or exists (
      select 1
        from public.forfeited_packages fp
       where fp.id = tender_revaluations.forfeited_package_id
         and fp.yard = (select p.yard from public.profiles p
                         where p.id = auth.uid())
    )
  );

-- 2. ── Any authenticated officer may read a re-valuation ────────────────────
--    The history is a read-only audit trail and every portal that shows the
--    popup needs it. Kept separate from (1) so the yard rule stays explicit.
drop policy if exists tender_reval_auth_read on public.tender_revaluations;
create policy tender_reval_auth_read on public.tender_revaluations
  for select using (auth.role() = 'authenticated');

-- 3. ── Committees: re-assert the blanket read ───────────────────────────────
--    Already created by 20260718_tender_committees.sql; repeated here so a
--    database that only ran the later migrations still lists the members.
drop policy if exists tender_committees_auth_read on public.tender_committees;
create policy tender_committees_auth_read on public.tender_committees
  for select using (auth.role() = 'authenticated');

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('tender_revaluations', 'tender_committees', 'tender_bids')
 order by tablename, policyname;
