-- ============================================================================
--  Yard → Central Disposal "Disposal Requests"
--  Run after 20260610_disposal_directorate.sql / 20260610_disposal_forfeited.sql
--
--  A yard submits a request for items whose 30-day appeal window has passed.
--  Each request groups several forfeited packages, and every package in the
--  request is tagged for either DESTRUCTION or SALE. The Central Disposal
--  Directorate reads every yard's requests (cross-yard) on a dedicated page;
--  each request stays a separate, per-yard record.
-- ============================================================================

-- 1. ── Request header (one per submission, scoped to a yard) ─────────────────
create table if not exists public.disposal_requests (
  id           uuid primary key default uuid_generate_v4(),
  yard         text not null,
  request_date date not null,
  status       text not null default 'pending', -- pending | reviewed
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);

create index if not exists idx_disposal_requests_yard on public.disposal_requests(yard);
create index if not exists idx_disposal_requests_created_at on public.disposal_requests(created_at);

-- 2. ── Request line items (one per forfeited package) ────────────────────────
create table if not exists public.disposal_request_items (
  id                   uuid primary key default uuid_generate_v4(),
  request_id           uuid not null references public.disposal_requests(id) on delete cascade,
  forfeited_package_id uuid not null references public.forfeited_packages(id) on delete cascade,
  disposition          text not null check (disposition in ('destruction', 'sale')),
  created_at           timestamptz not null default now()
);

create index if not exists idx_disposal_request_items_request on public.disposal_request_items(request_id);
create index if not exists idx_disposal_request_items_forfeited on public.disposal_request_items(forfeited_package_id);

alter table public.disposal_requests       enable row level security;
alter table public.disposal_request_items  enable row level security;

-- 3. ── RLS: a yard manages its own requests; disposal reads them all ─────────
-- Header: the owning yard can do everything with its own rows.
drop policy if exists disposal_requests_yard on public.disposal_requests;
create policy disposal_requests_yard on public.disposal_requests
  for all
  using (yard = (select yard from public.profiles where id = auth.uid()))
  with check (yard = (select yard from public.profiles where id = auth.uid()));

-- Header: Central Disposal Directorate reads every yard's requests.
drop policy if exists disposal_requests_read_all on public.disposal_requests;
create policy disposal_requests_read_all on public.disposal_requests
  for select using (public.auth_user_is_disposal());

-- Items: scoped through the parent request's yard.
drop policy if exists disposal_request_items_yard on public.disposal_request_items;
create policy disposal_request_items_yard on public.disposal_request_items
  for all
  using (exists (
    select 1 from public.disposal_requests r
    where r.id = request_id
      and r.yard = (select yard from public.profiles where id = auth.uid())
  ))
  with check (exists (
    select 1 from public.disposal_requests r
    where r.id = request_id
      and r.yard = (select yard from public.profiles where id = auth.uid())
  ));

-- Items: Central Disposal Directorate reads every yard's items.
drop policy if exists disposal_request_items_read_all on public.disposal_request_items;
create policy disposal_request_items_read_all on public.disposal_request_items
  for select using (public.auth_user_is_disposal());

-- Done.
