-- ============================================================================
--  Strict per-yard isolation for SL Customs SR Management System
--  Run this once in the Supabase SQL editor, AFTER 001_multi_yard.sql.
--
--  Every user — administrators included — can only see and modify rows that
--  belong to the single yard they registered with. There is NO cross-yard
--  access for anyone. This migration re-asserts the strict policies from 001
--  (so it is safe to run even if an earlier "admin cross-yard" policy was
--  applied) and removes the admin-bypass helper if it exists.
--
--  Yard codes: GL1, GL2, RCT, BQ, JCT, NNR, CVT
-- ============================================================================

-- 1. ── Profiles: own row + same-yard profiles only (no admin bypass) ───────
alter table public.profiles enable row level security;

drop policy if exists yard_profiles_select on public.profiles;
create policy yard_profiles_select on public.profiles
  for select using (id = sr_auth.uid() or yard = public.auth_user_yard());

drop policy if exists yard_profiles_update on public.profiles;
create policy yard_profiles_update on public.profiles
  for update using (id = sr_auth.uid());

drop policy if exists yard_profiles_insert on public.profiles;
create policy yard_profiles_insert on public.profiles
  for insert with check (id = sr_auth.uid());

-- 2. ── Data tables: caller's yard only, for every role ─────────────────────
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

-- 3. ── Drop the admin-bypass helper (no longer used) ───────────────────────
drop function if exists public.auth_user_is_admin();

-- Done.
