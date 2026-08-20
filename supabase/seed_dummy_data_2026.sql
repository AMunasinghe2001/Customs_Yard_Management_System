-- ============================================================================
--  DUMMY DATA SEED — full SR register for testing
--
--  STEP 1 wipes ALL package data, STEP 2 inserts 41 realistic SRs, STEP 3
--  parks SR 05-35's expired forfeits mid-pipeline, STEP 4 runs SR 36-41 all
--  the way to SOLD / DESTROYED.
--  Officers / profiles / warehouses / storage rates / admin config are KEPT.
--
--  ⚠️ RUN THE WHOLE FILE ONCE. Running only STEP 2/3, or running the file
--     twice without STEP 1, duplicates every row (that is what produced the
--     45 forfeited rows instead of 19, with SR/20 items listed twice).
--
--  Coverage (every SR-form field is filled — nothing left null that the form
--  would normally capture):
--    * 41 SR numbers, entry dates spread over Nov 2025 – Feb 2026
--    * 8 packages carry MULTIPLE items (2–4 each); the rest are single-item
--    * Old Entries    → 4 packages with old_sr_number set
--    * Released       → 3 packages with [FINAL:RELEASED] warehouse entries
--    * Abandoned      → 3 packages with Abandoned items / [ABANDONED] entries
--    * Other          → 3 packages — COURT CASES ([FINAL:OTHER] — court order)
--    * Forfeited      → 16 SR numbers producing 24 ROWS, because forfeiture is
--                       recorded PER ITEM: a multi-item package makes one row
--                       per item, all repeating the SAME SR number (which is
--                       exactly what the Forfeited Packages table lists).
--        - 13 SRs / 18 rows with the appeal window CLOSED → "Appeal Expired"
--        -  3 SRs /  6 rows with the appeal window OPEN   → "In Appeal"
--        - SRs appearing on several rows: 05 (×3), 20 (×4), 25 (×2), 28 (×3)
--    * STEP 3 parks the EXPIRED forfeits MID-PIPELINE. Nothing is finished,
--      so **Sold Packages and Destroyed Packages stay EMPTY** and every
--      earlier stage has real work waiting in it:
--        Pending Valuation  SR 05+23 (12 days ago) | SR 31+34 (4 days ago)
--        Disposal Requests  SR 24 (75 days ago)    | SR 29 (26 days ago)
--        Unsold Tenders     SR 20 x1 | SR 33 x2 | SR 26 x3 | SR 27 x2 rounds
--        Tender Committees  SR 32 x4 rounds (tenderCount >= 4)
--        Undestroyed        SR 12
--        Forfeited UNTOUCHED SR 35 (30 days up, nothing started)
--      Each tender ROUND is its own tender_sales row on its own day, so the
--      yard's Tender Sale page lists 12 sales spread Apr-Aug 2026 rather than
--      one. Every round is UNSOLD (sold = false, deadline passed).
--      The goods never leave the yard: no [FINAL:...] entry, the held
--      warehouse entry is kept, item status stays 'Forfeit'.
--    * STEP 4 COMPLETES six more packages, so Sold / Destroyed have data.
--      Each finishes on its LAST round; earlier rounds stay recorded as
--      unsold/undestroyed attempts, so the yard's Tender Sale page shows the
--      whole history (old rounds Unsold, final round Sold):
--        SOLD       SR 36 x1 round | SR 40 x2 rounds | SR 37 x4 rounds
--        DESTROYED  SR 38 x1 round | SR 41 x2 rounds | SR 39 x3 rounds
--      The final round writes what the real RPCs write: a [FINAL:SOLD] /
--      [FINAL:DESTROYED] returned entry, status sold/destroyed, and the held
--      entry deleted. SR 37 and 39 are multi-item, so those tables show
--      several lines under one SR.
--    * Still held     → the remainder sit in warehouses as Detain
--
--  Yard: GL1 (Grey Line 1). SR format: GL1/SR/nn/YYYY.
--
--  Run in: Supabase Dashboard → SQL Editor.
--  ⚠️ Take a backup first if you need the current data — STEP 1 is destructive.
-- ============================================================================

-- ── STEP 0: PRE-FLIGHT ───────────────────────────────────────────────────────
-- Fail fast with a clear message if a migration is missing, rather than dying
-- half-way through the insert with a cryptic "column does not exist".
DO $$
DECLARE missing text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='packages' AND column_name='old_sr_number')
  THEN missing := missing || ' packages.old_sr_number (20260714_old_sr_number.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='packages' AND column_name='yard')
  THEN missing := missing || ' packages.yard (001_multi_yard.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='warehouse_entries' AND column_name='package_item_id')
  THEN missing := missing || ' warehouse_entries.package_item_id (20260327_split_items_to_warehouses.sql)'; END IF;

  -- STEP 3 (sold / destroyed) needs these:
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tender_sale_items' AND column_name='package_item_id')
  THEN missing := missing || ' tender_sale_items.package_item_id (20260622_tender_sale_item_per_item.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tender_sale_items' AND column_name='sold_price')
  THEN missing := missing || ' tender_sale_items.sold_price (20260611_tender_sale_sold_price.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='destruction_items' AND column_name='package_item_id')
  THEN missing := missing || ' destruction_items.package_item_id (20260625_destruction_per_di_item.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='disposal_request_items' AND column_name='valuation_cost')
  THEN missing := missing || ' disposal_request_items.valuation_cost (20260617_valuation_directorate.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='disposal_request_items' AND column_name='forwarded')
  THEN missing := missing || ' disposal_request_items.forwarded (20260717_valuation_per_item_forward.sql)'; END IF;

  IF missing <> '' THEN
    RAISE EXCEPTION 'Missing schema — run these migrations first:%', missing;
  END IF;
END $$;

-- ── STEP 1: CLEAR ────────────────────────────────────────────────────────────
-- Child-first so foreign keys never block. Wrapped in a DO block so tables that
-- do not exist in an older database are skipped instead of aborting the script.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'tender_committees', 'tender_revaluations', 'tender_bids',
    'destruction_items', 'destructions',
    'tender_sale_items', 'tender_sales',
    'disposal_request_items', 'disposal_requests',
    'tender_disposals', 'tenders',
    'forfeited_packages', 'warehouse_entries', 'package_items', 'packages',
    'audit_logs'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = t) THEN
      EXECUTE format('DELETE FROM public.%I;', t);
      RAISE NOTICE 'cleared %', t;
    END IF;
  END LOOP;
END $$;

-- ── STEP 2: SEED ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_yard  text := 'GL1';
  wh1     uuid;
  wh2     uuid;
  wh3     uuid;
  v_off   uuid;   -- officer to attribute entries to (may be NULL)

  r       record;
  it      record;
  v_pkg   uuid;
  v_item  uuid;
  v_first uuid;   -- first item of the package (for package-level actions)
  v_entry uuid;
  v_qty   int;
  v_total int;
  v_idx   int;
  v_forf_at timestamptz;  -- when the item was forfeited (drives the 30-day window)
