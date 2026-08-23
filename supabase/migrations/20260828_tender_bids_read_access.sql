-- ============================================================================
--  Read access to tender_bids for the High Panel and the yards.
--
--  `tender_bids` had SELECT policies for Central Disposal, the Appeal
--  Directorate and the Valuation Directorate only. The Tender History section
--  on the Unsold popup reads bids per round, so in the High Panel and yard
--  portals every round rendered "No bids recorded" — the rows were there, RLS
--  simply filtered them out.
--
--  Read-only: recording a bid stays with Central Disposal.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── High Panel (DG / ADG / DC): they review the whole tender history ─────
drop policy if exists tender_bids_executive_read on public.tender_bids;
create policy tender_bids_executive_read on public.tender_bids
  for select using (public.auth_user_is_executive());

-- 2. ── The owning yard: its own packages' bids ──────────────────────────────
--    Matched through the bid's own `yard` column, which is stamped when the
--    bid is recorded.
drop policy if exists tender_bids_yard_read on public.tender_bids;
create policy tender_bids_yard_read on public.tender_bids
  for select
  using (
    yard = (select p.yard from public.profiles p where p.id = auth.uid())
  );

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select policyname, cmd, qual
  from pg_policies
 where schemaname = 'public'
   and tablename  = 'tender_bids'
 order by policyname;
