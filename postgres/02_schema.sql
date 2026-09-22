-- ============================================================================
--  02 · Schema — every table, function, policy and trigger
--
--  GENERATED. Do not edit by hand: it is the base schema followed by all
--  80 migrations in date order, exactly as they were applied to Supabase.
--  Regenerate with scratchpad/build_schema.py after adding a migration.
--
--  Why stitched rather than consolidated: the migrations ARE the source of
--  truth, and they are idempotent and ordered. Hand-writing a single flat
--  schema would mean re-deriving 88 ALTERs, and one slip there is a column
--  silently missing in production.
--
--  Run AFTER 01_auth_and_session.sql — the migrations reference sr_auth.uid(),
--  sr_auth.users and the supabase_realtime publication, all of which that file
--  provides.
--
--  Safe to re-run: every statement is guarded (if not exists / or replace /
--  drop policy if exists).
-- ============================================================================

set client_min_messages = warning;

-- ==========================================================================
--  BASE SCHEMA (db/schema.sql)
-- ==========================================================================

-- ================================================================
-- Sri Lanka Customs Yard Management System - Supabase Schema
-- Run this in Supabase SQL Editor
-- ================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------
-- PROFILES (Officers & Admins linked to Supabase Auth)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES sr_auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  badge_number TEXT UNIQUE,
  role TEXT NOT NULL DEFAULT 'officer' CHECK (role IN ('admin', 'officer')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- WAREHOUSES (SR Unit - 3 warehouses, seeded)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS warehouses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  code TEXT NOT NULL UNIQUE,
  description TEXT,
  location TEXT,
  capacity INTEGER DEFAULT 500,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed the 3 SR Unit warehouses
INSERT INTO warehouses (name, code, description, location) VALUES
  ('SR Warehouse 01', 'SR-W01', 'SR Unit Primary Warehouse', 'SR Unit, Colombo Port'),
  ('SR Warehouse 02', 'SR-W02', 'SR Unit Secondary Warehouse', 'SR Unit, Colombo Port'),
  ('SR Warehouse 03', 'SR-W03', 'SR Unit Tertiary Warehouse', 'SR Unit, Colombo Port')
  ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------
-- PACKAGES (Incoming international packages)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS packages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sr_number TEXT NOT NULL UNIQUE,
  case_number TEXT,
  origin_country TEXT,
  declared_value NUMERIC(12,2) DEFAULT 0,
  weight_kg NUMERIC(8,3) DEFAULT 0,
  total_item_count INTEGER DEFAULT 1,
  description TEXT,
  container_number TEXT,
  consignee_name TEXT NOT NULL,
  consignee_nic TEXT,
  consignee_address TEXT,
  consignee_phone TEXT,
  declarant_name TEXT,
  cusdec_no TEXT,
  cusdec_date TEXT,
  entry_date TIMESTAMPTZ,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  inspected_by UUID REFERENCES profiles(id),
  inspected_at TIMESTAMPTZ,
  cleared_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- PACKAGE ITEMS (Individual items inside each package)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS package_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  package_id UUID NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
  item_name TEXT NOT NULL,
  goods_description TEXT,
  quantity INTEGER NOT NULL DEFAULT 1,
  unit_of_measure TEXT NOT NULL DEFAULT 'Pieces',
  unit_other TEXT,
  unit_value NUMERIC(10,2) DEFAULT 0,
  hs_code TEXT,
  category TEXT,
  is_prohibited BOOLEAN DEFAULT false,
  status TEXT NOT NULL DEFAULT 'Detain',
  reasons TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- WAREHOUSE ENTRIES (Package → Warehouse tracking)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS warehouse_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  package_id UUID NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
  warehouse_id UUID NOT NULL REFERENCES warehouses(id),
  hold_reason TEXT NOT NULL,
  item_count INTEGER NOT NULL DEFAULT 1,
  admitted_by UUID REFERENCES profiles(id),
  admitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_returned BOOLEAN NOT NULL DEFAULT false,
  returned_at TIMESTAMPTZ,
  returned_by UUID REFERENCES profiles(id),
  return_notes TEXT,
  daily_rate NUMERIC(12,2) DEFAULT 0,
  accumulated_storage_charge NUMERIC(12,2) DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------
-- CUSTOMS RULES (Admin-configurable clearance rules)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customs_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rule_name TEXT NOT NULL,
  rule_type TEXT NOT NULL CHECK (rule_type IN ('max_value', 'max_weight', 'prohibited_category', 'max_items', 'custom')),
  threshold_value NUMERIC(12,2),
  string_value TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  description TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default customs rules
INSERT INTO customs_rules (rule_name, rule_type, threshold_value, description) VALUES
  ('Maximum Declared Value', 'max_value', 75000.00, 'Packages with declared value over LKR 75,000 must be held'),
  ('Maximum Weight', 'max_weight', 30.00, 'Packages over 30 kg must be held for inspection'),
  ('Maximum Item Count', 'max_items', 50, 'Packages with more than 50 items must be held')
  ON CONFLICT DO NOTHING;

INSERT INTO customs_rules (rule_name, rule_type, string_value, description) VALUES
  ('Prohibited: Firearms', 'prohibited_category', 'firearms', 'Firearms and related accessories are prohibited'),
  ('Prohibited: Narcotics', 'prohibited_category', 'narcotics', 'All narcotics and illegal drugs are prohibited'),
  ('Prohibited: Explosives', 'prohibited_category', 'explosives', 'Explosives and related items are prohibited')
  ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------
-- ROW LEVEL SECURITY POLICIES
-- ----------------------------------------------------------------

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE package_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouse_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE customs_rules ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read their own profile
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (sr_auth.uid() = id);

DROP POLICY IF EXISTS "Admins can manage all profiles" ON profiles;
CREATE POLICY "Admins can manage all profiles" ON profiles
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role = 'admin')
  );

-- Packages - all officers can view and create
DROP POLICY IF EXISTS "Officers can view all packages" ON packages;
CREATE POLICY "Officers can view all packages" ON packages
  FOR SELECT USING (sr_auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Officers can create packages" ON packages;
CREATE POLICY "Officers can create packages" ON packages
  FOR INSERT WITH CHECK (sr_auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Officers can update packages" ON packages;
CREATE POLICY "Officers can update packages" ON packages
  FOR UPDATE USING (sr_auth.role() = 'authenticated');

-- Package items - linked to packages
DROP POLICY IF EXISTS "Officers can manage package items" ON package_items;
CREATE POLICY "Officers can manage package items" ON package_items
  FOR ALL USING (sr_auth.role() = 'authenticated');

-- Warehouses - read for all, write for admins
DROP POLICY IF EXISTS "All can view warehouses" ON warehouses;
CREATE POLICY "All can view warehouses" ON warehouses
  FOR SELECT USING (sr_auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admins can manage warehouses" ON warehouses;
CREATE POLICY "Admins can manage warehouses" ON warehouses
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role = 'admin')
  );

-- Warehouse entries - all officers
DROP POLICY IF EXISTS "Officers can manage warehouse entries" ON warehouse_entries;
CREATE POLICY "Officers can manage warehouse entries" ON warehouse_entries
  FOR ALL USING (sr_auth.role() = 'authenticated');

-- Customs rules - read for all, write for admins
DROP POLICY IF EXISTS "All can view customs rules" ON customs_rules;
CREATE POLICY "All can view customs rules" ON customs_rules
  FOR SELECT USING (sr_auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admins can manage customs rules" ON customs_rules;
CREATE POLICY "Admins can manage customs rules" ON customs_rules
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role = 'admin')
  );

-- ----------------------------------------------------------------
-- HELPER FUNCTIONS & TRIGGERS
-- ----------------------------------------------------------------

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_packages_updated_at ON packages;
CREATE TRIGGER update_packages_updated_at BEFORE UPDATE ON packages
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_warehouse_entries_updated_at ON warehouse_entries;
CREATE TRIGGER update_warehouse_entries_updated_at BEFORE UPDATE ON warehouse_entries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_profiles_updated_at ON profiles;
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'officer')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON sr_auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON sr_auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ----------------------------------------------------------------
-- USEFUL VIEWS
-- ----------------------------------------------------------------

CREATE OR REPLACE VIEW warehouse_contents AS
SELECT
  we.id AS entry_id,
  w.name AS warehouse_name,
  w.code AS warehouse_code,
  p.sr_number,
  p.origin_country,
  p.consignee_name,
  p.total_item_count,
  we.item_count AS held_item_count,
  we.hold_reason,
  we.admitted_at,
  we.is_returned,
  we.returned_at,
  adm.full_name AS admitted_by_name,
  ret.full_name AS returned_by_name
FROM warehouse_entries we
JOIN warehouses w ON we.warehouse_id = w.id
JOIN packages p ON we.package_id = p.id
LEFT JOIN profiles adm ON we.admitted_by = adm.id
LEFT JOIN profiles ret ON we.returned_by = ret.id;

-- Dashboard stats view
CREATE OR REPLACE VIEW daily_stats AS
SELECT
  DATE(created_at) AS stat_date,
  COUNT(*) FILTER (WHERE status = 'cleared') AS cleared_count,
  COUNT(*) FILTER (WHERE status = 'held') AS held_count,
  COUNT(*) AS total_count,
  SUM(declared_value) FILTER (WHERE status = 'cleared') AS cleared_value
FROM packages
GROUP BY DATE(created_at)
ORDER BY stat_date DESC;

-- ⚠️ These two tables were created by hand in the Supabase dashboard and were
-- never written down here, so this file only ever ALTERed them. That went
-- unnoticed for as long as the live database already had them — but it meant
-- the schema could NOT be built from scratch: a fresh
-- `psql -f schema.sql` died at the ALTER below with
-- `relation "package_categories" does not exist`. The definitions are
-- reconstructed here from what the app reads (PackageCategory in
-- lib/models/models.dart) and from the ALTERs that follow.
CREATE TABLE IF NOT EXISTS package_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ⚠️ The column is `reason_text`, not `name`. Nothing in this repo ever
-- created this table (it was made in the Supabase dashboard), so the shape
-- here is taken from the live database rather than guessed.
CREATE TABLE IF NOT EXISTS hold_reasons (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reason_text TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Same story: made in the dashboard, never written down. Columns follow
-- AuditLogModel (lib/models/models.dart) and AuditLogService.recordLog.
-- `yard` is added later by the multi-yard migration, so it is not here.
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- The log is read newest-first, filtered to the last year (see
-- purge_old_audit_logs), so this is the index that query needs.
CREATE INDEX IF NOT EXISTS audit_logs_created_at_idx
  ON audit_logs (created_at DESC);

-- The warehouse storage charge, kept as a HISTORY rather than a single value:
-- a package accrues at whichever rate was in force on each day, so changing
-- the rate must not rewrite what older packages already owe. The app reads the
-- whole table ordered by effective_from and picks per-day (storageRateProvider).
CREATE TABLE IF NOT EXISTS storage_rates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rate NUMERIC(12,2) NOT NULL,
  effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS storage_rates_effective_from_idx
  ON storage_rates (effective_from DESC);

-- Guarded because the CREATEs above already run on a fresh database, while an
-- existing one reaches here with the columns long since added.
ALTER TABLE package_categories ADD COLUMN IF NOT EXISTS target_warehouse_id UUID REFERENCES warehouses(id);
ALTER TABLE package_categories ADD COLUMN IF NOT EXISTS target_zone TEXT;

ALTER TABLE warehouse_entries ADD COLUMN IF NOT EXISTS zone TEXT;

ALTER TABLE hold_reasons ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE hold_reasons ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- ⚠️ Online presence — added in the Supabase dashboard and never written down,
-- like the four tables above. The app writes both on every sign-in, heartbeat
-- and sign-out (AuthService.updateHeartbeat / setUserOffline) and reads them
-- for the "Online in <yard>" panel on the dashboard. Without them each of
-- those writes failed with 42703; the failure is caught and logged, so
-- sign-in still worked while the presence list stayed permanently empty.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT false;
-- Nulled (not just stale) on sign-out, so the heartbeat-based list drops the
-- user instantly instead of holding them online for ~90s.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;
ALTER TABLE warehouse_entries ADD COLUMN IF NOT EXISTS package_item_id UUID REFERENCES package_items(id) ON DELETE CASCADE;


-- ==========================================================================
--  20260327_split_items_to_warehouses.sql
-- ==========================================================================


-- Update warehouse_entries to support individual items and zones
ALTER TABLE warehouse_entries ADD COLUMN IF NOT EXISTS package_item_id UUID REFERENCES package_items(id) ON DELETE CASCADE;
ALTER TABLE warehouse_entries ADD COLUMN IF NOT EXISTS zone TEXT;

-- Migration: If there are existing entries, they might not be linked to specific items.
-- We keep them linked to the package overall, which is fine for backward compatibility.


-- ==========================================================================
--  20260403_add_profile_fields.sql
-- ==========================================================================

alter table profiles
  add column if not exists mobile_number text,
  add column if not exists job_role text,
  add column if not exists department text,
  add column if not exists profile_image_url text;


-- ==========================================================================
--  20260527_add_warehouse_admin_policy.sql
-- ==========================================================================

-- Add RLS policy for admins to manage warehouses
-- This fixes the "row-level security policy" error when adding/editing warehouses

DROP POLICY IF EXISTS "Admins can manage warehouses" ON warehouses;
CREATE POLICY "Admins can manage warehouses" ON warehouses
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role = 'admin')
  );


-- ==========================================================================
--  20260528_add_forfeited_packages_and_tenders.sql
-- ==========================================================================

-- ================================================================
-- Forfeited Packages & Tenders Management
-- ================================================================

-- ────────────────────────────────────────────────────────────────
-- FORFEITED_PACKAGES Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS forfeited_packages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  package_id UUID NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
  sr_number TEXT NOT NULL,
  consignee_name TEXT NOT NULL,
  forfeited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  appeal_deadline TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_forfeited_packages_package_id ON forfeited_packages(package_id);
CREATE INDEX IF NOT EXISTS idx_forfeited_packages_appeal_deadline ON forfeited_packages(appeal_deadline);

-- ────────────────────────────────────────────────────────────────
-- TENDERS Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tenders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tender_number TEXT NOT NULL UNIQUE,
  tender_date TIMESTAMPTZ NOT NULL,
  forfeited_package_ids TEXT[] NOT NULL, -- JSON array of package IDs
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tenders_tender_date ON tenders(tender_date);
CREATE INDEX IF NOT EXISTS idx_tenders_created_by ON tenders(created_by);

-- ────────────────────────────────────────────────────────────────
-- TENDER_DISPOSALS Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tender_disposals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tender_package_id TEXT NOT NULL,
  forfeited_package_id UUID NOT NULL REFERENCES forfeited_packages(id) ON DELETE CASCADE,
  disposal_type TEXT NOT NULL CHECK (disposal_type IN ('sold', 're_export', 'govt_use', 'destroy', 'other')),
  receipt_number TEXT, -- For 'sold' disposals
  other_details TEXT, -- For 'other' disposals
  disposed_by UUID REFERENCES profiles(id),
  disposed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tender_disposals_tender_package_id ON tender_disposals(tender_package_id);
CREATE INDEX IF NOT EXISTS idx_tender_disposals_forfeited_package_id ON tender_disposals(forfeited_package_id);

-- ────────────────────────────────────────────────────────────────
-- ENABLE RLS
-- ────────────────────────────────────────────────────────────────
ALTER TABLE forfeited_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenders ENABLE ROW LEVEL SECURITY;
ALTER TABLE tender_disposals ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "All authenticated users can view forfeited packages" ON forfeited_packages;
CREATE POLICY "All authenticated users can view forfeited packages" ON forfeited_packages
  FOR SELECT USING (sr_auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admins can manage forfeited packages" ON forfeited_packages;
CREATE POLICY "Admins can manage forfeited packages" ON forfeited_packages
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "All authenticated users can view tenders" ON tenders;
CREATE POLICY "All authenticated users can view tenders" ON tenders
  FOR SELECT USING (sr_auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admins can create and manage tenders" ON tenders;
CREATE POLICY "Admins can create and manage tenders" ON tenders
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "All authenticated users can view tender disposals" ON tender_disposals;
CREATE POLICY "All authenticated users can view tender disposals" ON tender_disposals
  FOR SELECT USING (sr_auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Admins can manage tender disposals" ON tender_disposals;
CREATE POLICY "Admins can manage tender disposals" ON tender_disposals
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role = 'admin')
  );

-- ────────────────────────────────────────────────────────────────
-- TRIGGERS
-- ────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS update_forfeited_packages_updated_at ON forfeited_packages;
CREATE TRIGGER update_forfeited_packages_updated_at BEFORE UPDATE ON forfeited_packages
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_tenders_updated_at ON tenders;
CREATE TRIGGER update_tenders_updated_at BEFORE UPDATE ON tenders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_tender_disposals_updated_at ON tender_disposals;
CREATE TRIGGER update_tender_disposals_updated_at BEFORE UPDATE ON tender_disposals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ==========================================================================
--  20260601_add_container_and_goods_description.sql
-- ==========================================================================

ALTER TABLE packages
  ADD COLUMN IF NOT EXISTS container_number TEXT;

ALTER TABLE package_items
  ADD COLUMN IF NOT EXISTS goods_description TEXT,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'Detain',
  ADD COLUMN IF NOT EXISTS reasons TEXT;


-- ==========================================================================
--  20260609_officer_username_auth.sql
-- ==========================================================================

-- ============================================================================
--  Officer/Admin username support + username-or-email login + officer OTP flow
--  Run this once in the Supabase SQL editor.
--
--  Adds:
--   1. profiles.username        — unique (case-insensitive) login handle.
--   2. officer_signup_otps      — short-lived OTP store for admin-created
--                                 officers (service_role only).
--   3. email_for_login(text)    — resolves a username OR email to the auth
--                                 email, so the app can sign in with either.
--
--  Used together with the `admin-officers` Edge Function (service_role) which
--  creates the auth user, generates the random username/password and emails
--  the credentials.
-- ============================================================================

-- 1. ── Username column ──────────────────────────────────────────────────────
alter table public.profiles add column if not exists username text;

-- Case-insensitive uniqueness (only enforced for rows that have a usernameල්R).
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username))
  where username is not null;

-- 2. ── OTP store for admin-created officers ─────────────────────────────────
--    Holds the pending officer details + OTP until the admin verifies the code.
--    RLS is enabled with NO policies, so only the service_role key (used by the
--    Edge Function) can read/write it. The anon/authenticated keys cannot.
create table if not exists public.officer_signup_otps (
  email         text primary key,
  otp           text not null,
  full_name     text not null,
  badge_number  text,
  mobile_number text,
  yard          text,
  attempts      int  not null default 0,
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now()
);

alter table public.officer_signup_otps enable row level security;
-- (intentionally no policies — service_role bypasses RLS)

-- 3. ── Resolve a username OR email to the login email ───────────────────────
--    The login screen accepts a single identifier. If it looks like an email
--    we return it as-is; otherwise we look it up by username and return the
--    matching auth email. SECURITY DEFINER so it can read sr_auth.users; granted
--    to anon because login happens before the user is authenticated.
create or replace function public.email_for_login(identifier text)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  found_email text;
begin
  if identifier is null or length(trim(identifier)) = 0 then
    return null;
  end if;

  -- Looks like an email → use directly.
  if position('@' in identifier) > 0 then
    return trim(identifier);
  end if;

  select u.email
    into found_email
  from public.profiles p
  join sr_auth.users u on u.id = p.id
  where lower(p.username) = lower(trim(identifier))
  limit 1;

  return found_email;
end;
$$;

grant execute on function public.email_for_login(text) to anon, authenticated;

-- Done.


-- ==========================================================================
--  20260610_disposal_directorate.sql
-- ==========================================================================

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
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'disposal'
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
    or exists (select 1 from public.profiles where id = sr_auth.uid() and role = 'admin')
  )
  with check (
    public.auth_user_is_disposal()
    or exists (select 1 from public.profiles where id = sr_auth.uid() and role = 'admin')
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
set search_path = public, extensions
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'disposal' and lower(username) = lower(code)
  );
$$;

grant execute on function public.disposal_position_available(text) to anon, authenticated;

-- Done.


-- ==========================================================================
--  20260610_disposal_forfeited.sql
-- ==========================================================================

-- ============================================================================
--  Cross-yard READ access to forfeited_packages for the Central Disposal
--  Directorate. Run after 20260610_disposal_directorate.sql.
--
--  Lets disposal (DC/SDDC) users view forfeited packages across ALL yards
--  (filtered in the UI by a yard dropdown), alongside the strict per-yard
--  `yard_all` policy that keeps everyone else scoped to their own yard.
-- ============================================================================

drop policy if exists disposal_read_all on public.forfeited_packages;
create policy disposal_read_all on public.forfeited_packages
  for select using (public.auth_user_is_disposal());

-- Done.


-- ==========================================================================
--  20260611_tender_sale_items.sql
-- ==========================================================================

-- ============================================================================
--  Tender Sale line items + "mark sold" for the Central Disposal Directorate.
--  Run after 20260611_disposal_requests.sql.
--
--  A Tender Sale now carries the actual packages being sold (only packages a
--  yard tagged "sale" in a disposal request can be added). The Disposal
--  Directorate can later mark each package SOLD; that writes a [FINAL:SOLD]
--  warehouse entry IN THE PACKAGE'S OWN YARD (via a SECURITY DEFINER RPC) so it
--  surfaces in that yard's Warehouses view and the cross-yard Sold Packages tab.
-- ============================================================================

-- 1. ── Line items ───────────────────────────────────────────────────────────
create table if not exists public.tender_sale_items (
  id                   uuid primary key default uuid_generate_v4(),
  tender_sale_id       uuid not null references public.tender_sales(id) on delete cascade,
  forfeited_package_id uuid not null references public.forfeited_packages(id) on delete cascade,
  yard                 text not null,
  sold                 boolean not null default false,
  sold_at              timestamptz,
  receipt_number       text,
  created_at           timestamptz not null default now(),
  unique (forfeited_package_id)
);

create index if not exists idx_tender_sale_items_sale on public.tender_sale_items(tender_sale_id);
create index if not exists idx_tender_sale_items_forfeited on public.tender_sale_items(forfeited_package_id);

alter table public.tender_sale_items enable row level security;

-- Disposal Directorate manages every row; a yard can read its own.
drop policy if exists tender_sale_items_disposal on public.tender_sale_items;
create policy tender_sale_items_disposal on public.tender_sale_items
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

drop policy if exists tender_sale_items_yard_read on public.tender_sale_items;
create policy tender_sale_items_yard_read on public.tender_sale_items
  for select
  using (yard = (select yard from public.profiles where id = sr_auth.uid()));

-- 2. ── Mark a tender-sale package SOLD (cross-yard, security definer) ────────
create or replace function public.disposal_mark_sale_item_sold(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.tender_sale_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  -- For each not-yet-finalised item write a [FINAL:SOLD] entry. The warehouse
  -- context prefers the item's own latest entry but falls back to ANY entry on
  -- the package (entries are often admitted package-level, with no item link).
  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- Nothing item-level was written (no items, or none linkable). Still surface
  -- the sale with one package-level [FINAL:SOLD] entry. Use any package entry;
  -- as a last resort anchor it to any warehouse so it appears in the lists.
  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.tender_sale_items
     set sold = true, sold_at = now(), receipt_number = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260611_delivery_toggle_yard.sql
-- ==========================================================================

-- ============================================================================
--  FIX: allow a yard (not just the Central Disposal Directorate) to toggle the
--  delivery status of its own sold packages from the yard Sold Packages table.
--  Run if you already ran 20260611_tender_sale_sold_price.sql — it only
--  REPLACES disposal_toggle_delivery_status. (Previously yard admins got
--  "not authorized / P0001".)
-- ============================================================================

create or replace function public.disposal_toggle_delivery_status(
  p_item_id uuid,
  p_is_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_yard text;
begin
  select yard into v_yard from public.tender_sale_items where id = p_item_id;
  if v_yard is null then
    raise exception 'tender sale item not found';
  end if;
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;
  update public.tender_sale_items
     set is_delivered = p_is_delivered,
         delivered_at = case when p_is_delivered then now() else null end
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_toggle_delivery_status(uuid, boolean)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260611_disposal_requests.sql
-- ==========================================================================

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
  using (yard = (select yard from public.profiles where id = sr_auth.uid()))
  with check (yard = (select yard from public.profiles where id = sr_auth.uid()));

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
      and r.yard = (select yard from public.profiles where id = sr_auth.uid())
  ))
  with check (exists (
    select 1 from public.disposal_requests r
    where r.id = request_id
      and r.yard = (select yard from public.profiles where id = sr_auth.uid())
  ));

-- Items: Central Disposal Directorate reads every yard's items.
drop policy if exists disposal_request_items_read_all on public.disposal_request_items;
create policy disposal_request_items_read_all on public.disposal_request_items
  for select using (public.auth_user_is_disposal());

-- Done.


-- ==========================================================================
--  20260611_disposal_taxes.sql
-- ==========================================================================

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
  using (sr_auth.role() = 'authenticated');

-- Done.


-- ==========================================================================
--  20260611_taxes_and_delivery.sql
-- ==========================================================================

-- ============================================================================
--  Taxes Configuration and Tender Sale Items updates for Delivery Status
-- ============================================================================

create table if not exists public.disposal_taxes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  percentage numeric(5,2) not null,
  is_active boolean default true,
  created_at timestamptz default now()
);

alter table public.disposal_taxes enable row level security;

DROP POLICY IF EXISTS "authenticated can read disposal taxes" ON public.disposal_taxes;
create policy "authenticated can read disposal taxes"
  on public.disposal_taxes for select
  to authenticated using (true);

DROP POLICY IF EXISTS "disposal users can manage taxes" ON public.disposal_taxes;
create policy "disposal users can manage taxes"
  on public.disposal_taxes for all
  to authenticated
  using (public.auth_user_is_disposal());

-- Add new columns to tender_sale_items
alter table public.tender_sale_items
  add column if not exists sold_price numeric(12,2) default 0.00,
  add column if not exists applied_taxes jsonb default '[]'::jsonb,
  add column if not exists is_delivered boolean default false,
  add column if not exists delivered_at timestamptz;

-- Update the mark sold RPC to save price and taxes
create or replace function public.disposal_mark_sale_item_sold(
  p_item_id uuid,
  p_receipt text default null,
  p_sold_price numeric default 0.00,
  p_applied_taxes jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.tender_sale_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.tender_sale_items
     set sold = true, 
         sold_at = now(), 
         receipt_number = p_receipt,
         sold_price = p_sold_price,
         applied_taxes = p_applied_taxes
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

-- Function to toggle delivery status
create or replace function public.disposal_toggle_delivery_status(
  p_item_id uuid,
  p_is_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.tender_sale_items
     set is_delivered = p_is_delivered,
         delivered_at = case when p_is_delivered then now() else null end
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_toggle_delivery_status(uuid, boolean)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260611_tender_disposal_release.sql
-- ==========================================================================

-- ============================================================================
--  Allow 'release' as a tender-disposal outcome.
--  The yard Tender Disposals "Record Disposal" popup gains a Release option
--  (goods released back to the owner). Widen the CHECK constraint to accept it.
-- ============================================================================

alter table public.tender_disposals
  drop constraint if exists tender_disposals_disposal_type_check;

alter table public.tender_disposals
  add constraint tender_disposals_disposal_type_check
  check (disposal_type in ('sold', 're_export', 'govt_use', 'destroy', 'other', 'release'));

-- Done.


-- ==========================================================================
--  20260611_tender_sale_items_realtime.sql
-- ==========================================================================

-- ============================================================================
--  Enable Supabase Realtime on tender_sale_items so a delivery toggle / new
--  sale made in one session (e.g. a yard marking a package Delivered) shows up
--  live in the Central Disposal Sold Packages table (and vice-versa), instead
--  of staying stale until the page is reopened.
--  Idempotent — safe to run more than once.
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tender_sale_items'
  ) then
    alter publication supabase_realtime add table public.tender_sale_items;
  end if;
end $$;

-- Done.


-- ==========================================================================
--  20260611_tender_sale_mark_sold_fix.sql
-- ==========================================================================

-- ============================================================================
--  FIX: make disposal_mark_sale_item_sold robust.
--  Run this if you already ran 20260611_tender_sale_items.sql (it only
--  REPLACES the function). The earlier version keyed the warehouse context
--  strictly on package_item_id, so packages whose entries are admitted at
--  PACKAGE level (no item link) — or have none — wrote no [FINAL:SOLD] row and
--  never showed up in the Sold Packages / Warehouses views.
--
--  New behaviour: per item, take the item's own latest entry, else ANY entry on
--  the package; if the package has no entries at all, anchor a single
--  package-level SOLD entry to any warehouse so the sale still surfaces.
-- ============================================================================

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.tender_sale_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.tender_sale_items
     set sold = true, sold_at = now(), receipt_number = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260611_tender_sale_sold_price.sql
-- ==========================================================================

-- ============================================================================
--  Tender Sale: sold price + applied taxes + delivery tracking.
--  Run after 20260611_tender_sale_items.sql (and the mark-sold fix).
--
--  The Mark Package Sold dialog now captures a Sold Price and the taxes applied
--  (VAT/PAL…), and packages can be flagged Delivered. This adds the columns and
--  REPLACES disposal_mark_sale_item_sold with a 4-arg version, plus a new
--  disposal_toggle_delivery_status RPC.
-- ============================================================================

-- 1. ── New columns ──────────────────────────────────────────────────────────
alter table public.tender_sale_items
  add column if not exists sold_price    numeric(14,2) not null default 0,
  add column if not exists applied_taxes jsonb         not null default '[]'::jsonb,
  add column if not exists is_delivered  boolean       not null default false,
  add column if not exists delivered_at  timestamptz;

-- 2. ── Mark sold (now also stores sold_price + applied_taxes) ────────────────
drop function if exists public.disposal_mark_sale_item_sold(uuid, text);

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id      uuid,
  p_receipt      text default null,
  p_sold_price   numeric default 0,
  p_applied_taxes jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.tender_sale_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.tender_sale_items
     set sold = true,
         sold_at = now(),
         receipt_number = p_receipt,
         sold_price = coalesce(p_sold_price, 0),
         applied_taxes = coalesce(p_applied_taxes, '[]'::jsonb)
   where id = p_item_id;
end;
$$;

grant execute on function
  public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

-- 3. ── Toggle delivery ──────────────────────────────────────────────────────
create or replace function public.disposal_toggle_delivery_status(
  p_item_id uuid,
  p_is_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_yard text;
begin
  select yard into v_yard from public.tender_sale_items where id = p_item_id;
  if v_yard is null then
    raise exception 'tender sale item not found';
  end if;
  -- The Central Disposal Directorate OR the package's own yard may update
  -- delivery (yard admins confirm delivery from their Sold Packages table).
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;
  update public.tender_sale_items
     set is_delivered = p_is_delivered,
         delivered_at = case when p_is_delivered then now() else null end
   where id = p_item_id;
end;
$$;

grant execute on function
  public.disposal_toggle_delivery_status(uuid, boolean)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260612_destructions.sql
-- ==========================================================================

-- ============================================================================
--  Destruction procedure tables and functions.
--  Mirrors the Tender Sales procedure for "Destruction" items.
-- ============================================================================

-- 1. ── destructions ─────────────────────────────────────────────────────────
create table if not exists public.destructions (
  id               uuid primary key default uuid_generate_v4(),
  sale_number      text,
  sale_date        date,
  serial           int,
  year             int,
  tender_type      text, -- e.g. 'special' | 'general_cargo' | 'motor_vehicle'
  yard             text,
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now(),
  sale_time        text
);

alter table public.destructions enable row level security;

-- Disposal users and admins manage destructions.
drop policy if exists destructions_manage on public.destructions;
create policy destructions_manage on public.destructions
  for all
  using (
    public.auth_user_is_disposal()
    or exists (select 1 from public.profiles where id = sr_auth.uid() and role = 'admin')
  )
  with check (
    public.auth_user_is_disposal()
    or exists (select 1 from public.profiles where id = sr_auth.uid() and role = 'admin')
  );

-- 2. ── destruction_items ───────────────────────────────────────────────────
create table if not exists public.destruction_items (
  id                   uuid primary key default uuid_generate_v4(),
  destruction_id       uuid not null references public.destructions(id) on delete cascade,
  forfeited_package_id uuid not null references public.forfeited_packages(id) on delete cascade,
  yard                 text not null,
  destroyed            boolean not null default false,
  destroyed_at         timestamptz,
  notes                text,
  created_at           timestamptz not null default now(),
  unique (forfeited_package_id)
);

create index if not exists idx_destruction_items_sale on public.destruction_items(destruction_id);
create index if not exists idx_destruction_items_forfeited on public.destruction_items(forfeited_package_id);

alter table public.destruction_items enable row level security;

-- Disposal Directorate manages every row; a yard can read its own.
drop policy if exists destruction_items_disposal on public.destruction_items;
create policy destruction_items_disposal on public.destruction_items
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

drop policy if exists destruction_items_yard_read on public.destruction_items;
create policy destruction_items_yard_read on public.destruction_items
  for select
  using (yard = (select yard from public.profiles where id = sr_auth.uid()));

-- 3. ── Mark a destruction item DESTROYED (cross-yard, security definer) ────
create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.destruction_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'destroyed' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260612_disposal_manage_tenders.sql
-- ==========================================================================

-- ============================================================================
--  Move tender management to the Central Disposal Directorate.
--  Tenders + tender_disposals were admin-only for writes; the disposal role now
--  manages them (place tender, record disposal, re-tender) across all yards.
--  (SELECT was already permissive for all authenticated users.)
-- ============================================================================

drop policy if exists disposal_manage_tenders on public.tenders;
create policy disposal_manage_tenders on public.tenders
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

drop policy if exists disposal_manage_tender_disposals on public.tender_disposals;
create policy disposal_manage_tender_disposals on public.tender_disposals
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

-- Done.


-- ==========================================================================
--  20260612_disposal_requests_realtime.sql
-- ==========================================================================

alter publication supabase_realtime add table disposal_requests;

-- ==========================================================================
--  20260612_mark_forfeited_sold.sql
-- ==========================================================================

-- ============================================================================
--  Mark a forfeited package SOLD directly (used when a TENDER outcome is "Sold").
--  Writes a [FINAL:SOLD] warehouse entry in the package's own yard so the lot
--  moves to that yard's Warehouses + the cross-yard Sold Packages tab. Mirrors
--  disposal_mark_sale_item_sold but keyed on forfeited_package_id.
-- ============================================================================

create or replace function public.disposal_mark_forfeited_sold(
  p_forfeited_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_package uuid;
  v_yard    text;
  r         record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select package_id, yard into v_package, v_yard
    from public.forfeited_packages where id = p_forfeited_id;
  if v_package is null then
    raise exception 'forfeited package not found';
  end if;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;
end;
$$;

grant execute on function public.disposal_mark_forfeited_sold(uuid, text)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260612_tender_sale_sale_time.sql
-- ==========================================================================

alter table public.tender_sales add column if not exists sale_time text;

-- ==========================================================================
--  20260612_tender_sale_schedule.sql
-- ==========================================================================

-- ============================================================================
--  Tender sale schedule — a tender now carries the date/time its sale runs.
--  After the sale date (+1 grace day) any package in the tender that was not
--  marked SOLD becomes eligible to be re-tendered (unlimited times) under a new
--  tender number. Tendered-but-unsold packages are surfaced on a dedicated view.
-- ============================================================================

alter table public.tenders
  add column if not exists sale_date date,
  add column if not exists sale_time text; -- sale start time, e.g. '10:00'

-- Done.


-- ==========================================================================
--  20260613_appeal_directorate.sql
-- ==========================================================================

-- ============================================================================
--  Appeal Directorate role + appeal-hold on forfeited packages
--  Run after the disposal migrations (esp. 20260610_disposal_directorate.sql,
--  20260611_tender_sale_sold_price.sql, 20260612_destructions.sql).
--
--  Adds a fourth institutional role, `appeal` (Appeal Directorate), modelled on
--  the disposal (DC/SDDC) role: cross-yard READ of forfeited packages, OTP login,
--  two positions (AD / ADD). The Appeal Directorate can place an "appeal hold" on
--  a forfeited package whose 30-day appeal window has NOT yet expired; a held
--  package CANNOT be sold or destroyed (the finalize RPCs hard-block on it) and
--  the owning yard sees a warning.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

-- 1. ── Allow the new role ───────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'officer', 'disposal', 'appeal'));

-- 2. ── Helper: is the caller an Appeal Directorate user? ────────────────────
create or replace function public.auth_user_is_appeal()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'appeal'
  );