BEGIN
  SELECT id INTO wh1 FROM public.warehouses ORDER BY code LIMIT 1;
  SELECT id INTO wh2 FROM public.warehouses ORDER BY code OFFSET 1 LIMIT 1;
  SELECT id INTO wh3 FROM public.warehouses ORDER BY code OFFSET 2 LIMIT 1;
  IF wh1 IS NULL THEN
    RAISE EXCEPTION 'No warehouses found — seed the warehouses table first.';
  END IF;
  wh2 := COALESCE(wh2, wh1);
  wh3 := COALESCE(wh3, wh1);

  -- Any officer/admin of this yard; NULL is acceptable (columns are nullable).
  SELECT id INTO v_off FROM public.profiles
   WHERE yard = v_yard AND role IN ('officer', 'admin')
   ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN
    SELECT id INTO v_off FROM public.profiles ORDER BY created_at LIMIT 1;
  END IF;

  -- ══════════════════════════════════════════════════════════════════════════
  --  Package master list.
  --  outcome: held | released | abandoned | other | forfeit
  --  old_sr : non-null → shows on the Old Entries page
  -- ══════════════════════════════════════════════════════════════════════════
  FOR r IN
    SELECT * FROM (VALUES
      -- sr_no, entry_date,      origin,      consignee, nic, phone, address,
      -- declarant, cusdec_no, cusdec_date, case_no, container, descr, weight,
      -- reason, notes, outcome, old_sr
      (1 , DATE '2025-11-04', 'China',     'Silva Traders (Pvt) Ltd',      '199012345678', '0771234567', 'No 45, Sea Street, Colombo 11',
       'Lanka Clearing Agency',      'CUSDEC/2025/8801', '2025-11-03', 'GL1/CASE/2025/301', 'MSKU7841203', 'Assorted household electrical goods', 420.500,
       'Undervalued declaration — held for verification', 'Consignee notified by phone on arrival.', 'held', NULL),

      (2 , DATE '2025-11-09', 'India',     'Ceylon Auto Imports',          '198523456789', '0712345678', 'No 12, Galle Road, Panadura',
       'Trans Asia Logistics',       'CUSDEC/2025/8834', '2025-11-08', 'GL1/CASE/2025/302', 'TGHU4592017', 'Vehicle spare parts consignment', 1250.000,
       'Pending SLSI conformity certificate', 'Bulk consignment, 3 item lines.', 'released', NULL),

      (3 , DATE '2025-11-15', 'Dubai',     'Nimal Enterprises',            '197734567890', '0763456789', 'No 8, Main Street, Negombo',
       'Swift Cargo Services',       'CUSDEC/2025/8877', '2025-11-14', 'GL1/CASE/2025/303', 'CSQU3054383', 'Textile rolls and garment accessories', 780.250,
       'Import licence not produced', 'Awaiting licence from Dept of Commerce.', 'held', 'SR/2019/0442'),

      (4 , DATE '2025-11-21', 'Singapore', 'Global Tech Lanka',            '199145678901', '0774567890', 'No 220, Kandy Road, Kadawatha',
       'Prime Freight (Pvt) Ltd',    'CUSDEC/2025/8912', '2025-11-20', 'GL1/CASE/2025/304', 'OOLU8123456', 'Computer peripherals and accessories', 310.750,
       'Classification dispute — HS code under review', 'Sample drawn for valuation.', 'abandoned', NULL),

      (5 , DATE '2025-11-28', 'Japan',     'Rathnayake Motors',            '196856789012', '0715678901', 'No 77, Station Road, Gampaha',
       'Ocean Link Clearing',        'CUSDEC/2025/8945', '2025-11-27', 'GL1/CASE/2025/305', 'NYKU5567891', 'Used motorcycle engine parts', 950.000,
       'Suspected undeclared quantity', 'Physical count differs from manifest.', 'forfeit', NULL),

      (6 , DATE '2025-12-03', 'China',     'Kandy Electricals',            '198967890123', '0726789012', 'No 15, Peradeniya Road, Kandy',
       'Highland Cargo Agents',      'CUSDEC/2025/9001', '2025-12-02', 'GL1/CASE/2025/306', 'HLXU3345678', 'Ceiling fans and electrical fittings', 640.400,
       'Pending NNRA clearance', 'Radiation check requested.', 'held', NULL),

      (7 , DATE '2025-12-08', 'Malaysia',  'Win Commodities (Pvt) Ltd',    '199278901234', '0777890123', 'No 3, Fourth Cross Street, Colombo 11',
       'Unity Shipping Lanka',       'CUSDEC/2025/9038', '2025-12-07', 'GL1/CASE/2025/307', 'TCLU9911223', 'PET bottles and plastic containers', 520.000,
       'Case filed — Magistrate Court Colombo 45821/2025', 'Goods produced before court; awaiting order.', 'other', NULL),

      (8 , DATE '2025-12-12', 'Thailand',  'Southern Food Imports',        '197589012345', '0718901234', 'No 91, Matara Road, Galle',
       'Ruhunu Clearing House',      'CUSDEC/2025/9074', '2025-12-11', 'GL1/CASE/2025/308', 'MAEU1122334', 'Packaged food items and beverages', 880.600,
       'Pending Food Authority certificate', 'Perishable — expedite.', 'released', 'SR/2020/1187'),

      (9 , DATE '2025-12-18', 'India',     'Jaffna Hardware Stores',       '198690123456', '0769012345', 'No 5, Hospital Road, Jaffna',
       'Northern Freight Agency',    'CUSDEC/2025/9110', '2025-12-17', 'GL1/CASE/2025/309', 'GESU6677889', 'Hand tools and hardware items', 1100.300,
       'Duty short-levied — held pending payment', 'Consignee agreed to pay difference.', 'held', NULL),

      (10, DATE '2025-12-24', 'China',     'Metro Distributors',           '199301234567', '0720123456', 'No 108, Nawala Road, Nugegoda',
       'Metro Clearing Services',    'CUSDEC/2025/9146', '2025-12-23', 'GL1/CASE/2025/310', 'CMAU4455667', 'Toys and stationery items', 295.900,
       'Trademark verification pending', 'Brand owner notified.', 'abandoned', NULL),

      (11, DATE '2026-01-06', 'Vietnam',   'Lanka Furniture Mart',         '198412345098', '0711234509', 'No 62, Horana Road, Piliyandala',
       'Delta Logistics Lanka',      'CUSDEC/2026/1002', '2026-01-05', 'GL1/CASE/2026/401', 'SEGU7788990', 'Wooden furniture components', 1680.000,
       'Fumigation certificate not produced', 'Quarantine inspection scheduled.', 'held', NULL),

      (12, DATE '2026-01-09', 'Dubai',     'Al Falah Trading',             '197923456109', '0772345610', 'No 30, Dam Street, Colombo 12',
       'Gulf Line Clearing',         'CUSDEC/2026/1039', '2026-01-08', 'GL1/CASE/2026/402', 'APZU1234509', 'Perfumery and cosmetic products', 210.150,
       'Suspected counterfeit branding', 'Samples sent to brand agent.', 'forfeit', NULL),

      (13, DATE '2026-01-14', 'China',     'Ceylon Sports Goods',          '199034567210', '0763456721', 'No 19, Baseline Road, Colombo 09',
       'Island Cargo Movers',        'CUSDEC/2026/1075', '2026-01-13', 'GL1/CASE/2026/403', 'FCIU5566778', 'Sports equipment and gym accessories', 730.800,
       'Valuation under review', 'Comparable prices requested.', 'released', NULL),

      (14, DATE '2026-01-19', 'Korea',     'Auto Lanka Spares',            '198845678321', '0714567832', 'No 250, Colombo Road, Kurunegala',
       'Wayamba Clearing Agents',    'CUSDEC/2026/1111', '2026-01-18', 'GL1/CASE/2026/404', 'HDMU8899001', 'Automotive filters and belts', 540.250,
       'Pending import control licence', 'Licence applied for by importer.', 'held', 'SR/2021/0765'),

      (15, DATE '2026-01-23', 'Indonesia', 'Green Leaf Exporters',         '197756789432', '0765678943', 'No 41, Temple Road, Matale',
       'Central Cargo Lanka',        'CUSDEC/2026/1148', '2026-01-22', 'GL1/CASE/2026/405', 'TRLU2233445', 'Agricultural machinery parts', 1420.700,
       'Case filed — Magistrate Court Colombo 46114/2026', 'Detained on court order pending inquiry.', 'other', NULL),

      (16, DATE '2026-01-28', 'India',     'Lanka Pharma Supplies',        '199167890543', '0776789054', 'No 88, Sri Sangaraja Mawatha, Colombo 10',
       'Medi Freight Services',      'CUSDEC/2026/1184', '2026-01-27', 'GL1/CASE/2026/406', 'MRKU3344556', 'Medical consumables and devices', 180.400,
       'NMRA registration pending', 'Cold chain not required.', 'held', NULL),

      (17, DATE '2026-02-03', 'China',     'Star Lighting Lanka',          '198678901654', '0716789065', 'No 7, Hill Street, Dehiwala',
       'Star Clearing Agency',       'CUSDEC/2026/1220', '2026-02-02', 'GL1/CASE/2026/407', 'BMOU7766554', 'LED lighting fixtures and drivers', 385.600,
       'Energy efficiency certificate pending', 'SLSI sample submitted.', 'abandoned', NULL),

      (18, DATE '2026-02-07', 'Taiwan',    'Precision Tools Lanka',        '199289012765', '0729890176', 'No 134, Negombo Road, Wattala',
       'Pacific Cargo Lanka',        'CUSDEC/2026/1257', '2026-02-06', 'GL1/CASE/2026/408', 'SUDU9900112', 'Precision measuring instruments', 260.900,
       'End-use declaration required', 'Dual-use goods verification.', 'held', NULL),

      (19, DATE '2026-02-12', 'Bangladesh','Fashion Point Lanka',          '197890123876', '0778901287', 'No 22, Galle Road, Mount Lavinia',
       'Trend Clearing Services',    'CUSDEC/2026/1293', '2026-02-11', 'GL1/CASE/2026/409', 'OOCL4433221', 'Ready-made garments assortment', 610.350,
       'Case filed — Magistrate Court Colombo 46390/2026', 'Court ordered confiscation; order received.', 'other', 'SR/2022/0318'),

      (20, DATE '2026-02-17', 'Singapore', 'Ocean Marine Supplies',        '198501234987', '0710123498', 'No 60, Marine Drive, Colombo 03',
       'Harbour Clearing Lanka',     'CUSDEC/2026/1330', '2026-02-16', 'GL1/CASE/2026/410', 'PONU6655443', 'Marine safety equipment', 890.100,
       'Pending Merchant Shipping approval', 'Certificates requested.', 'forfeit', NULL),

      (21, DATE '2026-02-21', 'China',     'Value Mart Lanka',             '199312345098', '0723456109', 'No 5, High Level Road, Maharagama',
       'Value Clearing Agents',      'CUSDEC/2026/1366', '2026-02-20', 'GL1/CASE/2026/411', 'CAIU1199887', 'General merchandise assortment', 1050.500,
       'Mixed consignment — itemised check', 'Multiple item lines declared.', 'released', NULL),

      (22, DATE '2026-02-25', 'India',     'Hill Country Traders',         '198723456210', '0767654321', 'No 3, Badulla Road, Bandarawela',
       'Uva Clearing Services',      'CUSDEC/2026/1402', '2026-02-24', 'GL1/CASE/2026/412', 'TEMU5544332', 'Tea packing materials and machinery', 1320.250,
       'Pending Tea Board endorsement', 'Machinery spares included.', 'held', NULL),

      -- ── Extra forfeits: APPEAL WINDOW ALREADY CLOSED ──────────────────────
      (23, DATE '2025-11-12', 'China',     'Capital Imports Lanka',        '198334567123', '0701234567', 'No 210, Old Moor Street, Colombo 12',
       'Capital Clearing Agents',    'CUSDEC/2025/8859', '2025-11-11', 'GL1/CASE/2025/313', 'DFSU2211334', 'Assorted mobile phone accessories', 145.800,
       'Undeclared branded goods', 'Seized after examination.', 'forfeit', NULL),

      (24, DATE '2025-12-15', 'Dubai',     'Orient Traders (Pvt) Ltd',     '197645678234', '0702345678', 'No 56, Keyzer Street, Colombo 11',
       'Orient Cargo Lanka',         'CUSDEC/2025/9092', '2025-12-14', 'GL1/CASE/2025/314', 'ECMU3322445', 'Wrist watches and fashion jewellery', 62.400,
       'Counterfeit trademark goods', 'Brand agent confirmed counterfeit.', 'forfeit', NULL),

      -- ── Forfeits with the 30-DAY APPEAL WINDOW STILL OPEN (6 SRs) ─────────
      -- forfeited_at = recent, so appeal_deadline = forfeited_at + 30 days is
      -- still in the future → these show as "In Appeal" on the Forfeited page.
      (25, DATE '2026-02-02', 'India',     'Nova Impex Lanka',             '199456789345', '0703456789', 'No 18, Layards Broadway, Colombo 14',
       'Nova Clearing Services',     'CUSDEC/2026/1210', '2026-02-01', 'GL1/CASE/2026/413', 'HASU4433556', 'Stainless steel kitchenware', 470.600,
       'Misdeclaration of goods description', 'Notice of forfeiture issued.', 'forfeit_open', NULL),

      (26, DATE '2026-02-06', 'China',     'Bright Future Trading',        '198867890456', '0704567890', 'No 92, Panchikawatte Road, Colombo 10',
       'Bright Clearing Lanka',      'CUSDEC/2026/1246', '2026-02-05', 'GL1/CASE/2026/414', 'KKFU5544667', 'Power tools and accessories', 355.200,
       'Undervaluation confirmed on inquiry', 'Appeal period over; unsold twice at tender.', 'forfeit', NULL),

      (27, DATE '2026-02-10', 'Malaysia',  'Sunrise Distributors',         '197978901567', '0705678901', 'No 34, Grandpass Road, Colombo 14',
       'Sunrise Freight Lanka',      'CUSDEC/2026/1282', '2026-02-09', 'GL1/CASE/2026/415', 'SEKU6655778', 'Household cleaning chemicals', 690.750,
       'Restricted chemicals without permit', 'Appeal period over; awaiting disposal.', 'forfeit', NULL),

      (28, DATE '2026-02-14', 'Thailand',  'Palm Grove Enterprises',       '199589012678', '0706789012', 'No 71, Aluthmawatha Road, Colombo 15',
       'Palm Clearing Agency',       'CUSDEC/2026/1318', '2026-02-13', 'GL1/CASE/2026/416', 'TGBU7766889', 'Rubber and latex based products', 820.300,
       'Import ban violation', 'Consignee informed of appeal rights.', 'forfeit_open', NULL),

      (29, DATE '2026-02-19', 'Singapore', 'Trident Marine Lanka',         '198690123789', '0707890123', 'No 6, Bristol Street, Colombo 01',
       'Trident Clearing Lanka',     'CUSDEC/2026/1354', '2026-02-18', 'GL1/CASE/2026/417', 'MSMU8877990', 'Navigation and radio equipment', 240.450,
       'TRC approval not produced', 'Appeal period over; valuation requested.', 'forfeit', NULL),

      (30, DATE '2026-02-23', 'Korea',     'Summit Auto Lanka',            '199201234890', '0708901234', 'No 145, Kandy Road, Kiribathgoda',
       'Summit Cargo Services',      'CUSDEC/2026/1390', '2026-02-22', 'GL1/CASE/2026/418', 'CBHU9988001', 'Used vehicle body panels', 1580.900,
       'Prohibited used parts import', 'Within the 30-day appeal window.', 'forfeit_open', NULL),

      -- ── More EXPIRED forfeits, so every disposal stage gets its own SR ────
      (31, DATE '2025-11-06', 'China',     'Eastern Traders Lanka',        '198445678901', '0709012345', 'No 25, Bankshall Street, Colombo 11',
       'Eastern Clearing Lanka',     'CUSDEC/2025/8815', '2025-11-05', 'GL1/CASE/2025/319', 'TCNU1234098', 'Ceramic floor tiles, assorted', 2100.500,
       'Undervalued declaration confirmed', 'Forfeited after inquiry.', 'forfeit', NULL),

      (32, DATE '2025-11-19', 'India',     'Lanka Steel Mart',             '197756789012', '0700123456', 'No 140, Sri Sangaraja Mw, Colombo 10',
       'Steel Line Clearing',        'CUSDEC/2025/8890', '2025-11-18', 'GL1/CASE/2025/320', 'GLDU2345109', 'Steel reinforcement mesh sheets', 3400.000,
       'Import licence not produced', 'Repeatedly unsold at tender.', 'forfeit', NULL),

      (33, DATE '2025-12-02', 'Dubai',     'Royal Gems & Metals',          '199067890123', '0701234560', 'No 8, Chatham Street, Colombo 01',
       'Royal Clearing Agents',      'CUSDEC/2025/8998', '2025-12-01', 'GL1/CASE/2025/321', 'BEAU3456210', 'Costume jewellery and fittings', 85.750,
       'Suspected counterfeit hallmarks', 'Awaiting disposal decision.', 'forfeit', NULL),

      (34, DATE '2025-12-20', 'Thailand',  'Tropical Foods Lanka',         '198578901234', '0702345601', 'No 55, Hill Street, Kandy',
       'Tropical Clearing House',    'CUSDEC/2025/9128', '2025-12-19', 'GL1/CASE/2025/322', 'IPXU4567321', 'Canned seafood and preserves', 1180.400,
       'Expired shelf life on arrival', 'Recommended for destruction.', 'forfeit', NULL),

      (35, DATE '2026-01-16', 'Malaysia',  'Skyline Electricals',          '199689012345', '0703456012', 'No 77, Galle Road, Kalutara',
       'Skyline Cargo Lanka',        'CUSDEC/2026/1093', '2026-01-15', 'GL1/CASE/2026/423', 'KMTU5678432', 'Electrical switchgear components', 760.250,
       'Safety certification not produced', 'Held pending disposal.', 'forfeit', NULL),

      -- ── COMPLETED disposals: these reach Sold / Destroyed in STEP 4 ───────
      -- 36, 37 → SOLD    (36 straight away; 37 after 3 unsold rounds)
      -- 38, 39 → DESTROYED (38 straight away; 39 after 2 undestroyed rounds)
      -- 40, 41 → one more of each, so both tables have a couple of rows.
      (36, DATE '2025-11-25', 'China',     'Horizon Imports Lanka',        '198812345670', '0711112223', 'No 112, Maradana Road, Colombo 10',
       'Horizon Clearing Ltd',      'CUSDEC/2025/8930', '2025-11-24', 'GL1/CASE/2025/336', 'HRZU1122330', 'Aluminium kitchen sinks and taps', 940.500,
       'Undeclared quantity on manifest', 'Sold at the first tender.', 'forfeit_sold', NULL),

      (37, DATE '2025-12-05', 'India',     'Pearl Hardware Traders',       '197923456781', '0712223334', 'No 64, Kotahena Street, Colombo 13',
       'Pearl Cargo Services',      'CUSDEC/2025/9015', '2025-12-04', 'GL1/CASE/2025/337', 'PRLU2233441', 'Galvanised pipe fittings assortment', 1560.750,
       'Import licence not produced', 'Sold only at the fourth tender.', 'forfeit_sold_late', NULL),

      (38, DATE '2025-12-11', 'Thailand',  'Nature Fresh Lanka',           '199034567892', '0713334445', 'No 9, Station Road, Ratnapura',
       'Nature Clearing Agents',    'CUSDEC/2025/9060', '2025-12-10', 'GL1/CASE/2025/338', 'NTFU3344552', 'Preserved fruit pulp cartons', 1240.300,
       'Unfit for human consumption', 'Destroyed at the first destruction.', 'forfeit_destroyed', NULL),

      (39, DATE '2026-01-12', 'Vietnam',   'Delta Chemicals Lanka',        '198645678903', '0714445556', 'No 38, Baseline Road, Colombo 09',
       'Delta Clearing House',      'CUSDEC/2026/1055', '2026-01-11', 'GL1/CASE/2026/439', 'DLTU4455663', 'Industrial solvent drums', 2250.000,
       'Hazardous chemicals without permit', 'Destroyed at the third attempt.', 'forfeit_destroyed_late', NULL),

      (40, DATE '2026-01-26', 'Dubai',     'Sunset Textiles Lanka',        '199756789014', '0715556667', 'No 21, First Cross Street, Colombo 11',
       'Sunset Clearing Lanka',     'CUSDEC/2026/1170', '2026-01-25', 'GL1/CASE/2026/440', 'SNST5566774', 'Curtain fabric rolls, assorted', 680.400,
       'Counterfeit brand labels', 'Sold at the second tender.', 'forfeit_sold_late', NULL),

      (41, DATE '2026-02-09', 'Malaysia',  'Apex Plastics Lanka',          '198567890125', '0716667778', 'No 143, Negombo Road, Ja-Ela',
       'Apex Cargo Lanka',          'CUSDEC/2026/1270', '2026-02-08', 'GL1/CASE/2026/441', 'APXU6677885', 'Expired PVC resin sacks', 3100.600,
       'Degraded stock, unusable', 'Destroyed at the second attempt.', 'forfeit_destroyed_late', NULL)
    ) AS t(n, entry_date, origin, consignee, nic, phone, address, declarant,
           cusdec_no, cusdec_date, case_no, container, descr, weight,
           reason, notes, outcome, old_sr)
  LOOP
    v_pkg   := gen_random_uuid();
    v_first := NULL;
    v_total := 0;

    INSERT INTO public.packages (
      id, sr_number, old_sr_number, case_number, yard, origin_country,
      declared_value, weight_kg, total_item_count, description, container_number,
      consignee_name, consignee_nic, consignee_address, consignee_phone,
      declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
      notes, inspected_by, inspected_at, created_at, updated_at)
    VALUES (
      v_pkg,
      'GL1/SR/' || lpad(r.n::text, 2, '0') || '/' ||
        CASE WHEN r.entry_date < DATE '2026-01-01' THEN '2025' ELSE '2026' END,
      r.old_sr, r.case_no, v_yard, r.origin,
      0, r.weight, 0, r.descr, r.container,
      r.consignee, r.nic, r.address, r.phone,
      r.declarant, r.cusdec_no, r.cusdec_date,
      r.entry_date::timestamptz + interval '9 hours',
      r.reason, 'pending', r.notes, v_off,
      r.entry_date::timestamptz + interval '11 hours',
      r.entry_date::timestamptz + interval '9 hours',
      r.entry_date::timestamptz + interval '9 hours');

    -- ── Items ───────────────────────────────────────────────────────────────
    -- Packages 2, 4, 8, 11, 13, 15, 21, 22 get several item lines; the rest
    -- get a single line. Item status mirrors the package outcome so the
    -- Abandoned / Forfeited pages pick them up.
    v_idx := 0;
    FOR it IN
      SELECT * FROM (VALUES
        (2 , 1, 'Brake Pad Set',          'Ceramic brake pads, front axle',        60 , 'Pieces',  3200.00, '8708.30.00', 'Vehicle Parts'),
        (2 , 2, 'Oil Filter',             'Spin-on engine oil filters',            150, 'Pieces',   950.00, '8421.23.00', 'Vehicle Parts'),
        (2 , 3, 'Wiper Blade',            'Rubber wiper blades, 22 inch',          80 , 'Pieces',   620.00, '8512.90.00', 'Vehicle Parts'),

        (4 , 1, 'Wireless Keyboard',      'USB wireless keyboard with receiver',   45 , 'Pieces',  4200.00, '8471.60.00', 'Electronics'),
        (4 , 2, 'Optical Mouse',          'USB optical mouse, 1600 DPI',           70 , 'Pieces',  1450.00, '8471.60.00', 'Electronics'),
        (4 , 3, 'USB Hub',                '4-port USB 3.0 hub',                    35 , 'Pieces',  2100.00, '8471.80.00', 'Electronics'),
        (4 , 4, 'Laptop Sleeve',          'Neoprene laptop sleeve, 15 inch',       25 , 'Pieces',  1800.00, '4202.92.00', 'General Cargo'),

        (8 , 1, 'Instant Noodles',        'Packaged instant noodles, 70g',         600, 'Pieces',   120.00, '1902.30.00', 'Food Items'),
        (8 , 2, 'Fruit Juice Cartons',    'Mixed fruit juice, 1L tetra pack',      240, 'Pieces',   380.00, '2009.90.00', 'Food Items'),

        -- ── Multi-item FORFEIT packages ─────────────────────────────────────
        -- Forfeiture is recorded per item, so each of these produces SEVERAL
        -- rows on the Forfeited Packages page that all repeat the same SR.
        (5 , 1, 'Engine Cylinder Block',  'Used motorcycle cylinder blocks, 125cc', 55 , 'Pieces',  7800.00, '8409.91.00', 'Vehicle Parts'),
        (5 , 2, 'Crankshaft Assembly',    'Used motorcycle crankshafts',            40 , 'Pieces',  9200.00, '8483.10.00', 'Vehicle Parts'),
        (5 , 3, 'Clutch Plate Set',       'Friction clutch plates, 5-plate set',    75 , 'Pieces',  2400.00, '8708.93.00', 'Vehicle Parts'),

        (20, 1, 'Life Jackets',           'Marine life jackets, adult size',        60 , 'Pieces',  5400.00, '6307.20.00', 'Marine Equipment'),
        (20, 2, 'Life Buoys',             'Ring-type life buoys, 2.5kg',            30 , 'Pieces',  6800.00, '8907.90.00', 'Marine Equipment'),
        (20, 3, 'Distress Flares',        'Handheld marine distress flares',       120, 'Pieces',  1900.00, '3604.90.00', 'Marine Equipment'),
        (20, 4, 'Emergency Beacons',      'EPIRB emergency position beacons',       18 , 'Pieces', 42000.00, '8526.91.00', 'Marine Equipment'),

        (25, 1, 'Steel Cooking Pots',     'Stainless steel pots, 5L',              110, 'Pieces',  3100.00, '7323.93.00', 'Kitchenware'),
        (25, 2, 'Cutlery Sets',           'Stainless steel cutlery, 24 piece',      95 , 'Pieces',  2750.00, '8215.10.00', 'Kitchenware'),

        (28, 1, 'Latex Gloves',           'Powder-free latex examination gloves',  400, 'Pieces',    45.00, '4015.12.00', 'Rubber Products'),
        (28, 2, 'Rubber Floor Mats',      'Anti-slip rubber floor matting, 1m',    150, 'Pieces',  1350.00, '4016.91.00', 'Rubber Products'),
        (28, 3, 'Rubber Hose Reels',      'Reinforced rubber hose, 20m reel',       48 , 'Pieces',  4600.00, '4009.31.00', 'Rubber Products'),

        -- Package 32 goes to the Tender Committees stage (unsold 4 times), so
        -- give it a couple of lines to make that table read realistically.
        (32, 1, 'Steel Mesh Sheets',      'Reinforcement mesh, 6mm x 2m x 3m',      65 , 'Pieces',  9800.00, '7314.20.00', 'Steel Products'),
        (32, 2, 'Binding Wire Coils',     'Galvanised binding wire, 25kg coil',     38 , 'Pieces',  4200.00, '7217.20.00', 'Steel Products'),

        -- Multi-item completed disposals, so the Sold / Destroyed tables show
        -- several lines under one SR.
        (37, 1, 'Pipe Elbows 2in',        'Galvanised 90-degree elbows, 2 inch',   240, 'Pieces',   680.00, '7307.19.00', 'Hardware'),
        (37, 2, 'Pipe Tees 2in',          'Galvanised equal tees, 2 inch',         180, 'Pieces',   820.00, '7307.19.00', 'Hardware'),
        (37, 3, 'Pipe Unions 2in',        'Galvanised screwed unions, 2 inch',     150, 'Pieces',   950.00, '7307.19.00', 'Hardware'),

        (39, 1, 'Solvent Drums 200L',     'Industrial solvent, 200L steel drum',    24 , 'Pieces', 32000.00, '3814.00.00', 'Chemicals'),
        (39, 2, 'Thinner Cans 20L',       'Paint thinner, 20L can',                 90 , 'Pieces',  4800.00, '3814.00.00', 'Chemicals'),

        (11, 1, 'Chair Frames',           'Knock-down wooden chair frames',        90 , 'Pieces',  5600.00, '9401.69.00', 'Furniture'),
        (11, 2, 'Table Tops',             'Laminated MDF table tops, 4ft',         40 , 'Pieces',  8900.00, '9403.30.00', 'Furniture'),
        (11, 3, 'Drawer Runners',         'Metal drawer runner pairs, 450mm',      200, 'Pieces',   740.00, '8302.42.00', 'Hardware'),

        (13, 1, 'Dumbbell Set',           'Rubber-coated dumbbells, 5kg pair',     50 , 'Pieces',  6200.00, '9506.91.00', 'Sports Goods'),
        (13, 2, 'Yoga Mats',              'TPE yoga mats, 6mm',                    120, 'Pieces',  1900.00, '9506.99.00', 'Sports Goods'),

        (15, 1, 'Sprayer Nozzles',        'Brass agricultural sprayer nozzles',    300, 'Pieces',   450.00, '8424.90.00', 'Machinery'),
        (15, 2, 'Water Pump Impellers',   'Cast iron impellers, 3 inch',           60 , 'Pieces',  3800.00, '8413.91.00', 'Machinery'),
        (15, 3, 'Drive Belts',            'V-belts for agricultural machinery',    180, 'Pieces',   890.00, '4010.32.00', 'Machinery'),

        (21, 1, 'Kitchen Utensil Set',    'Stainless steel utensil sets, 6 piece', 140, 'Pieces',  2300.00, '8215.20.00', 'General Cargo'),
        (21, 2, 'Storage Boxes',          'Stackable plastic storage boxes, 20L',  200, 'Pieces',  1250.00, '3924.90.00', 'General Cargo'),
        (21, 3, 'Wall Clocks',            'Quartz wall clocks, 30cm',              85 , 'Pieces',  1650.00, '9105.21.00', 'General Cargo'),
        (21, 4, 'Door Mats',              'Coir door mats, 40x60cm',               160, 'Pieces',   780.00, '5702.20.00', 'General Cargo'),

        (22, 1, 'Aluminium Foil Rolls',   'Food-grade aluminium foil, 300m',       110, 'Pieces',  2650.00, '7607.11.00', 'Packing Material'),
        (22, 2, 'Carton Sealing Tape',    'BOPP sealing tape, 48mm x 100m',        420, 'Pieces',   310.00, '3919.10.00', 'Packing Material')
      ) AS x(pkg_n, seq, item_name, descr, qty, uom, unit_val, hs, cat)
      WHERE x.pkg_n = r.n
      ORDER BY x.seq
    LOOP
      v_item := gen_random_uuid();
      v_idx  := v_idx + 1;
      IF v_first IS NULL THEN v_first := v_item; END IF;
      v_total := v_total + it.qty;

      INSERT INTO public.package_items (
        id, package_id, yard, item_name, goods_description, quantity,
        unit_of_measure, unit_value, hs_code, category, is_prohibited,
        status, reasons, notes, created_at)
      VALUES (
        v_item, v_pkg, v_yard, it.item_name, it.descr, it.qty,
        it.uom, it.unit_val, it.hs, it.cat, false,
        CASE
          WHEN r.outcome = 'abandoned'      THEN 'Abandoned'
          WHEN r.outcome LIKE 'forfeit%'    THEN 'Forfeit'
          WHEN r.outcome = 'other'          THEN 'Other: Pending court case'
          ELSE 'Detain' END,
        CASE
          WHEN r.outcome = 'abandoned'   THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%_destroyed%'
                                         THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%' THEN 'Supposed to be Sold / Auction'
          WHEN r.outcome = 'other'       THEN 'Supposed to be Converted'
          ELSE 'Pending Licence, Pending Classification / Valuation' END,
        NULL,
        r.entry_date::timestamptz + interval '10 hours');

      INSERT INTO public.warehouse_entries (
        id, package_id, package_item_id, warehouse_id, yard, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate, is_returned, created_at, updated_at)
      VALUES (
        gen_random_uuid(), v_pkg, v_item,
        CASE (r.n + it.seq) % 3 WHEN 0 THEN wh1 WHEN 1 THEN wh2 ELSE wh3 END,
        v_yard,
        CASE (r.n + it.seq) % 3 WHEN 0 THEN 'A' WHEN 1 THEN 'B' ELSE 'C' END,
        CASE
          WHEN r.outcome = 'abandoned'   THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%_destroyed%'
                                         THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%' THEN 'Supposed to be Sold / Auction'
          WHEN r.outcome = 'other'       THEN 'Supposed to be Converted'
          ELSE 'Pending Licence' END,
        it.qty, v_off,
        r.entry_date::timestamptz + interval '14 hours',
        50.0, false,
        r.entry_date::timestamptz + interval '14 hours',
        r.entry_date::timestamptz + interval '14 hours');
    END LOOP;

    -- Single-item packages (everything not listed above).
    IF v_idx = 0 THEN
      v_item  := gen_random_uuid();
      v_first := v_item;
      v_qty   := 20 + (r.n * 7) % 130;
      v_total := v_qty;

      INSERT INTO public.package_items (
        id, package_id, yard, item_name, goods_description, quantity,
        unit_of_measure, unit_value, hs_code, category, is_prohibited,
        status, reasons, notes, created_at)
      VALUES (
        v_item, v_pkg, v_yard,
        split_part(r.descr, ' and ', 1), r.descr, v_qty,
        'Pieces', 500 + (r.n * 137) % 6000,
        lpad(((8400 + r.n * 3) % 9999)::text, 4, '0') || '.'
          || lpad(((10 + r.n) % 99)::text, 2, '0') || '.00',
        'General Cargo', false,
        CASE
          WHEN r.outcome = 'abandoned'      THEN 'Abandoned'
          WHEN r.outcome LIKE 'forfeit%'    THEN 'Forfeit'
          WHEN r.outcome = 'other'          THEN 'Other: Pending court case'
          ELSE 'Detain' END,
        CASE
          WHEN r.outcome = 'abandoned'   THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%_destroyed%'
                                         THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%' THEN 'Supposed to be Sold / Auction'
          WHEN r.outcome = 'other'       THEN 'Supposed to be Donated'
          ELSE 'Pending Inquiry' END,
        NULL,
        r.entry_date::timestamptz + interval '10 hours');

      INSERT INTO public.warehouse_entries (
        id, package_id, package_item_id, warehouse_id, yard, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate, is_returned, created_at, updated_at)
      VALUES (
        gen_random_uuid(), v_pkg, v_item,
        CASE r.n % 3 WHEN 0 THEN wh1 WHEN 1 THEN wh2 ELSE wh3 END,
        v_yard,
        CASE r.n % 3 WHEN 0 THEN 'A' WHEN 1 THEN 'B' ELSE 'C' END,
        CASE
          WHEN r.outcome = 'abandoned'   THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%_destroyed%'
                                         THEN 'Supposed to be Destroyed'
          WHEN r.outcome LIKE 'forfeit%' THEN 'Supposed to be Sold / Auction'
          WHEN r.outcome = 'other'       THEN 'Supposed to be Donated'
          ELSE 'Pending Inquiry' END,
        v_qty, v_off,
        r.entry_date::timestamptz + interval '14 hours',
        50.0, false,
        r.entry_date::timestamptz + interval '14 hours',
        r.entry_date::timestamptz + interval '14 hours');
    END IF;

    -- Keep the header totals consistent with the item lines.
    UPDATE public.packages
       SET total_item_count = v_total,
           declared_value = (SELECT COALESCE(SUM(quantity * unit_value), 0)
                               FROM public.package_items WHERE package_id = v_pkg)
     WHERE id = v_pkg;

    -- ══════════════════════════════════════════════════════════════════════
    --  Outcomes — close the warehouse entries the way the app does, so each
    --  package lands on the right page.
    -- ══════════════════════════════════════════════════════════════════════

    -- RELEASED → "[FINAL:RELEASED]" on every entry of the package.
    IF r.outcome = 'released' THEN
      UPDATE public.warehouse_entries
         SET is_returned = true,
             returned_at = r.entry_date::timestamptz + interval '38 days',
             returned_by = v_off,
             return_notes = '[FINAL:RELEASED] — Cleared after document verification | Receipt No: RCP/'
                            || to_char(r.entry_date, 'YYYY') || '/' || lpad(r.n::text, 4, '0')
       WHERE package_id = v_pkg;

      UPDATE public.package_items SET status = 'returned' WHERE package_id = v_pkg;
    END IF;

    -- ABANDONED → an "[ABANDONED]" disposition event on the first item.
    IF r.outcome = 'abandoned' THEN
      UPDATE public.warehouse_entries
         SET is_returned = true,
             returned_at = r.entry_date::timestamptz + interval '52 days',
             returned_by = v_off,
             return_notes = '[ABANDONED] — Consignee failed to claim within the notice period'
       WHERE package_id = v_pkg AND package_item_id = v_first;
    END IF;

    -- OTHER → a terminal "[FINAL:OTHER] — <custom outcome>" event.
    IF r.outcome = 'other' THEN
      UPDATE public.warehouse_entries
         SET is_returned = true,
             returned_at = r.entry_date::timestamptz + interval '46 days',
             returned_by = v_off,
             return_notes = '[FINAL:OTHER] — '
               || CASE r.n
                    WHEN 7  THEN 'Released on court order — MC Colombo 45821/2025'
                    WHEN 15 THEN 'Held under court order — MC Colombo 46114/2026'
                    ELSE 'Confiscated by court order — MC Colombo 46390/2026'
                  END
       WHERE package_id = v_pkg;
      -- status stays the "Other: <text>" marker set on the item lines above,
      -- which is what _isOtherMarker() in other_packages_screen.dart matches.
    END IF;

    -- FORFEIT → ONE forfeited_packages row PER ITEM. Forfeiture is decided item
    -- by item, so a multi-item package produces several rows that all carry the
    -- SAME SR number — which is exactly what the Forfeited Packages table shows
    -- (one line per forfeited item, repeating the SR).
    -- 'forfeit'      → window CLOSED  (forfeited long ago)   → "Appeal Expired"
    -- 'forfeit_open' → window OPEN    (forfeited days ago)   → "In Appeal"
    --   The 30-day window is measured from forfeited_at, so an OPEN one is
    --   backdated only a few days from today and its deadline is in the future.
    IF r.outcome LIKE 'forfeit%' THEN
      v_forf_at := CASE
        -- OPEN: forfeited 3–20 days ago, so deadline = +30d is still ahead.
        WHEN r.outcome = 'forfeit_open'
          THEN now() - make_interval(days => 3 + (r.n % 6) * 3)
        -- CLOSED: forfeited 40 days after entry, long past its +30d deadline.
        ELSE r.entry_date::timestamptz + interval '40 days'
      END;

      INSERT INTO public.forfeited_packages (
        id, package_id, sr_number, consignee_name, forfeited_at, appeal_deadline,
        reason, yard, source, item_id, appeal_hold, created_at, updated_at)
      SELECT
        gen_random_uuid(), v_pkg,
        'GL1/SR/' || lpad(r.n::text, 2, '0') || '/' ||
          CASE WHEN r.entry_date < DATE '2026-01-01' THEN '2025' ELSE '2026' END,
        r.consignee,
        v_forf_at,
        v_forf_at + interval '30 days',
        r.reason, v_yard, 'forfeit', pi.id, false,
        v_forf_at, v_forf_at
      FROM public.package_items pi
      WHERE pi.package_id = v_pkg;
    END IF;

  END LOOP;
