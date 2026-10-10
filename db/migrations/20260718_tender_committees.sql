-- ============================================================================
--  Tender Committees — DG appoints a 5-member committee for a tender package
--  that has gone unsold more than 3 times (≥4 tender attempts).
--  Run after the executive + tender migrations.
--
--  The Director General's Office sees the eligible packages and appoints the
--  committee (5 member names + optional designations). Central Disposal
--  officers see each such package with its committee (read-only).
--  Idempotent where practical — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Table ────────────────────────────────────────────────────────────────
create table if not exists public.tender_committees (
  id                   uuid primary key default gen_random_uuid(),
  forfeited_package_id uuid not null unique
                         references public.forfeited_packages(id) on delete cascade,
  -- [{ "name": "...", "designation": "..." }, …] up to 5 members
  members              jsonb not null default '[]'::jsonb,
  note                 text,
  yard                 text,
  created_by           uuid references auth.users(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists tender_committees_fp_idx
  on public.tender_committees(forfeited_package_id);

alter table public.tender_committees enable row level security;

-- 2. ── Executive Office (DG/ADG): full read/write (appoint the committee) ────
drop policy if exists tender_committees_exec_all on public.tender_committees;
create policy tender_committees_exec_all on public.tender_committees
  for all
  using (public.auth_user_is_executive())
  with check (public.auth_user_is_executive());

-- 3. ── Central Disposal + Appeal: read-only (see the committee) ─────────────
drop policy if exists tender_committees_disposal_read on public.tender_committees;
create policy tender_committees_disposal_read on public.tender_committees
  for select using (public.auth_user_is_disposal());

drop policy if exists tender_committees_appeal_read on public.tender_committees;
create policy tender_committees_appeal_read on public.tender_committees
  for select using (public.auth_user_is_appeal());

-- Central Disposal officers are per-yard (not the disposal directorate); allow
-- any authenticated yard officer to read committees for their own visibility.
drop policy if exists tender_committees_auth_read on public.tender_committees;
create policy tender_committees_auth_read on public.tender_committees
  for select using (auth.role() = 'authenticated');

-- 4. ── Executive needs to READ the unsold-tender data + bids to list them ───
--  (mirrors the valuation grants) so the DG page can compute the ≥4× packages.
drop policy if exists executive_read_all on public.tender_sales;
create policy executive_read_all on public.tender_sales
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.tender_sale_items;
create policy executive_read_all on public.tender_sale_items
  for select using (public.auth_user_is_executive());

-- 5. ── Realtime: publish so the committee live-updates across portals ────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'tender_committees'
  ) then
    alter publication supabase_realtime add table public.tender_committees;
  end if;
end $$;
