-- ============================================================================
--  Committee valuation — the two-step price for a package that stayed unsold
--  through the Valuation Tender plus Tender 1, 2 and 3.
--
--  Flow:
--    1. DG appoints the 5-member tender committee   (tender_committees.members)
--    2. THE COMMITTEE inspects the goods and records its own valuation
--         → committee_value / committee_valued_at / committee_note
--    3. THE ADG submits that figure as the FINAL valuation for the next tender
--         → submitted_value / submitted_at / submitted_by
--       which also writes the usual tender_revaluations row, so the price flows
--       into the tender exactly like a Valuation Directorate re-valuation.
--
--  Steps 2 and 3 are deliberately separate columns: the committee's opinion and
--  the ADG's formal submission are different acts, and the UI must be able to
--  show "committee valued, awaiting ADG" as its own state.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.tender_committees
  add column if not exists committee_value    numeric,
  add column if not exists committee_valued_at timestamptz,
  add column if not exists committee_note     text,
  add column if not exists submitted_value    numeric,
  add column if not exists submitted_at       timestamptz,
  add column if not exists submitted_by       uuid references auth.users(id);

-- The High Panel (DG appoints, ADG submits) already has full access via
-- 20260718_tender_committees.sql. Central Disposal / Valuation keep read-only.

reset lock_timeout;