END $$;

-- ── STEP 3: PARK THE EXPIRED FORFEITS MID-PIPELINE ───────────────────────────
--  NOTHING is finished here. Every appeal-EXPIRED item is left at some stage
--  IN PROGRESS, so the Sold Packages and Destroyed Packages tables stay EMPTY
--  and each earlier stage has real work waiting in it.
--
--  Routing is by PACKAGE (not by row) so each stage shows a DIFFERENT SR —
--  routing per row put two rows of the same package in one stage, which the
--  Unsold/Undestroyed views group per package and so listed the SR twice.
--
--  Stage map (see v_stage below):
--    PENDING VALUATION  SR 05 + 23  request A (12 days ago)
--                       SR 31 + 34  request B ( 4 days ago)
--    DISPOSAL REQUESTS  SR 24       request C (75 days ago, forwarded)
--                       SR 29       request D (26 days ago, forwarded)
--    UNSOLD TENDERS     SR 20  1 round   · SR 33  2 rounds
--                       SR 26  3 rounds  · SR 27  2 rounds
--    TENDER COMMITTEES  SR 32  4 rounds  (tenderCount >= 4)
--    UNDESTROYED        SR 12
--    UNTOUCHED FORFEIT  SR 35       30 days up, nothing started
--
--  TENDER ROUNDS ARE SEPARATE SALES ON SEPARATE DAYS. Each round n of a
--  package goes into its own tender_sales row (GL1/TS/2026/Rn), so the yard's
--  Tender Sale page lists several sales on several dates instead of one.
--  Round n is dated (n * 35) days before the newest round, and every round's
--  next-working-day deadline has passed, so all of them read as UNSOLD.
--
--  The goods NEVER leave the yard at any of these stages: no [FINAL:…]
--  warehouse entry is written, the held entry is not deleted, and
--  package_items.status stays 'Forfeit'.
DO $$
DECLARE
  v_yard      text := 'GL1';
  v_off       uuid;
  v_req_fwd   uuid;  -- forwarded request C → Central Disposal (older)
  v_req_fwd2  uuid;  -- forwarded request D → Central Disposal (newer day)
  v_req_p1    uuid;  -- pending request A   → Valuation Directorate
  v_req_p2    uuid;  -- pending request B   → Valuation Directorate
  v_destr_und uuid;  -- destruction that went UNDESTROYED
  v_sale      uuid;
  f           record;
  v_qty       int;
  v_val       numeric;
  v_stage     text;
  v_rounds    int;   -- how many unsold tender rounds this package gets
  v_age       int;   -- days before today that its NEWEST round ran
  i           int;
  v_n_unsold  int := 0;
  v_n_undestr int := 0;
  v_n_pending int := 0;
  v_n_val     int := 0;
  v_n_cmte    int := 0;
  v_n_idle    int := 0;
