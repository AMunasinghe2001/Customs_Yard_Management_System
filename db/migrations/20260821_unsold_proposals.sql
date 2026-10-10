-- ============================================================================
--  Unsold proposals — the FINAL outcome the High Panel decides for a package
--  that could not be sold by any means.
--
--  A package reaches this point only when every avenue is exhausted:
--    Valuation Tender -> Tender 1 -> Tender 2 -> Tender 3   (all unsold)
--      -> High Panel committee re-values it
--      -> the ADG submits that figure
--      -> it is tendered again
--      -> it STILL does not sell.
--
--  The High Panel then chooses one of: destroy | remand | government_use |
--  auction. Central Disposal and the owning yard both read that decision so
--  they know what to do with the goods.
--
--  One decision per forfeited package, replaceable while it stands.
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

create table if not exists public.unsold_proposals (
  id                   uuid primary key default gen_random_uuid(),
  forfeited_package_id uuid not null unique
                         references public.forfeited_packages(id) on delete cascade,
  -- destroy | remand | government_use | auction
  proposal             text not null
                         check (proposal in
                           ('destroy', 'remand', 'government_use', 'auction')),
  note                 text,
  yard                 text,
  decided_by           uuid references auth.users(id),
  decided_at           timestamptz not null default now(),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists unsold_proposals_fp_idx
  on public.unsold_proposals(forfeited_package_id);
create index if not exists unsold_proposals_yard_idx
  on public.unsold_proposals(yard);

alter table public.unsold_proposals enable row level security;

-- 1. ── High Panel (DG / ADG): they make the decision, so full access ─────────
drop policy if exists unsold_proposals_executive_all on public.unsold_proposals;
create policy unsold_proposals_executive_all on public.unsold_proposals
  for all
  using (public.auth_user_is_executive())
  with check (public.auth_user_is_executive());

-- 2. ── Central Disposal: read-only (they carry the decision out) ─────────────
drop policy if exists unsold_proposals_disposal_read on public.unsold_proposals;
create policy unsold_proposals_disposal_read on public.unsold_proposals
  for select using (public.auth_user_is_disposal());

-- 3. ── The owning yard: read-only, own yard only ─────────────────────────────
drop policy if exists unsold_proposals_yard_read on public.unsold_proposals;
create policy unsold_proposals_yard_read on public.unsold_proposals
  for select
  using (yard = (select yard from public.profiles where id = auth.uid()));

-- 4. ── Valuation / Appeal: read-only context ─────────────────────────────────
drop policy if exists unsold_proposals_valuation_read on public.unsold_proposals;
create policy unsold_proposals_valuation_read on public.unsold_proposals
  for select using (public.auth_user_is_valuation());

drop policy if exists unsold_proposals_appeal_read on public.unsold_proposals;
create policy unsold_proposals_appeal_read on public.unsold_proposals
  for select using (public.auth_user_is_appeal());

-- 5. ── Realtime, so a decision propagates to every open portal ───────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'unsold_proposals'
  ) then
    alter publication supabase_realtime add table public.unsold_proposals;
  end if;
end $$;

reset lock_timeout;
