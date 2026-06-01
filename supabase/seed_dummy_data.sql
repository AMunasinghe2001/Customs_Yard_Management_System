-- Seed dummy data for Forfeited Packages & Tenders
-- Run this in the Supabase SQL Editor

-- 0. Fix the status constraint to allow 'forfeited'
-- This ensures 'forfeited' is a valid status in the packages table
ALTER TABLE packages DROP CONSTRAINT IF EXISTS packages_status_check;
ALTER TABLE packages ADD CONSTRAINT packages_status_check 
CHECK (status IN ('pending', 'inspecting', 'held', 'detained', 'cleared', 'confiscated', 'returned', 'forfeited'));

-- 1. Create Dummy Packages
INSERT INTO packages (id, sr_number, case_number, consignee_name, origin_country, status, entry_date)
VALUES 
  (uuid_generate_v4(), 'SR/2026/1001', 'C/2026/01', 'Kamal Perera', 'China', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1002', 'C/2026/02', 'Sunil Silva', 'India', 'forfeited', NOW() - INTERVAL '35 days'),
  (uuid_generate_v4(), 'SR/2026/1003', 'C/2026/03', 'Nimal Fonseka', 'Dubai', 'forfeited', NOW() - INTERVAL '40 days'),
  (uuid_generate_v4(), 'SR/2026/1004', 'C/2026/04', 'Aruni Jayawardena', 'Singapore', 'forfeited', NOW() - INTERVAL '50 days'),
  (uuid_generate_v4(), 'SR/2026/1005', 'C/2026/05', 'Priyantha Bandara', 'Japan', 'forfeited', NOW() - INTERVAL '60 days'),
  (uuid_generate_v4(), 'SR/2026/1006', 'C/2026/06', 'Dhammika Siriwardena', 'China', 'forfeited', NOW() - INTERVAL '32 days'),
  (uuid_generate_v4(), 'SR/2026/1007', 'C/2026/07', 'Roshan Ranasinghe', 'India', 'forfeited', NOW() - INTERVAL '10 days'),
  (uuid_generate_v4(), 'SR/2026/1008', 'C/2026/08', 'Gihan Wickramasinghe', 'Dubai', 'forfeited', NOW() - INTERVAL '5 days'),
  (uuid_generate_v4(), 'SR/2026/1009', 'C/2026/09', 'Anura Kumara', 'Singapore', 'forfeited', NOW() - INTERVAL '15 days'),
  (uuid_generate_v4(), 'SR/2026/1010', 'C/2026/10', 'Susil Premajayantha', 'Japan', 'forfeited', NOW() - INTERVAL '20 days'),
  (uuid_generate_v4(), 'SR/2026/1011', 'C/2026/11', 'Main Consignee 11', 'China', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1012', 'C/2026/12', 'Main Consignee 12', 'India', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1013', 'C/2026/13', 'Main Consignee 13', 'Dubai', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1014', 'C/2026/14', 'Main Consignee 14', 'Singapore', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1015', 'C/2026/15', 'Main Consignee 15', 'Japan', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1016', 'C/2026/16', 'Main Consignee 16', 'China', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1017', 'C/2026/17', 'Main Consignee 17', 'India', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1018', 'C/2026/18', 'Main Consignee 18', 'Dubai', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1019', 'C/2026/19', 'Main Consignee 19', 'Singapore', 'forfeited', NOW() - INTERVAL '45 days'),
  (uuid_generate_v4(), 'SR/2026/1020', 'C/2026/20', 'Main Consignee 20', 'Japan', 'forfeited', NOW() - INTERVAL '45 days');

-- 2. Create Forfeited Packages
INSERT INTO forfeited_packages (id, package_id, sr_number, consignee_name, forfeited_at, appeal_deadline, reason)
SELECT 
  uuid_generate_v4(), 
  id, 
  sr_number, 
  consignee_name, 
  entry_date, 
  entry_date + INTERVAL '30 days', 
  'Statutory forfeiture after storage period'
FROM packages;

-- 3. Create a few Tenders for some of the expired packages
WITH expired_pkgs AS (
  SELECT id FROM forfeited_packages WHERE appeal_deadline < NOW() LIMIT 5
)
INSERT INTO tenders (id, tender_number, tender_date, forfeited_package_ids, created_by)
VALUES (
  uuid_generate_v4(), 
  'TDR/2026/001', 
  NOW(), 
  (SELECT array_agg(id::text) FROM expired_pkgs), 
  NULL -- Leaving NULL to avoid FK issues with profiles
);

-- 4. Record some Disposals
WITH tender_data AS (
  SELECT id, forfeited_package_ids FROM tenders LIMIT 1
)
INSERT INTO tender_disposals (tender_package_id, forfeited_package_id, disposal_type, receipt_number, disposed_by, disposed_at)
SELECT 
  (SELECT id::text FROM tender_data), 
  (SELECT (forfeited_package_ids)[1]::uuid FROM tender_data), 
  'sold', 
  'R-556677', 
  NULL, -- Leaving NULL to avoid FK issues with profiles
  NOW();

INSERT INTO tender_disposals (tender_package_id, forfeited_package_id, disposal_type, other_details, disposed_by, disposed_at)
SELECT 
  (SELECT id::text FROM tender_data), 
  (SELECT (forfeited_package_ids)[2]::uuid FROM tender_data), 
  'govt_use', 
  'Transferred to Customs HQ', 
  NULL, -- Leaving NULL to avoid FK issues with profiles
  NOW();

