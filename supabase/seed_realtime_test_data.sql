-- ============================================================================
--  Sri Lanka Customs Yard Management — FULL TEST DATA SEED
--  ---------------------------------------------------------------------------
--  • Wipes ALL transactional data but KEEPS members (profiles / auth.users).
--  • Keeps reference/config tables (warehouses, customs_rules) and backfills
--    the optional reference tables (hold_reasons, package_categories,
--    disposal_taxes, storage_rates) if they are empty.
--  • Inserts fresh data that exercises EVERY table and EVERY feature/function
--    so every screen (SR Reg, Warehouses, Released, Abandoned, Forfeited,
--    Sold, Destroyed, Re-exported, Other, Disposal Requests, Tender Sales,
--    Unsold Tenders, Destructions, Undestroyed, Taxes, Appeal Directorate)
--    has live, realtime-compatible data.
--
--  All data is created under yard 'GL1' (Grey Line 1) so the existing GL1
--  members own/reference it. Officer/admin references are resolved dynamically
--  from existing profiles — no member rows are created or deleted.
--
--  Safe to run repeatedly. Run AFTER all schema migrations are applied.
-- ============================================================================

begin;

-- ── 1. Wipe transactional data (KEEP profiles + reference tables) ────────────
-- Child→parent order; FKs are ON DELETE CASCADE but we delete explicitly so the
-- realtime channels emit deletes for every open view.
delete from public.tender_sale_items;
delete from public.tender_sales;
delete from public.destruction_items;
delete from public.destructions;
delete from public.disposal_request_items;
delete from public.disposal_requests;
delete from public.tender_disposals;
delete from public.tenders;
delete from public.forfeited_packages;
delete from public.warehouse_entries;
delete from public.package_items;
delete from public.packages;
delete from public.audit_logs;

-- ── 2. Backfill optional reference tables if empty ───────────────────────────
insert into public.hold_reasons (reason_text, description, is_active)
select * from (values
  ('Prohibited Item',        'Goods prohibited under customs law', true),
  ('Documentation Issue',    'Incomplete or invalid documents',   true),
  ('Payment Pending',        'Duties / charges not settled',       true),
  ('Inspection Required',    'Physical inspection pending',        true),
  ('Undervalued Declaration','Declared value appears understated', true),
  ('Restricted Goods',       'Requires special permit',            true)
) as v(reason_text, description, is_active)
where not exists (select 1 from public.hold_reasons);

insert into public.package_categories (name, description)
select * from (values
  ('General',        'General cargo'),
  ('Electronics',    'Electronic goods and accessories'),
  ('Textiles',       'Clothing and fabrics'),
  ('Motor Vehicle',  'Vehicles and parts'),
  ('Food & Beverage','Perishable and packaged food'),
  ('Hardware',       'Tools and machinery')
) as v(name, description)
where not exists (select 1 from public.package_categories);

insert into public.disposal_taxes (name, percentage, is_active)
select * from (values
  ('VAT', 18.0, true),
  ('PAL', 10.0, true)
) as v(name, percentage, is_active)
where not exists (select 1 from public.disposal_taxes);

insert into public.storage_rates (rate, effective_from)
select 50.0, now() - interval '400 days'
where not exists (select 1 from public.storage_rates);

-- ============================================================================
--  3. PACKAGES + ITEMS + WAREHOUSE ENTRIES (one DO block so we can reference
--     ids, the resolved officer and warehouses as we go).
-- ============================================================================
do $$
declare
  v_yard     text := 'GL1';
  v_officer  uuid;
  v_w1 uuid; v_w2 uuid; v_w3 uuid;
  v_pkg uuid; v_item uuid; v_item2 uuid;
  v_fp uuid;
  v_ts uuid;   -- tender_sale id
  v_de uuid;   -- destruction id
  v_dr uuid;   -- disposal_request id