$$;

-- 3. ── Cross-yard READ access for appeal users (SELECT only) ────────────────
do $$
declare t text;
begin
  foreach t in array array['packages', 'package_items', 'warehouse_entries', 'forfeited_packages']
  loop
    execute format('drop policy if exists appeal_read_all on public.%I;', t);
    execute format(
      'create policy appeal_read_all on public.%I for select using (public.auth_user_is_appeal());',
      t);
  end loop;
end $$;

-- Appeal users can also read profiles across yards (so the dashboard resolves names).
drop policy if exists appeal_read_profiles on public.profiles;
create policy appeal_read_profiles on public.profiles
  for select using (public.auth_user_is_appeal());

-- 4. ── Appeal-hold columns on forfeited_packages ────────────────────────────
alter table public.forfeited_packages
  add column if not exists appeal_hold      boolean not null default false,
  add column if not exists appeal_hold_note text,
  add column if not exists appeal_held_at   timestamptz,
  add column if not exists appeal_held_by   uuid references public.profiles(id);

create index if not exists idx_forfeited_packages_appeal_hold
  on public.forfeited_packages(appeal_hold) where appeal_hold;

-- 5. ── Limit to one AD and one ADD account ──────────────────────────────────
create or replace function public.appeal_position_available(code text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'appeal' and lower(username) = lower(code)
  );
$$;

grant execute on function public.appeal_position_available(text) to anon, authenticated;

-- 6. ── Set / clear an appeal hold (Appeal Directorate only) ─────────────────
--    Refuses to hold a package whose appeal window has already passed. Clearing
--    (p_hold = false) is always allowed so a resolved/rejected appeal can be
--    released. SECURITY DEFINER → the appeal role needs no broad UPDATE grant.
create or replace function public.set_appeal_hold(
  p_forfeited_id uuid,
  p_hold         boolean,
  p_note         text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_deadline timestamptz;
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select appeal_deadline into v_deadline
    from public.forfeited_packages where id = p_forfeited_id;
  if v_deadline is null then
    raise exception 'forfeited package not found';
  end if;

  if p_hold and v_deadline < now() then
    raise exception 'appeal_window_passed';
  end if;

  update public.forfeited_packages
     set appeal_hold      = p_hold,
         appeal_hold_note = case when p_hold then p_note else null end,
         appeal_held_at   = case when p_hold then now() else null end,
         appeal_held_by   = case when p_hold then sr_auth.uid() else null end
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.set_appeal_hold(uuid, boolean, text) to authenticated;

-- 7. ── Hard block: a held package cannot be sold or destroyed ────────────────
--    Re-create the two finalize RPCs with an appeal-hold guard added right after
--    the forfeited-package id is resolved. Bodies are otherwise identical to
--    20260611_tender_sale_sold_price.sql / 20260612_destructions.sql.

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id      uuid,
  p_receipt      text default null,
  p_sold_price   numeric default 0,
  p_applied_taxes jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.tender_sale_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  -- Appeal hold: block the sale outright.
  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.tender_sale_items
     set sold = true,
         sold_at = now(),
         receipt_number = p_receipt,
         sold_price = coalesce(p_sold_price, 0),
         applied_taxes = coalesce(p_applied_taxes, '[]'::jsonb)
   where id = p_item_id;
end;
$$;

grant execute on function
  public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited uuid;
  v_package   uuid;
  v_yard      text;
  r           record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.destruction_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  -- Appeal hold: block the destruction outright.
  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  select package_id into v_package
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'destroyed' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260613_disposal_realtime.sql
-- ==========================================================================

-- ============================================================================
--  Enable Supabase Realtime on the remaining disposal-pipeline tables so data
--  moving between tables (request → tender sale / destruction → sold/destroyed)
--  updates every open view live, instead of needing a page reload:
--    • disposal_requests / disposal_request_items  (the requests feed)
--    • destructions / destruction_items            (the destructions + undestroyed views)
--  (tender_sale_items is already published — see 20260611_tender_sale_items_realtime.sql.)
--  Idempotent — safe to run more than once.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'disposal_requests',
    'disposal_request_items',
    'destructions',
    'destruction_items'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Done.


-- ==========================================================================
--  20260613_forfeited_source.sql
-- ==========================================================================

-- ============================================================================
--  Forfeited-package SOURCE tag (Forfeit vs Abandoned)
--  Run after 20260528_add_forfeited_packages_and_tenders.sql.
--
--  Yards can now route ABANDONED packages through the same disposal-request →
--  tender-sale / destruction pipeline as forfeited ones. To reuse that pipeline
--  unchanged, an abandoned package gets a real forfeited_packages row when it is
--  requested; `source` records where it came from so the Central Disposal
--  "Disposal Requests" page can badge each item Forfeit vs Abandoned, and so the
--  yard's "true forfeits only" lists can filter the synthetic rows out.
-- ============================================================================

alter table public.forfeited_packages
  add column if not exists source text not null default 'forfeit'
    check (source in ('forfeit', 'abandoned'));

-- Existing rows are all genuine forfeits — the default already covers them, but
-- be explicit for any row that somehow has a NULL.
update public.forfeited_packages set source = 'forfeit' where source is null;

create index if not exists idx_forfeited_packages_source
  on public.forfeited_packages(source);


-- ==========================================================================
--  20260613_password_updated_at.sql
-- ==========================================================================

alter table public.profiles
  add column if not exists password_updated_at timestamptz default now();

-- Update existing rows to have password_updated_at = created_at to be safe
update public.profiles
set password_updated_at = created_at
where password_updated_at is null;

-- Function to track password updates
create or replace function public.handle_password_update()
returns trigger as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    update public.profiles
    set password_updated_at = now()
    where id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

-- Trigger for sr_auth.users
drop trigger if exists on_auth_user_password_update on sr_auth.users;
DROP TRIGGER IF EXISTS on_auth_user_password_update ON sr_auth.users;
CREATE TRIGGER on_auth_user_password_update
  after update on sr_auth.users
  for each row execute procedure public.handle_password_update();


-- ==========================================================================
--  20260614_add_hs_code.sql
-- ==========================================================================

-- Per-item HS (Harmonised System) code for package items.
-- Sits alongside the existing unit_value column so each item carries both
-- its HS classification code and its declared value.
ALTER TABLE package_items
  ADD COLUMN IF NOT EXISTS hs_code TEXT;


-- ==========================================================================
--  20260614_appeal_decision.sql
-- ==========================================================================

-- ── Appeal decision on release ───────────────────────────────────────────────
-- When the Appeal Directorate lifts an appeal hold (appeal processed), it must
-- record what the owning yard should do next with the package: Release the
-- goods to the owner, Sell, Destroy, Re-export or Other. This decision is stored
-- on the forfeited package so the yard can act on it.

alter table public.forfeited_packages
  add column if not exists appeal_decision      text,
  add column if not exists appeal_decision_note text,
  add column if not exists appeal_decided_at    timestamptz,
  add column if not exists appeal_decided_by    uuid references public.profiles(id);

-- Lift an appeal hold AND record the directorate's decision in one call.
-- Decision is one of: RELEASE, SALE, DESTROY, RE-EXPORT, OTHER (free text for
-- OTHER is carried in p_note). Appeal-role only; SECURITY DEFINER.
create or replace function public.release_appeal_with_decision(
  p_forfeited_id uuid,
  p_decision     text,
  p_note         text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  if not exists (select 1 from public.forfeited_packages where id = p_forfeited_id) then
    raise exception 'forfeited package not found';
  end if;

  update public.forfeited_packages
     set appeal_hold           = false,
         appeal_hold_note      = null,
         appeal_held_at        = null,
         appeal_held_by        = null,
         appeal_decision       = p_decision,
         appeal_decision_note  = p_note,
         appeal_decided_at     = now(),
         appeal_decided_by     = sr_auth.uid()
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.release_appeal_with_decision(uuid, text, text) to authenticated;


-- ==========================================================================
--  20260614_forfeited_realtime.sql
-- ==========================================================================

-- ============================================================================
--  Ensure EVERY table that has a realtime channel in the app is in the
--  `supabase_realtime` publication, so changes broadcast to all open views live
--  (no page reload needed). The Appeal Directorate dashboard + the yard
--  Forfeited Packages screen subscribe to `forfeited-packages-realtime` but
--  received nothing while `forfeited_packages` was absent from the publication —
--  this backfills it together with every other channelled table.
--  Idempotent — safe to run more than once.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'packages',
    'package_items',
    'warehouse_entries',
    'profiles',
    'package_categories',
    'audit_logs',
    'forfeited_packages',
    'destructions',
    'destruction_items',
    'disposal_requests',
    'disposal_request_items',
    'tender_sale_items'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Send the full row on UPDATE/DELETE so realtime payloads carry the changed
-- columns (e.g. forfeited_packages.appeal_decision), not just the primary key.
alter table public.forfeited_packages replica identity full;

-- Done.


-- ==========================================================================
--  20260615_audit_log_retention.sql
-- ==========================================================================

-- ============================================================================
--  Audit-log retention — keep only the last 12 months of activity logs.
--  ---------------------------------------------------------------------------
--  The Admin Panel "Logs" tab only ever shows the last year (filtered in
--  getAllLogs). This migration prunes anything older so the table doesn't grow
--  unbounded. purge_old_audit_logs() is called opportunistically by the app
--  (AuditLogService.recordLog) on each new log write; it can also be scheduled
--  via pg_cron if the project has it enabled.
-- ============================================================================

create or replace function public.purge_old_audit_logs()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_deleted integer;
begin
  delete from public.audit_logs
   where created_at < now() - interval '365 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

grant execute on function public.purge_old_audit_logs() to authenticated;

-- One-off prune of any existing backlog when this migration runs.
select public.purge_old_audit_logs();

-- Optional (only if pg_cron is enabled on the project): run daily at 02:00 UTC.
-- Safe to leave commented out — the app prunes opportunistically regardless.
-- select cron.schedule('purge-audit-logs', '0 2 * * *',
--   $$ select public.purge_old_audit_logs(); $$);

-- Done.


-- ==========================================================================
--  20260616_forfeited_source_other.sql
-- ==========================================================================

-- ============================================================================
--  Forfeited-package SOURCE: add 'other'
--  Run after 20260613_forfeited_source.sql.
--
--  Packages registered with an "Other" item status (a custom disposition set on
--  the SR form — e.g. court-held / pending-decision) can now be routed through
--  the same disposal-request → tender-sale / destruction pipeline as forfeited
--  and abandoned goods, with NO appeal period. They get a real
--  forfeited_packages row (source='other') only when requested; `source` lets
--  the Central Disposal "Disposal Requests" page badge them and lets the yard's
--  "true forfeits only" lists filter the synthetic rows out.
-- ============================================================================

alter table public.forfeited_packages
  drop constraint if exists forfeited_packages_source_check;

alter table public.forfeited_packages
  add constraint forfeited_packages_source_check
    check (source in ('forfeit', 'abandoned', 'other'));


-- ==========================================================================
--  20260617_forfeited_item_id.sql
-- ==========================================================================

-- ============================================================================
--  Add item_id to forfeited_packages so synthetic abandoned / "Other"
--  disposal-request rows can pin to a SPECIFIC package item.
--
--  Before: a synthetic forfeited_packages row was created per (package, source),
--  with no item_id — so several items of the same package+source collapsed into
--  ONE row. In the Valuation / Central Disposal tables that row then aggregated
--  EVERY package item's quantity (e.g. two rows both showing qty 67), and the
--  details popup showed the wrong/whole package.
--
--  Now: createDisposalRequest() creates one forfeited_packages row per
--  (package, item, source) and stores item_id. The app's coveredItems / qty /
--  HS-code / details-popup logic already prefers forfeited.item_id when present,
--  so each row shows exactly its own item.
--  Idempotent — safe to re-run.
-- ============================================================================

alter table public.forfeited_packages
  add column if not exists item_id uuid references public.package_items(id) on delete set null;

create index if not exists idx_forfeited_packages_item_id
  on public.forfeited_packages(item_id);

-- Done.


-- ==========================================================================
--  20260617_valuation_directorate.sql
-- ==========================================================================

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
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'valuation'
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
set search_path = public, extensions
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
set search_path = public, extensions
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
           valued_by = sr_auth.uid()
     where id = p_request_id;
  end if;
end;
$$;

grant execute on function public.valuation_set_costs(uuid, jsonb, boolean) to authenticated;

-- Done.

-- ==========================================================================
--  20260620_destruction_delivery.sql
-- ==========================================================================

-- ============================================================================
--  Destroyed-package delivery tracking.
--
--  Destroyed packages can also be physically delivered out (like sold ones), so
--  the Destroyed Packages tables (Central + yard) show a Delivered / Pending
--  status and the details popup gets a "Mark Delivered" button — mirroring the
--  Sold Packages flow.
--
--  1. Adds `delivered` / `delivered_at` to destruction_items.
--  2. Adds a toggle RPC (yard OR Central Disposal may flip it), mirroring
--     disposal_toggle_delivery_status for sold packages.
--
--  Idempotent — safe to re-run. ⚠️ CLOSE THE APP FIRST (brief table lock).
-- ============================================================================

-- 1. ── Columns ──────────────────────────────────────────────────────────────
alter table public.destruction_items
  add column if not exists delivered     boolean not null default false;
alter table public.destruction_items
  add column if not exists delivered_at   timestamptz;

-- 2. ── Toggle RPC ────────────────────────────────────────────────────────────
create or replace function public.disposal_toggle_destruction_delivery(
  p_item_id uuid,
  p_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_yard text;
begin
  select yard into v_yard from public.destruction_items where id = p_item_id;
  if v_yard is null then
    raise exception 'destruction item not found';
  end if;
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;
  update public.destruction_items
     set delivered = p_delivered,
         delivered_at = case when p_delivered then now() else null end
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_toggle_destruction_delivery(uuid, boolean)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260620_per_item_appeal_hold.sql
-- ==========================================================================

-- ============================================================================
--  Per-item appeal hold on forfeited_packages
--  Adds a held_item_ids UUID[] column so the Appeal Directorate can hold
--  individual items within a multi-item package, not the whole package at once.
--  The package-level appeal_hold boolean is kept for backward-compat but is
--  no longer used by the hold RPC — instead it mirrors (held_item_ids != '{}').
-- ============================================================================

-- 1. New column: array of package_item IDs currently on hold
alter table public.forfeited_packages
  add column if not exists held_item_ids uuid[] not null default '{}';

-- 2. Migrate existing holds: if appeal_hold=true and we don't know which item,
--    leave held_item_ids empty (the UI will show correct state via the flag).

-- 3. Replace set_appeal_hold RPC with per-item version
--    p_item_id: the specific package_item.id to hold/release, or NULL to
--    hold/release ALL items (backward-compat for single-item packages).
create or replace function public.set_appeal_hold(
  p_forfeited_id uuid,
  p_hold         boolean,
  p_note         text    default null,
  p_item_id      uuid    default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_deadline    timestamptz;
  v_item_ids    uuid[];
  v_new_ids     uuid[];
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select appeal_deadline, held_item_ids
    into v_deadline, v_item_ids
    from public.forfeited_packages
   where id = p_forfeited_id;

  if v_deadline is null then
    raise exception 'forfeited package not found';
  end if;

  if p_hold and v_deadline < now() then
    raise exception 'appeal_window_passed';
  end if;

  if p_hold then
    if p_item_id is not null then
      -- Add item to held set (avoid duplicates)
      if not (v_item_ids @> array[p_item_id]) then
        v_new_ids := v_item_ids || array[p_item_id];
      else
        v_new_ids := v_item_ids;
      end if;
    else
      -- p_item_id null → not used in new flow, keep existing
      v_new_ids := v_item_ids;
    end if;
  else
    if p_item_id is not null then
      -- Remove specific item from held set
      select array_agg(x) into v_new_ids
        from unnest(v_item_ids) x
       where x <> p_item_id;
      if v_new_ids is null then v_new_ids := '{}'; end if;
    else
      -- Release all
      v_new_ids := '{}';
    end if;
  end if;

  update public.forfeited_packages
     set held_item_ids  = v_new_ids,
         -- keep legacy flag in sync (true if any item held)
         appeal_hold    = (array_length(v_new_ids, 1) > 0),
         appeal_hold_note = case
           when array_length(v_new_ids, 1) > 0 then p_note
           else null
         end,
         appeal_held_at = case
           when array_length(v_new_ids, 1) > 0 then coalesce(appeal_held_at, now())
           else null
         end,
         appeal_held_by = case
           when array_length(v_new_ids, 1) > 0 then coalesce(appeal_held_by, sr_auth.uid())
           else null
         end
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.set_appeal_hold(uuid, boolean, text, uuid) to authenticated;


-- ==========================================================================
--  migrations/001_multi_yard.sql (folded in — adds the yard column the seed data below writes to)
-- ==========================================================================

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
set search_path = public, extensions
as $$
  select yard from public.profiles where id = sr_auth.uid();
$$;

-- 4. ── Enable RLS and add per-yard policies ────────────────────────────────
--    Each policy restricts rows to the caller's yard. A user can always read
--    their own profile row; data tables are fully yard-scoped.

-- profiles: a user sees profiles in their own yard (and always their own row)
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


-- ==========================================================================
--  20260620_seed_data.sql
-- ==========================================================================

-- ============================================================================
--  SEED DATA SCRIPT  v2
--  1. Clear all package-related data (profiles/auth untouched)
--  2. Insert 12 realistic packages with full fields + warehouse entries
--
--  Run in Supabase SQL Editor.
-- ============================================================================

-- ── STEP 1: CLEAR ────────────────────────────────────────────────────────────
DELETE FROM public.destruction_items;
DELETE FROM public.destructions;
DELETE FROM public.disposal_request_items;
DELETE FROM public.disposal_requests;
DELETE FROM public.tender_sale_items;
DELETE FROM public.tender_sales;
DELETE FROM public.forfeited_packages;
DELETE FROM public.warehouse_entries;
DELETE FROM public.package_items;
DELETE FROM public.packages;
DELETE FROM public.audit_logs;

-- ── STEP 2: INSERT ───────────────────────────────────────────────────────────
DO $$
DECLARE
  -- ── Warehouse IDs (fetched from real warehouses table) ─────────────────
  wh1 UUID;  -- first warehouse  (e.g. Warehouse 1 / SR Warehouse 01)
  wh2 UUID;  -- second warehouse (e.g. Warehouse 2 / SR Warehouse 02)
  wh3 UUID;  -- third warehouse  (e.g. Warehouse 3 / SR Warehouse 03)

  -- ── Package IDs ────────────────────────────────────────────────────────
  p1  UUID := gen_random_uuid();
  p2  UUID := gen_random_uuid();
  p3  UUID := gen_random_uuid();
  p4  UUID := gen_random_uuid();
  p5  UUID := gen_random_uuid();
  p6  UUID := gen_random_uuid();
  p7  UUID := gen_random_uuid();
  p8  UUID := gen_random_uuid();
  p9  UUID := gen_random_uuid();
  p10 UUID := gen_random_uuid();
  p11 UUID := gen_random_uuid();
  p12 UUID := gen_random_uuid();

  -- ── Package item IDs (for warehouse_entries FK) ─────────────────────
  i1a UUID := gen_random_uuid();
  i2a UUID := gen_random_uuid();
  i2b UUID := gen_random_uuid();
  i2c UUID := gen_random_uuid();
  i2d UUID := gen_random_uuid();
  i3a UUID := gen_random_uuid();
  i4a UUID := gen_random_uuid();
  i4b UUID := gen_random_uuid();
  i4c UUID := gen_random_uuid();
  i5a UUID := gen_random_uuid();
  i5b UUID := gen_random_uuid();
  i6a UUID := gen_random_uuid();
  i7a UUID := gen_random_uuid();
  i7b UUID := gen_random_uuid();
  i7c UUID := gen_random_uuid();
  i7d UUID := gen_random_uuid();
  i7e UUID := gen_random_uuid();
  i8a UUID := gen_random_uuid();
  i8b UUID := gen_random_uuid();
  i9a UUID := gen_random_uuid();
  i9b UUID := gen_random_uuid();
  i9c UUID := gen_random_uuid();
  i10a UUID := gen_random_uuid();
  i11a UUID := gen_random_uuid();
  i11b UUID := gen_random_uuid();
  i11c UUID := gen_random_uuid();
  i11d UUID := gen_random_uuid();
  i12a UUID := gen_random_uuid();
  i12b UUID := gen_random_uuid();
  i12c UUID := gen_random_uuid();
  i12d UUID := gen_random_uuid();
  i12e UUID := gen_random_uuid();

  -- ── Forfeited record IDs ───────────────────────────────────────────────
  f3 UUID := gen_random_uuid();
  f4 UUID := gen_random_uuid();
  f5 UUID := gen_random_uuid();
  f6 UUID := gen_random_uuid();

BEGIN

  -- Load real warehouse IDs ordered by code/name
  SELECT id INTO wh1 FROM public.warehouses ORDER BY code ASC LIMIT 1 OFFSET 0;
  SELECT id INTO wh2 FROM public.warehouses ORDER BY code ASC LIMIT 1 OFFSET 1;
  SELECT id INTO wh3 FROM public.warehouses ORDER BY code ASC LIMIT 1 OFFSET 2;

  -- Fall back: if fewer than 3 warehouses exist, reuse the first one
  IF wh2 IS NULL THEN wh2 := wh1; END IF;
  IF wh3 IS NULL THEN wh3 := wh1; END IF;

-- ════════════════════════════════════════════════════════════════════════════
-- P1 · GL1/SR/101/2026 · held · 1 item
-- Mobile phones — undeclared quantity
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p1, 'GL1/SR/101/2026', 'CASE/2026/101', 'GL1', 'China',
  45000, 12.5, 1, 'Household electronics shipment', 'CNTR-2026-001',
  'Kapila Perera', '198805601234', '42 Galle Road, Colombo 03', '0771234567',
  'Saman Kumara', 'C1001', '2026-05-10', '2026-05-12',
  'Undeclared items found during inspection', 'held',
  'Requires further review by supervisor.',
  NOW() - INTERVAL '40 days', NOW() - INTERVAL '40 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES (i1a, p1, 'Mobile Phones',
  'Samsung Galaxy S24 smartphones in original sealed boxes',
  15, 'Pieces', 3000, '8517120000', 'Electronics', false, 'Detain',
  'Undeclared quantity — declared 5, found 15');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES (p1, i1a, wh1, 'GL1', '3', 'Undeclared items found during inspection',
  15, 50, NOW() - INTERVAL '39 days', false);

-- ════════════════════════════════════════════════════════════════════════════
-- P2 · GL1/SR/102/2026 · cleared · 4 items
-- Mixed garments — cleared after inspection
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p2, 'GL1/SR/102/2026', 'CASE/2026/102', 'GL1', 'India',
  28500, 8.0, 4, 'Mixed textile and garment shipment', 'CNTR-2026-002',
  'Nirosha Fernando', '199203702345', '15 Temple Road, Kandy', '0762345678',
  'Pradeep Wickramasinghe', 'C1002', '2026-05-12', '2026-05-14',
  NULL, 'cleared', NULL,
  NOW() - INTERVAL '35 days', NOW() - INTERVAL '35 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status)
VALUES
  (i2a, p2, 'Cotton T-Shirts',
   'Men''s cotton round-neck T-shirts, assorted colours', 200, 'Pieces', 25,
   '6109100000', 'Garments', false, 'Other'),
  (i2b, p2, 'Denim Jeans',
   'Ladies'' slim-fit denim jeans, sizes 28–36', 150, 'Pieces', 85,
   '6204620000', 'Garments', false, 'Other'),
  (i2c, p2, 'Cotton Sarees',
   'Handloom cotton sarees, 5.5 m length', 80, 'Pieces', 120,
   '5007200000', 'Garments', false, 'Other'),
  (i2d, p2, 'Silk Scarves',
   'Pure silk neck scarves, 90×90 cm', 50, 'Pieces', 450,
   '6214100000', 'Garments', false, 'Other');

-- Cleared: warehouse entry returned
INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at,
  is_returned, returned_at, return_notes)
VALUES (p2, i2a, wh2, 'GL1', '5', 'Routine inspection hold',
  480, 20, NOW() - INTERVAL '34 days', true,
  NOW() - INTERVAL '32 days', 'All documents verified. Goods released.');

-- ════════════════════════════════════════════════════════════════════════════
-- P3 · GL1/SR/103/2026 · forfeited · 1 item · WINDOW PASSED (45 days ago)
-- Counterfeit luxury watches
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p3, 'GL1/SR/103/2026', 'CASE/2026/103', 'GL1', 'UAE',
  125000, 5.5, 1, 'Luxury watches shipment', NULL,
  'Roshan Jayawardena', '197806503456', '88 Station Road, Gampaha', '0713456789',
  'Lalith Gunaratne', 'C1003', '2026-04-20', '2026-04-22',
  'Counterfeit luxury goods — trademark infringement', 'forfeited',
  'Goods confiscated under Customs Ordinance Section 84.',
  NOW() - INTERVAL '45 days', NOW() - INTERVAL '45 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES (i3a, p3, 'Counterfeit Watches',
  'Fake Rolex and Omega watches in individual branded boxes',
  48, 'Pieces', 2600, '9102110000', 'Luxury Goods', true, 'Forfeit',
  'Trademark infringement — Customs Ordinance Section 84');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES (p3, i3a, wh3, 'GL1', '1', 'Forfeited — trademark infringement',
  48, 50, NOW() - INTERVAL '44 days', false);

INSERT INTO public.forfeited_packages (id, package_id, sr_number, consignee_name,
  forfeited_at, appeal_deadline, reason, yard, source, appeal_hold, created_at, updated_at)
VALUES (f3, p3, 'GL1/SR/103/2026', 'Roshan Jayawardena',
  NOW() - INTERVAL '45 days', NOW() - INTERVAL '15 days',
  'Counterfeit luxury goods — trademark infringement', 'GL1', 'forfeit', false,
  NOW() - INTERVAL '45 days', NOW() - INTERVAL '45 days');

-- ════════════════════════════════════════════════════════════════════════════
-- P4 · GL1/SR/104/2026 · forfeited · 3 items · WINDOW PASSED (35 days ago)
-- Uncertified electrical goods
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p4, 'GL1/SR/104/2026', 'CASE/2026/104', 'GL1', 'Pakistan',
  67000, 22.0, 3, 'Electrical goods and accessories', 'CNTR-2026-004',
  'Chamari Dissanayake', '199512804567', '23 Peradeniya Road, Peradeniya', '0754567890',
  'Buddhika Rathnayake', 'C1004', '2026-04-28', '2026-04-30',
  'Prohibited electrical goods without proper certification', 'forfeited',
  'No SLS certification for electrical items.',
  NOW() - INTERVAL '35 days', NOW() - INTERVAL '35 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES
  (i4a, p4, 'Electric Kettles',
   'Uncertified electric kettles, 1.7 L capacity', 60, 'Pieces', 450,
   '8516400000', 'Electronics', true, 'Forfeit', 'No SLS certification'),
  (i4b, p4, 'Phone Chargers',
   'Fast-charging USB-C adapters, 65 W, no approval mark', 200, 'Pieces', 250,
   '8504401000', 'Electronics', true, 'Forfeit', 'Uncertified electrical equipment'),
  (i4c, p4, 'Extension Cords',
   '5-socket extension boards, 3 m cable, no earthing', 100, 'Pieces', 380,
   '8544422000', 'Electronics', true, 'Forfeit', 'Safety hazard — no earthing');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES
  (p4, i4a, wh1, 'GL1', '2', 'Forfeited — uncertified electrical goods', 60, 50, NOW() - INTERVAL '34 days', false),
  (p4, i4b, wh1, 'GL1', '2', 'Forfeited — uncertified electrical goods', 200, 20, NOW() - INTERVAL '34 days', false),
  (p4, i4c, wh1, 'GL1', '2', 'Forfeited — uncertified electrical goods', 100, 20, NOW() - INTERVAL '34 days', false);

INSERT INTO public.forfeited_packages (id, package_id, sr_number, consignee_name,
  forfeited_at, appeal_deadline, reason, yard, source, appeal_hold, created_at, updated_at)
VALUES (f4, p4, 'GL1/SR/104/2026', 'Chamari Dissanayake',
  NOW() - INTERVAL '35 days', NOW() - INTERVAL '5 days',
  'Prohibited electrical goods without proper certification', 'GL1', 'forfeit', false,
  NOW() - INTERVAL '35 days', NOW() - INTERVAL '35 days');

-- ════════════════════════════════════════════════════════════════════════════
-- P5 · GL1/SR/105/2026 · forfeited · 2 items · ACTIVE WINDOW (20 days left)
-- Misdeclared graphics cards
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p5, 'GL1/SR/105/2026', 'CASE/2026/105', 'GL1', 'Japan',
  89000, 18.0, 2, 'Computer hardware and peripherals', 'CNTR-2026-005',
  'Tech World Pvt Ltd', '200123450001', '45 IT Park, Malabe', '0112345678',
  'Asanka Wijesekara', 'C1005', '2026-06-05', '2026-06-07',
  'Misdeclaration of goods value', 'forfeited', NULL,
  NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES
  (i5a, p5, 'Graphics Cards',
   'NVIDIA RTX 4090 GPUs, declared as "PC accessories"', 20, 'Pieces', 3800,
   '8473309000', 'Electronics', false, 'Forfeit',
   'Value misdeclaration — declared at 10% of actual value'),
  (i5b, p5, 'Gaming Monitors',
   '32″ 4K gaming monitors, 144 Hz refresh', 10, 'Pieces', 1200,
   '8528590000', 'Electronics', false, 'Forfeit',
   'Misdeclared as "display screens"');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES
  (p5, i5a, wh2, 'GL1', '4', 'Forfeited — misdeclaration of value', 20, 50, NOW() - INTERVAL '9 days', false),
  (p5, i5b, wh2, 'GL1', '4', 'Forfeited — misdeclaration of value', 10, 50, NOW() - INTERVAL '9 days', false);

INSERT INTO public.forfeited_packages (id, package_id, sr_number, consignee_name,
  forfeited_at, appeal_deadline, reason, yard, source, appeal_hold, created_at, updated_at)
VALUES (f5, p5, 'GL1/SR/105/2026', 'Tech World Pvt Ltd',
  NOW() - INTERVAL '10 days', NOW() + INTERVAL '20 days',
  'Misdeclaration of goods value', 'GL1', 'forfeit', false,
  NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days');

-- ════════════════════════════════════════════════════════════════════════════
-- P6 · GL1/SR/106/2026 · forfeited · 1 item · ACTIVE WINDOW (25 days left)
-- Unregistered pharmaceutical products
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p6, 'GL1/SR/106/2026', 'CASE/2026/106', 'GL1', 'China',
  34500, 9.0, 1, 'Pharmaceutical products', NULL,
  'Smart Fix Repairs', '200198760002', '12 Hospital Road, Nugegoda', '0776789012',
  'Rasika Mendis', 'C1006', '2026-06-10', '2026-06-12',
  'Pharmaceutical goods without import licence', 'forfeited',
  'No NMRA approval for pharmaceutical imports.',
  NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES (i6a, p6, 'Herbal Supplements',
  'Unregistered herbal weight-loss capsules, 500 mg bottles',
  500, 'Bottles', 69, '2106909000', 'Pharmaceuticals', true, 'Forfeit',
  'No NMRA licence — unregistered pharmaceutical product');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES (p6, i6a, wh3, 'GL1', '6', 'Forfeited — no pharmaceutical import licence',
  500, 20, NOW() - INTERVAL '4 days', false);

INSERT INTO public.forfeited_packages (id, package_id, sr_number, consignee_name,
  forfeited_at, appeal_deadline, reason, yard, source, appeal_hold, created_at, updated_at)
VALUES (f6, p6, 'GL1/SR/106/2026', 'Smart Fix Repairs',
  NOW() - INTERVAL '5 days', NOW() + INTERVAL '25 days',
  'Pharmaceutical goods without import licence', 'GL1', 'forfeit', false,
  NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days');

-- ════════════════════════════════════════════════════════════════════════════
-- P7 · GL1/SR/107/2026 · pending · 5 items · Large mixed electronics
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p7, 'GL1/SR/107/2026', 'CASE/2026/107', 'GL1', 'South Korea',
  195000, 45.0, 5, 'Mixed electronics and home appliances', 'CNTR-2026-007',
  'Sampath Electronics', '200089230003', '78 Baseline Road, Colombo 09', '0117890123',
  'Dulshan Karunaratne', 'C1007', '2026-06-14', '2026-06-15',
  NULL, 'pending', 'Awaiting inspection clearance.',
  NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status)
VALUES
  (i7a, p7, 'Smart TVs', '55″ OLED Smart TV, Android OS', 8, 'Pieces', 85000, '8528720000', 'Electronics', false, 'Detain'),
  (i7b, p7, 'Washing Machines', 'Front-load washing machine, 7 kg', 5, 'Pieces', 95000, '8450110000', 'Home Appliances', false, 'Detain'),
  (i7c, p7, 'Air Conditioners', '1.5-ton inverter split AC', 4, 'Pieces', 145000, '8415100000', 'Home Appliances', false, 'Detain'),
  (i7d, p7, 'Microwave Ovens', '28 L convection microwave with grill', 10, 'Pieces', 32000, '8516500000', 'Home Appliances', false, 'Detain'),
  (i7e, p7, 'Bluetooth Speakers', 'Portable waterproof speaker, 30 W', 25, 'Pieces', 8500, '8518220000', 'Electronics', false, 'Detain');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES
  (p7, i7a, wh1, 'GL1', '1', 'Pending inspection', 8, 50, NOW() - INTERVAL '4 days', false),
  (p7, i7b, wh1, 'GL1', '1', 'Pending inspection', 5, 50, NOW() - INTERVAL '4 days', false),
  (p7, i7c, wh1, 'GL1', '2', 'Pending inspection', 4, 50, NOW() - INTERVAL '4 days', false),
  (p7, i7d, wh1, 'GL1', '2', 'Pending inspection', 10, 20, NOW() - INTERVAL '4 days', false),
  (p7, i7e, wh1, 'GL1', '2', 'Pending inspection', 25, 20, NOW() - INTERVAL '4 days', false);

-- ════════════════════════════════════════════════════════════════════════════
-- P8 · GL1/SR/108/2026 · held · 2 items · Agricultural produce
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p8, 'GL1/SR/108/2026', 'CASE/2026/108', 'GL1', 'Thailand',
  52000, 320.0, 2, 'Agricultural produce and processed foods', 'CNTR-2026-008',
  'Green Valley Foods', '199867340004', '34 Factory Road, Ratmalana', '0119012345',
  'Nilanka Seneviratne', 'C1008', '2026-06-16', '2026-06-17',
  'Phytosanitary certificate not produced', 'held',
  'Held for phytosanitary inspection. DOA notification sent.',
  NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES
  (i8a, p8, 'Jasmine Rice', 'Thai fragrant jasmine rice, 25 kg bags',
   200, 'Bags', 180, '1006302000', 'Food & Agriculture', false, 'Detain',
   'No phytosanitary certificate'),
  (i8b, p8, 'Palm Oil', 'Refined palm olein, 18 L cans',
   100, 'Cans', 340, '1511902000', 'Food & Agriculture', false, 'Detain',
   'Label not in Sinhala / Tamil as required');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES
  (p8, i8a, wh2, 'GL1', '7', 'Held — phytosanitary certificate missing', 200, 20, NOW() - INTERVAL '2 days', false),
  (p8, i8b, wh2, 'GL1', '7', 'Held — labelling non-compliance',           100, 20, NOW() - INTERVAL '2 days', false);

-- ════════════════════════════════════════════════════════════════════════════
-- P9 · GL1/SR/109/2026 · cleared · 3 items · Motor vehicle parts
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p9, 'GL1/SR/109/2026', NULL, 'GL1', 'Japan',
  380000, 850.0, 3, 'Motor vehicle spare parts and accessories', 'CNTR-2026-009',
  'AutoParts Lanka Pvt Ltd', '200201230005', '56 Nawala Road, Rajagiriya', '0112901234',
  'Manjula Pathirana', 'C1009', '2026-06-17', '2026-06-18',
  NULL, 'cleared', NULL,
  NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status)
VALUES
  (i9a, p9, 'Engine Pistons', 'Cast iron pistons for Toyota 2NZ-FE engine',
   48, 'Pieces', 3500, '8409910000', 'Auto Parts', false, 'Other'),
  (i9b, p9, 'Brake Pads', 'Ceramic brake pads, front and rear sets',
   120, 'Sets', 2800, '8708302000', 'Auto Parts', false, 'Other'),
  (i9c, p9, 'Shock Absorbers', 'KYB Gas shock absorbers, front pair',
   36, 'Pieces', 12000, '8708803000', 'Auto Parts', false, 'Other');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at,
  is_returned, returned_at, return_notes)
