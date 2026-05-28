-- ================================================================
-- Forfeited Packages & Tenders Management
-- ================================================================

-- ────────────────────────────────────────────────────────────────
-- FORFEITED_PACKAGES Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE forfeited_packages (
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

CREATE INDEX idx_forfeited_packages_package_id ON forfeited_packages(package_id);
CREATE INDEX idx_forfeited_packages_appeal_deadline ON forfeited_packages(appeal_deadline);

-- ────────────────────────────────────────────────────────────────
-- TENDERS Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE tenders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tender_number TEXT NOT NULL UNIQUE,
  tender_date TIMESTAMPTZ NOT NULL,
  forfeited_package_ids TEXT[] NOT NULL, -- JSON array of package IDs
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tenders_tender_date ON tenders(tender_date);
CREATE INDEX idx_tenders_created_by ON tenders(created_by);

-- ────────────────────────────────────────────────────────────────
-- TENDER_DISPOSALS Table
-- ────────────────────────────────────────────────────────────────
CREATE TABLE tender_disposals (
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

CREATE INDEX idx_tender_disposals_tender_package_id ON tender_disposals(tender_package_id);
CREATE INDEX idx_tender_disposals_forfeited_package_id ON tender_disposals(forfeited_package_id);

-- ────────────────────────────────────────────────────────────────
-- ENABLE RLS
-- ────────────────────────────────────────────────────────────────
ALTER TABLE forfeited_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenders ENABLE ROW LEVEL SECURITY;
ALTER TABLE tender_disposals ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "All authenticated users can view forfeited packages" ON forfeited_packages
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage forfeited packages" ON forfeited_packages
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "All authenticated users can view tenders" ON tenders
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can create and manage tenders" ON tenders
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "All authenticated users can view tender disposals" ON tender_disposals
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage tender disposals" ON tender_disposals
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- ────────────────────────────────────────────────────────────────
-- TRIGGERS
-- ────────────────────────────────────────────────────────────────
CREATE TRIGGER update_forfeited_packages_updated_at BEFORE UPDATE ON forfeited_packages
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tenders_updated_at BEFORE UPDATE ON tenders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tender_disposals_updated_at BEFORE UPDATE ON tender_disposals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
