-- ============================================================================
--  Multi-yard support for SL Customs SR Management System
--  Run this once in the Supabase SQL editor.
--
--  Adds a `yard` column to every data table, backfills existing rows to the
--  default yard (GL1 / Grey Line 1), and enables Row-Level Security so each
--  signed-in user can only see/modify rows belonging to their own yard.
--
--  Yard codes: GL1, GL2, RCT, BQ, JCT, NNR, CVT
-- ============================================================================

-- 1. ── Add the yard column everywhere ──────────────────────────────────────
alter table public.profiles          add column if not exists yard text;
alter table public.packages          add column if not exists yard text;
alter table public.package_items     add column if not exists yard text;
alter table public.warehouse_entries add column if not exists yard text;
alter table public.forfeited_packages add column if not exists yard text;
alter table public.tenders           add column if not exists yard text;
alter table public.tender_disposals  add column if not exists yard text;
alter table public.audit_logs        add column if not exists yard text;

-- 2. ── Backfill existing data to Grey Line 1 ───────────────────────────────
update public.profiles          set yard = 'GL1' where yard is null;
update public.packages          set yard = 'GL1' where yard is null;
update public.package_items     set yard = 'GL1' where yard is null;
update public.warehouse_entries set yard = 'GL1' where yard is null;
update public.forfeited_packages set yard = 'GL1' where yard is null;
update public.tenders           set yard = 'GL1' where yard is null;
update public.tender_disposals  set yard = 'GL1' where yard is null;
update public.audit_logs        set yard = 'GL1' where yard is null;

-- 3. ── Default + helper to read the current user's yard ────────────────────
alter table public.profiles alter column yard set default 'GL1';

create or replace function public.auth_user_yard()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select yard from public.profiles where id = auth.uid();
$$;

-- 4. ── Enable RLS and add per-yard policies ────────────────────────────────
--    Each policy restricts rows to the caller's yard. A user can always read
--    their own profile row; data tables are fully yard-scoped.

-- profiles: a user sees profiles in their own yard (and always their own row)
alter table public.profiles enable row level security;
drop policy if exists yard_profiles_select on public.profiles;
create policy yard_profiles_select on public.profiles
  for select using (id = auth.uid() or yard = public.auth_user_yard());
drop policy if exists yard_profiles_update on public.profiles;
create policy yard_profiles_update on public.profiles
  for update using (id = auth.uid());
drop policy if exists yard_profiles_insert on public.profiles;
create policy yard_profiles_insert on public.profiles
  for insert with check (id = auth.uid());

-- Generic per-yard policy generator for the data tables
do $$
declare t text;
begin
  foreach t in array array[
    'packages','package_items','warehouse_entries',
    'forfeited_packages','tenders','tender_disposals','audit_logs'
  ]
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists yard_all on public.%I;', t);
    execute format($f$
      create policy yard_all on public.%I
        for all
        using (yard = public.auth_user_yard())
        with check (yard = public.auth_user_yard());
    $f$, t);
  end loop;
end $$;

-- 5. ── Shared reference tables stay global (NOT yard-scoped) ───────────────
--    hold_reasons and package_categories are shared lookups; leave as-is.

-- Done.