BEGIN
  SELECT id INTO v_off FROM public.profiles
   WHERE yard = v_yard ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN
    SELECT id INTO v_off FROM public.profiles ORDER BY created_at LIMIT 1;
  END IF;

  v_req_fwd   := gen_random_uuid();
  v_req_fwd2  := gen_random_uuid();
  v_req_p1    := gen_random_uuid();
  v_req_p2    := gen_random_uuid();
  v_destr_und := gen_random_uuid();

  -- TWO forwarded requests on DIFFERENT days → Central Disposal's Disposal
  -- Requests tab shows two dated cards.
  INSERT INTO public.disposal_requests (
    id, yard, request_date, status, valuation_status, valued_at, valued_by,
    created_by, created_at)
  VALUES
    (v_req_fwd,  v_yard, (now() - interval '75 days')::date, 'reviewed',
     'forwarded', now() - interval '70 days', v_off, v_off, now() - interval '75 days'),
    (v_req_fwd2, v_yard, (now() - interval '26 days')::date, 'reviewed',
     'forwarded', now() - interval '24 days', v_off, v_off, now() - interval '26 days');

  -- TWO requests still awaiting valuation, also on different days.
  INSERT INTO public.disposal_requests (
    id, yard, request_date, status, valuation_status, created_by, created_at)
  VALUES
    (v_req_p1, v_yard, (now() - interval '12 days')::date, 'pending',
     'pending_valuation', v_off, now() - interval '12 days'),
    (v_req_p2, v_yard, (now() - interval '4 days')::date,  'pending',
     'pending_valuation', v_off, now() - interval '4 days');

  -- Destruction that went UNDESTROYED (14 days ago, deadline passed).
  INSERT INTO public.destructions (
    id, sale_number, sale_date, serial, year, tender_type, yard, sale_time,
    created_by, created_at)
  VALUES (
    v_destr_und, 'GL1/DS/2026/001', (now() - interval '14 days')::date, 1, 2026,
    'general_cargo', v_yard, '09:30', v_off, now() - interval '28 days');

  FOR f IN
    SELECT fp.id, fp.package_id, fp.item_id, p.sr_number
      FROM public.forfeited_packages fp
      JOIN public.packages p ON p.id = fp.package_id
     WHERE fp.appeal_deadline <= now()
     ORDER BY fp.appeal_deadline DESC, fp.id
  LOOP
    SELECT quantity, unit_value INTO v_qty, v_val
      FROM public.package_items WHERE id = f.item_id;
    v_qty := COALESCE(v_qty, 1);
    v_val := COALESCE(v_val, 1000);

    -- Route by SR number so every stage gets a distinct package, and give the
    -- tendered ones a DIFFERENT number of unsold rounds + a different age.
    v_stage  := 'val_a';
    v_rounds := 0;
    v_age    := 0;
    CASE
      WHEN f.sr_number LIKE '%/20/%' THEN v_stage := 'tendered'; v_rounds := 1; v_age := 18;
      WHEN f.sr_number LIKE '%/33/%' THEN v_stage := 'tendered'; v_rounds := 2; v_age := 25;
      WHEN f.sr_number LIKE '%/26/%' THEN v_stage := 'tendered'; v_rounds := 3; v_age := 11;
      WHEN f.sr_number LIKE '%/27/%' THEN v_stage := 'tendered'; v_rounds := 2; v_age := 40;
      WHEN f.sr_number LIKE '%/32/%' THEN v_stage := 'tendered'; v_rounds := 4; v_age := 30;
      WHEN f.sr_number LIKE '%/12/%' THEN v_stage := 'undestroyed';
      WHEN f.sr_number LIKE '%/24/%' THEN v_stage := 'pending_request';
      WHEN f.sr_number LIKE '%/29/%' THEN v_stage := 'pending_request2';
      WHEN f.sr_number LIKE '%/35/%' THEN v_stage := 'idle';
      WHEN f.sr_number LIKE '%/31/%' THEN v_stage := 'val_b';
      WHEN f.sr_number LIKE '%/34/%' THEN v_stage := 'val_b';
      -- SR 36-41 are the COMPLETED disposals — STEP 4 owns them entirely, so
      -- leave them alone here (without this they would fall into 'val_a').
      WHEN f.sr_number LIKE '%/36/%' OR f.sr_number LIKE '%/37/%'
        OR f.sr_number LIKE '%/38/%' OR f.sr_number LIKE '%/39/%'
        OR f.sr_number LIKE '%/40/%' OR f.sr_number LIKE '%/41/%'
                                     THEN v_stage := 'skip';
      ELSE v_stage := 'val_a';          -- SR 05 and 23
    END CASE;

    -- ── Left completely alone: forfeited, 30 days passed, nothing started ──
    IF v_stage = 'idle' THEN
      v_n_idle := v_n_idle + 1;
      CONTINUE;
    END IF;

    -- Completed disposals are built by STEP 4.
    IF v_stage = 'skip' THEN CONTINUE; END IF;

    -- ── AWAITING VALUATION ─────────────────────────────────────────────────
    -- forwarded = FALSE and no valuation_cost yet: the Valuation Directorate
    -- has to price it. Nothing downstream can see it.
    IF v_stage IN ('val_a', 'val_b') THEN
      INSERT INTO public.disposal_request_items (
        id, request_id, forfeited_package_id, disposition, forwarded, created_at)
      VALUES (
        gen_random_uuid(),
        CASE WHEN v_stage = 'val_a' THEN v_req_p1 ELSE v_req_p2 END,
        f.id,
        CASE WHEN f.sr_number LIKE '%/23/%' OR f.sr_number LIKE '%/34/%'
             THEN 'destruction' ELSE 'sale' END,
        false,
        CASE WHEN v_stage = 'val_a' THEN now() - interval '12 days'
             ELSE now() - interval '4 days' END)
      ON CONFLICT DO NOTHING;
      v_n_val := v_n_val + 1;
      CONTINUE;
    END IF;

    -- Everything below has been valued and forwarded.
    INSERT INTO public.disposal_request_items (
      id, request_id, forfeited_package_id, disposition, valuation_cost,
      forwarded, created_at)
    VALUES (
      gen_random_uuid(),
      CASE WHEN v_stage = 'pending_request2' THEN v_req_fwd2 ELSE v_req_fwd END,
      f.id,
      CASE WHEN v_stage = 'undestroyed' THEN 'destruction' ELSE 'sale' END,
      v_val, true,
      CASE WHEN v_stage = 'pending_request2' THEN now() - interval '26 days'
           ELSE now() - interval '75 days' END)
    ON CONFLICT DO NOTHING;

    IF v_stage = 'tendered' THEN
      -- ── UNSOLD TENDER ROUNDS (→ re-tender / committee) ───────────────────
      -- One tender_sales row PER ROUND, each on its own day, all with
      -- sold = FALSE. Goods stay HELD in the warehouse throughout.
      -- Round i is (v_rounds - i) * 35 days older than the newest round, so
      -- the yard's Tender Sale page lists sales across several dates.
      FOR i IN 1..v_rounds LOOP
        SELECT id INTO v_sale FROM public.tender_sales
         WHERE sale_number = 'GL1/TS/2026/R'
                              || lpad((v_age + (v_rounds - i) * 35)::text, 3, '0');

        IF v_sale IS NULL THEN
          v_sale := gen_random_uuid();
          INSERT INTO public.tender_sales (
            id, sale_number, sale_date, serial, year, tender_type, yard,
            sale_time, created_by, created_at)
          VALUES (
            v_sale,
            'GL1/TS/2026/R' || lpad((v_age + (v_rounds - i) * 35)::text, 3, '0'),
            (now() - make_interval(days => v_age + (v_rounds - i) * 35))::date,
            i::text, 2026, 'general_cargo', v_yard, '10:00', v_off,
            now() - make_interval(days => v_age + (v_rounds - i) * 35 + 2));
        END IF;

        INSERT INTO public.tender_sale_items (
          id, tender_sale_id, forfeited_package_id, package_item_id, yard,
          sold, sold_price, applied_taxes, is_delivered, created_at)
        VALUES (
          gen_random_uuid(), v_sale, f.id, f.item_id, v_yard,
          false, 0, '[]'::jsonb, false,
          now() - make_interval(days => v_age + (v_rounds - i) * 35 + 2))
        ON CONFLICT DO NOTHING;

        -- Bids fell below the valuation each round — that is why it did not
        -- sell, and it gives the Valuation Directorate something to review.
        INSERT INTO public.tender_bids
          (id, forfeited_package_id, tender_sale_id, amount, yard, created_by, created_at)
        SELECT gen_random_uuid(), f.id, v_sale,
               round((v_val * v_qty * x)::numeric, 2), v_yard, v_off,
               now() - make_interval(days => v_age + (v_rounds - i) * 35 - 1)
          FROM unnest(ARRAY[0.82 - (i * 0.04), 0.71 - (i * 0.04), 0.60 - (i * 0.04)]) AS x;

        -- Rounds 2+ were priced by a Valuation re-valuation (round 1 used the
        -- original valuation from the disposal request).
        IF i > 1 THEN
          INSERT INTO public.tender_revaluations (
            id, forfeited_package_id, tender_sale_id, valuation_cost, note,
            yard, created_by, created_at)
          VALUES (
            gen_random_uuid(), f.id, v_sale,
            round((v_val * (1 - (i - 1) * 0.12))::numeric, 2),
            'Re-valued after the previous round went unsold',
            v_yard, v_off,
            now() - make_interval(days => v_age + (v_rounds - i) * 35 + 3));
        END IF;
      END LOOP;

      IF v_rounds >= 4 THEN v_n_cmte := v_n_cmte + 1;
      ELSE v_n_unsold := v_n_unsold + 1;
      END IF;

    ELSIF v_stage = 'undestroyed' THEN
      -- ── UNDESTROYED (→ re-destruction) ───────────────────────────────────
      INSERT INTO public.destruction_items (
        id, destruction_id, forfeited_package_id, package_item_id, yard,
        destroyed, notes, created_at)
      VALUES (
        gen_random_uuid(), v_destr_und, f.id, f.item_id, v_yard,
        false, 'Destruction could not be carried out on the scheduled date',
        now() - interval '28 days')
      ON CONFLICT DO NOTHING;
      v_n_undestr := v_n_undestr + 1;

    ELSE
      -- ── PENDING DISPOSAL REQUEST ─────────────────────────────────────────
      -- Valued and forwarded, but in NO tender and NO destruction, so it waits
      -- on the Central Disposal "Disposal Requests" tab for a tender placement.
      v_n_pending := v_n_pending + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'unsold=% committee=% undestroyed=% pending_request=% awaiting_valuation=% untouched=%',
    v_n_unsold, v_n_cmte, v_n_undestr, v_n_pending, v_n_val, v_n_idle;
