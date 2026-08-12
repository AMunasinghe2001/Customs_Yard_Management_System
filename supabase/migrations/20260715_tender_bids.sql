-- ============================================================================
--  Tender Bids — bid values recorded for unsold tender packages
--  Run after the disposal + appeal migrations
--  (20260610_disposal_directorate.sql, 20260613_appeal_directorate.sql).
--
--  When a tender sale fails (goes to Unsold Tenders in Central Disposal), the
--  Central Disposal Directorate records the bid amounts that were placed for
--  that package. The Appeal Directorate can then VIEW those bids (read-only).
--
--  Keyed by (forfeited_package_id, tender_sale_id) — one bid SET per tender
--  ROUND (attempt). A package that goes unsold across several re-tenders keeps
--  its rounds' bids separate. One row per bid amount.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Table ────────────────────────────────────────────────────────────────
create table if not exists public.tender_bids (
  id                   uuid primary key default gen_random_uuid(),
  forfeited_package_id uuid not null
                         references public.forfeited_packages(id) on delete cascade,
  tender_sale_id       uuid
                         references public.tender_sales(id) on delete cascade,
  amount               numeric not null,
  yard                 text,
  created_by           uuid references auth.users(id),
  created_at           timestamptz not null default now()
);

-- Added later for existing installs: the tender round the bid belongs to.
alter table public.tender_bids
  add column if not exists tender_sale_id uuid
    references public.tender_sales(id) on delete cascade;

create index if not exists tender_bids_fp_idx
  on public.tender_bids(forfeited_package_id);
create index if not exists tender_bids_sale_idx
  on public.tender_bids(tender_sale_id);

alter table public.tender_bids enable row level security;

-- 2. ── Central Disposal: full read/write (they enter the bids) ──────────────
drop policy if exists tender_bids_disposal_all on public.tender_bids;
create policy tender_bids_disposal_all on public.tender_bids
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

-- 3. ── Appeal Directorate: read-only (view the recorded bids) ───────────────
drop policy if exists tender_bids_appeal_read on public.tender_bids;
create policy tender_bids_appeal_read on public.tender_bids
  for select
  using (public.auth_user_is_appeal());
