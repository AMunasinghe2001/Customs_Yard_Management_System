-- ============================================================================
--  Destroying Deposit
--
--  A deposit the declarant lodges against the cost of destroying the goods.
--  It is collected ONCE per SR at registration — a PACKAGE-level figure, not
--  a per-goods-item one — so it lives on `packages`, beside container_number.
--
--  Nullable: older SRs have none, and it is optional on the form.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.packages
  add column if not exists destroying_deposit numeric;

comment on column public.packages.destroying_deposit is
  'Deposit lodged by the declarant against the cost of destroying the goods. '
  'One figure per SR (package-level), set at registration.';

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'packages'
   and column_name  = 'destroying_deposit';