END $$;

-- ── STEP 4: COMPLETED DISPOSALS (SR 36-41) ───────────────────────────────────
--  These packages run all the way through and FINISH, so the Sold Packages and
--  Destroyed Packages tables have data. Two routes to each outcome:
--
--    SOLD
--      SR 36  sold at the FIRST tender          (1 round)
--      SR 40  sold at the SECOND tender         (2 rounds: 1 unsold, then sold)
--      SR 37  sold at the FOURTH tender         (4 rounds: 3 unsold, then sold)
--    DESTROYED
--      SR 38  destroyed at the FIRST destruction  (1 round)
--      SR 41  destroyed at the SECOND destruction (2 rounds)
--      SR 39  destroyed at the THIRD destruction  (3 rounds)
--
--  Every round is its own tender_sales / destructions row on its own date, so
--  the yard's Tender Sale page shows the whole history: the earlier rounds sit
--  there as Unsold and the last one as Sold.
--
--  The final round reproduces exactly what disposal_mark_sale_item_sold /
--  disposal_mark_destruction_item_destroyed write:
--    * a [FINAL:SOLD] / [FINAL:DESTROYED] RETURNED warehouse entry
--    * package_items.status = 'sold' / 'destroyed'
--    * the open (held) warehouse entry DELETED
--    * tender_sale_items.sold / destruction_items.destroyed = true
--
--  Dates: forfeited -> appeal expires -> request -> valuation -> rounds -> sale.
--  Every instant is in the PAST and always AFTER that item's appeal deadline.
DO $$
DECLARE
  v_yard     text := 'GL1';
  v_off      uuid;
  v_req      uuid;
  f          record;
  v_wh       uuid;
  v_zone     text;
  v_hold     text;
  v_rate     numeric;
  v_admat    timestamptz;
  v_qty      int;
  v_val      numeric;
  v_rounds   int;    -- how many attempts before it finished
  v_age      int;    -- days ago the FINAL (successful) round ran
  v_destroy  boolean;
  v_sale     uuid;
  v_when     timestamptz;
  v_last     boolean;
  v_seq      int := 0;
  i          int;
  v_n_sold   int := 0;
  v_n_destr  int := 0;
