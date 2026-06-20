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
