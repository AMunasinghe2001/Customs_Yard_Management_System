-- ============================================================================
--  Tender Re-valuations — a fresh valuation the Valuation Directorate sets for
--  an unsold tender package, per tender ROUND. Central Disposal reads it back.
--  Run after 20260715_tender_bids.sql.
--
--  Flow: unsold tender → Central Disposal records the bids → Valuation reviews
--  the bids and sets a NEW valuation for the current tender round → Central
--  Disposal sees that re-valuation → re-tenders. If it goes unsold again the
--  same cycle repeats for the next round.
--
--  Keyed by (forfeited_package_id, tender_sale_id) — one re-valuation per round.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Table ────────────────────────────────────────────────────────────────
create table if not exists public.tender_revaluations (
  id                   uuid primary key default gen_random_uuid(),
  forfeited_package_id uuid not null
                         references public.forfeited_packages(id) on delete cascade,
  tender_sale_id       uuid
                         references public.tender_sales(id) on delete cascade,
  valuation_cost       numeric not null,
  note                 text,
  yard                 text,
  created_by           uuid references auth.users(id),
  created_at           timestamptz not null default now()
);

create index if not exists tender_revaluations_fp_idx
  on public.tender_revaluations(forfeited_package_id);
create index if not exists tender_revaluations_sale_idx
  on public.tender_revaluations(tender_sale_id);

alter table public.tender_revaluations enable row level security;

-- 2. ── Valuation Directorate: full read/write (they set the re-valuation) ────
drop policy if exists tender_reval_valuation_all on public.tender_revaluations;
create policy tender_reval_valuation_all on public.tender_revaluations
  for all
  using (public.auth_user_is_valuation())
  with check (public.auth_user_is_valuation());

-- 3. ── Central Disposal: read-only (sees the re-valuation before re-tender) ──
drop policy if exists tender_reval_disposal_read on public.tender_revaluations;
create policy tender_reval_disposal_read on public.tender_revaluations
  for select
  using (public.auth_user_is_disposal());

-- 4. ── Appeal Directorate: read-only (context alongside the bids) ────────────
drop policy if exists tender_reval_appeal_read on public.tender_revaluations;
create policy tender_reval_appeal_read on public.tender_revaluations
  for select
  using (public.auth_user_is_appeal());

-- 5. ── Valuation needs to READ the unsold-tender data + the bids ─────────────
--  The Valuation "Unsold Tenders" page loads getUnsoldTenderSales() (tender
--  sales/items) and the recorded bids — grant cross-yard SELECT on those.
drop policy if exists valuation_read_all on public.tender_sales;
create policy valuation_read_all on public.tender_sales
  for select using (public.auth_user_is_valuation());

drop policy if exists valuation_read_all on public.tender_sale_items;
create policy valuation_read_all on public.tender_sale_items
  for select using (public.auth_user_is_valuation());

drop policy if exists tender_bids_valuation_read on public.tender_bids;
create policy tender_bids_valuation_read on public.tender_bids
  for select using (public.auth_user_is_valuation());

-- 6. ── Realtime: publish tender_revaluations for live cross-portal updates ───
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'tender_revaluations'
  ) then
    alter publication supabase_realtime add table public.tender_revaluations;
  end if;
end $$;