BEGIN
  SELECT id INTO v_off FROM public.profiles
   WHERE yard = v_yard ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN
    SELECT id INTO v_off FROM public.profiles ORDER BY created_at LIMIT 1;
  END IF;

  -- The disposal request these were raised under (valued + forwarded).
  v_req := gen_random_uuid();
  INSERT INTO public.disposal_requests (
    id, yard, request_date, status, valuation_status, valued_at, valued_by,
    created_by, created_at)
  VALUES (
    v_req, v_yard, (now() - interval '200 days')::date, 'reviewed',
    'forwarded', now() - interval '195 days', v_off, v_off,
    now() - interval '200 days');

  FOR f IN
    SELECT fp.id, fp.package_id, fp.item_id, fp.appeal_deadline, p.sr_number
      FROM public.forfeited_packages fp
      JOIN public.packages p ON p.id = fp.package_id
     WHERE p.sr_number LIKE '%/36/%' OR p.sr_number LIKE '%/37/%'
        OR p.sr_number LIKE '%/38/%' OR p.sr_number LIKE '%/39/%'
        OR p.sr_number LIKE '%/40/%' OR p.sr_number LIKE '%/41/%'
     ORDER BY p.sr_number, fp.id
  LOOP
    v_seq := v_seq + 1;

    -- How many attempts, how long ago it finished, and which outcome.
    v_destroy := false;
    CASE
      WHEN f.sr_number LIKE '%/36/%' THEN v_rounds := 1; v_age := 95;
      WHEN f.sr_number LIKE '%/40/%' THEN v_rounds := 2; v_age := 34;
      WHEN f.sr_number LIKE '%/37/%' THEN v_rounds := 4; v_age := 20;
      WHEN f.sr_number LIKE '%/38/%' THEN v_rounds := 1; v_age := 88;
                                          v_destroy := true;
      WHEN f.sr_number LIKE '%/41/%' THEN v_rounds := 2; v_age := 27;
                                          v_destroy := true;
      ELSE                                v_rounds := 3; v_age := 45;
                                          v_destroy := true;   -- SR 39
    END CASE;

    SELECT quantity, unit_value INTO v_qty, v_val
      FROM public.package_items WHERE id = f.item_id;
    v_qty := COALESCE(v_qty, 1);
    v_val := COALESCE(v_val, 1000);

    -- Reset first: a SELECT ... INTO that finds NO row leaves the variables
    -- holding the PREVIOUS iteration's values, which would silently attach
    -- this item to another package's warehouse.
    v_wh := NULL; v_zone := NULL; v_hold := NULL; v_rate := NULL; v_admat := NULL;

    SELECT warehouse_id, zone, hold_reason, daily_rate, admitted_at
      INTO v_wh, v_zone, v_hold, v_rate, v_admat
      FROM public.warehouse_entries
     WHERE package_id = f.package_id
     ORDER BY (package_item_id = f.item_id) DESC NULLS LAST, admitted_at DESC
     LIMIT 1;

    -- A multi-item package loses its held entries one by one as each item is
    -- finalised below, so by the 2nd/3rd item the lookup can come back empty.
    -- Fall back to any warehouse rather than skipping the item.
    IF v_wh IS NULL THEN
      SELECT id INTO v_wh FROM public.warehouses ORDER BY code LIMIT 1;
      v_zone := 'A';
    END IF;
    IF v_wh IS NULL THEN CONTINUE; END IF;

    -- hold_reason and item_count are parsed as NON-NULLABLE in
    -- WarehouseEntryModel.fromJson — a NULL in either throws and the whole
    -- package disappears from the UI. Guarantee values here.
    v_hold  := COALESCE(v_hold, 'Supposed to be Sold / Auction');
    v_rate  := COALESCE(v_rate, 50);
    v_admat := COALESCE(v_admat, now() - interval '200 days');

    -- The valuation line this item was priced at.
    INSERT INTO public.disposal_request_items (
      id, request_id, forfeited_package_id, disposition, valuation_cost,
      forwarded, created_at)
    VALUES (
      gen_random_uuid(), v_req, f.id,
      CASE WHEN v_destroy THEN 'destruction' ELSE 'sale' END,
      v_val, true, now() - interval '200 days')
    ON CONFLICT DO NOTHING;

    -- ── The rounds ─────────────────────────────────────────────────────────
    -- Round i runs (v_rounds - i) * 32 days before the final one. Only the
    -- LAST round succeeds; the earlier ones are recorded as unsold/undestroyed
    -- attempts so the history is visible on the yard's Tender Sale page.
    FOR i IN 1..v_rounds LOOP
      v_last := (i = v_rounds);
      v_when := now() - make_interval(days => v_age + (v_rounds - i) * 32);
      -- Never before this item's own appeal deadline.
      IF v_when < f.appeal_deadline THEN
        v_when := f.appeal_deadline + interval '3 days';
      END IF;

      IF v_destroy THEN
        SELECT id INTO v_sale FROM public.destructions
         WHERE sale_number = 'GL1/DS/2026/D'
                             || lpad((v_age + (v_rounds - i) * 32)::text, 3, '0');
        IF v_sale IS NULL THEN
          v_sale := gen_random_uuid();
          INSERT INTO public.destructions (
            id, sale_number, sale_date, serial, year, tender_type, yard,
            sale_time, created_by, created_at)
          VALUES (
            v_sale,
            'GL1/DS/2026/D' || lpad((v_age + (v_rounds - i) * 32)::text, 3, '0'),
            v_when::date, i, 2026, 'general_cargo', v_yard, '09:30', v_off,
            v_when - interval '2 days');
        END IF;

        INSERT INTO public.destruction_items (
          id, destruction_id, forfeited_package_id, package_item_id, yard,
          destroyed, destroyed_at, destroyed_price, applied_taxes, notes,
          created_at)
        VALUES (
          gen_random_uuid(), v_sale, f.id, f.item_id, v_yard,
          v_last,
          CASE WHEN v_last THEN v_when END,
          -- The Destroyed Packages table reads destruction_items.destroyed_price
          -- (NOT NULL DEFAULT 0), so leaving it out shows "Rs 0.00". This is the
          -- contractor's destruction charge, so it is a COST, not a sale price.
          CASE WHEN v_last THEN round((v_val * v_qty * 0.06)::numeric, 2)
               ELSE 0 END,
          '[]'::jsonb,
          CASE WHEN v_last
               THEN 'Destroyed under supervision of the disposal committee'
               ELSE 'Destruction could not be carried out on this date' END,
          v_when - interval '2 days')
        ON CONFLICT DO NOTHING;

      ELSE
        SELECT id INTO v_sale FROM public.tender_sales
         WHERE sale_number = 'GL1/TS/2026/S'
                             || lpad((v_age + (v_rounds - i) * 32)::text, 3, '0');
        IF v_sale IS NULL THEN
          v_sale := gen_random_uuid();
          INSERT INTO public.tender_sales (
            id, sale_number, sale_date, serial, year, tender_type, yard,
            sale_time, created_by, created_at)
          VALUES (
            v_sale,
            'GL1/TS/2026/S' || lpad((v_age + (v_rounds - i) * 32)::text, 3, '0'),
            v_when::date, i::text, 2026, 'general_cargo', v_yard, '10:00',
            v_off, v_when - interval '2 days');
        END IF;

        INSERT INTO public.tender_sale_items (
          id, tender_sale_id, forfeited_package_id, package_item_id, yard,
          sold, sold_at, receipt_number, sold_price, applied_taxes,
          is_delivered, delivered_at, created_at)
        VALUES (
          gen_random_uuid(), v_sale, f.id, f.item_id, v_yard,
          v_last,
          CASE WHEN v_last THEN v_when END,
          CASE WHEN v_last
               THEN 'RCP/2026/' || lpad((900 + v_seq)::text, 4, '0') END,
          CASE WHEN v_last THEN round((v_val * v_qty * 1.18)::numeric, 2)
               ELSE 0 END,
          '[]'::jsonb,
          -- Most sold items were collected; leave one pending per package.
          (v_last AND v_seq % 3 <> 0),
          CASE WHEN v_last AND v_seq % 3 <> 0 THEN v_when + interval '5 days' END,
          v_when - interval '2 days')
        ON CONFLICT DO NOTHING;

        -- Bids on every round. On the losing rounds they fall short of the
        -- valuation; on the winning round the top bid clears it.
        INSERT INTO public.tender_bids
          (id, forfeited_package_id, tender_sale_id, amount, yard, created_by, created_at)
        SELECT gen_random_uuid(), f.id, v_sale,
               round((v_val * v_qty * x)::numeric, 2), v_yard, v_off,
               v_when + interval '1 hour'
          FROM unnest(
                 CASE WHEN v_last THEN ARRAY[1.18, 0.94, 0.81]
                      ELSE ARRAY[0.80 - (i * 0.05), 0.69 - (i * 0.05)] END) AS x;
      END IF;

      -- Rounds 2+ were re-priced by the Valuation Directorate after the
      -- previous attempt failed (sales only — destructions are not re-valued).
      IF i > 1 AND NOT v_destroy THEN
        INSERT INTO public.tender_revaluations (
          id, forfeited_package_id, tender_sale_id, valuation_cost, note,
          yard, created_by, created_at)
        VALUES (
          gen_random_uuid(), f.id, v_sale,
          round((v_val * (1 - (i - 1) * 0.10))::numeric, 2),
          'Re-valued after the previous round went unsold',
          v_yard, v_off, v_when - interval '3 days');
      END IF;
    END LOOP;

    -- ── Finish it: the goods leave the yard ────────────────────────────────
    v_when := now() - make_interval(days => v_age);
    IF v_when < f.appeal_deadline THEN
      v_when := f.appeal_deadline + interval '3 days';
    END IF;

    INSERT INTO public.warehouse_entries (
      id, package_id, yard, package_item_id, warehouse_id, zone, hold_reason,
      item_count, admitted_by, admitted_at, daily_rate,
      is_returned, returned_at, returned_by, return_notes, created_at, updated_at)
    VALUES (
      gen_random_uuid(), f.package_id, v_yard, f.item_id, v_wh, v_zone,
      COALESCE(v_hold, 'Forfeit'), v_qty, v_off, COALESCE(v_admat, v_when),
      COALESCE(v_rate, 50),
      true, v_when, v_off,
      CASE WHEN v_destroy
           THEN '[FINAL:DESTROYED] — Receipt/Notes: DSR/2026/'
                || lpad((900 + v_seq)::text, 4, '0')
           ELSE '[FINAL:SOLD] — Receipt: RCP/2026/'
                || lpad((900 + v_seq)::text, 4, '0') END,
      v_when, v_when);

    UPDATE public.package_items
       SET status = CASE WHEN v_destroy THEN 'destroyed' ELSE 'sold' END
     WHERE id = f.item_id;

    DELETE FROM public.warehouse_entries
     WHERE package_item_id = f.item_id AND is_returned = false;

    IF v_destroy THEN v_n_destr := v_n_destr + 1;
    ELSE v_n_sold := v_n_sold + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'completed: % sold, % destroyed', v_n_sold, v_n_destr;
