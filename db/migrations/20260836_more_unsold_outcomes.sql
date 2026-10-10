-- ============================================================================
--  Three more outcomes for goods that could not be sold by any means.
--
--  The High Panel could choose Destroy / Remand / Government Use / Auction.
--  Goods that none of those suit have three further routes:
--
--      re_export             — sent back to the country of origin
--      convert               — converted to another use or form
--      remove_from_premises  — removed from the yard under a separate order
--
--  Widening the CHECK is enough; nothing stored becomes invalid.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.unsold_proposals
  drop constraint if exists unsold_proposals_proposal_check;

alter table public.unsold_proposals
  add constraint unsold_proposals_proposal_check
    check (proposal in ('destroy',
                        'remand',
                        'government_use',
                        'auction',
                        're_export',
                        'convert',
                        'remove_from_premises'));

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.unsold_proposals'::regclass
   and conname = 'unsold_proposals_proposal_check';
