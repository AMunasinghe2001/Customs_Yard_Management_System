-- ============================================================================
--  Tax configuration for the Central Disposal Directorate (Taxes tab).
--  Stores named tax rates (e.g. VAT 18%) applied to disposal/tender sales.
-- ============================================================================

create table if not exists public.disposal_taxes (
  id         uuid primary key default uuid_generate_v4(),
  name       text not null,
  percentage numeric(6,2) not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.disposal_taxes enable row level security;

-- Central Disposal Directorate manages tax config; everyone authenticated can
-- read it (rates may be displayed/applied elsewhere).
drop policy if exists disposal_taxes_manage on public.disposal_taxes;
create policy disposal_taxes_manage on public.disposal_taxes
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

drop policy if exists disposal_taxes_read on public.disposal_taxes;
create policy disposal_taxes_read on public.disposal_taxes
  for select
  using (auth.role() = 'authenticated');

-- Done.