END $$;

-- ── VERIFY ───────────────────────────────────────────────────────────────────
SELECT 'packages'          AS table_name, count(*) FROM public.packages
UNION ALL SELECT 'package_items',      count(*) FROM public.package_items
UNION ALL SELECT 'warehouse_entries',  count(*) FROM public.warehouse_entries
UNION ALL SELECT 'forfeited_packages', count(*) FROM public.forfeited_packages
UNION ALL SELECT 'old entries',        count(*) FROM public.packages WHERE old_sr_number IS NOT NULL
UNION ALL SELECT 'released entries',   count(*) FROM public.warehouse_entries WHERE return_notes LIKE '[FINAL:RELEASED]%'
UNION ALL SELECT 'abandoned entries',  count(*) FROM public.warehouse_entries WHERE return_notes LIKE '[ABANDONED]%'
UNION ALL SELECT 'other entries',      count(*) FROM public.warehouse_entries WHERE return_notes LIKE '[FINAL:OTHER]%'
UNION ALL SELECT 'multi-item packages',count(*) FROM (
  SELECT package_id FROM public.package_items GROUP BY package_id HAVING count(*) > 1) z
UNION ALL SELECT 'forfeited: IN APPEAL',   count(*) FROM public.forfeited_packages WHERE appeal_deadline > now()
UNION ALL SELECT 'forfeited: EXPIRED',     count(*) FROM public.forfeited_packages WHERE appeal_deadline <= now()
UNION ALL SELECT 'forfeited: distinct SRs',count(DISTINCT sr_number) FROM public.forfeited_packages;

