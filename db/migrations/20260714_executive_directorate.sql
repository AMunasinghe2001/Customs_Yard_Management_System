-- ============================================================================
--  Executive Office role (DG / ADG) — Customs' two highest posts.
--  Run after 20260617_valuation_directorate.sql.
--
--  Adds a 6th institutional role, `executive`, modelled on the `valuation`
--  directorate: cross-yard READ access, OTP login/signup, two positions
--  (DG / ADG). The Executive dashboard reuses the Reports hub and scopes each
--  report to a yard the DG/ADG picks — but they must be able to READ every
--  yard, hence the cross-yard SELECT policies below.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

-- 1. ── Allow the new role ───────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'officer', 'disposal', 'appeal', 'valuation', 'executive'));

-- 2. ── Helper: is the caller an Executive Office user? ───────────────────────
create or replace function public.auth_user_is_executive()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'executive'
  );
$$;

-- 3. ── Cross-yard READ access for executive users (SELECT only) ──────────────
--    One statement per table (each takes a brief ACCESS EXCLUSIVE lock) with a
--    short lock_timeout, to avoid deadlocking against a live app. If a table
--    below does not exist in your schema, remove that one line and re-run.
--    ➜ On "deadlock"/"lock timeout": close the app and re-run (idempotent).
set lock_timeout = '5s';

drop policy if exists executive_read_all on public.packages;
create policy executive_read_all on public.packages
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.package_items;
create policy executive_read_all on public.package_items
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.warehouse_entries;
create policy executive_read_all on public.warehouse_entries
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.warehouses;
create policy executive_read_all on public.warehouses
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.forfeited_packages;
create policy executive_read_all on public.forfeited_packages
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.disposal_requests;
create policy executive_read_all on public.disposal_requests
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.disposal_request_items;
create policy executive_read_all on public.disposal_request_items
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.package_categories;
create policy executive_read_all on public.package_categories
  for select using (public.auth_user_is_executive());

drop policy if exists executive_read_all on public.storage_rates;
create policy executive_read_all on public.storage_rates
  for select using (public.auth_user_is_executive());

-- Executive users can also read profiles across yards (report name lookups).
drop policy if exists executive_read_profiles on public.profiles;
create policy executive_read_profiles on public.profiles
  for select using (public.auth_user_is_executive());

reset lock_timeout;

-- 4. ── Limit to one DG and one ADG executive account ─────────────────────────
create or replace function public.executive_position_available(code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'executive' and lower(username) = lower(code)
  );
$$;

grant execute on function public.executive_position_available(text) to anon, authenticated;