begin
  -- Pick any GL1 admin/officer to attribute actions to; fall back to any profile.
  select id into v_officer from public.profiles
   where yard = v_yard and role in ('admin','officer')
   order by (role = 'admin') desc limit 1;
  if v_officer is null then
    select id into v_officer from public.profiles order by created_at limit 1;
  end if;
  if v_officer is null then
    raise exception 'No profiles exist — create at least one member account first.';
  end if;

  select id into v_w1 from public.warehouses order by code limit 1;
  select id into v_w2 from public.warehouses order by code offset 1 limit 1;
  select id into v_w3 from public.warehouses order by code offset 2 limit 1;
  v_w2 := coalesce(v_w2, v_w1);
  v_w3 := coalesce(v_w3, v_w1);

  -- Helper note: storage daily_rate seeded at 50/unit/day.

  -- ────────────────────────────────────────────────────────────────────────
  -- A) HELD / DETAINED packages (Warehouses screen, charges accruing)
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, container_number, consignee_name,
    consignee_nic, consignee_address, consignee_phone, declarant_name, cusdec_no,
    cusdec_date, entry_date, reason, status, inspected_by, inspected_at, yard)
  values ('GL1/SR/101/2026','CASE/2026/101','India',180000,45.0,2,
    'Assorted electronics','CONT-1001','Lanka Electronics','912345678V','12 Main St, Colombo 03',
    '0771234567','FastTrack Logistics','C5101','2026-05-20', now()-interval '20 days',
    'Prohibited Item','held', v_officer, now()-interval '19 days', v_yard)
  returning id into v_pkg;

    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons, yard)
    values (v_pkg,'Bluetooth Speakers','Portable speakers',10,'Pieces',4500,'8518.22','Electronics',
      true,'Detain','Prohibited Item', v_yard) returning id into v_item;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'USB Cables','Charging cables',50,'Pieces',300,'8544.42','Electronics',
      'Detain','Documentation Issue', v_yard) returning id into v_item2;
    -- Both items currently held in warehouses
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A1','Prohibited Item',10, v_officer, now()-interval '19 days',50, v_yard);
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, daily_rate, yard)
    values (v_pkg, v_item2, v_w2, 'B2','Documentation Issue',50, v_officer, now()-interval '19 days',50, v_yard);

  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, container_number, consignee_name,
    consignee_phone, declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/102/2026','CASE/2026/102','China',90000,30.0,1,
    'Kitchenware','CONT-1002','Home Needs Pvt','0719876543','City Clearers','C5102',
    '2026-05-25', now()-interval '15 days','Inspection Required','detained',
    v_officer, now()-interval '14 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Steel Pots','Stainless cookware',40,'Pieces',1200,'7323.93','Hardware',
      'Detain','Inspection Required', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, daily_rate, yard)
    values (v_pkg, v_item, v_w3, 'C1','Inspection Required',40, v_officer, now()-interval '14 days',50, v_yard);

  -- ────────────────────────────────────────────────────────────────────────
  -- B) RELEASED package (Released Packages screen — returned with receipt)
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/103/2026','CASE/2026/103','UK',60000,8.0,1,'Apparel samples',
    'Fashion House','0761112223','Express Clearers','C5103','2026-05-10',
    now()-interval '30 days','Documentation Issue','returned', v_officer,
    now()-interval '29 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Designer Jackets','Branded jackets',12,'Pieces',8000,'6201.40','Textiles',
      'Released','Documentation Issue', v_yard) returning id into v_item;
    -- 4 released (returned) + 8 still held → partial release
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A2','Documentation Issue',4, v_officer, now()-interval '29 days',
      true, now()-interval '6 days', v_officer,
      'Receipt No: RC-34567 | Date: 2026-06-04 | Notes: Cleared after duty payment',50, v_yard);
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A2','Documentation Issue',8, v_officer, now()-interval '29 days',50, v_yard);

  -- ────────────────────────────────────────────────────────────────────────
  -- C) ABANDONED package → Abandoned screen (REQUESTABLE)
  --    NB: an abandoned package has NO forfeited_packages row until it is sent
  --    in a disposal request (createDisposalRequest creates a source='abandoned'
  --    FP row then). Seeding that row early would make the package look
  --    already-requested and disable the "Send Disposal Request" button, so we
  --    leave it out — the package is surfaced from packages/package_items.
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/104/2026','CASE/2026/104','Dubai',25000,6.0,1,'Cosmetic products',
    'Beauty Care','0759876543','Self','C5104','2026-04-15', now()-interval '55 days',
    'Restricted Goods','held', v_officer, now()-interval '54 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons, yard)
    values (v_pkg,'Perfume Sets','Assorted fragrances',18,'Meters',1500,'3303.00','General',
      true,'abandoned','Restricted Goods', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w2, 'B1','Restricted Goods',18, v_officer, now()-interval '54 days',
      true, now()-interval '30 days', v_officer,'[ABANDONED] Declared abandoned',0, v_yard);

  -- ────────────────────────────────────────────────────────────────────────
  -- D) FORFEITED — appeal window OPEN (Appeal "In Appeal Window")
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/105/2026','CASE/2026/105','USA',90000,20.0,1,'Computer accessories',
    'Tech World','0761234567','FastTrack Logistics','C5105','2026-05-12',
    now()-interval '28 days','Prohibited Item','forfeited', v_officer,
    now()-interval '27 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Graphics Cards','High-end GPUs',6,'Pieces',95000,'8473.30','Electronics',
      'forfeit','Prohibited Item', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A3','Prohibited Item',6, v_officer, now()-interval '27 days',
      true, now()-interval '14 days', v_officer,'[FORFEIT] Unclaimed after detention',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/105/2026','Tech World', now()-interval '14 days',
      now()+interval '16 days','Unclaimed after 14 days','forfeit', v_yard);

  -- ────────────────────────────────────────────────────────────────────────
  -- E) FORFEITED — currently ON APPEAL HOLD (Appeal "On Appeal Hold")
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/106/2026','CASE/2026/106','Singapore',150000,25.0,1,'Mobile phones',
    'Smart Fix','0701234567','Express Clearers','C5106','2026-05-14',
    now()-interval '26 days','Prohibited Item','forfeited', v_officer,
    now()-interval '25 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Smartphones','Flagship phones',8,'Pieces',120000,'8517.13','Electronics',
      'forfeit','Prohibited Item', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w2, 'B3','Prohibited Item',8, v_officer, now()-interval '25 days',
      true, now()-interval '12 days', v_officer,'[FORFEIT] Unclaimed',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, appeal_hold, appeal_hold_note, appeal_held_at, appeal_held_by, yard)
    values (v_pkg,'GL1/SR/106/2026','Smart Fix', now()-interval '12 days',
      now()+interval '18 days','Unclaimed after 14 days','forfeit',
      true,'Appeal received from consignee — do not dispose', now()-interval '2 days', v_officer, v_yard);

  -- ────────────────────────────────────────────────────────────────────────
  -- F) FORFEITED — appeal DECIDED (hold lifted with a decision = DESTROY)
  --     Yard sees "→ Destroy" instruction.
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/107/2026','CASE/2026/107','China',70000,18.0,1,'Counterfeit goods',
    'Unknown Importer','0712223334','City Clearers','C5107','2026-05-01',
    now()-interval '40 days','Prohibited Item','forfeited', v_officer,
    now()-interval '39 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons, yard)
    values (v_pkg,'Counterfeit Watches','Fake branded watches',30,'Pieces',2000,'9102.11','General',
      true,'forfeit','Prohibited Item', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w3, 'C2','Prohibited Item',30, v_officer, now()-interval '26 days',
      true, now()-interval '26 days', v_officer,'[FORFEIT] Counterfeit — confiscated',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, appeal_decision, appeal_decision_note, appeal_decided_at, appeal_decided_by, yard)
    values (v_pkg,'GL1/SR/107/2026','Unknown Importer', now()-interval '26 days',
      now()-interval '1 day','Counterfeit goods','forfeit',
      'DESTROY', null, now()-interval '1 day', v_officer, v_yard);

  -- ────────────────────────────────────────────────────────────────────────
  -- G) FORFEITED → DISPOSAL REQUEST (yard requested Sale + Destruction)
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.disposal_requests (yard, request_date, status, created_by)
  values (v_yard, current_date - 2, 'pending', v_officer) returning id into v_dr;

  -- G1: a SALE-requested forfeited package
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/108/2026','CASE/2026/108','Japan',300000,90.0,1,'Audio equipment',
    'Sound Systems','0773334444','Pro Logistics','C5108','2026-04-01',
    now()-interval '70 days','Unclaimed','forfeited', v_officer, now()-interval '69 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Studio Monitors','Pro audio',12,'Pieces',45000,'8518.21','Electronics',
      'forfeit','Unclaimed', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A4','Unclaimed',12, v_officer, now()-interval '55 days',
      true, now()-interval '40 days', v_officer,'[FORFEIT] Unclaimed',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/108/2026','Sound Systems', now()-interval '40 days',
      now()-interval '10 days','Unclaimed after detention','forfeit', v_yard)
    returning id into v_fp;
    insert into public.disposal_request_items (request_id, forfeited_package_id, disposition)
    values (v_dr, v_fp, 'sale');

  -- G2: a DESTRUCTION-requested forfeited package
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/109/2026','CASE/2026/109','India',40000,12.0,1,'Expired food items',
    'Foodie Paradise','0755556666','FastTrack Logistics','C5109','2026-04-05',
    now()-interval '66 days','Restricted Goods','forfeited', v_officer, now()-interval '65 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons, yard)
    values (v_pkg,'Canned Goods','Expired tins',60,'Pieces',250,'2005.99','Food & Beverage',
      true,'forfeit','Restricted Goods', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w2, 'B4','Restricted Goods',60, v_officer, now()-interval '50 days',
      true, now()-interval '35 days', v_officer,'[FORFEIT] Expired stock',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/109/2026','Foodie Paradise', now()-interval '35 days',
      now()-interval '5 days','Unclaimed after detention','forfeit', v_yard)
    returning id into v_fp;
    insert into public.disposal_request_items (request_id, forfeited_package_id, disposition)
    values (v_dr, v_fp, 'destruction');

  -- ────────────────────────────────────────────────────────────────────────
  -- H) TENDER SALE — one SOLD+delivered, one SOLD+pending, one UNSOLD
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.tender_sales (sale_number, sale_date, serial, year, tender_type, yard, sale_time, created_by)
  values ('TS/2026/001', current_date - 7, '001', 2026, 'general_cargo', v_yard, '10:00', v_officer)
  returning id into v_ts;

  -- H1: SOLD + DELIVERED (Sold Packages screen, Delivered)
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/110/2026','CASE/2026/110','Germany',500000,200.0,1,'Machinery parts',
    'Factory Solutions','0719998888','Pro Logistics','C5110','2026-03-01',
    now()-interval '95 days','Unclaimed','forfeited', v_officer, now()-interval '94 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Industrial Motors','Heavy machinery',5,'Pieces',90000,'8501.53','Hardware',
      'sold','Unclaimed', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A5','Unclaimed',5, v_officer, now()-interval '90 days',
      true, now()-interval '5 days', v_officer,'[FINAL:SOLD] Receipt: SALE-2026-001',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/110/2026','Factory Solutions', now()-interval '60 days',
      now()-interval '30 days','Unclaimed','forfeit', v_yard) returning id into v_fp;
    insert into public.tender_sale_items (tender_sale_id, forfeited_package_id, yard, sold,
      sold_at, receipt_number, sold_price, applied_taxes, is_delivered, delivered_at)
    values (v_ts, v_fp, v_yard, true, now()-interval '5 days','SALE-2026-001', 2352.00,
      '[{"name":"VAT","percentage":18.0,"amount":423.36},{"name":"PAL","percentage":10.0,"amount":235.20}]'::jsonb,
      true, now()-interval '2 days');

  -- H2: SOLD + delivery PENDING
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/111/2026','CASE/2026/111','Vietnam',80000,35.0,1,'Handmade crafts',
    'Heritage Shops','0776667777','Self','C5111','2026-03-05', now()-interval '92 days',
    'Unclaimed','forfeited', v_officer, now()-interval '91 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Wooden Carvings','Decorative crafts',25,'Pieces',3200,'4420.10','General',
      'sold','Unclaimed', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w2, 'B5','Unclaimed',25, v_officer, now()-interval '88 days',
      true, now()-interval '4 days', v_officer,'[FINAL:SOLD] Receipt: SALE-2026-002',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/111/2026','Heritage Shops', now()-interval '58 days',
      now()-interval '28 days','Unclaimed','forfeit', v_yard) returning id into v_fp;
    insert into public.tender_sale_items (tender_sale_id, forfeited_package_id, yard, sold,
      sold_at, receipt_number, sold_price, applied_taxes, is_delivered)
    values (v_ts, v_fp, v_yard, true, now()-interval '4 days','SALE-2026-002', 4500.00,
      '[{"name":"VAT","percentage":18.0,"amount":810.00}]'::jsonb, false);

  -- H3: in a tender sale but NOT yet sold (Unsold Tenders)
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/112/2026','CASE/2026/112','Malaysia',95000,75.0,1,'Hardware tools',
    'Tools & More','0766667777','Self','C5112','2026-03-08', now()-interval '90 days',
    'Unclaimed','forfeited', v_officer, now()-interval '89 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Power Drills','Cordless drills',20,'Pieces',6500,'8467.21','Hardware',
      'forfeit','Unclaimed', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w3, 'C3','Unclaimed',20, v_officer, now()-interval '85 days',
      true, now()-interval '50 days', v_officer,'[FORFEIT] Unclaimed',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/112/2026','Tools & More', now()-interval '50 days',
      now()-interval '20 days','Unclaimed','forfeit', v_yard) returning id into v_fp;
    insert into public.tender_sale_items (tender_sale_id, forfeited_package_id, yard, sold)
    values (v_ts, v_fp, v_yard, false);

  -- ────────────────────────────────────────────────────────────────────────
  -- I) DESTRUCTION — one DESTROYED, one UNDESTROYED
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.destructions (sale_number, sale_date, serial, year, tender_type, yard, sale_time, created_by)
  values ('DS/2026/001', current_date - 6, 1, 2026, 'special', v_yard, '09:00', v_officer)
  returning id into v_de;

  -- I1: DESTROYED (Destroyed Packages screen)
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/113/2026','CASE/2026/113','Thailand',20000,10.0,1,'Narcotic precursors',
    'Unknown','0700000000','Self','C5113','2026-03-10', now()-interval '88 days',
    'Prohibited Item','forfeited', v_officer, now()-interval '87 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons, yard)
    values (v_pkg,'Controlled Chemicals','Restricted substances',15,'Pieces',5000,'2939.79','General',
      true,'destroyed','Prohibited Item', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A6','Prohibited Item',15, v_officer, now()-interval '80 days',
      true, now()-interval '3 days', v_officer,'[FINAL:DESTROYED] Incinerated under supervision',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/113/2026','Unknown', now()-interval '55 days',
      now()-interval '25 days','Prohibited','forfeit', v_yard) returning id into v_fp;
    insert into public.destruction_items (destruction_id, forfeited_package_id, yard, destroyed,
      destroyed_at, notes)
    values (v_de, v_fp, v_yard, true, now()-interval '3 days','Incinerated under supervision');

  -- I2: queued for destruction but NOT yet destroyed (Undestroyed)
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/114/2026','CASE/2026/114','China',18000,8.0,1,'Counterfeit cosmetics',
    'Fake Beauty','0701112233','City Clearers','C5114','2026-03-12', now()-interval '86 days',
    'Prohibited Item','forfeited', v_officer, now()-interval '85 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, is_prohibited, status, reasons, yard)
    values (v_pkg,'Fake Creams','Counterfeit skincare',40,'Pieces',800,'3304.99','General',
      true,'forfeit','Prohibited Item', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w2, 'B6','Prohibited Item',40, v_officer, now()-interval '78 days',
      true, now()-interval '45 days', v_officer,'[FORFEIT] Counterfeit',0, v_yard);
    insert into public.forfeited_packages (package_id, sr_number, consignee_name, forfeited_at,
      appeal_deadline, reason, source, yard)
    values (v_pkg,'GL1/SR/114/2026','Fake Beauty', now()-interval '45 days',
      now()-interval '15 days','Counterfeit','forfeit', v_yard) returning id into v_fp;
    insert into public.destruction_items (destruction_id, forfeited_package_id, yard, destroyed)
    values (v_de, v_fp, v_yard, false);

  -- ────────────────────────────────────────────────────────────────────────
  -- J) RE-EXPORTED + OTHER dispositions (Re-exported / Other Dispositions screens)
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/115/2026','CASE/2026/115','UK',110000,28.0,1,'Vintage furniture',
    'Antiques Ltd','0711112222','Express Clearers','C5115','2026-03-15', now()-interval '84 days',
    'Documentation Issue','returned', v_officer, now()-interval '83 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Antique Chairs','Vintage seating',8,'Pieces',15000,'9401.61','General',
      're-exported','Documentation Issue', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w3, 'C4','Documentation Issue',8, v_officer, now()-interval '80 days',
      true, now()-interval '10 days', v_officer,'[FINAL:RE-EXPORTED] Returned to origin (UK)',0, v_yard);

  insert into public.packages (sr_number, case_number, origin_country, declared_value,
    weight_kg, total_item_count, description, consignee_name, consignee_phone,
    declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
    inspected_by, inspected_at, yard)
  values ('GL1/SR/116/2026','CASE/2026/116','India',55000,14.0,1,'Government supplies',
    'State Dept','0112223344','Self','C5116','2026-03-18', now()-interval '82 days',
    'Restricted Goods','returned', v_officer, now()-interval '81 days', v_yard)
  returning id into v_pkg;
    insert into public.package_items (package_id, item_name, goods_description, quantity,
      unit_of_measure, unit_value, hs_code, category, status, reasons, yard)
    values (v_pkg,'Office Equipment','Government use',10,'Pieces',5500,'8472.90','General',
      'other','Restricted Goods', v_yard) returning id into v_item;
    insert into public.warehouse_entries (package_id, package_item_id, warehouse_id, zone,
      hold_reason, item_count, admitted_by, admitted_at, is_returned, returned_at, returned_by,
      return_notes, daily_rate, yard)
    values (v_pkg, v_item, v_w1, 'A7','Restricted Goods',10, v_officer, now()-interval '78 days',
      true, now()-interval '8 days', v_officer,'[FINAL:OTHER] Transferred to government use',0, v_yard);

  -- ────────────────────────────────────────────────────────────────────────
  -- K) AUDIT LOGS (a few sample entries)
  -- ────────────────────────────────────────────────────────────────────────
  insert into public.audit_logs (user_id, action, entity_type, entity_id, yard)
  values
    (v_officer,'Registered package','package','GL1/SR/101/2026', v_yard),
    (v_officer,'Released package item','warehouse_entry','GL1/SR/103/2026', v_yard),
    (v_officer,'Marked package forfeited','package','GL1/SR/105/2026', v_yard);

end $$;

commit;

-- ============================================================================
--  Done. Every screen now has live data:
--    Warehouses (held), Released, Abandoned, Forfeited (open/hold/decided),
--    Disposal Requests, Tender Sales (sold/unsold), Sold (delivered/pending),
--    Destructions (destroyed/undestroyed), Re-exported, Other, Taxes, Appeal.
-- ============================================================================