VALUES
  (p9, i9a, wh3, 'GL1', '8', 'Routine inspection hold', 48, 20, NOW() - INTERVAL '2 days',
   true, NOW() - INTERVAL '1 day', 'Documents verified. Goods released.'),
  (p9, i9b, wh3, 'GL1', '8', 'Routine inspection hold', 120, 20, NOW() - INTERVAL '2 days',
   true, NOW() - INTERVAL '1 day', 'Documents verified. Goods released.'),
  (p9, i9c, wh3, 'GL1', '8', 'Routine inspection hold', 36, 20, NOW() - INTERVAL '2 days',
   true, NOW() - INTERVAL '1 day', 'Documents verified. Goods released.');

-- ════════════════════════════════════════════════════════════════════════════
-- P10 · GL1/SR/110/2026 · pending · 1 item · Controlled chemicals
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p10, 'GL1/SR/110/2026', 'CASE/2026/110', 'GL1', 'Germany',
  720000, 1200.0, 1, 'Industrial chemical reagents', NULL,
  'ChemTech Industries Ltd', '198945670006', '12 Industrial Estate, Sapugaskanda', '0116789012',
  'Tharaka Silva', 'C1010', '2026-06-18', '2026-06-18',
  'Controlled chemical — licence verification pending', 'pending',
  'Awaiting National Dangerous Drugs Board clearance.',
  NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES (i10a, p10, 'Controlled Chemicals',
  'Acetone, methanol and precursor reagents in 25 L drums',
  48, 'Drums', 15000, '2914110000', 'Chemicals', true, 'Detain',
  'Precursor chemicals — NDDB licence required');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES (p10, i10a, wh2, 'GL1', '9', 'Controlled substance — pending NDDB clearance',
  48, 50, NOW() - INTERVAL '20 hours', false);

-- ════════════════════════════════════════════════════════════════════════════
-- P11 · GL1/SR/111/2026 · held · 4 items · High-value jewellery
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p11, 'GL1/SR/111/2026', 'CASE/2026/111', 'GL1', 'Italy',
  4500000, 2.8, 4, 'Gold and diamond jewellery', NULL,
  'Luxe Gems International', '197623410007', '88 Jewellers Street, Colombo 11', '0112345901',
  'Sumudu Rajapaksa', 'C1011', '2026-06-19', '2026-06-19',
  'Undeclared jewellery exceeding duty-free threshold', 'held',
  'Held — duties and taxes outstanding. Owner notified.',
  NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons)
VALUES
  (i11a, p11, 'Gold Necklaces', '22 K gold necklace sets with pendant, 45 g each',
   12, 'Pieces', 180000, '7113191000', 'Jewellery', false, 'Detain',
   'Duty not paid — value exceeds duty-free limit'),
  (i11b, p11, 'Diamond Rings', '18 K white gold solitaire diamond rings, 0.5 ct',
   8, 'Pieces', 350000, '7113191000', 'Jewellery', false, 'Detain',
   'Undeclared high-value item'),
  (i11c, p11, 'Gold Bangles', '21 K gold bangles, 30 g each, plain design',
   20, 'Pieces', 120000, '7113191000', 'Jewellery', false, 'Detain',
   'Aggregate value far exceeds declared amount'),
  (i11d, p11, 'Pearl Earrings', 'South Sea cultured pearl drop earrings, 12 mm',
   15, 'Pairs', 95000, '7116100000', 'Jewellery', false, 'Detain',
   'No certificate of authenticity');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES
  (p11, i11a, wh3, 'GL1', '10', 'Held — undeclared high-value jewellery, duties outstanding', 12, 50, NOW() - INTERVAL '11 hours', false),
  (p11, i11b, wh3, 'GL1', '10', 'Held — undeclared high-value jewellery, duties outstanding', 8,  50, NOW() - INTERVAL '11 hours', false),
  (p11, i11c, wh3, 'GL1', '10', 'Held — undeclared high-value jewellery, duties outstanding', 20, 50, NOW() - INTERVAL '11 hours', false),
  (p11, i11d, wh3, 'GL1', '10', 'Held — undeclared high-value jewellery, duties outstanding', 15, 50, NOW() - INTERVAL '11 hours', false);

-- ════════════════════════════════════════════════════════════════════════════
-- P12 · GL1/SR/120/2026 · pending · 5 items · Mixed Apple devices
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.packages (id, sr_number, case_number, yard, origin_country,
  declared_value, weight_kg, total_item_count, description, container_number,
  consignee_name, consignee_nic, consignee_address, consignee_phone,
  declarant_name, cusdec_no, cusdec_date, entry_date,
  reason, status, notes, created_at, updated_at)
VALUES (p12, 'GL1/SR/120/2026', 'CASE/2026/120', 'GL1', 'Singapore',
  156000, 35.0, 5, 'Mobile phones and accessories', 'CNTR-2026-012',
  'rtvgubii Trading', '200045670008', '22 Tech City, Homagama', '0788314247',
  'Anushanga Munasinghe', 'C1012', '2026-05-14', '2026-05-19',
  'Excess Weight', 'pending', NULL,
  NOW() - INTERVAL '31 days', NOW() - INTERVAL '31 days');

INSERT INTO public.package_items (id, package_id, item_name, goods_description,
  quantity, unit_of_measure, unit_value, hs_code, category, is_prohibited, status)
VALUES
  (i12a, p12, 'Mobile Phones', 'iPhone 15 Pro Max, 256 GB, Titanium Natural', 35, 'Pieces', 3200, '8517120000', 'Electronics', false, 'Detain'),
  (i12b, p12, 'Laptop Computers', 'MacBook Pro M3 14″, 16 GB / 512 GB SSD',   10, 'Pieces', 9500, '8471300000', 'Electronics', false, 'Detain'),
  (i12c, p12, 'Wireless Earbuds', 'AirPods Pro 2nd Gen with MagSafe case',     50, 'Pieces', 800,  '8518300000', 'Electronics', false, 'Detain'),
  (i12d, p12, 'Smart Watches',   'Apple Watch Series 9, GPS 45 mm',            20, 'Pieces', 2100, '9102120000', 'Electronics', false, 'Detain'),
  (i12e, p12, 'Tablet Computers','iPad Air M2, 256 GB Wi-Fi',                  15, 'Pieces', 4200, '8471300000', 'Electronics', false, 'Detain');

INSERT INTO public.warehouse_entries (package_id, package_item_id, warehouse_id,
  yard, zone, hold_reason, item_count, daily_rate, admitted_at, is_returned)
VALUES
  (p12, i12a, wh2, 'GL1', '3', 'Excess weight — pending re-weigh', 35, 50, NOW() - INTERVAL '30 days', false),
  (p12, i12b, wh2, 'GL1', '3', 'Excess weight — pending re-weigh', 10, 50, NOW() - INTERVAL '30 days', false),
  (p12, i12c, wh2, 'GL1', '3', 'Excess weight — pending re-weigh', 50, 20, NOW() - INTERVAL '30 days', false),
  (p12, i12d, wh2, 'GL1', '3', 'Excess weight — pending re-weigh', 20, 20, NOW() - INTERVAL '30 days', false),
  (p12, i12e, wh2, 'GL1', '3', 'Excess weight — pending re-weigh', 15, 20, NOW() - INTERVAL '30 days', false);

END $$;


-- ==========================================================================
--  20260621_destruction_per_item.sql
-- ==========================================================================

-- ============================================================================
--  Fix disposal_mark_destruction_item_destroyed to respect per-item forfeited
--  package rows (forfeited_packages.item_id != null).
--
--  Previously the function destroyed ALL package_items when called, regardless
--  of which specific item the destruction_item was linked to via its
--  forfeited_package. Now when the forfeited_package has item_id set (i.e. a
--  per-item FP row created by the new disposal-request flow), only that single
--  item is destroyed. Legacy package-level FP rows (item_id is null) continue
--  to destroy all un-finalised items as before.
-- ============================================================================

create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited   uuid;
  v_package     uuid;
  v_yard        text;
  v_fp_item_id  uuid;   -- item_id on the forfeited_package row (may be null)
  r             record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select forfeited_package_id, yard
    into v_forfeited, v_yard
    from public.destruction_items
   where id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  -- Appeal hold: block the destruction outright.
  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  select package_id, item_id
    into v_package, v_fp_item_id
    from public.forfeited_packages
   where id = v_forfeited;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  -- When the forfeited_package has a specific item_id (per-item FP row created
  -- by the new disposal-request flow), destroy only that item. Otherwise fall
  -- back to destroying all un-finalised items on the package (legacy behaviour).
  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
       and (v_fp_item_id is null or pi.id = v_fp_item_id)
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        r.qty, v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'destroyed' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- Nothing item-level was written (no items, or none linkable). Still surface
  -- the destruction with one package-level [FINAL:DESTROYED] entry.
  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260621_forfeited_entry_qty.sql
-- ==========================================================================

-- ============================================================================
--  Add entry_qty to forfeited_packages so per-entry abandoned disposal-request
--  rows carry the EXACT quantity abandoned in that warehouse entry event.
--
--  Before: a synthetic per-entry abandoned row (one [ABANDONED] warehouse entry
--  = one row, e.g. qty 15 and qty 19 for the same item) created a
--  forfeited_packages row with no quantity. When the Valuation / Central
--  Disposal screens reloaded the row from the DB, the in-memory entryQty was
--  lost and totalQuantity fell back to the FULL PackageItem.quantity (e.g. 200),
--  so both rows wrongly showed 200 and the cost × qty totalled against 200.
--
--  Now: createDisposalRequest() stores the originating warehouse entry's
--  item_count in entry_qty. DisposalRequestItemModel.totalQuantity prefers
--  forfeited.entryQty when present, so each row shows + prices its own qty.
--  Idempotent — safe to re-run.
-- ============================================================================

alter table public.forfeited_packages
  add column if not exists entry_qty integer;

-- Done.


-- ==========================================================================
--  20260622_tender_sale_item_per_item.sql
-- ==========================================================================

-- ============================================================================
--  Per-item delivery tracking for tender_sale_items.
--
--  When a package has multiple items and disposal_mark_sale_item_sold is called,
--  each package_item gets its own [FINAL:SOLD] warehouse entry (with a distinct
--  package_item_id). Previously the delivery flag lived on the single
--  tender_sale_items row for the whole forfeited_package, so toggling delivery
--  for one item showed ALL items of that package as Delivered.
--
--  Fix:
--  1. Add nullable package_item_id to tender_sale_items.
--  2. Drop the unique(forfeited_package_id) constraint and replace it with
--     unique(forfeited_package_id, package_item_id) so we can have one row
--     per sold item when a package has multiple items.
--  3. Replace disposal_mark_sale_item_sold to INSERT one TSI row per item
--     (copying price/taxes from the original package-level TSI row).
--  4. Replace disposal_toggle_delivery_status — unchanged behaviour, but now
--     only the matching TSI row is toggled.
--
--  Idempotent for the schema changes; the function replacements are always safe.
-- ============================================================================

-- 1. ── Add package_item_id column ───────────────────────────────────────────
alter table public.tender_sale_items
  add column if not exists package_item_id uuid
    references public.package_items(id) on delete set null;

create index if not exists idx_tsi_package_item
  on public.tender_sale_items(package_item_id);

-- 2. ── Replace unique constraint ────────────────────────────────────────────
-- Drop old unique(forfeited_package_id) — may have different name depending on
-- when the table was created.
alter table public.tender_sale_items
  drop constraint if exists tender_sale_items_forfeited_package_id_key;

-- Add composite unique with NULLS NOT DISTINCT so (fp_id, NULL) is treated as
-- one slot — without this, every NULL package_item_id is considered distinct
-- and ON CONFLICT can never match the package-level row.
alter table public.tender_sale_items
  drop constraint if exists tender_sale_items_fp_item_unique;
alter table public.tender_sale_items
  add constraint tender_sale_items_fp_item_unique
    unique nulls not distinct (forfeited_package_id, package_item_id);

-- 3. ── Replace disposal_mark_sale_item_sold ──────────────────────────────────
-- Must DROP first because the parameter names changed (p_sold_price → p_price,
-- p_applied_taxes → p_taxes) and PostgreSQL does not allow renaming params with
-- CREATE OR REPLACE.
drop function if exists public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb);

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id   uuid,
  p_receipt   text    default null,
  p_price     numeric default 0,
  p_taxes     jsonb   default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited    uuid;
  v_package      uuid;
  v_yard         text;
  v_fp_item_id   uuid;   -- FP's specific item_id (null = package-level row)
  v_fp_entry_qty int;    -- FP's actual abandoned/forfeited qty (null = use pi.quantity)
  r              record;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_inserted int := 0;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  -- Check appeal hold and read the FP's specific item_id and entry_qty.
  select fp.id, fp.package_id, tsi.yard, fp.item_id, fp.entry_qty
    into v_forfeited, v_package, v_yard, v_fp_item_id, v_fp_entry_qty
    from public.tender_sale_items tsi
    join public.forfeited_packages fp on fp.id = tsi.forfeited_package_id
   where tsi.id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  -- Insert a [FINAL:SOLD] warehouse entry for the relevant package item(s).
  -- When the FP row is per-item (v_fp_item_id is not null) only that specific
  -- item is sold.  When the FP row is package-level (v_fp_item_id is null) all
  -- un-finalised items in the package are sold together (legacy behaviour).
  for r in
    select pi.id as item_id, pi.quantity as qty
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other')
       and (v_fp_item_id is null or pi.id = v_fp_item_id)
  loop
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = r.item_id) desc nulls last, admitted_at desc
     limit 1;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, r.item_id, v_wh, v_zone, v_hold,
        coalesce(v_fp_entry_qty, r.qty), v_adm, coalesce(v_admat, now()), v_rate,
        true, now(), sr_auth.uid(), v_note);

      update public.package_items set status = 'sold' where id = r.item_id;

      delete from public.warehouse_entries
       where package_item_id = r.item_id and is_returned = false;

      -- Upsert a per-item TSI row (copies price/taxes from the package-level row).
      insert into public.tender_sale_items(
        tender_sale_id, forfeited_package_id, package_item_id,
        yard, sold, sold_at, receipt_number,
        sold_price, applied_taxes)
      select
        tsi.tender_sale_id, tsi.forfeited_package_id, r.item_id,
        tsi.yard, true, now(), p_receipt,
        p_price, p_taxes
      from public.tender_sale_items tsi
      where tsi.id = p_item_id
      on conflict (forfeited_package_id, package_item_id)
      do update set
        sold          = true,
        sold_at       = now(),
        receipt_number = p_receipt,
        sold_price    = p_price,
        applied_taxes = p_taxes;

      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- Fallback: package has no individual items linkable to a warehouse entry.
  if v_inserted = 0 then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by admitted_at desc
     limit 1;

    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_wh is not null then
      insert into public.warehouse_entries(
        package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate,
        is_returned, returned_at, returned_by, return_notes)
      values (
        v_package, v_yard, null, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
        1, v_adm, coalesce(v_admat, now()), coalesce(v_rate, 0),
        true, now(), sr_auth.uid(), v_note);
    end if;
  end if;

  -- Mark the original package-level TSI row sold too (keeps backward compat).
  update public.tender_sale_items
     set sold = true, sold_at = now(), receipt_number = p_receipt,
         sold_price = p_price, applied_taxes = p_taxes
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260624_tender_sales_yard_read.sql
-- ==========================================================================

-- ============================================================================
--  Allow yard officers to read tender_sales that contain their yard's packages.
--
--  Previously tender_sales had no read policy for officers/admins — only
--  disposal-directorate users could query it. The yard Tender Sale screen
--  (tender_disposal_screen.dart) watches tenderSalesProvider which calls
--  getTenderSales(), so without this policy the screen always returned empty.
-- ============================================================================

-- Officers & admins can read a tender_sale when at least one of its items
-- belongs to their yard (profiles.yard match).
drop policy if exists tender_sales_yard_read on public.tender_sales;
create policy tender_sales_yard_read on public.tender_sales
  for select
  using (
    exists (
      select 1
        from public.tender_sale_items tsi
        join public.profiles p on p.id = sr_auth.uid()
       where tsi.tender_sale_id = tender_sales.id
         and tsi.yard = p.yard
    )
  );


-- ==========================================================================
--  20260625_destruction_per_di_item.sql
-- ==========================================================================

-- ============================================================================
--  Item-scope destruction the same way tender sales are item-scoped.
--
--  Bug: when a forfeited_packages row is package-level (item_id IS NULL), the
--  disposal_mark_destruction_item_destroyed RPC destroyed EVERY un-finalised
--  item in the package — destroying e.g. Palm Oil when the yard only meant to
--  destroy Jasmine Rice. This corrupts data at scale.
--
--  Fix:
--    1. Add nullable package_item_id to destruction_items + composite unique
--       (forfeited_package_id, package_item_id) with NULLS NOT DISTINCT.
--    2. createDestruction now stores the covered item's id on each row.
--    3. RPC prefers the destruction_items row's own package_item_id, then the
--       FP's item_id; only when BOTH are null does it fall back to legacy
--       whole-package destruction.
--
--  Idempotent for schema; the function replacement is always safe.
-- ============================================================================

-- 1. ── Add package_item_id column ───────────────────────────────────────────
alter table public.destruction_items
  add column if not exists package_item_id uuid
    references public.package_items(id) on delete set null;

create index if not exists idx_di_package_item
  on public.destruction_items(package_item_id);

-- 2. ── Replace unique constraint ────────────────────────────────────────────
alter table public.destruction_items
  drop constraint if exists destruction_items_forfeited_package_id_key;
alter table public.destruction_items
  drop constraint if exists destruction_items_fp_item_unique;
alter table public.destruction_items
  add constraint destruction_items_fp_item_unique
    unique nulls not distinct (forfeited_package_id, package_item_id);

-- 3. ── Replace the RPC to honour the row's own package_item_id ───────────────
create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited    uuid;
  v_package      uuid;
  v_yard         text;
  v_fp_item_id   uuid;   -- FP row's item_id (null = package-level row)
  v_fp_entry_qty int;    -- FP row's recorded forfeited/abandoned qty
  v_di_item_id   uuid;   -- the destruction_items row's own package_item_id
  v_target_item  uuid;   -- item we will actually destroy
  v_target_qty   int;    -- qty to record for a single-item destruction
  v_unfinalised  int;    -- count of un-finalised items in the package
  v_only_item    uuid;   -- the sole un-finalised item id (when count = 1)
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select di.forfeited_package_id, di.yard, di.package_item_id
    into v_forfeited, v_yard, v_di_item_id
    from public.destruction_items di
   where di.id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  select package_id, item_id, entry_qty
    into v_package, v_fp_item_id, v_fp_entry_qty
    from public.forfeited_packages
   where id = v_forfeited;

  -- The item to destroy: the DI row's own item wins, then the FP's item.
  v_target_item := coalesce(v_di_item_id, v_fp_item_id);
  v_target_qty  := v_fp_entry_qty;

  -- Safety net: if no specific item resolved AND the package has >1 un-finalised
  -- item, refuse rather than bulk-destroying every item. Auto-pick only when the
  -- package has exactly one un-finalised item.
  if v_target_item is null then
    select count(*), min(pi.id)
      into strict v_unfinalised, v_only_item
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other');
    if v_unfinalised > 1 then
      raise exception 'ambiguous_destruction_item: destruction_item % covers a '
        'package with % un-finalised items but names no package_item_id',
        p_item_id, v_unfinalised;
    end if;
    v_target_item := v_only_item;
  end if;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  -- Record EXACTLY ONE [FINAL:DESTROYED] entry for the resolved item — directly,
  -- not via a loop — so we never bulk-destroy siblings and partial destructions
  -- of the same item still record (no status gate / NULL-item fallback).
  if v_target_item is not null then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = v_target_item) desc nulls last, admitted_at desc
     limit 1;
    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_target_qty is null then
      select pi.quantity into v_target_qty
        from public.package_items pi where pi.id = v_target_item;
    end if;

    insert into public.warehouse_entries(
      package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
      item_count, admitted_by, admitted_at, daily_rate,
      is_returned, returned_at, returned_by, return_notes)
    values (
      v_package, v_yard, v_target_item, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
      coalesce(v_target_qty, 1), v_adm, coalesce(v_admat, now()),
      coalesce(v_rate, 0), true, now(), sr_auth.uid(), v_note);

    update public.package_items set status = 'destroyed' where id = v_target_item;

    delete from public.warehouse_entries
     where package_item_id = v_target_item and is_returned = false;
  end if;

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260625_autofill_package_item.sql
-- ==========================================================================

