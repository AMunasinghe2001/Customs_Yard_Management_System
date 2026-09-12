-- ================================================================
-- Sri Lanka Customs Yard Management System - Supabase Schema
-- Run this in Supabase SQL Editor
-- ================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------
-- PROFILES (Officers & Admins linked to Supabase Auth)
-- ----------------------------------------------------------------
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
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
CREATE TABLE warehouses (
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
  ('SR Warehouse 03', 'SR-W03', 'SR Unit Tertiary Warehouse', 'SR Unit, Colombo Port');

-- ----------------------------------------------------------------
-- PACKAGES (Incoming international packages)
-- ----------------------------------------------------------------
CREATE TABLE packages (
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
CREATE TABLE package_items (
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
CREATE TABLE warehouse_entries (
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
CREATE TABLE customs_rules (
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
  ('Maximum Item Count', 'max_items', 50, 'Packages with more than 50 items must be held');

INSERT INTO customs_rules (rule_name, rule_type, string_value, description) VALUES
  ('Prohibited: Firearms', 'prohibited_category', 'firearms', 'Firearms and related accessories are prohibited'),
  ('Prohibited: Narcotics', 'prohibited_category', 'narcotics', 'All narcotics and illegal drugs are prohibited'),
  ('Prohibited: Explosives', 'prohibited_category', 'explosives', 'Explosives and related items are prohibited');

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
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Admins can manage all profiles" ON profiles
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Packages - all officers can view and create
CREATE POLICY "Officers can view all packages" ON packages
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Officers can create packages" ON packages
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Officers can update packages" ON packages
  FOR UPDATE USING (auth.role() = 'authenticated');

-- Package items - linked to packages
CREATE POLICY "Officers can manage package items" ON package_items
  FOR ALL USING (auth.role() = 'authenticated');

-- Warehouses - read for all, write for admins
CREATE POLICY "All can view warehouses" ON warehouses
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage warehouses" ON warehouses
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Warehouse entries - all officers
CREATE POLICY "Officers can manage warehouse entries" ON warehouse_entries
  FOR ALL USING (auth.role() = 'authenticated');

-- Customs rules - read for all, write for admins
CREATE POLICY "All can view customs rules" ON customs_rules
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage customs rules" ON customs_rules
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
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

CREATE TRIGGER update_packages_updated_at BEFORE UPDATE ON packages
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_warehouse_entries_updated_at BEFORE UPDATE ON warehouse_entries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

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

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
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

ALTER TABLE warehouse_entries ADD COLUMN zone TEXT;

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
