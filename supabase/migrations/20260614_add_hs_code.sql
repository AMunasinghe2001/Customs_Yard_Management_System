-- Per-item HS (Harmonised System) code for package items.
-- Sits alongside the existing unit_value column so each item carries both
-- its HS classification code and its declared value.
ALTER TABLE package_items
  ADD COLUMN IF NOT EXISTS hs_code TEXT;