-- ============================================================================
--  BULLETPROOF item-scoping for tender / destruction sale rows.
--
--  Problem: tender_sale_items / destruction_items rows sometimes had
--  package_item_id = NULL (e.g. the app build that created them predated the
--  client-side stamping). With a NULL item id the mark-sold / mark-destroyed
--  RPC could not tell which item to process and bulk-processed the whole
--  package — selling Palm Oil alongside Jasmine Rice.
--
--  This migration makes the item id self-healing at the DATABASE layer, so it
--  works regardless of which app build inserts the row:
--
--    1. BEFORE INSERT triggers auto-fill package_item_id from the forfeited
--       package's own item_id whenever the client leaves it NULL.
--    2. A one-time backfill repairs existing rows the same way (skipping any
--       that would collide with an already-stamped sibling row).
--
--  Pair this with 20260625_mark_sold_per_tsi_item.sql /
--  20260625_destruction_per_di_item.sql (the guarded RPCs) for full coverage:
--  if an FP row is genuinely package-level (item_id NULL) the RPC refuses to
--  bulk-process instead of corrupting data.
--
--  Idempotent.
-- ============================================================================

-- 1. ── Auto-fill function (shared shape, one per table for clarity) ──────────
create or replace function public.tsi_autofill_package_item()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.package_item_id is null then
    select fp.item_id
      into new.package_item_id
      from public.forfeited_packages fp
     where fp.id = new.forfeited_package_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_tsi_autofill_package_item on public.tender_sale_items;
DROP TRIGGER IF EXISTS trg_tsi_autofill_package_item ON public.tender_sale_items;
CREATE TRIGGER trg_tsi_autofill_package_item
  before insert on public.tender_sale_items
  for each row execute function public.tsi_autofill_package_item();

create or replace function public.di_autofill_package_item()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.package_item_id is null then
    select fp.item_id
      into new.package_item_id
      from public.forfeited_packages fp
     where fp.id = new.forfeited_package_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_di_autofill_package_item on public.destruction_items;
DROP TRIGGER IF EXISTS trg_di_autofill_package_item ON public.destruction_items;
CREATE TRIGGER trg_di_autofill_package_item
  before insert on public.destruction_items
  for each row execute function public.di_autofill_package_item();

-- 2. ── Backfill existing rows from the FP's item_id (collision-safe) ─────────
--  Only stamps a row when the FP names a specific item AND no sibling row for
--  the same (forfeited_package_id, item_id) already exists.
update public.tender_sale_items tsi
   set package_item_id = fp.item_id
  from public.forfeited_packages fp
 where tsi.forfeited_package_id = fp.id
   and tsi.package_item_id is null
   and fp.item_id is not null
   and not exists (
     select 1 from public.tender_sale_items x
      where x.forfeited_package_id = tsi.forfeited_package_id
        and x.package_item_id = fp.item_id
        and x.id <> tsi.id
   );

update public.destruction_items di
   set package_item_id = fp.item_id
  from public.forfeited_packages fp
 where di.forfeited_package_id = fp.id
   and di.package_item_id is null
   and fp.item_id is not null
   and not exists (
     select 1 from public.destruction_items x
      where x.forfeited_package_id = di.forfeited_package_id
        and x.package_item_id = fp.item_id
        and x.id <> di.id
   );

-- Done.


-- ==========================================================================
--  20260625_mark_sold_per_tsi_item.sql
-- ==========================================================================

-- ============================================================================
--  Fix disposal_mark_sale_item_sold so it sells exactly ONE item when the
--  tender_sale_items row identifies one — never the whole package.
--
--  Bug: when a forfeited_packages row is package-level (item_id IS NULL) the
--  function looped over EVERY un-finalised item in the package and marked them
--  all SOLD (e.g. selling Palm Oil when the yard only sold Jasmine Rice), each
--  copying the same sold_price. This produced bogus extra Sold rows.
--
--  Fix: prefer the TSI row's own package_item_id (per-item sale rows carry it);
--  fall back to the FP's item_id; only when BOTH are null do we keep the legacy
--  whole-package behaviour. The qty uses the FP's recorded entry_qty.
--
--  Always-safe replacement (same signature).
-- ============================================================================

create or replace function public.disposal_mark_sale_item_sold(
  p_item_id   uuid,
  p_receipt   text    default null,
  p_price     numeric default 0,
  p_taxes     jsonb   default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited     uuid;
  v_package       uuid;
  v_yard          text;
  v_fp_item_id    uuid;   -- FP's specific item_id (null = package-level row)
  v_fp_entry_qty  int;    -- FP's actual abandoned/forfeited qty
  v_tsi_item_id   uuid;   -- the TSI row's own package_item_id (per-item sales)
  v_target_item   uuid;   -- the item we will actually sell
  v_target_qty    int;    -- qty to record for a single-item sale
  v_unfinalised   int;    -- count of un-finalised items in the package
  v_only_item     uuid;   -- the sole un-finalised item id (when count = 1)
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  -- Read FP item/qty AND the TSI row's own package_item_id (per-item sales).
  select fp.id, fp.package_id, tsi.yard, fp.item_id, fp.entry_qty,
         tsi.package_item_id
    into v_forfeited, v_package, v_yard, v_fp_item_id, v_fp_entry_qty,
         v_tsi_item_id
    from public.tender_sale_items tsi
    join public.forfeited_packages fp on fp.id = tsi.forfeited_package_id
   where tsi.id = p_item_id;
  if v_forfeited is null then
    raise exception 'tender sale item not found';
  end if;

  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  -- The item to sell: the TSI row's own item wins, then the FP's item.
  v_target_item := coalesce(v_tsi_item_id, v_fp_item_id);
  -- The qty to record for a single-item sale: the FP's recorded entry_qty.
  v_target_qty  := v_fp_entry_qty;

  -- Safety net: if we couldn't resolve a specific item AND the package has more
  -- than one un-finalised item, refuse rather than bulk-selling every item
  -- (which is the bug that sold Palm Oil alongside Jasmine Rice). Auto-pick the
  -- item only when the package has exactly one un-finalised item.
  if v_target_item is null then
    select count(*), min(pi.id)
      into strict v_unfinalised, v_only_item
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other');
    if v_unfinalised > 1 then
      raise exception 'ambiguous_sale_item: tender_sale_item % covers a package '
        'with % un-finalised items but names no package_item_id', p_item_id,
        v_unfinalised;
    end if;
    v_target_item := v_only_item;  -- the single item (or null when none left)
  end if;

  v_note := '[FINAL:SOLD]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt: ' || p_receipt else '' end;

  -- At this point v_target_item is a single resolved item id (or null only when
  -- the package genuinely has no un-finalised items). Record EXACTLY ONE
  -- [FINAL:SOLD] entry for it — directly, not via a loop over package_items, so
  -- that:
  --   • we never bulk-sell sibling items (the Palm-Oil bug), and
  --   • partial sales of the SAME item still record (no status gate that would
  --     otherwise force a bogus NULL-item fallback entry on the 2nd partial).
  if v_target_item is not null then
    -- Warehouse context: prefer an entry already on this item, else any on the
    -- package, else any warehouse.
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = v_target_item) desc nulls last, admitted_at desc
     limit 1;
    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    -- Qty: the disposition's recorded qty, else the item's registered quantity.
    if v_target_qty is null then
      select pi.quantity into v_target_qty
        from public.package_items pi where pi.id = v_target_item;
    end if;

    insert into public.warehouse_entries(
      package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
      item_count, admitted_by, admitted_at, daily_rate,
      is_returned, returned_at, returned_by, return_notes)
    values (
      v_package, v_yard, v_target_item, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
      coalesce(v_target_qty, 1), v_adm, coalesce(v_admat, now()),
      coalesce(v_rate, 0), true, now(), sr_auth.uid(), v_note);

    update public.package_items set status = 'sold' where id = v_target_item;

    -- Clear any lingering ACTIVE (un-returned) entry for this item so it leaves
    -- the live warehouse view; the [FINAL:SOLD] row above is the record of sale.
    delete from public.warehouse_entries
     where package_item_id = v_target_item and is_returned = false;
  end if;

  -- Mark this tender_sale_item row sold (price/taxes/receipt recorded on it).
  update public.tender_sale_items
     set sold = true, sold_at = now(), receipt_number = p_receipt,
         sold_price = p_price, applied_taxes = p_taxes
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_sale_item_sold(uuid, text, numeric, jsonb)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260630_destruction_price.sql
-- ==========================================================================

-- ============================================================================
--  Add a destruction price + taxes to destruction_items, and let the
--  Mark-Destroyed RPC store them — mirroring the tender-sale flow so the
--  Destroyed Packages table / popup can show the destruction price.
-- ============================================================================

alter table public.destruction_items
  add column if not exists destroyed_price numeric(14,2) not null default 0,
  add column if not exists applied_taxes  jsonb        not null default '[]'::jsonb;

-- Replace the RPC to accept + store the price/taxes (extra optional params, so
-- existing callers keep working). The function otherwise matches
-- 20260625_destruction_per_di_item.sql.
drop function if exists public.disposal_mark_destruction_item_destroyed(uuid, text);
drop function if exists public.disposal_mark_destruction_item_destroyed(uuid, text, numeric, jsonb);