-- SR numbers that appear on SEVERAL forfeited rows (multi-item forfeitures).
SELECT sr_number, count(*) AS forfeited_rows
  FROM public.forfeited_packages
 GROUP BY sr_number HAVING count(*) > 1
 ORDER BY sr_number;

-- Entry-date spread (should be Nov 2025 – Feb 2026).
SELECT to_char(entry_date, 'YYYY-MM') AS month, count(*)
  FROM public.packages GROUP BY 1 ORDER BY 1;

-- ── STEP 3 verification: everything must be MID-PROCESS ───────────────────
-- The first four rows MUST be 0 — nothing is sold or destroyed yet.
SELECT 'SOLD items (STEP 4: SR 36/37/40)'  AS check, count(*) FROM public.package_items WHERE status = 'sold'
UNION ALL SELECT 'DESTROYED items (STEP 4: SR 38/39/41)', count(*) FROM public.package_items WHERE status = 'destroyed'
UNION ALL SELECT '[FINAL:SOLD] entries',      count(*) FROM public.warehouse_entries WHERE return_notes LIKE '[FINAL:SOLD]%'
UNION ALL SELECT '[FINAL:DESTROYED] entries', count(*) FROM public.warehouse_entries WHERE return_notes LIKE '[FINAL:DESTROYED]%'
-- … and these are the stages that SHOULD have work in them.
UNION ALL SELECT 'UNSOLD (Unsold Tenders tab)',  count(*)
    FROM public.tender_sale_items WHERE NOT sold
UNION ALL SELECT 'UNDESTROYED (Undestroyed tab)', count(*)
    FROM public.destruction_items WHERE NOT destroyed
UNION ALL SELECT 'PENDING (Disposal Requests tab)', count(*)
    FROM public.disposal_request_items dri
   WHERE dri.forwarded
     AND dri.forfeited_package_id NOT IN (SELECT forfeited_package_id FROM public.tender_sale_items)
     AND dri.forfeited_package_id NOT IN (SELECT forfeited_package_id FROM public.destruction_items)
UNION ALL SELECT 'AWAITING VALUATION (Pending Valuation tab)', count(*)
    FROM public.disposal_request_items WHERE NOT forwarded
UNION ALL SELECT 'Pending Valuation REQUESTS (want 2, different days)', count(*)
    FROM public.disposal_requests WHERE valuation_status = 'pending_valuation'
UNION ALL SELECT 'COMMITTEE candidates (unsold 4x)', count(*) FROM (
    SELECT t.forfeited_package_id
      FROM public.tender_sale_items t
     GROUP BY t.forfeited_package_id
    HAVING count(*) >= 4 AND bool_and(NOT t.sold)) c
UNION ALL SELECT 'FORFEITED untouched (expired, nothing started)', count(*)
    FROM public.forfeited_packages fp
   WHERE fp.appeal_deadline <= now()
     AND fp.id NOT IN (SELECT forfeited_package_id FROM public.disposal_request_items)
UNION ALL SELECT 'forfeits still in appeal', count(*)
    FROM public.forfeited_packages WHERE appeal_deadline > now()
UNION ALL SELECT 'tender_bids recorded', count(*) FROM public.tender_bids;

-- Tender rounds per package: SR 20 x1, SR 33 x2, SR 26 x3, SR 27 x2, SR 32 x4.
-- All rounds must be UNSOLD; 4+ rounds makes a Tender Committee candidate.
SELECT p.sr_number,
       count(*)                                  AS tender_rounds,
       count(*) FILTER (WHERE t.sold)            AS sold_rounds,
       (count(*) >= 4)                           AS committee_candidate
  FROM public.tender_sale_items t
  JOIN public.forfeited_packages f ON f.id = t.forfeited_package_id
  JOIN public.packages p ON p.id = f.package_id
 GROUP BY p.sr_number, t.forfeited_package_id
 ORDER BY tender_rounds DESC, p.sr_number;

-- The yard's Tender Sale page should list MANY sales on MANY dates.
SELECT sale_number, sale_date, count(t.id) AS packages_in_sale
  FROM public.tender_sales s
  LEFT JOIN public.tender_sale_items t ON t.tender_sale_id = s.id
 GROUP BY s.id, sale_number, sale_date
 ORDER BY sale_date;

-- Pending Valuation should show TWO requests raised on DIFFERENT dates.
SELECT request_date, count(dri.id) AS items_awaiting
  FROM public.disposal_requests dr
  JOIN public.disposal_request_items dri
    ON dri.request_id = dr.id AND NOT dri.forwarded
 WHERE dr.valuation_status = 'pending_valuation'
 GROUP BY request_date ORDER BY request_date;

-- Which SR sits at which stage — each stage should list a DIFFERENT SR.
SELECT 'Unsold Tenders' AS stage, p.sr_number, count(*) AS items
  FROM public.tender_sale_items t
  JOIN public.forfeited_packages f ON f.id = t.forfeited_package_id
  JOIN public.packages p ON p.id = f.package_id
 WHERE NOT t.sold GROUP BY p.sr_number
UNION ALL
SELECT 'Undestroyed', p.sr_number, count(*)
  FROM public.destruction_items d
  JOIN public.forfeited_packages f ON f.id = d.forfeited_package_id
  JOIN public.packages p ON p.id = f.package_id
 WHERE NOT d.destroyed GROUP BY p.sr_number
UNION ALL
SELECT 'Pending Valuation', p.sr_number, count(*)
  FROM public.disposal_request_items dri
  JOIN public.forfeited_packages f ON f.id = dri.forfeited_package_id
  JOIN public.packages p ON p.id = f.package_id
 WHERE NOT dri.forwarded GROUP BY p.sr_number
UNION ALL
SELECT 'Tender Committees', p.sr_number, count(DISTINCT f.id)
  FROM public.forfeited_packages f
  JOIN public.packages p ON p.id = f.package_id
 WHERE f.id IN (SELECT forfeited_package_id FROM public.tender_sale_items
                 GROUP BY forfeited_package_id HAVING count(*) >= 4)
 GROUP BY p.sr_number
UNION ALL
SELECT 'Forfeited (untouched)', p.sr_number, count(*)
  FROM public.forfeited_packages f
  JOIN public.packages p ON p.id = f.package_id
 WHERE f.appeal_deadline <= now()
   AND f.id NOT IN (SELECT forfeited_package_id FROM public.disposal_request_items)
 GROUP BY p.sr_number
 ORDER BY stage, sr_number;

-- The Unsold / Undestroyed pools only fill once the sale-day deadline has
-- PASSED. Both sale dates must therefore be in the past — check they are.
SELECT sale_number, sale_date,
       (sale_date < current_date) AS deadline_passed
  FROM public.tender_sales
UNION ALL
SELECT sale_number, sale_date, (sale_date < current_date)
  FROM public.destructions
 ORDER BY sale_number;

-- No sale/destruction may be dated in the future, and none may pre-date its
-- own appeal deadline. Both queries MUST return zero rows.
SELECT 'future-dated sale' AS problem, count(*) FROM public.tender_sale_items WHERE sold_at > now()
UNION ALL SELECT 'future-dated destruction', count(*) FROM public.destruction_items WHERE destroyed_at > now()
UNION ALL SELECT 'sold before appeal expiry', count(*)
    FROM public.tender_sale_items tsi
    JOIN public.forfeited_packages fp ON fp.id = tsi.forfeited_package_id
   WHERE tsi.sold AND tsi.sold_at < fp.appeal_deadline
UNION ALL SELECT 'destroyed before appeal expiry', count(*)
    FROM public.destruction_items di
    JOIN public.forfeited_packages fp ON fp.id = di.forfeited_package_id
   WHERE di.destroyed AND di.destroyed_at < fp.appeal_deadline;

-- ── STEP 4 verification: completed disposals ────────────────────────────────
-- Each SR should show its attempt count and exactly ONE successful round.
SELECT p.sr_number,
       'SALE'                                   AS route,
       count(*)                                 AS attempts,
       count(*) FILTER (WHERE t.sold)           AS succeeded,
       max(t.sold_at)::date                     AS finished_on
  FROM public.tender_sale_items t
  JOIN public.forfeited_packages f ON f.id = t.forfeited_package_id
  JOIN public.packages p ON p.id = f.package_id
 WHERE EXISTS (SELECT 1 FROM public.tender_sale_items x
                WHERE x.forfeited_package_id = f.id AND x.sold)
 GROUP BY p.sr_number, t.forfeited_package_id
UNION ALL
SELECT p.sr_number, 'DESTRUCTION',
       count(*), count(*) FILTER (WHERE d.destroyed), max(d.destroyed_at)::date
  FROM public.destruction_items d
  JOIN public.forfeited_packages f ON f.id = d.forfeited_package_id
  JOIN public.packages p ON p.id = f.package_id
 WHERE EXISTS (SELECT 1 FROM public.destruction_items x
                WHERE x.forfeited_package_id = f.id AND x.destroyed)
 GROUP BY p.sr_number, d.forfeited_package_id
 ORDER BY route, sr_number;
