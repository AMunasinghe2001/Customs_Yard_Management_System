-- ============================================================================
--  Central Disposal Directorate role + Tender Sales
--  Run this once in the Supabase SQL editor (after the earlier migrations).
--
--  Adds a third role, `disposal` (Central Disposal Directorate), which — unlike
--  officers/admins — can read SOLD packages across ALL yards (the rest of the
--  app stays strictly yard-isolated). Also adds the `tender_sales` table for
--  the Tender Sale form.
-- ============================================================================

-- 1. ── Allow the new role ───────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'officer', 'disposal'));

-- 2. ── Helper: is the caller a Central Disposal Directorate user? ───────────
create or replace function public.auth_user_is_disposal()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'disposal'
  );
$$;

-- 3. ── Cross-yard READ access for disposal users ────────────────────────────
--    These are permissive SELECT policies that sit alongside the strict
--    per-yard `yard_all` policies (policies are OR-ed), so a disposal user can
--    read every yard's rows while everyone else stays yard-scoped.
do $$
declare t text;
begin
  foreach t in array array['packages', 'package_items', 'warehouse_entries']
  loop
    execute format('drop policy if exists disposal_read_all on public.%I;', t);
    execute format(
      'create policy disposal_read_all on public.%I for select using (public.auth_user_is_disposal());',
      t);
  end loop;
end $$;

-- Disposal users can also read profiles across yards (so "sold by" names show).
drop policy if exists disposal_read_profiles on public.profiles;
create policy disposal_read_profiles on public.profiles
  for select using (public.auth_user_is_disposal());

-- 4. ── Tender Sales ─────────────────────────────────────────────────────────
create table if not exists public.tender_sales (
  id           uuid primary key default uuid_generate_v4(),
  sale_number  text,
  sale_date    date,
  serial       text,
  year         int,
  tender_type  text, -- 'special' | 'general_cargo' | 'motor_vehicle'
  yard         text,
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);

alter table public.tender_sales enable row level security;

-- Disposal users and admins manage tender sales.
drop policy if exists tender_sales_manage on public.tender_sales;
create policy tender_sales_manage on public.tender_sales
  for all
  using (
    public.auth_user_is_disposal()
    or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  )
  with check (
    public.auth_user_is_disposal()
    or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- 5. ── Limit to one DC and one SDDC account ─────────────────────────────────
--    Anon-callable check so the signup screen can block a duplicate position
--    before emailing an OTP. Hard uniqueness is also enforced by the
--    profiles_username_lower_idx index (usernames 'dc' / 'sddc').
create or replace function public.disposal_position_available(code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'disposal' and lower(username) = lower(code)
  );
$$;

grant execute on function public.disposal_position_available(text) to anon, authenticated;

-- Done.