create or replace function public.disposal_mark_destruction_item_destroyed(
  p_item_id uuid,
  p_receipt text    default null,
  p_price   numeric default 0,
  p_taxes   jsonb   default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_forfeited    uuid;
  v_package      uuid;
  v_yard         text;
  v_fp_item_id   uuid;
  v_fp_entry_qty int;
  v_di_item_id   uuid;
  v_target_item  uuid;
  v_target_qty   int;
  v_unfinalised  int;
  v_only_item    uuid;
  v_wh    uuid;
  v_zone  text;
  v_hold  text;
  v_adm   uuid;
  v_admat timestamptz;
  v_rate  numeric;
  v_note  text;
begin
  if not public.auth_user_is_disposal() then
    raise exception 'not authorized';
  end if;

  select di.forfeited_package_id, di.yard, di.package_item_id
    into v_forfeited, v_yard, v_di_item_id
    from public.destruction_items di
   where di.id = p_item_id;
  if v_forfeited is null then
    raise exception 'destruction item not found';
  end if;

  if (select appeal_hold from public.forfeited_packages where id = v_forfeited) then
    raise exception 'appeal_hold_active';
  end if;

  select package_id, item_id, entry_qty
    into v_package, v_fp_item_id, v_fp_entry_qty
    from public.forfeited_packages
   where id = v_forfeited;

  v_target_item := coalesce(v_di_item_id, v_fp_item_id);
  v_target_qty  := v_fp_entry_qty;

  if v_target_item is null then
    select count(*), min(pi.id)
      into strict v_unfinalised, v_only_item
      from public.package_items pi
     where pi.package_id = v_package
       and lower(pi.status) not in
           ('sold', 'destroyed', 'released', 're-exported', 'other');
    if v_unfinalised > 1 then
      raise exception 'ambiguous_destruction_item: destruction_item % covers a '
        'package with % un-finalised items but names no package_item_id',
        p_item_id, v_unfinalised;
    end if;
    v_target_item := v_only_item;
  end if;

  v_note := '[FINAL:DESTROYED]' ||
    case when coalesce(p_receipt, '') <> ''
         then ' — Receipt/Notes: ' || p_receipt else '' end;

  if v_target_item is not null then
    select warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate
      into v_wh, v_zone, v_hold, v_adm, v_admat, v_rate
      from public.warehouse_entries
     where package_id = v_package
     order by (package_item_id = v_target_item) desc nulls last, admitted_at desc
     limit 1;
    if v_wh is null then
      select id into v_wh from public.warehouses order by created_at limit 1;
      v_hold := 'Forfeit';
    end if;

    if v_target_qty is null then
      select pi.quantity into v_target_qty
        from public.package_items pi where pi.id = v_target_item;
    end if;

    insert into public.warehouse_entries(
      package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
      item_count, admitted_by, admitted_at, daily_rate,
      is_returned, returned_at, returned_by, return_notes)
    values (
      v_package, v_yard, v_target_item, v_wh, v_zone, coalesce(v_hold, 'Forfeit'),
      coalesce(v_target_qty, 1), v_adm, coalesce(v_admat, now()),
      coalesce(v_rate, 0), true, now(), sr_auth.uid(), v_note);

    update public.package_items set status = 'destroyed' where id = v_target_item;

    delete from public.warehouse_entries
     where package_item_id = v_target_item and is_returned = false;
  end if;

  update public.destruction_items
     set destroyed = true, destroyed_at = now(), notes = p_receipt,
         destroyed_price = p_price, applied_taxes = p_taxes
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_mark_destruction_item_destroyed(uuid, text, numeric, jsonb)
  to authenticated;

-- Done.


-- ==========================================================================
--  20260707_admin_config_realtime.sql
-- ==========================================================================

-- ============================================================================
--  Realtime for Admin Panel config tables: hold_reasons + storage_rates.
--
--  Symptom this fixes: adding/editing a Hold Reason (or a Storage Charge) in one
--  logged-in session does NOT appear in another open session until that page is
--  manually refreshed. package_categories already live-updates because it is in
--  the publication; these two were missing.
--
--  The app subscribes to these tables via onPostgresChanges
--  (hold-reasons-realtime / storage-rates-realtime channels in providers.dart),
--  but Supabase only broadcasts row changes for tables in the
--  `supabase_realtime` publication — so the callback never fired.
--
--  IDEMPOTENT (safe to re-run). Run in the Supabase SQL Editor.
--  ⚠️  CLOSE THE RUNNING APP FIRST (the ALTERs take a brief lock).
-- ============================================================================

-- 1. ── Add the two tables to the realtime publication if missing ────────────
do $$
declare
  t text;
begin
  foreach t in array array['hold_reasons', 'storage_rates'] loop
    if to_regclass('public.' || t) is not null
       and not exists (
         select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = t
       ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
      raise notice 'added % to supabase_realtime', t;
    else
      raise notice 'skipped % (missing or already published)', t;
    end if;
  end loop;
end $$;

-- 2. ── REPLICA IDENTITY FULL so UPDATE/DELETE broadcast the whole row ────────
--    (e.g. toggling a hold reason's Active flag, or editing a storage rate).
alter table public.hold_reasons  replica identity full;
alter table public.storage_rates replica identity full;

-- 3. ── Verify: both should show published = true ─────────────────────────────
with app_tables(tablename) as (
  values ('hold_reasons'), ('storage_rates')
)
select a.tablename,
       (pt.tablename is not null) as published
  from app_tables a
  left join pg_publication_tables pt
    on pt.pubname = 'supabase_realtime'
   and pt.schemaname = 'public'
   and pt.tablename = a.tablename
 order by a.tablename;

-- Done. Relaunch the app — Hold Reasons and Storage Charges now live-update
-- across every open session (Admin Panel + SR-form reason pickers).


-- ==========================================================================
--  20260710_destructions_yard_read.sql
-- ==========================================================================

-- ============================================================================
--  Allow yard officers to read `destructions` that contain their yard's items.
--
--  BUG: the yard Destruction Sale screen (destruction_disposal_screen.dart)
--  watches destructionsProvider → getDestructions(), which selects from the
--  `destructions` header table with `destruction_items` nested. But the only
--  read policy on `destructions` was `destructions_manage`, restricted to
--  disposal users + admins. Officers therefore got ZERO destruction rows
--  (the header is RLS-blocked, so the nested items never surface either),
--  and the page always showed "No destruction sales for this yard yet" even
--  after an item was destroyed.
--
--  `destruction_items` already has a yard-read policy (destruction_items_yard_read),
--  so this mirrors 20260624_tender_sales_yard_read.sql for the header table:
--  an officer/admin may READ a destruction when at least one of its items
--  belongs to their yard.
-- ============================================================================

drop policy if exists destructions_yard_read on public.destructions;
create policy destructions_yard_read on public.destructions
  for select
  using (
    exists (
      select 1
        from public.destruction_items di
        join public.profiles p on p.id = sr_auth.uid()
       where di.destruction_id = destructions.id
         and di.yard = p.yard
    )
  );


-- ==========================================================================
--  20260710_fix_appeal_hold_null.sql
-- ==========================================================================

-- ============================================================================
--  FIX: set_appeal_hold set appeal_hold = NULL when releasing the last held
--  item, violating the NOT NULL constraint on forfeited_packages.appeal_hold.
--
--  BUG: the RPC synced the legacy boolean flag with
--       appeal_hold = (array_length(v_new_ids, 1) > 0)
--  In PostgreSQL, array_length('{}', 1) returns NULL (not 0) for an empty
--  array, so releasing the last held item made the expression NULL > 0 = NULL,
--  and the UPDATE tried to store appeal_hold = NULL → error 23502:
--    null value in column "appeal_hold" ... violates not-null constraint
--  This surfaced when the Appeal Directorate pressed "Confirm & Release Hold"
--  (or unheld an item), because that path clears held_item_ids to '{}'.
--
--  FIX: use cardinality(), which returns 0 (not NULL) for an empty array, so
--  the flag is always a real boolean. Same substitution in the note/date/by
--  CASE expressions for consistency.
-- ============================================================================

create or replace function public.set_appeal_hold(
  p_forfeited_id uuid,
  p_hold         boolean,
  p_note         text    default null,
  p_item_id      uuid    default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_deadline    timestamptz;
  v_item_ids    uuid[];
  v_new_ids     uuid[];
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select appeal_deadline, held_item_ids
    into v_deadline, v_item_ids
    from public.forfeited_packages
   where id = p_forfeited_id;

  if v_deadline is null then
    raise exception 'forfeited package not found';
  end if;

  if p_hold and v_deadline < now() then
    raise exception 'appeal_window_passed';
  end if;

  v_item_ids := coalesce(v_item_ids, '{}');

  if p_hold then
    if p_item_id is not null then
      -- Add item to held set (avoid duplicates).
      if not (v_item_ids @> array[p_item_id]) then
        v_new_ids := v_item_ids || array[p_item_id];
      else
        v_new_ids := v_item_ids;
      end if;
    else
      -- p_item_id null → not used in new flow, keep existing.
      v_new_ids := v_item_ids;
    end if;
  else
    if p_item_id is not null then
      -- Remove specific item from held set.
      select array_agg(x) into v_new_ids
        from unnest(v_item_ids) x
       where x <> p_item_id;
      if v_new_ids is null then v_new_ids := '{}'; end if;
    else
      -- Release all.
      v_new_ids := '{}';
    end if;
  end if;

  update public.forfeited_packages
     set held_item_ids  = v_new_ids,
         -- cardinality() → 0 (not NULL) for '{}', so the flag is never NULL.
         appeal_hold    = (cardinality(v_new_ids) > 0),
         appeal_hold_note = case
           when cardinality(v_new_ids) > 0 then p_note
           else null
         end,
         appeal_held_at = case
           when cardinality(v_new_ids) > 0 then coalesce(appeal_held_at, now())
           else null
         end,
         appeal_held_by = case
           when cardinality(v_new_ids) > 0 then coalesce(appeal_held_by, sr_auth.uid())
           else null
         end
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.set_appeal_hold(uuid, boolean, text, uuid) to authenticated;

-- ── Per-item appeal decisions ───────────────────────────────────────────────
-- The Appeal Directorate decides ONE item at a time, but the decision was being
-- written to the package-level appeal_decision column — so deciding one item of
-- a multi-item package wrongly marked EVERY item decided (it vanished from the
-- Appeal list and every yard row showed "→ Sell"). Mirror the per-item hold
-- design: store decisions in a jsonb map keyed by item id.
alter table public.forfeited_packages
  add column if not exists item_appeal_decisions jsonb not null default '{}'::jsonb;

-- release_appeal_with_decision now takes p_item_id. When given, it records the
-- decision for that ONE item (jsonb map) and releases only that item's hold —
-- leaving siblings untouched. When null (legacy / single-item), it keeps the old
-- package-level behaviour.
create or replace function public.release_appeal_with_decision(
  p_forfeited_id uuid,
  p_decision     text,
  p_note         text default null,
  p_item_id      uuid default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_item_ids uuid[];
  v_new_ids  uuid[];
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select coalesce(held_item_ids, '{}') into v_item_ids
    from public.forfeited_packages
   where id = p_forfeited_id;
  if v_item_ids is null then
    raise exception 'forfeited package not found';
  end if;

  if p_item_id is not null then
    -- Remove ONLY this item from the held set (siblings keep their holds).
    select coalesce(array_agg(x), '{}') into v_new_ids
      from unnest(v_item_ids) x
     where x <> p_item_id;

    update public.forfeited_packages
       set item_appeal_decisions = coalesce(item_appeal_decisions, '{}'::jsonb)
             || jsonb_build_object(
                  p_item_id::text,
                  jsonb_build_object(
                    'decision',    p_decision,
                    'note',        p_note,
                    'decided_at',  now(),
                    'decided_by',  sr_auth.uid()
                  )),
           held_item_ids = v_new_ids,
           appeal_hold   = (cardinality(v_new_ids) > 0),
           appeal_hold_note = case
             when cardinality(v_new_ids) > 0 then appeal_hold_note else null end,
           appeal_held_at = case
             when cardinality(v_new_ids) > 0 then appeal_held_at else null end,
           appeal_held_by = case
             when cardinality(v_new_ids) > 0 then appeal_held_by else null end
     where id = p_forfeited_id;
  else
    -- Legacy package-level decision (single-item / no item id supplied).
    update public.forfeited_packages
       set appeal_hold      = false,
           held_item_ids    = '{}',
           appeal_hold_note  = null,
           appeal_held_at    = null,
           appeal_held_by    = null,
           appeal_decision   = p_decision,
           appeal_decision_note = p_note,
           appeal_decided_at = now(),
           appeal_decided_by = sr_auth.uid()
     where id = p_forfeited_id;
  end if;
end;
$$;

grant execute on function public.release_appeal_with_decision(uuid, text, text, uuid) to authenticated;

-- Repair any rows the old buggy RPC may already have left with a NULL
-- appeal_hold (e.g. a failed "release last item" attempt): a NULL flag means
-- "no items held" → set it to a real boolean derived from held_item_ids.
update public.forfeited_packages
   set appeal_hold = (cardinality(coalesce(held_item_ids, '{}')) > 0)
 where appeal_hold is null;

-- Clear STALE package-level appeal decisions on MULTI-ITEM packages: the old
-- flow wrote one item's decision to the whole package, so a sibling with no
-- decision inherited it (e.g. deciding 34567rtyu marked erty "Sell" too). Now
-- that decisions are per-item (item_appeal_decisions), the package-level column
-- must not bleed across a multi-item package — clear it so undecided siblings
-- return to the appeal window. Single-item packages keep it (valid fallback).
update public.forfeited_packages fp
   set appeal_decision      = null,
       appeal_decision_note = null,
       appeal_decided_at    = null,
       appeal_decided_by    = null
 where fp.appeal_decision is not null
   and (select count(*) from public.package_items pi
         where pi.package_id = fp.package_id) > 1;


-- ==========================================================================
--  20260714_carton_inner_unit.sql
-- ==========================================================================

-- ============================================================================
--  Carton inner contents
-- ----------------------------------------------------------------------------
--  When a package item's unit is "Cartons", the registration form also captures
--  what each carton contains (inner unit type) and how many of that inner unit.
--  NULL for any item whose unit is not Cartons.
-- ============================================================================

alter table public.package_items
  add column if not exists inner_unit text;

alter table public.package_items
  add column if not exists inner_quantity int;


-- ==========================================================================
--  20260714_executive_directorate.sql
-- ==========================================================================

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
set search_path = public, extensions
as $$
  select exists(
    select 1 from public.profiles
    where id = sr_auth.uid() and role = 'executive'
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
set search_path = public, extensions
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'executive' and lower(username) = lower(code)
  );
$$;

grant execute on function public.executive_position_available(text) to anon, authenticated;


-- ==========================================================================
--  20260714_old_sr_number.sql
-- ==========================================================================

-- ============================================================================
--  Old-entry SR registration
-- ----------------------------------------------------------------------------
--  Package Registration now has two modes: "New Entry" (normal) and
--  "Old Entry". An Old Entry captures the SR number the goods carried in the
--  previous/legacy register, stored here alongside the freshly generated SR.
--  NULL for every normal (new) registration.
-- ============================================================================

alter table public.packages
  add column if not exists old_sr_number text;

-- ==========================================================================
--  20260714_retender_keep_original.sql
-- ==========================================================================

-- ============================================================================
--  Re-tender / re-destruction must KEEP the original sale row.
--
--  Before: tender_sale_items / destruction_items had a unique constraint on
--  (forfeited_package_id, package_item_id). Re-tendering an unsold item reused
--  the same forfeited_package_id, so the ON CONFLICT upsert UPDATED (moved) the
--  existing row into the new sale — the item vanished from the original sale.
--
--  The yard needs the item to stay in the ORIGINAL sale as Unsold AND appear in
--  the re-tender sale as Pending (same item, two sales, different status). So
--  scope uniqueness PER SALE by adding the sale id to the unique key. Then a
--  re-tender into a new sale INSERTS a fresh row and the original is untouched.
--
--  This is strictly more permissive than before (an extra column in the key),
--  so no existing row can violate it.
-- ============================================================================

-- 1. ── tender_sale_items ─────────────────────────────────────────────────────
alter table public.tender_sale_items
  drop constraint if exists tender_sale_items_fp_item_unique;
alter table public.tender_sale_items
  add constraint tender_sale_items_fp_item_unique
    unique nulls not distinct
      (tender_sale_id, forfeited_package_id, package_item_id);

-- 2. ── destruction_items ─────────────────────────────────────────────────────
alter table public.destruction_items
  drop constraint if exists destruction_items_fp_item_unique;
alter table public.destruction_items
  add constraint destruction_items_fp_item_unique
    unique nulls not distinct
      (destruction_id, forfeited_package_id, package_item_id);


-- ==========================================================================
--  20260715_tender_bids.sql
-- ==========================================================================

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
  created_by           uuid references sr_auth.users(id),
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

-- 4. ── Realtime: publish tender_bids so tables live-update across portals ────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'tender_bids'
  ) then
    alter publication supabase_realtime add table public.tender_bids;
  end if;
end $$;


-- ==========================================================================
--  20260716_tender_revaluations.sql
-- ==========================================================================

-- ============================================================================
--  Tender Re-valuations — a fresh valuation the Valuation Directorate sets for
--  an unsold tender package, per tender ROUND. Central Disposal reads it back.
--  Run after 20260715_tender_bids.sql.
--
--  Flow: unsold tender → Central Disposal records the bids → Valuation reviews
--  the bids and sets a NEW valuation for the current tender round → Central
--  Disposal sees that re-valuation → re-tenders. If it goes unsold again the
--  same cycle repeats for the next round.
--
--  Keyed by (forfeited_package_id, tender_sale_id) — one re-valuation per round.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Table ────────────────────────────────────────────────────────────────
create table if not exists public.tender_revaluations (
  id                   uuid primary key default gen_random_uuid(),
  forfeited_package_id uuid not null
                         references public.forfeited_packages(id) on delete cascade,
  tender_sale_id       uuid
                         references public.tender_sales(id) on delete cascade,
  valuation_cost       numeric not null,
  note                 text,
  yard                 text,
  created_by           uuid references sr_auth.users(id),
  created_at           timestamptz not null default now()
);

create index if not exists tender_revaluations_fp_idx
  on public.tender_revaluations(forfeited_package_id);
create index if not exists tender_revaluations_sale_idx
  on public.tender_revaluations(tender_sale_id);

alter table public.tender_revaluations enable row level security;

-- 2. ── Valuation Directorate: full read/write (they set the re-valuation) ────
drop policy if exists tender_reval_valuation_all on public.tender_revaluations;
create policy tender_reval_valuation_all on public.tender_revaluations
  for all
  using (public.auth_user_is_valuation())
  with check (public.auth_user_is_valuation());

-- 3. ── Central Disposal: read-only (sees the re-valuation before re-tender) ──
drop policy if exists tender_reval_disposal_read on public.tender_revaluations;
create policy tender_reval_disposal_read on public.tender_revaluations
  for select
  using (public.auth_user_is_disposal());

-- 4. ── Appeal Directorate: read-only (context alongside the bids) ────────────
drop policy if exists tender_reval_appeal_read on public.tender_revaluations;
create policy tender_reval_appeal_read on public.tender_revaluations
  for select
  using (public.auth_user_is_appeal());

-- 5. ── Valuation needs to READ the unsold-tender data + the bids ─────────────
--  The Valuation "Unsold Tenders" page loads getUnsoldTenderSales() (tender
--  sales/items) and the recorded bids — grant cross-yard SELECT on those.
drop policy if exists valuation_read_all on public.tender_sales;
create policy valuation_read_all on public.tender_sales
  for select using (public.auth_user_is_valuation());

drop policy if exists valuation_read_all on public.tender_sale_items;
create policy valuation_read_all on public.tender_sale_items
  for select using (public.auth_user_is_valuation());

drop policy if exists tender_bids_valuation_read on public.tender_bids;
create policy tender_bids_valuation_read on public.tender_bids
  for select using (public.auth_user_is_valuation());

-- 6. ── Realtime: publish tender_revaluations for live cross-portal updates ───
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'tender_revaluations'
  ) then
    alter publication supabase_realtime add table public.tender_revaluations;
  end if;
end $$;


-- ==========================================================================
--  20260717_valuation_per_item_forward.sql
-- ==========================================================================

-- ============================================================================
--  Per-item valuation forwarding
--  Run after 20260617_valuation_directorate.sql.
--
--  Until now the Valuation Directorate valued & forwarded a whole disposal
--  REQUEST at once (disposal_requests.valuation_status). This lets a single
--  ITEM be valued and forwarded on its own: each disposal_request_item carries
--  its own `forwarded` flag, and Central Disposal's feeds gate on that flag.
--  A "Forward All" still forwards every item of a request in one go.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Per-item forwarded flag ──────────────────────────────────────────────
alter table public.disposal_request_items
  add column if not exists forwarded boolean not null default false;

-- Backfill: items of requests already forwarded count as forwarded.
update public.disposal_request_items i
   set forwarded = true
  from public.disposal_requests r
 where i.request_id = r.id
   and r.valuation_status = 'forwarded'
   and i.forwarded = false;

-- 2. ── Set ONE item's cost (Valuation Directorate) ──────────────────────────
create or replace function public.valuation_set_item_cost(
  p_item_id uuid,
  p_cost    numeric
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;
  update public.disposal_request_items
     set valuation_cost = p_cost
   where id = p_item_id;
end;
$$;

grant execute on function public.valuation_set_item_cost(uuid, numeric)
  to authenticated;

-- 3. ── Forward ONE valued item to Central Disposal ──────────────────────────
create or replace function public.valuation_forward_item(
  p_item_id uuid
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_request uuid;
  v_cost    numeric;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  select request_id, valuation_cost into v_request, v_cost
    from public.disposal_request_items
   where id = p_item_id;

  if v_request is null then
    raise exception 'item not found';
  end if;
  if v_cost is null then
    raise exception 'valuation_incomplete';  -- this item still needs a cost
  end if;

  update public.disposal_request_items
     set forwarded = true
   where id = p_item_id;

  -- Keep the request-level status coherent: forwarded once any item is; and
  -- record who/when valued it (first forward wins for the timestamp).
  update public.disposal_requests
     set valuation_status = 'forwarded',
         valued_at = coalesce(valued_at, now()),
         valued_by = coalesce(valued_by, sr_auth.uid())
   where id = v_request;
end;
$$;

grant execute on function public.valuation_forward_item(uuid) to authenticated;

-- 4. ── Forward EVERY item of a request (bulk) — all must be valued ──────────
create or replace function public.valuation_forward_all(
  p_request_id uuid
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_missing int;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  select count(*) into v_missing
    from public.disposal_request_items
   where request_id = p_request_id
     and valuation_cost is null;
  if v_missing > 0 then
    raise exception 'valuation_incomplete';
  end if;

  update public.disposal_request_items
     set forwarded = true
   where request_id = p_request_id;

  update public.disposal_requests
     set valuation_status = 'forwarded',
         valued_at = coalesce(valued_at, now()),
         valued_by = coalesce(valued_by, sr_auth.uid())
   where id = p_request_id;
end;
$$;

grant execute on function public.valuation_forward_all(uuid) to authenticated;


-- ==========================================================================
--  20260718_tender_committees.sql
-- ==========================================================================

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
  created_by           uuid references sr_auth.users(id),
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
  for select using (sr_auth.role() = 'authenticated');

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


-- ==========================================================================
--  20260719_realtime_publish_all.sql
-- ==========================================================================

-- ============================================================================
--  Realtime: publish every table the app subscribes to, so a change on ONE
--  table live-updates all related tables across every open portal/session.
--  Idempotent — adds only the tables not already in supabase_realtime.
-- ============================================================================

do $$
declare
  t text;
  tables text[] := array[
    'packages',
    'package_items',
    'warehouse_entries',
    'warehouses',
    'forfeited_packages',
    'disposal_requests',
    'disposal_request_items',
    'tenders',
    'tender_sales',
    'tender_sale_items',
    'tender_bids',
    'tender_revaluations',
    'tender_committees',
    'destructions',
    'destruction_items',
    'storage_rates',
    'package_categories',
    'hold_reasons',
    'audit_logs',
    'profiles',
    'disposal_taxes'
  ];
begin
  foreach t in array tables loop
    -- Skip tables that do not exist in this database.
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = t
    ) then
      continue;
    end if;
    -- Add to the realtime publication only if not already a member.
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I;', t);
    end if;
  end loop;
end $$;


-- ==========================================================================
--  20260819_executive_valuation_reports.sql
-- ==========================================================================

-- ============================================================================
--  Executive Office (DG / ADG) read access for the valuation reports.
--
--  The Director General's Office reports ("List of Goods for Valuation" and
--  "List of Goods Valued") read the full valuation chain of a package:
--    * initial valuation → disposal_request_items.valuation_cost
--    * 2nd / 3rd / final → tender_revaluations rows, oldest first
--
--  `20260714_executive_directorate.sql` already granted executive SELECT on
--  disposal_request_items, but `tender_revaluations` was created afterwards
--  (20260716) and only granted to valuation / disposal / appeal. Without this
--  policy the DG's report silently shows blank 2nd/3rd/Final columns instead
--  of the real re-valuations.
--
--  The High Panel ALSO writes here: once a package is still unsold after the
--  Valuation Tender plus Tender 1-3, it goes to the Tender Committees tab and
--  the ADG sets that committee round's valuation. That write lands in the same
--  `tender_revaluations` table (keyed by tender_sale_id), so the valuation
--  chain — and every report built on it — stays a single continuous series.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

--  (tender_sales / tender_sale_items already carry `executive_read_all` from
--   20260718_tender_committees.sql, so only this table is missing.)

drop policy if exists tender_reval_executive_read on public.tender_revaluations;
create policy tender_reval_executive_read on public.tender_revaluations
  for select using (public.auth_user_is_executive());

-- Committee valuations set by the ADG (saveTenderRevaluation deletes the old
-- row for the round, then inserts the new one — so INSERT *and* DELETE).
drop policy if exists tender_reval_executive_write on public.tender_revaluations;
create policy tender_reval_executive_write on public.tender_revaluations
  for all
  using (public.auth_user_is_executive())
  with check (public.auth_user_is_executive());

reset lock_timeout;


-- ==========================================================================
--  20260820_committee_valuation.sql
-- ==========================================================================

-- ============================================================================
--  Committee valuation — the two-step price for a package that stayed unsold
--  through the Valuation Tender plus Tender 1, 2 and 3.
--
--  Flow:
--    1. DG appoints the 5-member tender committee   (tender_committees.members)
--    2. THE COMMITTEE inspects the goods and records its own valuation
--         → committee_value / committee_valued_at / committee_note
--    3. THE ADG submits that figure as the FINAL valuation for the next tender
--         → submitted_value / submitted_at / submitted_by
--       which also writes the usual tender_revaluations row, so the price flows
--       into the tender exactly like a Valuation Directorate re-valuation.
--
--  Steps 2 and 3 are deliberately separate columns: the committee's opinion and
--  the ADG's formal submission are different acts, and the UI must be able to
--  show "committee valued, awaiting ADG" as its own state.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.tender_committees
  add column if not exists committee_value    numeric,
  add column if not exists committee_valued_at timestamptz,
  add column if not exists committee_note     text,
  add column if not exists submitted_value    numeric,
  add column if not exists submitted_at       timestamptz,
  add column if not exists submitted_by       uuid references sr_auth.users(id);

-- The High Panel (DG appoints, ADG submits) already has full access via
-- 20260718_tender_committees.sql. Central Disposal / Valuation keep read-only.

reset lock_timeout;


-- ==========================================================================
--  20260821_unsold_proposals.sql
-- ==========================================================================

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
  decided_by           uuid references sr_auth.users(id),
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
  using (yard = (select yard from public.profiles where id = sr_auth.uid()));

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


-- ==========================================================================
--  20260823_appeal_window_all_statuses.sql
-- ==========================================================================

-- ============================================================================
--  The 30-day appeal window applies to EVERY status, not just forfeit.
--
--  Detain, Abandoned and "Other" goods are now frozen for the same 30 days as
--  a forfeiture: no Goods Action, no disposal request to Central Disposal, and
--  the Appeal Directorate can take an appeal on any of them.
--
--  The clock runs from the goods' ENTRY DATE (arrival at the yard), not from
--  the moment an officer changed the status — so a package that has been
--  sitting for months is actionable straight away, while a fresh one waits.
--
--  Abandoned / "Other" rows used to be written with
--      appeal_deadline = now() - 1 day
--  which deliberately skipped the window. This backfills them to the real
--  entry-date-based deadline, so old rows follow the same rule as new ones.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- ── Backfill: recompute the deadline from the package's entry date ──────────
--  Only touches rows whose deadline is the old "yesterday" sentinel, i.e. a
--  deadline at or before the row's own forfeited_at. A genuine forfeiture's
--  deadline is always forfeited_at + 30 days, so those are left alone.
with recomputed as (
  select fp.id,
         (coalesce(p.entry_date::date, p.created_at::date) + interval '30 days')
           as new_deadline
    from public.forfeited_packages fp
    join public.packages p on p.id = fp.package_id
   where fp.appeal_deadline <= fp.forfeited_at
)
update public.forfeited_packages fp
   set appeal_deadline = r.new_deadline
  from recomputed r
 where fp.id = r.id
   and fp.appeal_deadline is distinct from r.new_deadline;

-- ── Report what changed ─────────────────────────────────────────────────────
do $$
declare
  v_open int;
  v_past int;
begin
  select count(*) filter (where appeal_deadline > now()),
         count(*) filter (where appeal_deadline <= now())
    into v_open, v_past
    from public.forfeited_packages;

  raise notice 'appeal windows: % still open, % already passed', v_open, v_past;
end $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  Per source: how many are still inside the 30-day window.
select coalesce(fp.source, 'forfeit')                        as source,
       count(*)                                              as total,
       count(*) filter (where fp.appeal_deadline > now())     as in_appeal,
       count(*) filter (where fp.appeal_deadline <= now())    as actionable,
       min(fp.appeal_deadline)                               as earliest_deadline,
       max(fp.appeal_deadline)                               as latest_deadline
  from public.forfeited_packages fp
 group by coalesce(fp.source, 'forfeit')
 order by 1;


-- ==========================================================================
--  20260824_appeal_materialise_row.sql
-- ==========================================================================

-- ============================================================================
--  Let the Appeal Directorate lodge an appeal against Detain / Abandoned /
--  "Other" goods, not just forfeits.
--
--  Those three statuses carry NO `forfeited_packages` row until something acts
--  on them, so the appeal portal lists them as synthetic rows. The appeal RPCs
--  (`set_appeal_hold`, `release_appeal_with_decision`) take a real uuid, so the
--  first appeal against such goods has to create the row.
--
--  The appeal role only holds SELECT on `forfeited_packages`, so the insert
--  cannot be done from the client. This SECURITY DEFINER function does it, and
--  is the ONLY way the appeal role can write that table.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

create or replace function public.appeal_ensure_forfeited_row(
  p_package_id uuid,
  p_item_id    uuid,
  p_source     text
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id       uuid;
  v_pkg      record;
  v_qty      int;
  v_entry    date;
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  -- Only the three no-row statuses may be materialised this way; a genuine
  -- forfeit always has its row already.
  if p_source not in ('detain', 'abandoned', 'other') then
    raise exception 'unsupported source: %', p_source;
  end if;

  -- Already created by an earlier appeal?
  select id into v_id
    from public.forfeited_packages
   where package_id = p_package_id
     and item_id    = p_item_id
     and source     = p_source
   limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select p.sr_number, p.consignee_name, p.reason, p.yard,
         coalesce(p.entry_date::date, p.created_at::date) as entry_date
    into v_pkg
    from public.packages p
   where p.id = p_package_id;
  if v_pkg is null then
    raise exception 'package not found';
  end if;

  select quantity into v_qty
    from public.package_items where id = p_item_id;

  v_entry := v_pkg.entry_date;

  insert into public.forfeited_packages (
    package_id, item_id, entry_qty, sr_number, consignee_name,
    forfeited_at, appeal_deadline, reason, yard, source)
  values (
    p_package_id, p_item_id, v_qty, v_pkg.sr_number, v_pkg.consignee_name,
    v_entry,
    -- The same 30-day window the synthetic row was showing: entry + 30 days.
    v_entry + interval '30 days',
    coalesce(v_pkg.reason, 'Appeal lodged'),
    v_pkg.yard,
    p_source)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function
  public.appeal_ensure_forfeited_row(uuid, uuid, text) to authenticated;

reset lock_timeout;


-- ==========================================================================
--  20260825_forfeited_source_detain.sql
-- ==========================================================================

-- ============================================================================
--  Forfeited-package SOURCE: add 'detain'
--  Run after 20260616_forfeited_source_other.sql.
--
--  The 30-day appeal window now covers EVERY status, so a DETAINED package can
--  have an appeal lodged against it. Lodging one materialises a
--  forfeited_packages row (see `appeal_ensure_forfeited_row` in
--  20260824_appeal_materialise_row.sql), and that row's `source` is 'detain'.
--
--  The existing check constraint only allowed forfeit / abandoned / other, so
--  the insert failed with:
--    23514 ... violates check constraint "forfeited_packages_source_check"
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.forfeited_packages
  drop constraint if exists forfeited_packages_source_check;

alter table public.forfeited_packages
  add constraint forfeited_packages_source_check
    check (source in ('forfeit', 'abandoned', 'other', 'detain'));

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.forfeited_packages'::regclass
   and conname = 'forfeited_packages_source_check';


-- ==========================================================================
--  20260826_destroying_deposit.sql
-- ==========================================================================

-- ============================================================================
--  Destroying Deposit
--
--  A deposit the declarant lodges against the cost of destroying the goods.
--  It is collected ONCE per SR at registration — a PACKAGE-level figure, not
--  a per-goods-item one — so it lives on `packages`, beside container_number.
--
--  Nullable: older SRs have none, and it is optional on the form.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.packages
  add column if not exists destroying_deposit numeric;

comment on column public.packages.destroying_deposit is
  'Deposit lodged by the declarant against the cost of destroying the goods. '
  'One figure per SR (package-level), set at registration.';

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'packages'
   and column_name  = 'destroying_deposit';


-- ==========================================================================
--  20260827_financial_expenses.sql
-- ==========================================================================

-- ============================================================================
--  Financial expenses — the outgoings side of the High Panel's Financials tab.
--
--  Income is derived from records the system already holds (storage charges,
--  destroying deposits, sale proceeds, taxes). Expenses are NOT: advertising
--  costs, destruction costs and refunds are entered by hand, so they need a
--  table of their own.
--
--  `kind` is one of:
--    destruction_expense  — cost of carrying out a destruction
--    advertising_expense  — cost of advertising a tender
--    refund               — money paid back (deposit returned, appeal upheld …)
--
--  Optional `yard` and `sr_number` let an entry be attributed; both may be
--  null for a general expense.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

create table if not exists public.financial_expenses (
  id          uuid primary key default gen_random_uuid(),
  kind        text        not null
                check (kind in ('destruction_expense',
                                'advertising_expense',
                                'refund')),
  amount      numeric(14,2) not null check (amount >= 0),
  description text,
  yard        text,
  sr_number   text,
  incurred_on date        not null default current_date,
  created_by  uuid        references sr_auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists financial_expenses_kind_idx
  on public.financial_expenses(kind);
create index if not exists financial_expenses_date_idx
  on public.financial_expenses(incurred_on);
create index if not exists financial_expenses_yard_idx
  on public.financial_expenses(yard);

alter table public.financial_expenses enable row level security;

-- 1. ── High Panel (DG / ADG / DC): the Financials tab lives in their portal ──
--    The DC is view-only in the UI; writes are still gated to executives so a
--    yard cannot post an expense.
drop policy if exists financial_expenses_exec_all on public.financial_expenses;
create policy financial_expenses_exec_all on public.financial_expenses
  for all
  using (public.auth_user_is_executive())
  with check (public.auth_user_is_executive());

-- 2. ── Central Disposal: they run the tenders, so they record the costs ─────
drop policy if exists financial_expenses_disposal_all on public.financial_expenses;
create policy financial_expenses_disposal_all on public.financial_expenses
  for all
  using (public.auth_user_is_disposal())
  with check (public.auth_user_is_disposal());

-- 3. ── Everyone else authenticated: read-only ───────────────────────────────
drop policy if exists financial_expenses_read on public.financial_expenses;
create policy financial_expenses_read on public.financial_expenses
  for select using (sr_auth.role() = 'authenticated');

-- 4. ── Realtime, so a posted expense updates every open Financials tab ──────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'financial_expenses'
  ) then
    alter publication supabase_realtime add table public.financial_expenses;
  end if;
end $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select kind, count(*) as entries, coalesce(sum(amount), 0) as total
  from public.financial_expenses
 group by kind
 order by kind;


-- ==========================================================================
--  20260828_tender_bids_read_access.sql
-- ==========================================================================

-- ============================================================================
--  Read access to tender_bids for the High Panel and the yards.
--
--  `tender_bids` had SELECT policies for Central Disposal, the Appeal
--  Directorate and the Valuation Directorate only. The Tender History section
--  on the Unsold popup reads bids per round, so in the High Panel and yard
--  portals every round rendered "No bids recorded" — the rows were there, RLS
--  simply filtered them out.
--
--  Read-only: recording a bid stays with Central Disposal.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── High Panel (DG / ADG / DC): they review the whole tender history ─────
drop policy if exists tender_bids_executive_read on public.tender_bids;
create policy tender_bids_executive_read on public.tender_bids
  for select using (public.auth_user_is_executive());

-- 2. ── The owning yard: its own packages' bids ──────────────────────────────
--    Matched through the bid's own `yard` column, which is stamped when the
--    bid is recorded.
drop policy if exists tender_bids_yard_read on public.tender_bids;
create policy tender_bids_yard_read on public.tender_bids
  for select
  using (
    yard = (select p.yard from public.profiles p where p.id = sr_auth.uid())
  );

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select policyname, cmd, qual
  from pg_policies
 where schemaname = 'public'
   and tablename  = 'tender_bids'
 order by policyname;


-- ==========================================================================
--  20260829_tender_history_read_access.sql
-- ==========================================================================

-- ============================================================================
--  The Tender History popup reads three tables per round. Each had its own RLS,
--  and the gaps showed up as MISSING PARTS of the same history depending on who
--  was looking:
--
--      tender_sales / tender_sale_items → the round order   (already granted)
--      tender_revaluations              → each round's PRICE
--      tender_committees                → the committee round's members
--
--  `tender_revaluations` had SELECT policies for Valuation, Central Disposal,
--  Appeal and the High Panel — but NOT for the yards. So in a yard's Unsold
--  popup, Tender 1/2/3 rendered with no price and no "re-valued" mark, while
--  Central Disposal saw all of them.
--
--  This grants the owning yard read access to the re-valuations for its own
--  packages, and re-asserts the committee read so every portal lists the
--  appointed members. Read-only throughout: setting a re-valuation stays with
--  the Valuation Directorate, appointing a committee stays with the DG/ADG.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── The owning yard: re-valuations for its own packages ──────────────────
--    Matched on the re-valuation's own `yard` column where it is stamped, and
--    otherwise through the forfeited package it belongs to (older rows were
--    written before that column was populated).
drop policy if exists tender_reval_yard_read on public.tender_revaluations;
create policy tender_reval_yard_read on public.tender_revaluations
  for select
  using (
    yard = (select p.yard from public.profiles p where p.id = sr_auth.uid())
    or exists (
      select 1
        from public.forfeited_packages fp
       where fp.id = tender_revaluations.forfeited_package_id
         and fp.yard = (select p.yard from public.profiles p
                         where p.id = sr_auth.uid())
    )
  );

-- 2. ── Any authenticated officer may read a re-valuation ────────────────────
--    The history is a read-only audit trail and every portal that shows the
--    popup needs it. Kept separate from (1) so the yard rule stays explicit.
drop policy if exists tender_reval_auth_read on public.tender_revaluations;
create policy tender_reval_auth_read on public.tender_revaluations
  for select using (sr_auth.role() = 'authenticated');

-- 3. ── Committees: re-assert the blanket read ───────────────────────────────
--    Already created by 20260718_tender_committees.sql; repeated here so a
--    database that only ran the later migrations still lists the members.
drop policy if exists tender_committees_auth_read on public.tender_committees;
create policy tender_committees_auth_read on public.tender_committees
  for select using (sr_auth.role() = 'authenticated');

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('tender_revaluations', 'tender_committees', 'tender_bids')
 order by tablename, policyname;


-- ==========================================================================
--  20260830_expenses_per_goods.sql
-- ==========================================================================

-- ============================================================================
--  Expenses are recorded PER GOODS ITEM, and the refund is DERIVED.
--
--  Two changes to the Financials model:
--
--  1. Destruction and advertising costs are incurred goods by goods, not per
--     SR — one SR can hold many items and each is destroyed/advertised on its
--     own. `package_item_id` attributes an expense to a single item so the
--     Financials tab can break the whole ledger down goods by goods.
--
--  2. A REFUND is no longer typed in. It is what is left of the goods'
--     destroying deposit after its destruction and advertising costs:
--
--         refund = destroying_deposit - (destruction + advertising)
--
--     …floored at zero, since a deposit cannot refund more than it held. The
--     'refund' kind stays in the CHECK constraint so historical rows survive,
--     but the app no longer writes it and the Financials tab computes the
--     figure instead.
--
--  Central Disposal already had full write access (policy 2 of
--  20260827_financial_expenses.sql) — they run the destructions and the
--  tender advertising, so they are the ones who post these costs.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Attribute an expense to one goods item ───────────────────────────────
alter table public.financial_expenses
  add column if not exists package_item_id uuid
    references public.package_items(id) on delete set null;

create index if not exists financial_expenses_item_idx
  on public.financial_expenses(package_item_id);

-- 2. ── Backfill the yard / SR of any row that names an item but not them ────
--    Keeps older hand-entered rows groupable with the new per-item ones.
update public.financial_expenses fe
   set sr_number = coalesce(fe.sr_number, p.sr_number),
       yard      = coalesce(fe.yard, p.yard)
  from public.package_items pi
  join public.packages p on p.id = pi.package_id
 where pi.id = fe.package_item_id
   and (fe.sr_number is null or fe.yard is null);

-- 3. ── One entry of each kind per goods item ────────────────────────────────
--    Posting a cost twice for the same goods would double-count it against
--    that item's deposit, so the app UPSERTS on (package_item_id, kind) and a
--    correction replaces the figure instead of adding a second row.
--
--    Deliberately NOT a partial index: PostgREST can only infer a conflict
--    target from a full unique constraint, so `on_conflict=package_item_id,kind`
--    would fail against a `where`-qualified one. Rows with a null
--    package_item_id are unaffected — nulls never collide in a unique index —
--    so the general (unattributed) expenses stay insertable as before.
--    Any duplicates already in the table would block the constraint, so collapse
--    each (item, kind) group to its most recent row first. Only rows that name
--    an item can collide — nulls never do.
delete from public.financial_expenses fe
 using public.financial_expenses keep
 where fe.package_item_id is not null
   and fe.package_item_id = keep.package_item_id
   and fe.kind            = keep.kind
   and (fe.created_at, fe.id) < (keep.created_at, keep.id);

--    An earlier revision of this migration created it as a partial INDEX; drop
--    that shape before adding the constraint.
drop index if exists public.financial_expenses_item_kind_uniq;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'financial_expenses_item_kind_uniq'
       and conrelid = 'public.financial_expenses'::regclass
  ) then
    alter table public.financial_expenses
      add constraint financial_expenses_item_kind_uniq
      unique (package_item_id, kind);
  end if;
end $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select kind,
       count(*)                              as entries,
       count(package_item_id)                as attributed_to_goods,
       coalesce(sum(amount), 0)              as total
  from public.financial_expenses
 group by kind
 order by kind;


-- ==========================================================================
--  20260831_appeal_window_index.sql
-- ==========================================================================

-- ============================================================================
--  Index the appeal window's filter column.
--
--  The Appeal Directorate's "goods still open to appeal" query used to pull
--  EVERY package in the system — with its items, warehouse entries and profile
--  joins — and then discard the out-of-window ones in Dart. The portal sat
--  loading for about a minute.
--
--  It now asks the database for the window instead:
--
--      entry_date >= now() - 30 days
--      OR (entry_date IS NULL AND created_at >= now() - 30 days)
--
--  These indexes are what make that filter cheap. Without them the planner
--  still scans the whole table; the win is only in the smaller result set
--  travelling over the wire.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

create index if not exists packages_entry_date_idx
  on public.packages(entry_date desc);

-- Covers the fallback arm: rows that never had an entry_date recorded.
create index if not exists packages_created_at_idx
  on public.packages(created_at desc);

-- The Appeal portal also loads the real rows behind Detain / Abandoned /
-- "Other" appeals, keyed by (package_id, item_id) and filtered on source.
create index if not exists forfeited_packages_source_idx
  on public.forfeited_packages(source);

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select count(*)                                                as packages,
       count(*) filter (
         where coalesce(entry_date, created_at) >= now() - interval '30 days')
                                                                as in_window
  from public.packages;


-- ==========================================================================
--  20260832_warehouse_zones.sql
-- ==========================================================================

-- ============================================================================
--  Warehouse ZONES, each with its own capacity.
--
--  Capacity used to be a single number on `warehouses`, and nothing enforced
--  it: goods were admitted with no check at all, which is how Warehouse 01
--  reached 128% full. Space is really organised zone by zone, so that is where
--  the number belongs.
--
--    * A zone belongs to one warehouse and carries its own capacity.
--    * A WAREHOUSE's capacity is the SUM of its zones — never entered directly.
--    * `warehouse_entries.zone` already names the zone an entry sits in; it now
--      matches `warehouse_zones.name` within that warehouse.
--
--  `warehouses.capacity` is KEPT so nothing that still reads it breaks, but it
--  stops being the source of truth — the app sums the zones instead.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── The zones ────────────────────────────────────────────────────────────
create table if not exists public.warehouse_zones (
  id           uuid primary key default gen_random_uuid(),
  warehouse_id uuid    not null references public.warehouses(id) on delete cascade,
  -- Short label as it appears on a warehouse entry: 'A', 'B', 'Cold Room' …
  name         text    not null,
  description  text,
  capacity     integer not null default 500 check (capacity >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- One zone name per warehouse; the pair is what an entry resolves against.
  constraint warehouse_zones_name_uniq unique (warehouse_id, name)
);

create index if not exists warehouse_zones_warehouse_idx
  on public.warehouse_zones(warehouse_id);

alter table public.warehouse_zones enable row level security;

-- 2. ── RLS: everyone reads, admins write ────────────────────────────────────
--    Zones are reference data — the SR form must read them to place goods, and
--    every capacity view needs them. Only an admin may change the layout.
drop policy if exists warehouse_zones_read on public.warehouse_zones;
create policy warehouse_zones_read on public.warehouse_zones
  for select using (sr_auth.role() = 'authenticated');

drop policy if exists warehouse_zones_admin_write on public.warehouse_zones;
create policy warehouse_zones_admin_write on public.warehouse_zones
  for all
  using (exists (select 1 from public.profiles p
                  where p.id = sr_auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p
                       where p.id = sr_auth.uid() and p.role = 'admin'));

-- 3. ── Backfill from the zones already in use ───────────────────────────────
--    Every distinct `warehouse_entries.zone` becomes a real zone. Its capacity
--    starts at the parent warehouse's old figure divided evenly among them, so
--    the totals carry over and an over-full warehouse still reads as over-full
--    rather than being silently reset.
insert into public.warehouse_zones (warehouse_id, name, capacity)
select z.warehouse_id,
       z.zone,
       greatest(
         1,
         coalesce(w.capacity, 500) / greatest(1, count(*) over (
           partition by z.warehouse_id))
       )::int
  from (
    select distinct we.warehouse_id, trim(we.zone) as zone
      from public.warehouse_entries we
     where we.zone is not null
       and trim(we.zone) <> ''
       and upper(trim(we.zone)) <> 'N/A'
  ) z
  join public.warehouses w on w.id = z.warehouse_id
on conflict (warehouse_id, name) do nothing;

-- 4. ── A warehouse with no zones in use gets one default zone ───────────────
--    Otherwise it would show zero capacity and accept nothing.
insert into public.warehouse_zones (warehouse_id, name, capacity, description)
select w.id, 'A', coalesce(w.capacity, 500),
       'Default zone (created when zones were introduced)'
  from public.warehouses w
 where not exists (select 1 from public.warehouse_zones z
                    where z.warehouse_id = w.id)
on conflict (warehouse_id, name) do nothing;

reset lock_timeout;

-- ── VERIFY: each warehouse, its zones, and the capacity they now total ──────
select w.name                                   as warehouse,
       w.code,
       count(z.id)                              as zones,
       string_agg(z.name, ', ' order by z.name) as zone_names,
       coalesce(sum(z.capacity), 0)             as zone_capacity_total,
       w.capacity                               as legacy_capacity
  from public.warehouses w
  left join public.warehouse_zones z on z.warehouse_id = w.id
 group by w.id, w.name, w.code, w.capacity
 order by w.code;


-- ==========================================================================
--  20260833_warehouse_zone_code.sql
-- ==========================================================================

-- ============================================================================
--  Zones get their own CODE, alongside the name.
--
--  A warehouse has a name and a code (Warehouse 01 / W01); its zones read the
--  same way — "Zone A" / "W01-A" — so the admin table can show one column set
--  for both levels.
--
--  Backfills from the zone's name, prefixed with its warehouse's code, which
--  is what an operator would have written anyway.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.warehouse_zones
  add column if not exists code text;

-- Backfill: "<warehouse code>-<zone name>", uppercased and space-free.
update public.warehouse_zones z
   set code = upper(w.code || '-' || regexp_replace(z.name, '\s+', '', 'g'))
  from public.warehouses w
 where w.id = z.warehouse_id
   and (z.code is null or trim(z.code) = '');

-- One code per warehouse. Names were already unique per warehouse; codes are
-- too, so either identifies a zone within its warehouse.
create unique index if not exists warehouse_zones_code_uniq
  on public.warehouse_zones(warehouse_id, code)
 where code is not null;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select w.name as warehouse, w.code as warehouse_code,
       z.name as zone, z.code as zone_code, z.capacity
  from public.warehouse_zones z
  join public.warehouses w on w.id = z.warehouse_id
 order by w.code, z.name;


-- ==========================================================================
--  20260834_category_zone_names.sql
-- ==========================================================================

-- ============================================================================
--  Item categories point at a zone by NAME.
--
--  The category form used to offer a hardcoded "Zone 1 … Zone 10" list that
--  had nothing to do with the real zones, and stored the label verbatim
--  ("Zone 3"). Now it lists the actual rows of `warehouse_zones`, so
--  `package_categories.target_zone` must hold the zone's own NAME.
--
--  This normalises the legacy values:
--    1. Strip the "Zone " prefix where the warehouse has a zone by the bare
--       name ("Zone 3" -> "3" when zone "3" exists).
--    2. Otherwise create the missing zone, so a category that was pointing
--       somewhere keeps pointing there rather than silently losing its target.
--
--  Run AFTER 20260832_warehouse_zones.sql and 20260833_warehouse_zone_code.sql.
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── "Zone 3" -> "3" where that zone already exists ───────────────────────
update public.package_categories c
   set target_zone = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
 where c.target_zone is not null
   and c.target_zone ~ '^[Zz]one\s+'
   and exists (
     select 1 from public.warehouse_zones z
      where z.warehouse_id = c.target_warehouse_id
        and z.name = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
   );

-- 2. ── Create any zone a category still names but the warehouse lacks ───────
--    Capacity starts at 500 — the admin sets the real figure; leaving the
--    category pointing at nothing would be worse than a placeholder.
insert into public.warehouse_zones (warehouse_id, name, code, capacity, description)
select distinct
       c.target_warehouse_id,
       trim(regexp_replace(c.target_zone, '^[Zz]one\s+', '')),
       upper(w.code || '-' ||
             regexp_replace(
               trim(regexp_replace(c.target_zone, '^[Zz]one\s+', '')),
               '\s+', '', 'g')),
       500,
       'Created from an item category that referenced it'
  from public.package_categories c
  join public.warehouses w on w.id = c.target_warehouse_id
 where c.target_zone is not null
   and trim(c.target_zone) <> ''
   and not exists (
     select 1 from public.warehouse_zones z
      where z.warehouse_id = c.target_warehouse_id
        and z.name = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
   )
on conflict (warehouse_id, name) do nothing;

-- 3. ── Now every category can be normalised ─────────────────────────────────
update public.package_categories c
   set target_zone = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
 where c.target_zone is not null
   and c.target_zone ~ '^[Zz]one\s+';

reset lock_timeout;

-- ── VERIFY: every category's zone should resolve to a real one ──────────────
select c.name                          as category,
       w.name                          as warehouse,
       c.target_zone,
       (z.id is not null)              as zone_exists,
       z.capacity
  from public.package_categories c
  left join public.warehouses w      on w.id = c.target_warehouse_id
  left join public.warehouse_zones z on z.warehouse_id = c.target_warehouse_id
                                    and z.name = c.target_zone
 where c.target_zone is not null
 order by w.code, c.target_zone;


-- ==========================================================================
--  20260835_more_expense_kinds.sql
-- ==========================================================================

-- ============================================================================
--  Three more recorded costs: labour, transport and auction.
--
--  Central Disposal already records what a disposal cost to carry out
--  (destruction) and to advertise. Getting the goods there and selling them
--  costs money too, and it comes out of the same destroying deposit:
--
--      labour_expense     — handling / loading the goods
--      transport_expense  — moving them
--      auction_expense    — running the auction itself
--
--  The refund stays DERIVED — now from all five costs together:
--
--      refund = destroying_deposit - Σ(destruction + advertising
--                                      + labour + transport + auction)
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.financial_expenses
  drop constraint if exists financial_expenses_kind_check;

alter table public.financial_expenses
  add constraint financial_expenses_kind_check
    check (kind in ('destruction_expense',
                    'advertising_expense',
                    'labour_expense',
                    'transport_expense',
                    'auction_expense',
                    -- Historical rows only; a refund is derived, never written.
                    'refund'));

-- The one-per-(item, kind) rule covers the new kinds automatically — the
-- unique constraint from 20260830_expenses_per_goods.sql is on the pair, not
-- on a list of kinds, so nothing more is needed there.

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.financial_expenses'::regclass
   and conname = 'financial_expenses_kind_check';


-- ==========================================================================
--  20260836_more_unsold_outcomes.sql
-- ==========================================================================

-- ============================================================================
--  Three more outcomes for goods that could not be sold by any means.
--
--  The High Panel could choose Destroy / Remand / Government Use / Auction.
--  Goods that none of those suit have three further routes:
--
--      re_export             — sent back to the country of origin
--      convert               — converted to another use or form
--      remove_from_premises  — removed from the yard under a separate order
--
--  Widening the CHECK is enough; nothing stored becomes invalid.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.unsold_proposals
  drop constraint if exists unsold_proposals_proposal_check;

alter table public.unsold_proposals
  add constraint unsold_proposals_proposal_check
    check (proposal in ('destroy',
                        'remand',
                        'government_use',
                        'auction',
                        're_export',
                        'convert',
                        'remove_from_premises'));

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.unsold_proposals'::regclass
   and conname = 'unsold_proposals_proposal_check';


-- ==========================================================================
--  20260837_destruction_receipt_number.sql
-- ==========================================================================

-- ============================================================================
--  Destruction items get a RECEIPT NUMBER.
--
--  A sale records `tender_sale_items.receipt_number` when the goods are marked
--  sold. A destruction had no equivalent, so the Destroyed report could not
--  show the receipt the destruction was recorded against.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.destruction_items
  add column if not exists receipt_number text;

-- ── Backfill from `notes` ───────────────────────────────────────────────────
--  `disposal_mark_destruction_item_destroyed` stored the receipt in `notes`
--  for want of a column of its own. Carry those across so existing rows report
--  their receipt, and leave `notes` alone (it may hold other text too).
update public.destruction_items
   set receipt_number = trim(notes)
 where receipt_number is null
   and notes is not null
   and trim(notes) <> '';

-- ── Record the receipt in its own column from now on ────────────────────────
--  `disposal_mark_destruction_item_destroyed` also writes the [FINAL:DESTROYED]
--  warehouse entry and flips the item's status (see 20260630_destruction_price
--  .sql). Re-declaring the whole function here would be a copy that silently
--  drifts from it, so instead a TRIGGER mirrors `notes` into the new column —
--  the RPC keeps writing `notes` exactly as it does today, and nothing else
--  about it changes.
create or replace function public.destruction_items_sync_receipt()
returns trigger
language plpgsql
as $$
begin
  -- Only fill it in; never overwrite a receipt set deliberately.
  if new.receipt_number is null
     and new.notes is not null
     and trim(new.notes) <> '' then
    new.receipt_number := trim(new.notes);
  end if;
  return new;
end;
$$;

drop trigger if exists destruction_items_receipt_sync on public.destruction_items;
DROP TRIGGER IF EXISTS destruction_items_receipt_sync ON public.destruction_items;
CREATE TRIGGER destruction_items_receipt_sync
  before insert or update of notes on public.destruction_items
  for each row execute function public.destruction_items_sync_receipt();

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select count(*)                                   as destruction_items,
       count(receipt_number)                      as with_receipt,
       count(*) filter (where destroyed)          as destroyed
  from public.destruction_items;


-- ==========================================================================
--  20260838_disposal_read_warehouses.sql
-- ==========================================================================

-- ============================================================================
--  Central Disposal can read `warehouses` and `warehouse_zones`.
--
--  Their Report Generator carries the same Warehouse filter every other portal
--  has, but `warehouses` had SELECT policies for the executive role only — so
--  the list came back empty and the dropdown had to be hidden for them.
--
--  Read-only: creating and editing a warehouse stays with the yard admin.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

drop policy if exists warehouses_disposal_read on public.warehouses;
create policy warehouses_disposal_read on public.warehouses
  for select using (public.auth_user_is_disposal());

-- The zone list is read alongside it (capacity views, the SR form's picker).
drop policy if exists warehouse_zones_disposal_read on public.warehouse_zones;
create policy warehouse_zones_disposal_read on public.warehouse_zones
  for select using (public.auth_user_is_disposal());

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('warehouses', 'warehouse_zones')
 order by tablename, policyname;


-- ==========================================================================
--  20260839_ict_directorates_and_yards.sql
-- ==========================================================================

-- ============================================================================
--  ICT Directorate: the 'ict' role, plus yards & directorate categories as DATA
--
--  Three things, all provisioned from the ICT portal at run time:
--
--   1. `profiles.role` gains 'ict'. The ICT portal's screens already exist in
--      the app, but no migration ever widened the CHECK constraint — so every
--      ICT sign-up failed at the profile INSERT with a check violation that the
--      UI mis-reported as "Network problem". This is that fix.
--
--   2. `public.directorates` — the head-office divisions a yard belongs to
--      (CED, PSD, RTF, B/A, ACD, EXD, PRD, SSD). More can be added later from
--      the portal; nothing here hard-codes the list beyond the seed.
--
--   3. `public.yards` + `public.yard_directorates` — the yards themselves and
--      the MANY-TO-MANY link to directorates. Many-to-many is required, not
--      incidental: NNR belongs to both CED and PSD, and Katunayaka/Rathmalana/
--      Mattala belong to both B/A and ACD.
--
--  The SR number becomes `<DIRECTORATE>/<YARD>/SR/<NN>/<YYYY>`
--  (e.g. CED/GL1/SR/25/2026). Because a yard can sit under two directorates,
--  the prefix is decided by the SIGNED-IN USER's directorate, which is why
--  `profiles` gains a `directorate` column here.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- ── 1. The 'ict' role ───────────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'officer', 'disposal', 'appeal', 'valuation',
                  'executive', 'ict'));

-- ── 2. Directorates ─────────────────────────────────────────────────────────
create table if not exists public.directorates (
  code        text primary key,
  name        text not null,
  -- What goes in front of the SR number. Kept separate from `code` because
  -- "B/A" is the real prefix but a slash is awkward as a key elsewhere.
  sr_prefix   text not null,
  sort_order  int  not null default 100,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

insert into public.directorates (code, name, sr_prefix, sort_order) values
  ('CED', 'Customs Enforcement Directorate',        'CED', 10),
  ('PSD', 'Port & Shipping Directorate',            'PSD', 20),
  ('RTF', 'Revenue Task Force',                     'RTF', 30),
  ('BA',  'Baggage / Airport',                      'B/A', 40),
  ('ACD', 'Air Cargo Directorate',                  'ACD', 50),
  ('EXD', 'Export Directorate',                     'EXD', 60),
  ('PRD', 'Preventive Directorate',                 'PRD', 70),
  ('SSD', 'Social Protection & Security Directorate','SSD', 80)
on conflict (code) do nothing;

-- ── 3. Yards ────────────────────────────────────────────────────────────────
--  `code` matches the value already stored in `profiles.yard` and every
--  `*.yard` column, so existing rows keep resolving with no data change.
create table if not exists public.yards (
  code        text primary key,
  name        text not null,
  -- The yard's own segment of the SR number (the middle part).
  sr_prefix   text not null,
  sort_order  int  not null default 100,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Seeded from lib/core/yards.dart (kYards) so the table starts out matching
-- the app exactly. Order preserved: GL1 stays first (the historical default).
insert into public.yards (code, name, sr_prefix, sort_order) values
  ('GL1',     'Grey Line 1',    'GL1',      10),
  ('GL2',     'Grey Line 2',    'GL2',      20),
  ('RCT',     'RCT',            'RCT',      30),
  ('CVT',     'CVT',            'CVT',      40),
  ('BQ',      'BQ',             'BQ',       50),
  ('NNR',     'NNR',            'NNR',      60),
  ('JCT',     'JCT',            'JCT',      70),
  ('PREV',    'Preventive',     'PREV',     80),
  ('BAGG',    'Baggage Office', 'BAGG',     90),
  ('RTF',     'RTF',            'RTF',     100),
  ('BIA',     'BIA',            'BIA',     110),
  ('HMB',     'HMB',            'HMB',     120),
  ('TRINCO',  'Trinco',         'TRINCO',  130),
  ('KURU',    'Kurunegala',     'KURU',    140),
  ('CSL',     'CSL',            'CSL',     150),
  ('DAMB',    'Dambulla',       'DAMB',    160),
  ('MIDIGO',  'Midigo',         'MIDIGO',  170),
  ('KALK',    'Kalkisiri',      'KALK',    180),
  ('TRANSCO', 'Transco',        'TRANSCO', 190),
  ('SEREN',   'Serendib',       'SEREN',   200),
  ('TRIGO',   'Trigo',          'TRIGO',   210)
on conflict (code) do nothing;

-- Yards named in the directorate mapping that had no kYards entry yet.
insert into public.yards (code, name, sr_prefix, sort_order) values
  ('CRT',     'CRT',            'CRT',     220),
  ('MIDCO',   'Midco',          'MIDCO',   230),
  ('LAKSIRI', 'Laksiri Seva',   'LAKSIRI', 240),
  ('BO',      'BO',             'BO',      250),
  ('MOBILE',  'Mobile',         'MOBILE',  260),
  ('MAINOFF', 'Main Office',    'MAINOFF', 270),
  ('KAT',     'Katunayaka',     'KAT',     280),
  ('MATT',    'Mattala',        'MATT',    290),
  ('RATH',    'Rathmalana',     'RATH',    300),
  ('PALALI',  'Palali',         'PALALI',  310),
  ('TRIO',    'Trio',           'TRIO',    320),
  ('ACE',     'ACE',            'ACE',     330),
  ('ASIAN',   'Asian',          'ASIAN',   340)
on conflict (code) do nothing;

-- ── 4. Which yards sit under which directorate (many-to-many) ───────────────
create table if not exists public.yard_directorates (
  yard_code        text not null references public.yards(code) on delete cascade,
  directorate_code text not null references public.directorates(code) on delete cascade,
  created_at       timestamptz not null default now(),
  primary key (yard_code, directorate_code)
);

create index if not exists yard_directorates_dir_idx
  on public.yard_directorates (directorate_code);

insert into public.yard_directorates (yard_code, directorate_code) values
  -- CED
  ('GL1', 'CED'), ('GL2', 'CED'), ('RCT', 'CED'), ('CRT', 'CED'),
  ('NNR', 'CED'), ('BQ', 'CED'),  ('JCT', 'CED'),
  -- PSD  (NNR is deliberately in BOTH CED and PSD)
  ('TRINCO', 'PSD'), ('MIDCO', 'PSD'), ('TRANSCO', 'PSD'),
  ('LAKSIRI', 'PSD'), ('NNR', 'PSD'), ('CSL', 'PSD'), ('BO', 'PSD'),
  -- RTF
  ('MOBILE', 'RTF'), ('MAINOFF', 'RTF'),
  -- B/A  (Katunayaka, Mattala, Rathmalana are in BOTH B/A and ACD)
  ('KAT', 'BA'), ('MATT', 'BA'), ('RATH', 'BA'), ('PALALI', 'BA'),
  -- ACD
  ('KAT', 'ACD'), ('RATH', 'ACD'), ('MATT', 'ACD'),
  -- EXD
  ('TRIO', 'EXD'), ('ACE', 'EXD'), ('ASIAN', 'EXD')
on conflict (yard_code, directorate_code) do nothing;

-- ── 5. The signed-in user's directorate ─────────────────────────────────────
--  A yard can belong to two directorates, so the yard alone cannot decide the
--  SR prefix. The USER's directorate does — chosen at registration.
--
--  Nullable and unconstrained by a FK on purpose: pre-existing accounts have no
--  directorate, and the app falls back to the yard's sole directorate (or to no
--  prefix at all) rather than refusing to work.
alter table public.profiles
  add column if not exists directorate text;

comment on column public.profiles.directorate is
  'Head-office directorate (public.directorates.code) this account registers '
  'under. Decides the SR-number prefix, since one yard may sit under several.';

-- ── 6. Reading the lists ────────────────────────────────────────────────────
--  Every signed-in user needs the yard/directorate lists: the login pickers,
--  the SR form, the "All Yards" filters. These are reference data with nothing
--  yard-private in them, so SELECT is open to any authenticated user.
alter table public.directorates      enable row level security;
alter table public.yards             enable row level security;
alter table public.yard_directorates enable row level security;

drop policy if exists directorates_read on public.directorates;
create policy directorates_read on public.directorates
  for select using (true);

drop policy if exists yards_read on public.yards;
create policy yards_read on public.yards
  for select using (true);

drop policy if exists yard_directorates_read on public.yard_directorates;
create policy yard_directorates_read on public.yard_directorates
  for select using (true);

-- ── 7. Only the ICT Directorate may change them ─────────────────────────────
create or replace function public.auth_user_is_ict()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $fn$
  select exists (
    select 1 from public.profiles p
     where p.id = sr_auth.uid()
       and p.role = 'ict'
       and p.is_active
  );
$fn$;

grant execute on function public.auth_user_is_ict() to authenticated, anon;

drop policy if exists directorates_ict_write on public.directorates;
create policy directorates_ict_write on public.directorates
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

drop policy if exists yards_ict_write on public.yards;
create policy yards_ict_write on public.yards
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

drop policy if exists yard_directorates_ict_write on public.yard_directorates;
create policy yard_directorates_ict_write on public.yard_directorates
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

-- ── 8. ICT reads and writes every profile ───────────────────────────────────
--  Provisioning yard admins/officers is the portal's whole purpose, and those
--  accounts live in other yards than the ICT user's own.
drop policy if exists profiles_ict_read on public.profiles;
create policy profiles_ict_read on public.profiles
  for select using (public.auth_user_is_ict());

drop policy if exists profiles_ict_write on public.profiles;
create policy profiles_ict_write on public.profiles
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select pg_get_constraintdef(oid) as role_check
  from pg_constraint where conname = 'profiles_role_check';

select d.code, d.sr_prefix, count(yd.yard_code) as yards
  from public.directorates d
  left join public.yard_directorates yd on yd.directorate_code = d.code
 group by d.code, d.sr_prefix, d.sort_order
 order by d.sort_order;


-- ==========================================================================
--  20260840_sr_number_directorate_prefix.sql
-- ==========================================================================

-- ============================================================================
--  Re-write every existing SR number to carry its directorate prefix.
--
--      GL1/SR/62/2026   ->   CED/GL1/SR/62/2026
--
--  ⚠️ READ THIS BEFORE RUNNING. `sr_number` is a human-facing key, not just a
--  column. It is printed on the barcode/QR labels physically stuck to goods
--  sitting in the warehouses, and it appears in already-generated PDFs and in
--  audit-log detail blobs. Re-writing it means the paper in the yard no longer
--  matches the database until those labels are reprinted.
--
--  The safeguards below exist because of that:
--    * every old->new pair is kept in `public.sr_number_migration_log`,
--    * the whole thing runs in ONE transaction (all rows or none),
--    * a rollback script ships alongside it:
--        supabase/rollback_sr_number_directorate_prefix.sql
--    * it is idempotent — rows already carrying a prefix are skipped, so a
--      second run is a no-op rather than CED/CED/GL1/...
--
--  Yards under two directorates (NNR, Katunayaka, Rathmalana, Mattala) have no
--  single right answer from the yard alone. They are resolved by the LOWEST
--  sort_order directorate, and every such row is flagged `was_ambiguous` in the
--  log so ICT can review and correct them from the portal afterwards.
-- ============================================================================

set lock_timeout = '10s';

-- ── The audit trail / rollback source ───────────────────────────────────────
create table if not exists public.sr_number_migration_log (
  id            bigserial primary key,
  table_name    text not null,
  row_id        uuid not null,
  old_sr_number text not null,
  new_sr_number text not null,
  was_ambiguous boolean not null default false,
  migrated_at   timestamptz not null default now()
);

create index if not exists sr_number_migration_log_row_idx
  on public.sr_number_migration_log (table_name, row_id);

-- ── The rewrite ─────────────────────────────────────────────────────────────
do $mig$
declare
  v_updated int := 0;
  v_skipped int := 0;
  v_unknown int := 0;
begin
  -- A row is "already migrated" when its first segment names a directorate.
  -- Everything else with a recognisable <YARD>/SR/<n>/<yyyy> shape is a target.
  create temporary table _sr_map on commit drop as
  select
      p.id                                   as package_id,
      p.sr_number                            as old_sr,
      d.sr_prefix || '/' || p.sr_number      as new_sr,
      -- More than one directorate for this yard => the choice was a guess.
      (select count(*) from public.yard_directorates yd2
        where yd2.yard_code = y.code) > 1    as ambiguous
    from public.packages p
    join public.yards y
      on y.sr_prefix = split_part(p.sr_number, '/', 1)
    -- Lowest sort_order wins when a yard sits under several directorates.
    join lateral (
      select d2.sr_prefix, d2.sort_order
        from public.yard_directorates yd
        join public.directorates d2 on d2.code = yd.directorate_code
       where yd.yard_code = y.code
       order by d2.sort_order
       limit 1
    ) d on true
   where split_part(p.sr_number, '/', 2) = 'SR'
     and not exists (
       select 1 from public.directorates d3
        where d3.sr_prefix = split_part(p.sr_number, '/', 1)
     );

  select count(*) into v_updated from _sr_map;

  -- Rows we deliberately leave alone, reported so the run is auditable.
  select count(*) into v_skipped
    from public.packages p
   where exists (select 1 from public.directorates d
                  where d.sr_prefix = split_part(p.sr_number, '/', 1));

  select count(*) into v_unknown
    from public.packages p
   where split_part(p.sr_number, '/', 2) = 'SR'
     and not exists (select 1 from public.yards y
                      where y.sr_prefix = split_part(p.sr_number, '/', 1))
     and not exists (select 1 from public.directorates d
                      where d.sr_prefix = split_part(p.sr_number, '/', 1));

  insert into public.sr_number_migration_log
        (table_name, row_id, old_sr_number, new_sr_number, was_ambiguous)
  select 'packages', package_id, old_sr, new_sr, ambiguous from _sr_map;

  update public.packages p
     set sr_number = m.new_sr
    from _sr_map m
   where p.id = m.package_id;

  -- `forfeited_packages` denormalises the SR number; keep the two in step.
  insert into public.sr_number_migration_log
        (table_name, row_id, old_sr_number, new_sr_number, was_ambiguous)
  select 'forfeited_packages', f.id, m.old_sr, m.new_sr, m.ambiguous
    from public.forfeited_packages f
    join _sr_map m on m.package_id = f.package_id
   where f.sr_number = m.old_sr;

  update public.forfeited_packages f
     set sr_number = m.new_sr
    from _sr_map m
   where f.package_id = m.package_id
     and f.sr_number = m.old_sr;

  raise notice 'SR migration: % rewritten, % already prefixed, % unknown-prefix (left alone)',
    v_updated, v_skipped, v_unknown;
end
$mig$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- Ambiguous rows for ICT to review (a yard under two directorates).
select old_sr_number, new_sr_number
  from public.sr_number_migration_log
 where was_ambiguous
 order by id;

-- Anything still without a directorate prefix.
select sr_number
  from public.packages p
 where not exists (select 1 from public.directorates d
                    where d.sr_prefix = split_part(p.sr_number, '/', 1))
 order by sr_number
 limit 50;


-- ==========================================================================
--  20260841_sale_end_time.sql
-- ==========================================================================

-- Sale END time for tender sales and destructions.
--
-- A sale has a start moment (sale_date + sale_time) that unlocks Mark Sold /
-- Mark Destroyed, and now an END moment that closes bidding. The valuation is
-- the RESERVE PRICE, so it stays sealed until the sale has ENDED — not merely
-- started. Without this the reserve became visible the moment bidding opened,
-- which is exactly when it must not be.
--
-- Nullable on purpose: existing rows have no end time and fall back to the
-- start moment, so their behaviour is unchanged.
alter table if exists public.tender_sales
  add column if not exists sale_end_time text;

alter table if exists public.destructions
  add column if not exists sale_end_time text;

comment on column public.tender_sales.sale_end_time is
  'Sale close time, "HH:mm". The valuation stays sealed until this passes.';
comment on column public.destructions.sale_end_time is
  'Sale close time, "HH:mm". The valuation stays sealed until this passes.';


-- ==========================================================================
--  20260842_tender_unsold_actions.sql
-- ==========================================================================

-- Explicit UNSOLD and UNDESTROYED status for tender sale items and destruction items.
--
-- Allows officers to manually mark an item unsold/undestroyed immediately after
-- the sale moment, without having to wait for the automatic grace deadline.
alter table if exists public.tender_sale_items
  add column if not exists unsold boolean not null default false,
  add column if not exists unsold_at timestamptz;

alter table if exists public.destruction_items
  add column if not exists undestroyed boolean not null default false,
  add column if not exists undestroyed_at timestamptz;

comment on column public.tender_sale_items.unsold is
  'True when the officer explicitly marks the item unsold in this tender sale.';
comment on column public.destruction_items.undestroyed is
  'True when the officer explicitly marks the item undestroyed in this destruction.';


-- ==========================================================================
--  migrations/002_strict_yard_isolation.sql (folded in)
-- ==========================================================================

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


-- ==========================================================================
--  migrations/003_database_yard_isolation.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Enforced per-yard isolation for EVERY yard in the direct PostgreSQL client.
--
-- The desktop app must connect as the non-superuser `yard_app` role created by
-- postgres/66_yard_app_role.sql.  PostgreSQL superusers bypass RLS, so a
-- connection as `postgres` makes UI filters the only barrier between any two
-- yards.  This migration closes the database side of that gap:
--
--   * tables that carry operational data force their existing dynamic RLS
--     policy: `row.yard = auth_user_yard()`;
--   * reporting/list views run with the caller's permissions, so their base
--     table RLS policies apply too (views otherwise use their owner's rights).
--
-- Apply after 001_multi_yard.sql and 002_strict_yard_isolation.sql.
-- Requires PostgreSQL 15+ for `security_invoker`; the deployed server meets
-- that requirement.  Safe to re-run.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'packages', 'package_items', 'warehouse_entries',
    'forfeited_packages', 'tenders', 'tender_disposals', 'audit_logs',
    'disposal_requests', 'disposal_request_items',
    'tender_sales', 'tender_sale_items', 'tender_bids',
    'tender_revaluations', 'tender_committees', 'unsold_proposals',
    'destructions', 'destruction_items', 'financial_expenses'
  ]
  loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('alter table public.%I force row level security', t);
    end if;
  end loop;
end $$;

-- `auth_user_yard()` reads the logged-in account's profiles.yard.  It does
-- not contain a yard-code list: therefore a new ICT-created code (for example
-- `NEWYARD`) is isolated the instant an account is assigned to it, with no
-- Flutter rebuild, SQL edit, or special GL1/GL2 branch.
do $$
declare
  t text;
  policy_sql text;
begin
  foreach t in array array[
    'packages', 'package_items', 'warehouse_entries', 'forfeited_packages',
    'tenders', 'tender_disposals'
  ]
  loop
    select pg_get_expr(p.polqual, p.polrelid) into policy_sql
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = t and p.polname = 'yard_all';
    if policy_sql is null or policy_sql not like '%auth_user_yard%' then
      raise exception 'public.% does not have the dynamic yard_all RLS policy', t;
    end if;
  end loop;
end $$;

-- These views power Old Entries, Goods History, Warehouses, Held Goods,
-- Forfeited/Disposed tables, dashboard cards, and reports.  SECURITY INVOKER
-- means a GL2 user sees only rows permitted by the underlying table policies;
-- no view-owner (normally postgres) can accidentally widen the result set.
do $$
declare
  v text;
begin
  foreach v in array array[
    'held_goods_rows', 'perishable_rows', 'warehouse_rows', 'forfeit_rows',
    'disposition_rows', 'sr_financials', 'sr_expense_summary',
    'recent_package_activity', 'accrued_storage_by_yard',
    'appeal_rows', 'valuation_rows', 'disposal_request_summary',
    'tender_sale_summary', 'destruction_summary', 'unsold_retender_pool',
    'unsold_perishables', 'exhausted_unsold', 'committee_pool',
    'item_appeal_outcomes', 'zone_occupancy_entries'
  ]
  loop
    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v and c.relkind = 'v'
    ) then
      execute format('alter view public.%I set (security_invoker = true)', v);
    end if;
  end loop;
end $$;

-- A report or view accidentally created without SECURITY INVOKER is a data
-- isolation regression.  Fail this deployment instead of silently releasing
-- a report that can read another yard's records.
do $$
declare
  v text;
  invoker text;
begin
  foreach v in array array[
    'held_goods_rows', 'perishable_rows', 'warehouse_rows', 'forfeit_rows',
    'disposition_rows', 'sr_financials', 'sr_expense_summary',
    'recent_package_activity', 'accrued_storage_by_yard',
    'appeal_rows', 'valuation_rows', 'disposal_request_summary',
    'tender_sale_summary', 'destruction_summary', 'unsold_retender_pool',
    'unsold_perishables', 'exhausted_unsold', 'committee_pool',
    'item_appeal_outcomes', 'zone_occupancy_entries'
  ]
  loop
    if to_regclass('public.' || v) is not null then
      select coalesce(c.reloptions::text, '') into invoker
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v;
      if invoker not like '%security_invoker=true%' then
        raise exception 'view public.% must use security_invoker', v;
      end if;
    end if;
  end loop;
end $$;


-- ==========================================================================
--  migrations/004_warehouse_query_yard_scope.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Warehouse view: expose the owning yard for mandatory SQL-side filtering.
-- A physical warehouse is shared; its entries are not. Safe to re-run.
-- ============================================================================

create or replace view public.warehouse_rows as
select
  we.id as entry_id,
  we.warehouse_id,
  we.package_id,
  we.package_item_id,
  p.sr_number,
  p.consignee_name,
  we.hold_reason,
  we.item_count,
  we.admitted_at,
  pi.item_name,
  case
    when lower(trim(coalesce(pi.status, ''))) = 'forfiet' then 'Forfeit'
    else pi.status
  end as item_status,
  p.status as package_status,
  lower(coalesce(p.status, '')) = 'confiscated' as is_package_confiscated,
  extract(year from we.admitted_at at time zone 'Asia/Colombo')::text
    as admitted_year,
  substring(p.sr_number, '(20[0-9]{2})') as sr_year,
  p.yard
from public.warehouse_entries we
join public.packages p on p.id = we.package_id
left join public.package_items pi on pi.id = we.package_item_id
where not coalesce(we.is_returned, false)
  and lower(trim(coalesce(pi.status, ''))) not in
      ('released', 'returned', 'sold', 're-export', 're-exported',
       'destroy', 'destroyed', 'other');

alter view public.warehouse_rows set (security_invoker = true);

create index if not exists warehouse_entries_yard_warehouse_live_idx
  on public.warehouse_entries (yard, warehouse_id, admitted_at desc)
  where not coalesce(is_returned, false);

analyze public.warehouse_entries;


-- ==========================================================================
--  migrations/005_restrict_yard_staff_at_database.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Database-wide yard boundary for every operational table with a `yard`.
--
-- Older schema policies include permissive rules such as
-- `sr_auth.role() = 'authenticated'`. PostgreSQL combines permissive policies
-- with OR, so that old rule could override `yard_all` and leak a GL1 row to a
-- GL2 officer. This migration adds a RESTRICTIVE policy instead: restrictive
-- policies are AND-ed with every permissive policy, so no old or future broad
-- policy can widen a yard officer/admin's result set.
--
-- Directorate roles (ICT, Disposal, Appeal, Valuation, Executive) are not
-- yard staff and retain their intentional national workflows. Every officer
-- and yard admin is bound to exactly profiles.yard, including ICT-added yards.
-- Safe to re-run.
-- ============================================================================

create or replace function public.auth_user_is_yard_staff()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
      from public.profiles p
     where p.id = sr_auth.uid()
       and lower(coalesce(p.role, '')) in ('officer', 'admin')
  );
$$;

grant execute on function public.auth_user_is_yard_staff() to authenticated;

do $$
declare
  t text;
begin
  -- No hard-coded yard codes: this covers GL1, GL2 and every yard ICT creates.
  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name
     where c.table_schema = 'public'
       and c.column_name = 'yard'
       and tb.table_type = 'BASE TABLE'
       -- auth_user_yard() reads profiles itself. Applying this policy to
       -- profiles would make that lookup recursively invoke its own policy.
       and c.table_name <> 'profiles'
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('drop policy if exists yard_staff_boundary on public.%I', t);
    execute format($policy$
      create policy yard_staff_boundary on public.%I
        as restrictive
        for all
        using (
          not public.auth_user_is_yard_staff()
          or yard = public.auth_user_yard()
        )
        with check (
          not public.auth_user_is_yard_staff()
          or yard = public.auth_user_yard()
        )
    $policy$, t);
  end loop;
end $$;

-- Fail deployment rather than leaving even one yard-bearing data table open.
do $$
declare
  missing text;
begin
  select string_agg(c.table_name, ', ' order by c.table_name) into missing
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
   where c.table_schema = 'public'
     and c.column_name = 'yard'
     and tb.table_type = 'BASE TABLE'
     and c.table_name <> 'profiles'
     and not exists (
       select 1 from pg_policy p
       join pg_class pc on pc.oid = p.polrelid
       join pg_namespace pn on pn.oid = pc.relnamespace
       where pn.nspname = 'public'
         and pc.relname = c.table_name
         and p.polname = 'yard_staff_boundary'
         and p.polpermissive = false
     );
  if missing is not null then
    raise exception 'yard-staff boundary missing from: %', missing;
  end if;
end $$;


-- ==========================================================================
--  migrations/006_profiles_policy_recursion_fix.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Profiles are the source of auth_user_yard(), so they cannot carry the
-- generic yard_staff_boundary policy: evaluating it would read profiles to
-- decide whether profiles may be read, producing PostgreSQL error 42P17.
--
-- Operational tables keep the restrictive policy from migration 005. Profile
-- access remains governed by its dedicated own-row/same-yard policies.
-- Safe to re-run.
-- ============================================================================

drop policy if exists yard_staff_boundary on public.profiles;

-- Verify the migration repaired the recursive policy without weakening the
-- operational-table boundary.
do $$
begin
  if exists (
    select 1 from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'profiles'
     and p.polname = 'yard_staff_boundary'
  ) then
    raise exception 'profiles must not have yard_staff_boundary';
  end if;
end $$;


-- ==========================================================================
--  migrations/007_drop_admin_profiles_policy.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- The base schema's "Admins can manage all profiles" policy survived
-- migration 002, and it is wrong twice over.
--
-- 1. It recurses. It asks whether the caller is an admin by reading profiles
--    INLINE:
--
--      EXISTS (SELECT 1 FROM profiles WHERE id = sr_auth.uid() AND role='admin')
--
--    That subquery is itself subject to the policies on profiles, so deciding
--    whether profiles may be read requires reading profiles: PostgreSQL error
--    42P17. Every sign-in fails, because the router reads the profile.
--
-- 2. It is a cross-yard bypass. Migration 002 established that every user,
--    "administrators included", sees only their own yard, and it dropped
--    auth_user_is_admin() as "the admin-bypass helper (no longer used)". It
--    replaced admin access with yard_profiles_select/update/insert. It simply
--    never dropped this policy, which grants FOR ALL across every yard.
--
-- So the fix is to remove it, not to rewrite it with a SECURITY DEFINER
-- helper: reviving the helper would re-open the hole 002 closed. Profile
-- access stays governed by the own-row/same-yard policies from 002, plus the
-- directorate read policies. Migration 006 removed the same recursion from
-- yard_staff_boundary; this is the older, second source of it.
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists "Admins can manage all profiles" on public.profiles;

-- The helper 002 dropped must stay dropped: it exists only to bypass the yard
-- boundary, and 007 above is what re-created it in an earlier draft.
drop function if exists public.auth_user_is_admin();

-- Verify no policy on profiles reads profiles inline any more.
do $$
declare
  bad text;
begin
  select string_agg(p.polname, ', ') into bad
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'profiles'
     and (
       pg_get_expr(p.polqual, p.polrelid) ilike '%from profiles%'
       or pg_get_expr(p.polqual, p.polrelid) ilike '%from public.profiles%'
       or pg_get_expr(p.polwithcheck, p.polrelid) ilike '%from profiles%'
       or pg_get_expr(p.polwithcheck, p.polrelid) ilike '%from public.profiles%'
     );

  if bad is not null then
    raise exception 'profiles policies still read profiles inline: %', bad;
  end if;
end $$;


-- ==========================================================================
--  migrations/008_warehouses_belong_to_a_yard.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Warehouses and their zones had NO yard column, so every yard saw every
-- warehouse in the system. GL2, which has never had a warehouse added to it,
-- showed GL1's four ("Warehouse 01/02/03", "Open Area 01") plus 18 zones and
-- 72,000 units of capacity that do not exist in that yard.
--
-- Reading them was never yard-scoped either: "All can view warehouses" grants
-- SELECT to any authenticated user, and warehouse_zones inherits its yard
-- through its parent warehouse.
--
-- The workaround in warehousesForYardProvider derived the association from
-- warehouse_entries.yard, which cannot work for a NEW yard: a warehouse only
-- appeared once goods were stored in it, and goods cannot be stored in a
-- warehouse that is not offered. The column is the fix.
--
-- BACKFILL: every existing warehouse is GL1's. All 333 warehouse_entries rows
-- across all four warehouses carry yard 'GL1' and no other yard has ever
-- written one, so the assignment is unambiguous rather than a guess.
--
-- Safe to re-run.
-- ============================================================================

alter table public.warehouses
  add column if not exists yard text;

-- Derive each warehouse's yard from the entries written against it. Only when
-- EXACTLY ONE yard has used it — a warehouse two yards had written to would
-- have no right answer, and silently picking one would hand a yard another
-- yard's goods. There are none today; the guard is for a re-run on a database
-- where that is no longer true.
update public.warehouses w
   set yard = sole.yard
  from (
    select warehouse_id, min(yard) as yard
      from public.warehouse_entries
     where yard is not null
     group by warehouse_id
    having count(distinct yard) = 1
  ) as sole
 where w.id = sole.warehouse_id
   and w.yard is null;

-- A warehouse no yard has ever used cannot be placed by evidence. Leave it
-- NULL rather than guessing: an unplaced warehouse shows in NO yard, which is
-- the safe direction — it can be assigned in the admin panel, whereas a wrong
-- guess quietly exposes one yard's storage to another.
do $$
declare
  unplaced int;
begin
  select count(*) into unplaced from public.warehouses where yard is null;
  if unplaced > 0 then
    raise notice '% warehouse(s) have no entries and stay unassigned', unplaced;
  end if;
end $$;

create index if not exists warehouses_yard_idx on public.warehouses (yard);

-- ── Reads: a yard sees only its own warehouses ──────────────────────────────
-- The old policy granted every authenticated user every warehouse.
drop policy if exists "All can view warehouses" on public.warehouses;
drop policy if exists warehouses_yard_select on public.warehouses;
create policy warehouses_yard_select on public.warehouses
  for select using (yard = public.auth_user_yard());

-- ── Writes: an admin manages warehouses in their OWN yard ───────────────────
-- The replaced policy read profiles INLINE, the pattern that raises 42P17
-- (see migration 007), and granted every admin every yard. Both go.
drop policy if exists "Admins can manage warehouses" on public.warehouses;
drop policy if exists warehouses_yard_write on public.warehouses;
create policy warehouses_yard_write on public.warehouses
  for all
  using (yard = public.auth_user_yard())
  with check (yard = public.auth_user_yard());

-- ── Zones follow their warehouse ────────────────────────────────────────────
-- warehouse_zones has no yard of its own; it inherits through warehouse_id.
-- The parent lookup goes through a SECURITY DEFINER helper so that reading a
-- zone does not re-enter the warehouses policies.
create or replace function public.warehouse_yard(p_warehouse_id uuid)
returns text
language sql
stable
security definer
set search_path = public, extensions
as $function$
  select yard from public.warehouses where id = p_warehouse_id;
$function$;

revoke all on function public.warehouse_yard(uuid) from public;
grant execute on function public.warehouse_yard(uuid) to authenticated;

drop policy if exists warehouse_zones_read on public.warehouse_zones;
drop policy if exists warehouse_zones_admin_write on public.warehouse_zones;
drop policy if exists warehouse_zones_yard_select on public.warehouse_zones;
create policy warehouse_zones_yard_select on public.warehouse_zones
  for select using (
    public.warehouse_yard(warehouse_id) = public.auth_user_yard()
  );

drop policy if exists warehouse_zones_yard_write on public.warehouse_zones;
create policy warehouse_zones_yard_write on public.warehouse_zones
  for all
  using (public.warehouse_yard(warehouse_id) = public.auth_user_yard())
  with check (public.warehouse_yard(warehouse_id) = public.auth_user_yard());

alter table public.warehouses enable row level security;
alter table public.warehouse_zones enable row level security;

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  bad text;
  mixed int;
begin
  -- No policy on either table may read profiles inline (42P17).
  select string_agg(c.relname || '.' || p.polname, ', ') into bad
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('warehouses', 'warehouse_zones')
     and (
       pg_get_expr(p.polqual, p.polrelid) ilike '%from profiles%'
       or pg_get_expr(p.polwithcheck, p.polrelid) ilike '%from profiles%'
     );
  if bad is not null then
    raise exception 'policies still read profiles inline: %', bad;
  end if;

  -- The backfill must not have handed one yard another yard's warehouse.
  select count(*) into mixed
    from public.warehouses w
    join public.warehouse_entries e on e.warehouse_id = w.id
   where w.yard is not null
     and e.yard is not null
     and e.yard <> w.yard;
  if mixed > 0 then
    raise exception '% entrie(s) sit in a warehouse belonging to another yard', mixed;
  end if;
end $$;

-- ── warehouse_contents: the one view migration 003 missed ───────────────────
-- It joins warehouse_entries, warehouses, packages and profiles with no yard
-- filter, and without security_invoker it runs as its OWNER — so the policies
-- above would not apply to it and any authenticated caller could read every
-- yard's stock through it. Nothing in the app queries it, which is why it went
-- unnoticed; making it run as the caller closes the hole rather than leaving a
-- bypass in the schema for the next query that finds it.
alter view public.warehouse_contents set (security_invoker = true);

do $$
begin
  if not exists (
    select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'warehouse_contents'
       and 'security_invoker=true' = any (c.reloptions)
  ) then
    raise exception 'warehouse_contents must run as the caller';
  end if;
end $$;


-- ==========================================================================
--  migrations/009_warehouse_yard_boundary.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Migration 008 gave `warehouses` a yard, but left it protected only by
-- PERMISSIVE policies. PostgreSQL OR-s permissive policies together, so
-- `warehouses_disposal_read` and `executive_read_all` widen the result set
-- past `warehouses_yard_select` — correct for those national roles, but it
-- means a yard officer/admin has no policy that can never be widened.
--
-- Migration 005 already solved this for every operational table by adding a
-- RESTRICTIVE policy, which is AND-ed with all permissive ones. It applies
-- itself to every BASE TABLE carrying a `yard` column — but it ran BEFORE 008
-- existed, so `warehouses` was not a candidate at the time, and re-running it
-- is not part of a normal upgrade. `warehouse_zones` has no `yard` column at
-- all (it inherits through warehouse_id), so 005 can never cover it.
--
-- This closes both, using the same helpers so the rule stays one rule:
--   * yard staff (officer/admin) are pinned to their own yard
--   * directorate roles keep their intentional cross-yard reads
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists yard_staff_boundary on public.warehouses;
create policy yard_staff_boundary on public.warehouses
  as restrictive
  for all
  using (
    (not public.auth_user_is_yard_staff())
    or yard = public.auth_user_yard()
  );

-- Zones carry no yard of their own; the boundary follows the parent warehouse
-- through the SECURITY DEFINER helper added in 008, so evaluating it does not
-- re-enter the warehouses policies.
drop policy if exists yard_staff_boundary on public.warehouse_zones;
create policy yard_staff_boundary on public.warehouse_zones
  as restrictive
  for all
  using (
    (not public.auth_user_is_yard_staff())
    or public.warehouse_yard(warehouse_id) = public.auth_user_yard()
  );

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  missing text;
begin
  select string_agg(t, ', ') into missing
    from unnest(array['warehouses', 'warehouse_zones']) as t
   where not exists (
     select 1 from pg_policy p
       join pg_class c on c.oid = p.polrelid
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = t
        and p.polname = 'yard_staff_boundary'
        and not p.polpermissive
   );
  if missing is not null then
    raise exception 'restrictive yard boundary missing on: %', missing;
  end if;
end $$;


-- ==========================================================================
--  migrations/010_remaining_views_run_as_caller.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- The last two views that ignored RLS.
--
-- A view without `security_invoker` runs as its OWNER, so the policies that
-- scope a yard officer to their own yard never apply to it. `daily_stats`
-- aggregates `packages` across EVERY yard; `password_rotation_status` reports
-- on accounts. Neither is queried by the app today, which is why they went
-- unnoticed — but an unscoped view is a leak waiting for the first caller,
-- exactly like warehouse_contents was (migration 008).
--
-- Safe to re-run.
-- ============================================================================

-- ⚠️ Guarded. `password_rotation_status` is defined in postgres/52, which
-- is applied separately and is NOT folded into 02_schema.sql — so on a fresh
-- database this migration runs before the view exists. Failing there would
-- break the one file used to stand a new server up.
do $$
declare
  v text;
begin
  foreach v in array array['daily_stats', 'password_rotation_status'] loop
    if exists (select 1 from pg_class c
                 join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public' and c.relname = v
                  and c.relkind = 'v') then
      -- Same exclusion as the verification below: an extension's view is
      -- not ours to alter.
      if not exists (select 1 from pg_depend d
                       join pg_class c2 on c2.oid = d.objid
                       join pg_namespace n2 on n2.oid = c2.relnamespace
                      where n2.nspname = 'public' and c2.relname = v
                        and d.classid = 'pg_class'::regclass
                        and d.deptype = 'e') then
        execute format('alter view public.%I set (security_invoker = true)', v);
      end if;
    end if;
  end loop;
end $$;

-- Verification: NO view in public may bypass the caller's policies.
do $$
declare
  bad text;
begin
  -- ⚠️ EXTENSION-owned views are excluded, and must be.
  --
  -- A server with pg_stat_statements installed into `public` has two views
  -- there that belong to the extension, not to this project: they cannot be
  -- altered without owning the extension, and they carry no application data
  -- for a policy to protect. Without this the check failed on exactly such a
  -- server and took the whole schema build down with it — a deployment
  -- blocked by a rule about views the rule was never meant to cover.
  select string_agg(c.relname, ', ') into bad
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'v'
     and not exists (select 1 from pg_depend d
                      where d.objid = c.oid
                        and d.classid = 'pg_class'::regclass
                        and d.deptype = 'e')
     and not coalesce('security_invoker=true' = any (c.reloptions), false);

  if bad is not null then
    raise exception 'these views still run as their owner: %', bad;
  end if;
end $$;


-- ==========================================================================
--  migrations/011_yard_index_completeness.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Every yard-scoped read filters on `yard`, so every table carrying that
-- column needs an index on it. Three were missing: without one, each query
-- from any yard sequentially scans the whole table, and the cost grows with
-- the number of yards using the system rather than with one yard's data.
--
-- These three are empty today, which is exactly when to add the index: it is
-- free now, and the seq scan would only start hurting once the tenders
-- workflow is in real use across several yards.
--
-- Safe to re-run.
-- ============================================================================

-- ⚠️ CREATES the missing ones rather than naming three by hand.
--
-- Listing the three that happened to be missing on THIS database made the
-- migration a snapshot of one server. On a fresh database — the one case
-- that matters, because 02_schema.sql is what stands a new server up —
-- twelve more were missing and the verification below failed the whole
-- file. Deriving the list means the rule holds wherever it runs.
do $$
declare
  t text;
begin
  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name
     where c.table_schema = 'public'
       and c.column_name = 'yard'
       and tb.table_type = 'BASE TABLE'
       and not exists (
         select 1 from pg_indexes i
          where i.schemaname = 'public'
            and i.tablename = c.table_name
            and i.indexdef like '%(yard%'
       )
  loop
    execute format('create index if not exists %I on public.%I (yard)',
                   t || '_yard_idx', t);
  end loop;
end $$;

-- Verification: no BASE TABLE with a `yard` column may be left unindexed on
-- it. Catches the next table that adds the column and forgets the index.
do $$
declare
  missing text;
begin
  select string_agg(c.table_name, ', ') into missing
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
   where c.table_schema = 'public'
     and c.column_name = 'yard'
     and tb.table_type = 'BASE TABLE'
     and not exists (
       select 1 from pg_indexes i
        where i.schemaname = 'public'
          and i.tablename = c.table_name
          and i.indexdef like '%(yard%'
     );

  if missing is not null then
    raise exception 'yard column is not indexed on: %', missing;
  end if;
end $$;


-- ==========================================================================
--  migrations/013_other_goods_handover.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Goods disposed under an "Other" status leave the yard like any others, and
-- nothing recorded when they did.
--
-- An "Other" disposition (handed to the Police, auctioned per an appeal
-- ruling, taken for Government use...) is a RULING. The goods physically
-- leaving is a second, later event — exactly the distinction already drawn
-- for re-exports and releases, each of which has its own delivered flag.
-- "Other" had none, so the Other Goods table could show a completed
-- disposition with no way to say whether the goods were still standing in
-- the warehouse.
--
-- ⚠️ NOT reusing yard_toggle_reexport_delivery. That function rejects any
-- entry whose tag is not a re-export, and writes `re_export_delivered` —
-- marking these goods re-exported, which they are not.
--
-- Safe to re-run.
-- ============================================================================

alter table public.warehouse_entries
  add column if not exists other_delivered boolean not null default false,
  add column if not exists other_delivered_at timestamptz,
  add column if not exists other_delivered_by uuid references public.profiles(id);

create or replace function public.yard_toggle_other_delivery(
  p_entry_id uuid,
  p_delivered boolean,
  p_receipt_no text default null,
  p_charge numeric default null,
  p_handed_at timestamptz default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_yard text;
  v_tag  text;
begin
  select p.yard,
         upper(substring(upper(trim(coalesce(w.return_notes, '')))
                         from '^\[([^\]]+)\]'))
    into v_yard, v_tag
    from public.warehouse_entries w
    join public.packages p on p.id = w.package_id
   where w.id = p_entry_id;

  if v_yard is null then
    raise exception 'no warehouse_entry with id %', p_entry_id;
  end if;

  -- The same guard the re-export function uses, for the same reason: a
  -- delivery flag written against the wrong kind of disposition is a
  -- record that cannot be told apart from a correct one.
  if v_tag is null or v_tag not in ('FINAL:OTHER', 'OTHER') then
    raise exception 'entry % is not an "Other" disposition (tag %)',
      p_entry_id, coalesce(v_tag, 'none');
  end if;

  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;

  -- ⚠️ Does NOT close the warehouse entry: recording the disposition
  -- already closed it. Re-closing would overwrite returned_at with today.
  update public.warehouse_entries
     set other_delivered    = p_delivered,
         other_delivered_at =
           case when p_delivered then coalesce(p_handed_at, now()) end,
         other_delivered_by = case when p_delivered then sr_auth.uid() end,
         handover_receipt_no = case when p_delivered then p_receipt_no
                                    else handover_receipt_no end,
         handover_charge     = case when p_delivered then p_charge
                                    else handover_charge end
   where id = p_entry_id;
end;
$function$;

revoke all on function public.yard_toggle_other_delivery(uuid, boolean, text, numeric, timestamptz) from public;
grant execute on function public.yard_toggle_other_delivery(uuid, boolean, text, numeric, timestamptz) to authenticated;

-- Verification.
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'warehouse_entries'
                    and column_name = 'other_delivered') then
    raise exception 'other_delivered column missing';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public'
                    and p.proname = 'yard_toggle_other_delivery') then
    raise exception 'yard_toggle_other_delivery missing';
  end if;
end $$;


-- ==========================================================================
--  migrations/014_past_yard_staff_visible.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- A yard cannot see the staff who used to serve in it.
--
-- `yard_profiles_select` returns a profile only when `profiles.yard` equals
-- the caller's yard. `profiles.yard` holds ONE value — where a person is NOW
-- — so the moment an officer is transferred GL1 → GL2 their row leaves GL1's
-- result set, taking with it the record that they ever worked there.
--
-- The Admin Panel's staff table asks "who has served in this yard, and
-- when". It reads the service dates from `audit_logs`, which is already
-- scoped per yard and already readable — but the NAME beside each date lives
-- in `profiles`, and that row was invisible. The page could therefore show
-- a service span for nobody.
--
-- ⚠️ Narrow on purpose. This does NOT open profiles across yards: it grants
-- SELECT only on rows the caller's OWN yard has a recorded history with, and
-- only ever on the caller's own yard's log. A yard sees the people who
-- passed through it and nobody else.
--
-- Safe to re-run.
-- ============================================================================

-- Whether this yard's audit log has any profile event for that person.
--
-- SECURITY DEFINER because it is consulted BY a profiles policy: reading
-- audit_logs here must not re-enter the caller's own policies, and a plain
-- subquery against a table that itself joins profiles would risk the 42P17
-- recursion that migrations 006 and 007 removed.
create or replace function public.profile_served_in_my_yard(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $function$
  select exists (
    select 1
      from public.audit_logs l
     where l.entity_type = 'profile'
       and l.entity_id = p_profile_id::text
       and l.yard is not null
       and l.yard = public.auth_user_yard()
  );
$function$;

revoke all on function public.profile_served_in_my_yard(uuid) from public;
grant execute on function public.profile_served_in_my_yard(uuid) to authenticated;

drop policy if exists yard_profiles_select on public.profiles;
create policy yard_profiles_select on public.profiles
  for select using (
    id = (select sr_auth.uid())
    or yard = (select public.auth_user_yard())
    -- Someone who has since moved on, but whose service here is recorded.
    or (select public.profile_served_in_my_yard(id))
  );

-- ⚠️ The restrictive boundary must widen with it, or it AND-s the new rows
-- straight back out again. Same shape as the permissive rule above.
drop policy if exists yard_staff_boundary on public.profiles;

do $$
begin
  if exists (
    select 1 from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'profiles'
       and p.polname = 'yard_profiles_select'
       and pg_get_expr(p.polqual, p.polrelid) not like '%profile_served_in_my_yard%'
  ) then
    raise exception 'yard_profiles_select does not admit past staff';
  end if;
end $$;


-- ==========================================================================
--  postgres/47_item_appeal_outcomes_view.sql (folded in)
-- ==========================================================================

-- What the Appeal Directorate has ruled about each goods ITEM, whatever the
-- goods are.
--
-- ⚠️ Four screens read this — Warehouses, Detained, Abandoned and Other — to
-- decide whether goods may move: a DECISION releases them early, a HOLD keeps
-- them frozen past the deadline. It was
-- `forfeited_packages.select('*')`: every column of every forfeited row,
-- 171ms, to build a map of two values per item.
--
-- ⚠️ And it could not resolve the rule it was applying. `appealDecisionForItem`
-- needs the package's ITEM COUNT to know whether a package-level decision may
-- stand in for a missing per-item one — and `select('*')` embeds no package,
-- so `packageDetails` was always null and the multi-item guard could never
-- fire. A decision on one item therefore reported every sibling decided,
-- which is the exact bleed the model documents and defends against.
--
-- This is `appeal_rows`'s resolution without its membership: that view is the
-- Appeal PORTAL's feed and is `source = 'forfeit'` only, while a ruling can
-- exist against detained, abandoned and other goods too — 65 of them on the
-- live data, which would simply have vanished from these four screens.
--
--   decision  the per-item entry in item_appeal_decisions, else the
--             package-level column, and NEVER the package-level column for an
--             item of a multi-item package that has no entry of its own
--   on_hold   per item when held_item_ids names any, else the package-level
--             appeal_hold

drop view if exists public.item_appeal_outcomes cascade;

-- ⚠️ security_invoker on the view ITSELF. Migration 003 adds it to the
-- reporting views, but this file is now folded into 02_schema.sql AFTER that
-- migration, so recreating the view here would drop the flag and the view
-- would run as its owner — bypassing every per-yard policy underneath it.
create view public.item_appeal_outcomes
with (security_invoker = true) as
with item_count as (
  select package_id, count(*) as n
    from public.package_items
   group by package_id
),
-- Every (forfeited row, item) a ruling could be about.
candidate as (
  -- A per-item row speaks for its own item.
  select fp.id as fp_id, fp.package_id, fp.item_id
    from public.forfeited_packages fp
   where fp.item_id is not null

  union

  -- A package-level row: its per-item map names the items it ruled on...
  select fp.id, fp.package_id, k::uuid
    from public.forfeited_packages fp
   cross join lateral jsonb_object_keys(
     case jsonb_typeof(fp.item_appeal_decisions)
       when 'object' then fp.item_appeal_decisions
       else '{}'::jsonb
     end) as k
   where fp.item_id is null

  union

  -- ...and its held list names the items it froze.
  select fp.id, fp.package_id, h
    from public.forfeited_packages fp
   cross join lateral unnest(coalesce(fp.held_item_ids, '{}')) as h
   where fp.item_id is null
),
resolved as (
  select
    c.item_id,
    -- ⚠️ The multi-item guard, which the Dart could never apply here.
    case
      when nullif(trim(coalesce(
             fp.item_appeal_decisions -> c.item_id::text ->> 'decision',
             '')), '') is not null
        then nullif(trim(
               fp.item_appeal_decisions -> c.item_id::text ->> 'decision'), '')
      when coalesce(ic.n, 0) > 1
        then null
      else nullif(trim(coalesce(fp.appeal_decision, '')), '')
    end as decision,
    case
      when coalesce(array_length(fp.held_item_ids, 1), 0) > 0
        then c.item_id = any(fp.held_item_ids)
      else coalesce(fp.appeal_hold, false)
    end as on_hold,
    fp.appeal_decided_at
  from candidate c
  join public.forfeited_packages fp on fp.id = c.fp_id
  left join item_count ic on ic.package_id = c.package_id
)
-- ⚠️ One row per ITEM. Several forfeited rows can name the same item, and the
-- one carrying a ruling must win: a decision outranks a hold, and both outrank
-- silence. Dropping the wrong copy would tell a yard the goods are free to
-- move when the directorate has frozen them.
select distinct on (r.item_id)
  r.item_id,
  r.decision,
  r.on_hold,
  -- ⚠️ The yard the goods are in, so a caller can narrow without an
  -- embed. This is a VIEW, so it carries no foreign key for PostgREST to
  -- join through -- a caller trying `package_items!inner(...)` gets a
  -- resolve error, which is how this column came to be added.
  --
  -- Both the column and the SR number's own segment, because a row filed by
  -- one directorate can sit in another's yard.
  p.yard,
  p.sr_number
from resolved r
join public.package_items pi_y on pi_y.id = r.item_id
join public.packages p on p.id = pi_y.package_id
order by
  r.item_id,
  ((case when r.decision is not null then 2 else 0 end)
   + (case when r.on_hold then 1 else 0 end)) desc,
  r.appeal_decided_at desc nulls last;

comment on view public.item_appeal_outcomes is
  'One row per goods item the Appeal Directorate has ruled on or frozen, '
  'whatever the source. A package-level decision never bleeds onto an item '
  'of a multi-item package that has no entry of its own.';


-- ── Does it say what the four screens were being told? ───────────────────
do $verify$
declare
  n_rows     int;
  n_decided  int;
  n_held     int;
  n_sources  int;
  bad        int;
begin
  select count(*),
         count(*) filter (where decision is not null),
         count(*) filter (where on_hold)
    into n_rows, n_decided, n_held
    from public.item_appeal_outcomes;

  -- ⚠️ Rulings exist against every source, not just forfeits. Reading this
  -- from the Appeal portal's own feed would have dropped 65 of them.
  select count(distinct coalesce(fp.source, '')) into n_sources
    from public.forfeited_packages fp
    join public.item_appeal_outcomes o
      on o.item_id = fp.item_id
      or fp.item_appeal_decisions ? o.item_id::text
   where o.decision is not null or o.on_hold;
  -- ⚠️ Skipped on an EMPTY database. This asserts a property of the DATA,
  -- not of the view, and 02_schema.sql now folds this file in to stand a new
  -- server up — where there are no rulings yet and never can be. Failing
  -- there would block the deployment over a shape the data has not reached.
  if n_sources > 0 and n_sources < 2 then
    raise exception 'outcomes come from only % source(s) -- the view is '
                    'narrowed to one kind of goods', n_sources;
  end if;

  -- One row per item, or a screen reads whichever copy it happened to get.
  select count(*) into bad from (
    select item_id from public.item_appeal_outcomes
     group by item_id having count(*) > 1) d;
  if bad <> 0 then
    raise exception '% item(s) appear twice', bad;
  end if;

  -- The bleed rule, stated the other way round.
  select count(*) into bad
    from public.item_appeal_outcomes o
    join public.package_items pi on pi.id = o.item_id
   where o.decision is not null
     and (select count(*) from public.package_items pi2
           where pi2.package_id = pi.package_id) > 1
     and not exists (
       select 1 from public.forfeited_packages fp
        where fp.package_id = pi.package_id
          and nullif(trim(coalesce(
                fp.item_appeal_decisions -> o.item_id::text ->> 'decision',
                '')), '') is not null);
  if bad <> 0 then
    raise exception '% item(s) inherit a package-level decision across '
                    'siblings', bad;
  end if;

  -- Nothing is recorded that names no ruling at all.
  select count(*) into bad
    from public.item_appeal_outcomes
   where decision is null and not on_hold;
  if bad <> 0 then
    raise notice '% item(s) carry neither a decision nor a hold', bad;
  end if;

  raise notice 'item_appeal_outcomes: % item(s) — % decided, % on hold',
    n_rows, n_decided, n_held;
end
$verify$;


-- ==========================================================================
--  migrations/015_warehouse_rows_appeal_state.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- The Warehouses table can now be narrowed by appeal state, and that filter
-- has to run in SQL like every other one on the page.
--
-- ⚠️ Filtering it in Dart would break the pager. The page reads ONE page of
-- rows and takes its total from the server, so narrowing the twenty rows on
-- screen would leave the pager counting rows it had just removed — the exact
-- trap the comment above `pageRows` warns about.
--
-- Appeal state is NOT a package status: a DETAINED item can be appealing, on
-- hold, or decided, so the two questions narrow independently and the view
-- has to carry both.
--
-- ⚠️ The inner query is postgres/48 verbatim. Retyping it by hand is how the
-- two drift; this wraps it and adds three columns.
--
-- Safe to re-run.
-- ============================================================================

drop view if exists public.warehouse_rows cascade;

create view public.warehouse_rows
with (security_invoker = true) as
select
  r.*,
  -- Null for an entry with no item (a whole-package admission): there is no
  -- appeal to be in any state, and false would read as "enabled".
  ao.decision as appeal_decision,
  ao.on_hold  as appeal_on_hold,
  -- The three states the filter offers, resolved once here so the screen and
  -- the query cannot disagree about what "decided" means.
  -- ⚠️ FOUR states, and 'enabled' is the last of them.
  --
  -- An appeal can only be lodged inside the first 30 days. So:
  --   appealing — still inside that window; nobody may act yet
  --   hold      — the Directorate froze it past the deadline
  --   decided   — a ruling exists; the window no longer applies
  --   enabled   — the window CLOSED with no appeal, so the YARD may now
  --               act: a final disposition, or send the goods for sale
  --
  -- ⚠️ The window was missing here, so goods still inside their 30 days
  -- fell through to 'enabled' — and the filter returned rows whose own
  -- chip read "Appealing". Same rule as `isWithinAppealWindow`: the clock
  -- runs from the ENTRY DATE and lasts 30 days.
  case
    when r.package_item_id is null then null
    when coalesce(ao.on_hold, false) then 'hold'
    when coalesce(trim(ao.decision), '') <> '' then 'decided'
    when now() < (date_trunc('day', r.admitted_at at time zone 'Asia/Colombo')
                  + interval '30 days') at time zone 'Asia/Colombo'
      then 'appealing'
    else 'enabled'
  end as appeal_state
from (
select
  we.id as entry_id,
  we.warehouse_id,
  we.package_id,
  we.package_item_id,
  p.sr_number,
  p.consignee_name,
  we.hold_reason,
  we.item_count,
  we.admitted_at,

  -- The goods on this row.
  pi.item_name,

  -- ⚠️ Normalised. 'Forfiet' is a typo that reached the data; folding it here
  -- keeps the filter's one choice from matching only half its rows.
  case
    when lower(trim(coalesce(pi.status, ''))) = 'forfiet' then 'Forfeit'
    else pi.status
  end as item_status,

  -- The package-level status the 'confiscated' filter reads.
  p.status as package_status,
  lower(coalesce(p.status, '')) = 'confiscated' as is_package_confiscated,

  -- Both of the year filter's answers, so it can match either.
  extract(year from we.admitted_at at time zone 'Asia/Colombo')::text
    as admitted_year,
  substring(p.sr_number, '(20[0-9]{2})') as sr_year,

  -- A warehouse facility is shared, but an entry belongs to exactly one
  -- yard. Exposing this lets every yard-bound query narrow in SQL.
  p.yard

from public.warehouse_entries we
join public.packages p on p.id = we.package_id
left join public.package_items pi on pi.id = we.package_item_id
where
  not coalesce(we.is_returned, false)
  -- Goods with a final disposition have left the yard.
  and lower(trim(coalesce(pi.status, ''))) not in
      ('released', 'returned', 'sold', 're-export', 're-exported',
       'destroy', 'destroyed', 'other')
) r
left join public.item_appeal_outcomes ao on ao.item_id = r.package_item_id;

comment on view public.warehouse_rows is
  'Live warehouse entries — not returned, and not goods that have left the '
  'yard under a final disposition — with the item status, hold reason, both '
  'year values and the appeal state the Warehouses page filters on.';

-- Verification: only the three documented states may be produced.
do $$
declare
  bad text;
begin
  select string_agg(distinct appeal_state, ', ') into bad
    from public.warehouse_rows
   where appeal_state is not null
     and appeal_state not in ('appealing', 'enabled', 'hold', 'decided');
  if bad is not null then
    raise exception 'unexpected appeal_state: %', bad;
  end if;
end $$;


-- ==========================================================================
--  migrations/016_perishable_flag_on_outcome_views.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Perishable goods reach the Sold, Unsold and Final Outcome tables alongside
-- everything else, and nothing on those rows says so.
--
-- A perishable runs ONE special tender sale — no re-valuation, no second
-- round, no committee — so a reader scanning those tables cannot tell why a
-- row has one tender behind it and its neighbour has four. The tender pages
-- already mark them; these did not.
--
-- ⚠️ The flag goes in the VIEW, not in Dart, because these pages are
-- server-paged: the filter has to narrow the query, or the pager would go on
-- counting rows the screen had just removed.
--
-- ⚠️ `forfeited_packages.source` is the authority (postgres/07 made
-- 'perishable' a real source). `package_items.nature` is the fallback for
-- goods sold or released straight out of the yard without ever reaching a
-- forfeited record. Both agree on all 8 rows in this database; keeping both
-- means a route that skips one is still caught.
--
-- Safe to re-run.
-- ============================================================================

-- ⚠️ plpgsql with a dynamic fallback, not plain SQL.
--
-- `package_items.nature` is added by postgres/06, which is applied by hand
-- and is NOT folded into 02_schema.sql — so on the fresh database that file
-- stands a new server up, the column does not exist and a static reference
-- to it fails to parse the whole function. Checking the catalogue first
-- keeps the fallback where the column is present and skips it where it is
-- not, instead of making 02_schema.sql depend on another manual file.
create or replace function public.item_is_perishable(p_item_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $function$
declare
  hit boolean;
begin
  -- The authority: postgres/07 made 'perishable' a real forfeited source.
  select exists (select 1 from public.forfeited_packages fp
                  where fp.item_id = p_item_id
                    and lower(trim(coalesce(fp.source, ''))) = 'perishable')
    into hit;
  if hit then
    return true;
  end if;

  -- Fallback for goods sold or released straight out of the yard, which
  -- never reach a forfeited record.
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'package_items'
                and column_name = 'nature') then
    execute 'select lower(trim(coalesce(nature, ''''))) = ''perishable'' '
            'from public.package_items where id = $1'
      into hit using p_item_id;
    return coalesce(hit, false);
  end if;
  return false;
end;
$function$;

revoke all on function public.item_is_perishable(uuid) from public;
grant execute on function public.item_is_perishable(uuid) to authenticated;

-- ── disposition_rows: Sold / Destroyed / Re-exported / Released ────────────
do $$
declare
  body text;
begin
  -- Rebuild the view with one extra column, keeping its definition exactly
  -- as it stands rather than retyping it — that is how two copies drift.
  -- ⚠️ Guarded. disposition_rows is created by postgres/18, applied by
  -- hand and not folded into 02_schema.sql, so on a fresh database it does
  -- not exist yet. Failing here would break the file that stands a new
  -- server up.
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'disposition_rows') then
    return;
  end if;
  select pg_get_viewdef('public.disposition_rows'::regclass, true) into body;
  if body like '%is_perishable%' then
    return; -- already carries it
  end if;
  execute format(
    'create or replace view public.disposition_rows '
    'with (security_invoker = true) as '
    'select d.*, public.item_is_perishable(d.item_id) as is_perishable '
    'from (%s) d', rtrim(body, ';' || chr(10) || chr(13) || ' '));
end $$;

-- ── exhausted_unsold: the Unsold page and its Final Outcome tabs ───────────
do $$
declare
  body text;
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'exhausted_unsold') then
    return;
  end if;
  select pg_get_viewdef('public.exhausted_unsold'::regclass, true) into body;
  if body like '%is_perishable%' then
    return;
  end if;
  execute format(
    'create or replace view public.exhausted_unsold '
    'with (security_invoker = true) as '
    'select u.*, public.item_is_perishable(u.item_id) as is_perishable '
    'from (%s) u', rtrim(body, ';' || chr(10) || chr(13) || ' '));
end $$;

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  v text;
begin
  foreach v in array array['disposition_rows', 'exhausted_unsold'] loop
    -- Only assert about a view that actually exists here; see above.
    if not exists (select 1 from pg_class c
                     join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relname = v) then
      continue;
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = v
                      and column_name = 'is_perishable') then
      raise exception '% is missing is_perishable', v;
    end if;
    -- Both views must still run as the caller: recreating one drops the
    -- flag, and without it every per-yard policy under it is bypassed.
    if not exists (select 1 from pg_class c
                     join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relname = v
                      and 'security_invoker=true' = any (c.reloptions)) then
      raise exception '% must run as the caller', v;
    end if;
  end loop;
end $$;


-- ==========================================================================
--  migrations/017_unsold_includes_perishables.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Unsold perishables never reached the yard's Unsold Goods page, nor any of
-- the four Final Outcome pages.
--
-- The two routes are deliberately different (postgres/23 and /32):
--
--   normal goods  → 4+ failed tenders → committee re-valuation → proposal
--   perishable    → ONE failed Special Tender Sale → proposal
--
-- `exhausted_unsold` encodes the FIRST route, and its two gate conditions --
-- `tender_count > 3` and a `tender_committees` row -- are conditions a
-- perishable can never satisfy, by design: goods that spoil cannot wait for
-- the long route. So every unsold perishable was filtered out of the page
-- that is supposed to list unsold goods.
--
-- In this database that hid 9 packages, two of which the Top Management
-- Directorate had ALREADY ruled on ('destroy' and 'convert'). The rulings
-- were recorded; the yard had no page that could show them.
--
-- ⚠️ Fixed with a UNION view rather than by loosening `exhausted_unsold`.
-- Relaxing its gates would let a normal package through before its committee
-- has valued it, which is the very thing those gates exist to prevent. The
-- two routes stay separately defined and are joined only for DISPLAY.
--
-- ⚠️ The Top Management dashboard keeps reading the two views SEPARATELY
-- (its Unsold tab and its Perishables tab), because there the distinction is
-- the whole point -- one tab is deciding after a committee valuation, the
-- other after a single spoiled sale. This view is for the pages that ask
-- "what is unsold in this yard", where the answer is both.
--
-- Safe to re-run.
-- ============================================================================

-- ── The union both routes present to the yard's pages ─────────────────────
--
-- Column shape is `exhausted_unsold`'s, because that is what the pages,
-- filters and pager already read. Perishables have no committee, so the two
-- committee columns are NULL for them -- which is accurate, not missing
-- data: there was no committee to value them.
--
-- ⚠️ Guarded on BOTH sources existing. `exhausted_unsold` comes from
-- postgres/23 and `unsold_perishables` from postgres/32; both are applied by
-- hand and neither is folded into 02_schema.sql, so on the fresh database
-- that file stands a new server up they are absent. Creating a view over a
-- missing table would fail there and break the one file that has to work.
do $outer$
begin
if to_regclass('public.exhausted_unsold') is null
   or to_regclass('public.unsold_perishables') is null then
  return;
end if;

execute $ddl$
create or replace view public.unsold_all_routes
with (security_invoker = true) as
  select
    forfeited_package_id,
    package_id,
    item_id,
    sr_number,
    consignee_name,
    yard,
    entry_qty,
    forfeited_at,
    item_name,
    case_number,
    tender_count,
    submitted_value,
    submitted_at,
    proposal_id,
    proposal,
    decided_at,
    delivered,
    is_perishable
  from public.exhausted_unsold

  union all

  select
    forfeited_package_id,
    package_id,
    item_id,
    sr_number,
    consignee_name,
    yard,
    entry_qty,
    forfeited_at,
    item_name,
    case_number,
    tender_count,
    -- No committee on this route. NULL says so; 0 would read as "valued at
    -- nothing", which is a different and wrong statement.
    null::numeric  as submitted_value,
    null::timestamptz as submitted_at,
    proposal_id,
    proposal,
    decided_at,
    delivered,
    true as is_perishable
  from public.unsold_perishables
$ddl$;

execute $c$comment on view public.unsold_all_routes is
  'Every unsold package in a yard, by either route: the committee route '
  '(exhausted_unsold) and the single-special-sale perishable route '
  '(unsold_perishables). is_perishable says which. Display only -- the two '
  'source views stay separate for the Top Management decision tabs.'$c$;

execute 'grant select on public.unsold_all_routes to authenticated';
end
$outer$;

-- ── Verification ──────────────────────────────────────────────────────────
do $$
declare
  n_union int;
  n_parts int;
  n_peri  int;
begin
  -- Nothing to verify where the sources -- and so the view -- do not exist.
  if to_regclass('public.unsold_all_routes') is null then
    return;
  end if;

  -- The view must run as the caller, or every per-yard policy beneath it is
  -- bypassed and one yard reads another's unsold goods.
  if not exists (select 1 from pg_class c
                   join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'unsold_all_routes'
                    and 'security_invoker=true' = any (c.reloptions)) then
    raise exception 'unsold_all_routes must run as the caller';
  end if;

  select count(*) into n_union from public.unsold_all_routes;
  select (select count(*) from public.exhausted_unsold)
       + (select count(*) from public.unsold_perishables) into n_parts;
  if n_union <> n_parts then
    raise exception 'unsold_all_routes has % rows, its two sources have %',
      n_union, n_parts;
  end if;

  -- A package must not arrive by both routes: exhausted_unsold requires a
  -- committee, unsold_perishables requires source='perishable' and no
  -- committee is ever created for one. If that ever overlaps, a package
  -- would be listed twice and counted twice by the pager.
  if exists (select forfeited_package_id
               from public.unsold_all_routes
              group by forfeited_package_id having count(*) > 1) then
    raise exception 'a package reached unsold_all_routes by both routes';
  end if;

  -- Every perishable-route row must be flagged, or the page's filter and
  -- its row tint would disagree with the route the row actually took.
  select count(*) into n_peri from public.unsold_all_routes where is_perishable;
  if n_peri < (select count(*) from public.unsold_perishables) then
    raise exception 'perishable rows lost their flag in the union';
  end if;
end $$;


-- ==========================================================================
--  migrations/018_expired_password_locks_the_session.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- An expired password now blocks everything EXCEPT changing that password,
-- and the database is what enforces it.
--
-- Before this, the 90-day rotation rule lived entirely in the Flutter client:
-- the login screens hid "Skip for now" once a password was expired. That is a
-- hint, not a rule. Anything that talks to the database directly -- a second
-- copy of the app, a psql session, a modified build -- ignored it completely.
--
-- ⚠️ Rejecting the sign-in is NOT the fix, which is why this took a different
-- shape. A password is changed from INSIDE a signed-in session
-- (sr_auth.change_password runs after sr_auth.sign_in), so an account whose sign-in
-- is refused can never reach the screen that would fix it: the rule would
-- permanently lock out exactly the people it is meant to prompt. The account
-- would need ICT to reset it, turning a routine 90-day prompt into a support
-- ticket for every directorate.
--
-- So: the sign-in SUCCEEDS, and lands in a state where the only thing that
-- works is changing the password.
--
-- ── How ─────────────────────────────────────────────────────────────────────
--
-- `sr_auth.uid()` is the root of the whole authorization model: all 132 RLS
-- policies in `public` are written in terms of it. If it returns NULL the user
-- is, to every policy, signed out -- no yard, no packages, no profile. That is
-- precisely the state we want an expired password to be in.
--
-- ⚠️ The age is NOT looked up inside sr_auth.uid(). It is called once per policy
-- per row, so a `select ... from profiles` in its body would add a lookup to
-- every row of every query in the app. Instead the verdict is computed ONCE,
-- when the connection announces who it is, and parked in a session variable
-- that sr_auth.uid() reads for free.
--
-- ⚠️ sr_auth.change_password keeps working because it is SECURITY DEFINER and
-- takes the user id as an ARGUMENT -- it never calls sr_auth.uid(). That is what
-- makes the one permitted action possible from inside the locked state. It is
-- also why this migration tightens that function: taking an id as a parameter
-- means it must verify the caller owns it, or a locked session could change
-- somebody else's password.
--
-- Safe to re-run.
-- ============================================================================

-- ── 1. The verdict, computed once per session ───────────────────────────────
--
-- SECURITY DEFINER: a session that is about to be locked out still has to be
-- able to ask whether it is locked out.
create or replace function sr_auth.password_is_expired(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = sr_auth, public, extensions
as $fn$
  select coalesce(
    (select (now() - coalesce(p.password_updated_at, p.created_at))
              > interval '90 days'
       from public.profiles p
      where p.id = p_user_id),
    false)  -- no profile row: not this rule's business to decide
$fn$;

revoke all on function sr_auth.password_is_expired(uuid) from public;
grant execute on function sr_auth.password_is_expired(uuid) to public;

-- ── 2. Announcing the session sets the flag ─────────────────────────────────
--
-- The client calls this instead of setting app.current_user_id by hand, so
-- the CLIENT cannot choose its own answer: it supplies who it is, and the
-- database decides whether that identity is still usable.
create or replace function sr_auth.begin_session(p_user_id text, p_role text)
returns void
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_id      uuid;
  v_expired boolean := false;
begin
  v_id := nullif(trim(coalesce(p_user_id, '')), '')::uuid;
  if v_id is not null then
    v_expired := sr_auth.password_is_expired(v_id);
  end if;

  -- Always set all three, and never conditionally: a pooled connection is
  -- reused, so a variable left over from the previous occupant is how one
  -- user inherits another's state.
  perform set_config('app.current_user_id', coalesce(v_id::text, ''), false);
  perform set_config('app.current_role', coalesce(p_role, 'anon'), false);
  perform set_config('app.password_expired', case when v_expired then 'on' else 'off' end, false);
end;
$fn$;

revoke all on function sr_auth.begin_session(text, text) from public;
grant execute on function sr_auth.begin_session(text, text) to public;

-- ── 3. sr_auth.uid() honours the flag ──────────────────────────────────────────
--
-- ⚠️ Still a one-line, STABLE, no-table-access function. It reads two session
-- variables instead of one; it does not become a query. Every policy that
-- calls it keeps the same cost.
create or replace function sr_auth.uid()
returns uuid
language sql
stable
as $fn$
  select case
           when current_setting('app.password_expired', true) = 'on' then null
           else nullif(current_setting('app.current_user_id', true), '')::uuid
         end;
$fn$;

-- ── 3b. sr_auth.role() honours it too ──────────────────────────────────────────
--
-- ⚠️ sr_auth.uid() is NOT the only root. 13 policies are written against
-- sr_auth.role() instead -- "Officers can view all packages" is simply
-- `sr_auth.role() = 'authenticated'` -- and that function reads
-- app.current_role, which the flag above does not touch. Verified the hard
-- way: with only sr_auth.uid() gated, a locked session still read all 176
-- packages and all 320 forfeited packages. An expired password has to look
-- like 'anon' to these policies for the lock to mean anything.
create or replace function sr_auth.role()
returns text
language sql
stable
as $fn$
  select case
    when current_setting('app.password_expired', true) = 'on' then 'anon'
    else coalesce(
      nullif(current_setting('app.current_role', true), ''),
      case
        when nullif(current_setting('app.current_user_id', true), '') is null
          then 'anon'
        else 'authenticated'
      end
    )
  end;
$fn$;

-- ── 4. The one action that must still work ──────────────────────────────────
--
-- ⚠️ Also the one hole this opens. sr_auth.change_password takes the user id as
-- an argument and is SECURITY DEFINER, so before this it would change ANY
-- user's password for any caller who knew their id -- and a locked session is
-- exactly a caller with a reason to try. The real identity is
-- app.current_user_id (the flag hides it from sr_auth.uid(), but it is still
-- there), so the function can insist the target is the caller.
-- ⚠️ Order matters: the original body is copied to
-- sr_auth.change_password_unchecked FIRST, then change_password is replaced by a
-- wrapper that calls it. Doing it the other way round would copy the wrapper
-- into the unchecked function and produce infinite recursion.
do $$
declare
  body text;
  src  text;
begin
  -- Already done? The wrapper names the session variable; the original does
  -- not. That is the marker, so re-running changes nothing.
  select pg_get_functiondef(oid) into body
    from pg_proc
   where proname = 'change_password' and pronamespace = 'sr_auth'::regnamespace;

  -- ⚠️ Guarded, not asserted. sr_auth.change_password is not defined in
  -- 01_auth_and_session.sql or anywhere else in postgres/ -- it was added to
  -- the running database by hand, like the views postgres/23 and /32 build.
  -- So on the fresh database 02_schema.sql stands up it does not exist yet,
  -- and failing here would break the one file that has to work. The lock
  -- itself (sections 1-3) is already in place by this point; only the
  -- caller-owns-the-account check on a function that is not there yet is
  -- skipped.
  if body is null then
    raise notice 'sr_auth.change_password not present; skipping its guard';
    return;
  end if;
  if body like '%app.current_user_id%' then
    return;
  end if;

  -- Copy the CURRENT definition under the new name, renaming only the
  -- function itself. The policy check, the "must differ" rule and the bcrypt
  -- cost travel with it verbatim — retyping them is how two copies drift.
  src := replace(body,
                 'FUNCTION sr_auth.change_password(',
                 'FUNCTION sr_auth.change_password_unchecked(');
  if src = body then
    raise exception 'could not rename the body; definition shape changed';
  end if;
  execute src;

  execute 'revoke all on function sr_auth.change_password_unchecked(uuid, text) from public';

  -- Now the guarded front door.
  execute $ddl$
    create or replace function sr_auth.change_password(p_user_id uuid, p_password text)
    returns void
    language plpgsql
    security definer
    set search_path = sr_auth, public, extensions
    as $body$
    declare
      v_caller uuid;
    begin
      -- ⚠️ The caller's REAL id, read straight from the session variable
      -- rather than through sr_auth.uid() -- which is null precisely when this
      -- function is most needed, because the password has expired.
      v_caller := nullif(current_setting('app.current_user_id', true), '')::uuid;

      if v_caller is null or v_caller <> p_user_id then
        raise exception 'You may only change your own password.'
          using errcode = '42501';
      end if;

      perform sr_auth.change_password_unchecked(p_user_id, p_password);
    end;
    $body$;
  $ddl$;
end $$;

-- ── 5. Verification ─────────────────────────────────────────────────────────
do $$
declare
  v_uid uuid;
begin
  -- A fresh session with no flag set must behave exactly as before.
  perform set_config('app.current_user_id', '', false);
  perform set_config('app.password_expired', '', false);
  if sr_auth.uid() is not null then
    raise exception 'sr_auth.uid() must be null when signed out';
  end if;

  -- A normal session sees its id.
  perform set_config('app.current_user_id',
                     '11111111-1111-1111-1111-111111111111', false);
  perform set_config('app.password_expired', 'off', false);
  if sr_auth.uid() is null then
    raise exception 'sr_auth.uid() must return the id of a healthy session';
  end if;

  -- An expired one is, to every policy, nobody.
  perform set_config('app.password_expired', 'on', false);
  if sr_auth.uid() is not null then
    raise exception
      'an expired password must make sr_auth.uid() null, or the 132 RLS '
      'policies keep letting the session read';
  end if;

  -- ⚠️ And the OTHER root. Gating sr_auth.uid() alone left a locked session
  -- reading every package in the database, because those policies ask
  -- sr_auth.role() instead.
  perform set_config('app.current_role', 'authenticated', false);
  perform set_config('app.password_expired', 'on', false);
  if sr_auth.role() <> 'anon' then
    raise exception
      'an expired password must read as anon, or the 13 sr_auth.role() '
      'policies keep letting the session read';
  end if;

  perform set_config('app.password_expired', 'off', false);
  if sr_auth.role() <> 'authenticated' then
    raise exception 'a healthy session must keep its role';
  end if;

  -- Leave the session clean.
  perform set_config('app.current_user_id', '', false);
  perform set_config('app.current_role', '', false);
  perform set_config('app.password_expired', 'off', false);
end $$;


-- ==========================================================================
--  migrations/019_locked_session_can_read_its_own_profile.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- A locked session must still be able to read ITS OWN profile row.
--
-- ⚠️ Migration 018 locked an expired password out of everything by making
-- sr_auth.uid() null and sr_auth.role() 'anon'. That was too complete: the app
-- discovers that a password has expired by READING THE PROFILE
-- (ProfileModel.isPasswordExpired is computed from password_updated_at), and
-- the profile is exactly what 018 stopped it from reading.
--
-- The result was a dead end. finishOtpLogin signs in, then does
--
--   supabase.from('profiles').select().eq('id', user.id).single()
--
-- which came back with ZERO rows, so `.single()` threw and the login screen
-- showed "Sign in failed. Please try again." The officer never reached the
-- password-change dialog that 018 exists to force them into, and the code
-- they had just spent was gone. Verified against the live database: the
-- Disposal DC account returned 0 rows for its own id.
--
-- ⚠️ The fix is ONE row, not a relaxation. This policy matches a single
-- profile -- the caller's own -- and only while the session is flagged
-- expired. It is written against `app.current_user_id` rather than
-- sr_auth.uid(), because sr_auth.uid() is precisely what is null here; that is the
-- same reasoning that lets sr_auth.change_password keep working.
--
-- Everything else stays shut: other people's profiles, packages, warehouses,
-- tender sales. The session can see who it is and that its password has
-- expired, and it can change that password. Nothing more.
--
-- Safe to re-run.
-- ============================================================================

-- The caller's REAL id, regardless of the expiry flag.
--
-- ⚠️ Deliberately separate from sr_auth.uid(). sr_auth.uid() answers "who may act",
-- which is nobody while a password is expired; this answers "whose session is
-- this", which still has a truthful answer. Keeping them apart is what stops
-- a future edit from accidentally re-opening the lock by widening one of them.
create or replace function sr_auth.session_user_id()
returns uuid
language sql
stable
as $fn$
  select nullif(current_setting('app.current_user_id', true), '')::uuid;
$fn$;

comment on function sr_auth.session_user_id() is
  'The signed-in user id, even when the password has expired and sr_auth.uid() '
  'is therefore null. For the narrow set of things a locked session must '
  'still do: read its own profile, and change its own password.';

-- Only while locked, and only your own row.
--
-- ⚠️ Scoped with `password_expired = 'on'` so it adds nothing for a healthy
-- session -- those are already covered by "Users can view own profile". A
-- policy that applied always would be a second, parallel route to the same
-- row, and the day someone edits one they would not think to check the other.
drop policy if exists profiles_expired_self_read on public.profiles;
create policy profiles_expired_self_read on public.profiles
  for select
  using (
    current_setting('app.password_expired', true) = 'on'
    and id = sr_auth.session_user_id()
  );

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  v_id    uuid;
  v_seen  int;
  v_other int;
begin
  select id into v_id from public.profiles limit 1;
  if v_id is null then
    return;  -- empty database (a fresh server); nothing to assert against
  end if;

  -- Stand up a locked session for that user.
  perform set_config('app.current_user_id', v_id::text, false);
  perform set_config('app.current_role', 'authenticated', false);
  perform set_config('app.password_expired', 'on', false);

  -- The lock must still be in force.
  if sr_auth.uid() is not null or sr_auth.role() <> 'anon' then
    raise exception 'migration 018 is not in effect; apply it first';
  end if;

  -- ⚠️ These run as the table OWNER, which bypasses RLS, so they cannot
  -- prove the policy works -- only that the pieces it needs are right. The
  -- real check is the yard_app session in the migration header, which
  -- returned 1 own row and 0 of everything else.
  if sr_auth.session_user_id() <> v_id then
    raise exception
      'sr_auth.session_user_id() must survive the expiry flag, or a locked '
      'session cannot find out why it is locked';
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'profiles'
                    and policyname = 'profiles_expired_self_read') then
    raise exception 'profiles_expired_self_read was not created';
  end if;

  -- Leave the session clean.
  perform set_config('app.current_user_id', '', false);
  perform set_config('app.current_role', '', false);
  perform set_config('app.password_expired', 'off', false);
end $$;


-- ==========================================================================
--  migrations/020_password_max_length_is_practical.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- The password maximum becomes 24, from 128.
--
-- ⚠️ 128 was a ceiling on what the ALGORITHM can hash, not on what a person
-- can type. bcrypt stops at 72 bytes and the rule was set above even that, so
-- it could never fire: an officer would have had to enter 129 characters
-- correctly, twice, at a shared desk. A limit nobody can reach is not a
-- limit — it only made the requirement line read as noise beside the rules
-- that do matter.
--
-- 24 rather than 20 so a three-word passphrase still fits. Passphrases are
-- the easiest strong passwords to remember, and a 20-character cap quietly
-- rules them out while doing nothing for security.
--
-- ⚠️ Must move together with PasswordPolicy.maxLength in
-- lib/core/security_policy.dart. Those two numbers are the same rule written
-- twice; when they drift, the form promises what the server refuses — which
-- is exactly what the "Minimum 8 characters" hint was doing against this
-- function's 12.
--
-- ⚠️ No existing account is affected. Passwords are stored as bcrypt hashes
-- ($2a$), so their original length is unknowable and unchecked at sign-in —
-- this rule applies only when a NEW password is set. Nobody is locked out by
-- it; someone whose current password is longer than 24 simply cannot re-enter
-- that same one on their next rotation.
--
-- Safe to re-run.
-- ============================================================================

create or replace function public.password_policy_violation(p_password text)
returns text
language plpgsql
immutable
as $function$
begin
  if p_password is null or length(p_password) < 12 then
    return 'Password must be at least 12 characters.';
  end if;
  if length(p_password) > 24 then
    -- A practical ceiling, not bcrypt's. See the header: the old 128 sat
    -- above even bcrypt's 72-byte limit and could never be reached.
    return 'Password must be at most 24 characters.';
  end if;
  if p_password !~ '[A-Z]' then
    return 'Password must contain an uppercase letter.';
  end if;
  if p_password !~ '[a-z]' then
    return 'Password must contain a lowercase letter.';
  end if;
  if p_password !~ '[0-9]' then
    return 'Password must contain a number.';
  end if;
  if p_password !~ '[^A-Za-z0-9]' then
    return 'Password must contain a special character.';
  end if;
  -- The handful that a dictionary attack tries first. Not a substitute for a
  -- real breach list, but it costs nothing and stops the obvious ones.
  if lower(p_password) ~ '(password|passw0rd|welcome|customs|qwerty|admin123|letmein|12345678)' then
    return 'Password contains a commonly used word.';
  end if;
  return null;
end;
$function$;

-- ── Verification ────────────────────────────────────────────────────────────
do $$
begin
  -- The boundary itself is accepted.
  if public.password_policy_violation('Redwood#Harbor47x12345aA') is not null then
    raise exception '24 characters must be accepted, got: %',
      public.password_policy_violation('Redwood#Harbor47x12345aA');
  end if;

  -- One over is not.
  if public.password_policy_violation('Redwood#Harbor47x12345aAb') is null then
    raise exception '25 characters must be rejected';
  end if;

  -- And the message says which end was wrong, so the app can show the same
  -- thing the officer sees in the checklist.
  if public.password_policy_violation('Redwood#Harbor47x12345aAb')
       not like '%at most 24%' then
    raise exception 'the message must name the maximum';
  end if;

  -- The lower bound and the character classes are untouched.
  if public.password_policy_violation('Short1!') is null then
    raise exception 'the 12-character minimum was lost';
  end if;
  if public.password_policy_violation('alllowercase123!') is null then
    raise exception 'the uppercase rule was lost';
  end if;
  if public.password_policy_violation('Password1234!') is null then
    raise exception 'the common-word rule was lost';
  end if;
end $$;


-- ==========================================================================
--  migrations/012_rls_helpers_evaluated_once.sql (folded in)
-- ==========================================================================

-- ============================================================================
-- Every RLS policy here calls no-argument helpers — sr_auth.uid(), sr_auth.role(),
-- auth_user_yard(), auth_user_is_*() — and PostgreSQL was calling them ONCE
-- PER ROW. Each of those helpers runs `select ... from profiles`, so reading
-- 176 packages meant hundreds of profile lookups:
--
--   Seq Scan on packages (actual time=1.300..20.644 rows=176)
--     Filter: ((NOT auth_user_is_yard_staff()) OR (yard = auth_user_yard()))
--             AND ((yard = auth_user_yard()) OR auth_user_is_valuation()
--                  OR auth_user_is_executive() OR auth_user_is_disposal()
--                  OR auth_user_is_appeal() OR ...)
--     Buffers: shared hit=613
--
-- 613 buffer hits to count 176 rows, ~35ms per small query on localhost. The
-- app's heaviest page fetch (getAllPackages) took 639ms warm, and that is the
-- lag felt when moving between pages.
--
-- The fix is to wrap each no-argument call in a scalar subquery. `(select f())`
-- is hoisted into an InitPlan and evaluated ONCE per statement instead of once
-- per row. It is purely an evaluation-order change: the value is identical, so
-- no policy's meaning changes — which the verification at the bottom proves by
-- comparing visible rows for every role before and after.
--
-- Helpers that take an argument (warehouse_yard(warehouse_id)) genuinely vary
-- per row and are deliberately left alone.
--
-- Safe to re-run: it unwraps before it wraps, so it never nests.
-- ============================================================================

do $$
declare
  r record;
  q_old text;
  c_old text;
  q_new text;
  c_new text;
  stmt text;
  -- Unwrap: pg_get_expr renders a wrapped call as "( SELECT f() AS f)".
  unwrap_re constant text :=
    '\( SELECT (sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\) AS [a-z_]+\)';
  -- Wrap: only zero-argument calls, so warehouse_yard(warehouse_id) is safe.
  wrap_re constant text := '(sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\)';
begin
  for r in
    select c.relname                              as tbl,
           p.polname                              as pol,
           pg_get_expr(p.polqual, p.polrelid)     as qual,
           pg_get_expr(p.polwithcheck, p.polrelid) as wchk
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
  loop
    q_old := r.qual;
    c_old := r.wchk;

    q_new := q_old;
    if q_new is not null then
      q_new := regexp_replace(q_new, unwrap_re, '\1()', 'g');
      q_new := regexp_replace(q_new, wrap_re, '(select \1())', 'g');
    end if;

    c_new := c_old;
    if c_new is not null then
      c_new := regexp_replace(c_new, unwrap_re, '\1()', 'g');
      c_new := regexp_replace(c_new, wrap_re, '(select \1())', 'g');
    end if;

    -- Nothing to do unless a call actually moved.
    if q_new is not distinct from q_old and c_new is not distinct from c_old then
      continue;
    end if;

    -- USING and WITH CHECK must only be named when the policy already has
    -- them: an INSERT policy has no USING, and naming it is an error.
    stmt := format('alter policy %I on public.%I', r.pol, r.tbl);
    if q_new is not null then
      stmt := stmt || format(' using (%s)', q_new);
    end if;
    if c_new is not null then
      stmt := stmt || format(' with check (%s)', c_new);
    end if;

    execute stmt;
  end loop;
end $$;

-- ── Verification ────────────────────────────────────────────────────────────
-- Every no-argument helper must now be hoisted, on every policy.
do $$
declare
  bad text;
begin
  select string_agg(c.relname || '.' || p.polname, ', ') into bad
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and (
       -- a bare call is one NOT preceded by "SELECT "
       coalesce(pg_get_expr(p.polqual, p.polrelid), '')
         ~ '(?<!SELECT )(sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\)'
       or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
         ~ '(?<!SELECT )(sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\)'
     );

  if bad is not null then
    raise exception 'these policies still call a helper per row: %', bad;
  end if;
end $$;

