-- ============================================================================
--  Financial expenses — the outgoings side of the High Panel's Financials tab.
--
--  Income is derived from records the system already holds (storage charges,
--  destroying deposits, sale proceeds, taxes). Expenses are NOT: advertising
--  costs, destruction costs and refunds are entered by hand, so they need a
--  table of their own.
--
--  `kind` is one of:
--    destruction_expense  — cost of carrying out a destruction
--    advertising_expense  — cost of advertising a tender
--    refund               — money paid back (deposit returned, appeal upheld …)
--
--  Optional `yard` and `sr_number` let an entry be attributed; both may be
--  null for a general expense.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

create table if not exists public.financial_expenses (
  id          uuid primary key default gen_random_uuid(),
  kind        text        not null
                check (kind in ('destruction_expense',
                                'advertising_expense',
                                'refund')),
  amount      numeric(14,2) not null check (amount >= 0),
  description text,
  yard        text,
  sr_number   text,
  incurred_on date        not null default current_date,
  created_by  uuid        references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists financial_expenses_kind_idx
  on public.financial_expenses(kind);
create index if not exists financial_expenses_date_idx
  on public.financial_expenses(incurred_on);
create index if not exists financial_expenses_yard_idx
  on public.financial_expenses(yard);

alter table public.financial_expenses enable row level security;

-- 1. ── High Panel (DG / ADG / DC): the Financials tab lives in their portal ──
--    The DC is view-only in the UI; writes are still gated to executives so a
--    yard cannot post an expense.
drop policy if exists financial_expenses_exec_all on public.financial_expenses;
create policy financial_expenses_exec_all on public.financial_expenses
  for all
  using (public.auth_user_is_executive())
  with check (public.auth_user_is_executive());

-- 2. ── Central Disposal: they run the tenders, so they record the costs ─────
drop policy if exists financial_expenses_disposal_all on public.financial_expenses;
create policy financial_expenses_disposal_all on public.financial_expenses
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

-- 3. ── Everyone else authenticated: read-only ───────────────────────────────
drop policy if exists financial_expenses_read on public.financial_expenses;
create policy financial_expenses_read on public.financial_expenses
  for select using (auth.role() = 'authenticated');

-- 4. ── Realtime, so a posted expense updates every open Financials tab ──────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'financial_expenses'
  ) then
    alter publication supabase_realtime add table public.financial_expenses;
  end if;
end $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select kind, count(*) as entries, coalesce(sum(amount), 0) as total
  from public.financial_expenses
 group by kind
 order by kind;
