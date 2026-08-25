-- ============================================================================
--  Three more recorded costs: labour, transport and auction.
--
--  Central Disposal already records what a disposal cost to carry out
--  (destruction) and to advertise. Getting the goods there and selling them
--  costs money too, and it comes out of the same destroying deposit:
--
--      labour_expense     — handling / loading the goods
--      transport_expense  — moving them
--      auction_expense    — running the auction itself
--
--  The refund stays DERIVED — now from all five costs together:
--
--      refund = destroying_deposit - Σ(destruction + advertising
--                                      + labour + transport + auction)
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.financial_expenses
  drop constraint if exists financial_expenses_kind_check;

alter table public.financial_expenses
  add constraint financial_expenses_kind_check
    check (kind in ('destruction_expense',
                    'advertising_expense',
                    'labour_expense',
                    'transport_expense',
                    'auction_expense',
                    -- Historical rows only; a refund is derived, never written.
                    'refund'));

-- The one-per-(item, kind) rule covers the new kinds automatically — the
-- unique constraint from 20260830_expenses_per_goods.sql is on the pair, not
-- on a list of kinds, so nothing more is needed there.

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.financial_expenses'::regclass
   and conname = 'financial_expenses_kind_check';
