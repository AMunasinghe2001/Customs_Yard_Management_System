
-- Update warehouse_entries to support individual items and zones
ALTER TABLE warehouse_entries ADD COLUMN package_item_id UUID REFERENCES package_items(id) ON DELETE CASCADE;
ALTER TABLE warehouse_entries ADD COLUMN zone TEXT;

-- Migration: If there are existing entries, they might not be linked to specific items.
-- We keep them linked to the package overall, which is fine for backward compatibility.
