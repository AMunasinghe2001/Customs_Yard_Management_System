-- ============================================================================
--  Valuation Directorate role + mandatory valuation gate on disposal requests
--  Run after 20260613_appeal_directorate.sql and 20260611_disposal_requests.sql.
--
--  Adds a fifth institutional role, `valuation` (Valuation Directorate),
--  modelled on the appeal (and disposal) role: cross-yard READ access, OTP
--  login, two positions (DC / SDDC).
--
--  Flow change: a yard's Disposal Request now lands in the Valuation
--  Directorate FIRST. Valuation enters a cost per package item and FORWARDS the
--  request to the Central Disposal Directorate, which only sees forwarded
--  requests (and can read the valuation cost). Mandatory gate.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

-- 1. ── Allow the new role ───────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'officer', 'disposal', 'appeal', 'valuation'));

-- 2. ── Helper: is the caller a Valuation Directorate user? ───────────────────
create or replace function public.auth_user_is_valuation()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'valuation'
  );
$$;

-- 3. ── Cross-yard READ access for valuation users (SELECT only) ──────────────
--    Each policy drop+create takes a brief ACCESS EXCLUSIVE lock on its table.
--    If the app is live and holding ACCESS SHARE locks (realtime / queries),
--    one big multi-table transaction can DEADLOCK. So: fail fast on contention
--    (lock_timeout) and do each table as its OWN statement, so a lock is taken
--    and released one table at a time rather than all held together.
--    ➜ If this still errors with "deadlock"/"lock timeout", close the app and
--      re-run (it's idempotent).
set lock_timeout = '5s';

drop policy if exists valuation_read_all on public.packages;
create policy valuation_read_all on public.packages
  for select using (public.auth_user_is_valuation());

drop policy if exists valuation_read_all on public.package_items;
create policy valuation_read_all on public.package_items
  for select using (public.auth_user_is_valuation());

drop policy if exists valuation_read_all on public.warehouse_entries;
create policy valuation_read_all on public.warehouse_entries
  for select using (public.auth_user_is_valuation());

drop policy if exists valuation_read_all on public.forfeited_packages;
create policy valuation_read_all on public.forfeited_packages
  for select using (public.auth_user_is_valuation());

drop policy if exists valuation_read_all on public.disposal_requests;
create policy valuation_read_all on public.disposal_requests
  for select using (public.auth_user_is_valuation());

drop policy if exists valuation_read_all on public.disposal_request_items;
create policy valuation_read_all on public.disposal_request_items
  for select using (public.auth_user_is_valuation());

-- Valuation users can also read profiles across yards (dashboard name lookups).
drop policy if exists valuation_read_profiles on public.profiles;
create policy valuation_read_profiles on public.profiles
  for select using (public.auth_user_is_valuation());

reset lock_timeout;

-- 4. ── Limit to one DC and one SDDC valuation account ────────────────────────
create or replace function public.valuation_position_available(code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'valuation' and lower(username) = lower(code)
  );
$$;

grant execute on function public.valuation_position_available(text) to anon, authenticated;

-- 5. ── Valuation columns on the disposal-request tables ──────────────────────
--    valuation_status gates whether Central Disposal can see a request:
--      'pending_valuation' → only the Valuation Directorate sees it,
--      'forwarded'         → released to the Central Disposal Directorate.
alter table public.disposal_requests
  add column if not exists valuation_status text not null default 'pending_valuation',
  add column if not exists valued_at        timestamptz,
  add column if not exists valued_by        uuid references public.profiles(id);

alter table public.disposal_requests drop constraint if exists disposal_requests_valuation_status_check;
alter table public.disposal_requests
  add constraint disposal_requests_valuation_status_check
  check (valuation_status in ('pending_valuation', 'forwarded'));

-- Per-item valuation cost (null until the Valuation Directorate sets it).
alter table public.disposal_request_items
  add column if not exists valuation_cost numeric;

create index if not exists idx_disposal_requests_valuation_status
  on public.disposal_requests(valuation_status);

-- One-shot flags so re-runnable migrations can do "first run only" work. Tiny,
-- generic, and reused by future backfills.
create table if not exists public.app_migration_flags (
  flag       text primary key,
  applied_at timestamptz not null default now()
);

-- Backfill: every request that PRE-DATES this feature is treated as already
-- forwarded, so it keeps showing in Central Disposal (no regression). Only
-- requests created AFTER this migration default to 'pending_valuation' and must
-- pass through the Valuation Directorate.
--
-- ⚠️ Idempotency guard: this migration is documented as "safe to re-run", and an
-- UNCONDITIONAL backfill would re-forward EVERY request on each re-run — including
-- legitimate new ones still awaiting valuation, making them silently vanish from
-- the Valuation dashboard. To run the backfill exactly ONCE we record a sentinel
-- the first time and skip the UPDATE on every subsequent run.
do $$
begin
  if not exists (
    select 1 from public.app_migration_flags
    where flag = 'valuation_directorate_backfilled'
  ) then
    update public.disposal_requests
       set valuation_status = 'forwarded',
           valued_at = coalesce(valued_at, created_at);
    insert into public.app_migration_flags(flag) values ('valuation_directorate_backfilled');
  end if;
end $$;

-- 6. ── RPC: set per-item costs, optionally forward (Valuation only) ──────────
--    p_costs is a JSON object mapping disposal_request_items.id → numeric cost.
--    SECURITY DEFINER → the valuation role needs no broad UPDATE grant. Mirrors
--    set_appeal_hold. Forwarding requires every item to have a cost.
create or replace function public.valuation_set_costs(
  p_request_id uuid,
  p_costs      jsonb default '{}'::jsonb,
  p_forward    boolean default false
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  k text;
  v_missing int;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  if not exists (select 1 from public.disposal_requests where id = p_request_id) then
    raise exception 'disposal request not found';
  end if;

  -- Apply the per-item costs (only rows belonging to this request).
  for k in select jsonb_object_keys(coalesce(p_costs, '{}'::jsonb))
  loop
    update public.disposal_request_items
       set valuation_cost = (p_costs ->> k)::numeric
     where id = k::uuid
       and request_id = p_request_id;
  end loop;

  if p_forward then
    -- Every line item must have a cost before the request can be forwarded.
    select count(*) into v_missing
      from public.disposal_request_items
     where request_id = p_request_id
       and valuation_cost is null;
    if v_missing > 0 then
      raise exception 'valuation_incomplete';
    end if;

    update public.disposal_requests
       set valuation_status = 'forwarded',
           valued_at = now(),
           valued_by = auth.uid()
     where id = p_request_id;
  end if;
end;
$$;

grant execute on function public.valuation_set_costs(uuid, jsonb, boolean) to authenticated;

-- Done.