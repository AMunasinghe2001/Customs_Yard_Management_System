-- Seed comprehensive dummy data for SR Registration and Forfeit flow
-- This script adds a variety of packages with different statuses and dates

-- Clear existing data (optional, but good for a clean state)
-- TRUNCATE tenders, forfeited_packages, package_items, packages CASCADE;

-- Insert 20+ packages
INSERT INTO packages (
    sr_number, case_number, origin_country, declared_value, weight_kg, 
    description, consignee_name, consignee_nic, consignee_address, consignee_phone, 
    declarant_name, cusdec_no, cusdec_date, entry_date, status
) VALUES
-- 1. Pending Packages (Recent)
('GL1/SR/01/2025', 'CASE/2025/001', 'India', 50000.00, 15.5, 'Electronics and spare parts', 'John Doe Imports', '197856123V', '123 Main St, Colombo', '0712345678', 'FastTrack Logistics', 'C1001', '2025-01-10', NOW() - INTERVAL '2 days', 'pending'),
('GL1/SR/02/2025', 'CASE/2025/002', 'China', 120000.00, 45.0, 'Plastic kitchenware', 'Global Tradings', '198012345V', '45 Galle Rd, Wellawatte', '0771234567', 'Express Clearers', 'C1002', '2025-01-11', NOW() - INTERVAL '3 days', 'pending'),
('GL1/SR/03/2025', '', 'Dubai', 35000.00, 8.2, 'Gift items and chocolates', 'Personal Cargo', '200145678V', '88 Negombo Rd, Ja-Ela', '0112345678', 'Self', 'C1003', '2025-01-12', NOW() - INTERVAL '1 day', 'pending'),

-- 2. Detained Packages (Under 30 days, not yet forfeited)
('GL1/SR/04/2025', 'CASE/2025/044', 'Japan', 250000.00, 120.0, 'Car engine parts', 'Auto Hub (Pvt) Ltd', '199956789V', 'Kandy Road, Kelaniya', '0721234567', 'Pro Logistics', 'C2004', '2024-12-25', NOW() - INTERVAL '15 days', 'detained'),
('GL1/SR/05/2025', 'CASE/2025/045', 'UK', 75000.00, 12.0, 'Used clothing and shoes', 'Green Valley Boutique', '198734567V', 'Cross Street, Pettah', '0751234567', 'City Clearers', 'C2005', '2024-12-28', NOW() - INTERVAL '12 days', 'detained'),

-- 3. Forfeited Packages - Appealing (Under 30 days since entry)
('GL1/SR/06/2025', 'CASE/2025/066', 'USA', 90000.00, 20.0, 'Computer accessories', 'Tech World', '200067890V', 'Liberty Plaza, Colombo 03', '0761234567', 'FastTrack Logistics', 'C3006', '2025-01-01', NOW() - INTERVAL '10 days', 'forfeited'),
('GL1/SR/07/2025', 'CASE/2025/067', 'Singapore', 60000.00, 15.0, 'Mobile phone screens', 'Smart Fix', '199812345V', 'Unity Plaza, Colombo 04', '0701234567', 'Express Clearers', 'C3007', '2025-01-02', NOW() - INTERVAL '8 days', 'forfeited'),

-- 4. Forfeited Packages - Expired (Over 30 days since entry)
('GL1/SR/08/2024', 'CASE/2024/288', 'China', 450000.00, 500.0, 'Industrial machinery parts', 'Factory Solutions', '198245678V', 'Biyagama FTZ', '0719876543', 'Pro Logistics', 'C8008', '2024-11-20', NOW() - INTERVAL '45 days', 'forfeited'),
('GL1/SR/09/2024', 'CASE/2024/289', 'India', 30000.00, 25.0, 'Cotton fabrics', 'Sun Tex', '197934567V', 'Pamunuwa, Maharagama', '0779876543', 'Self', 'C8009', '2024-11-25', NOW() - INTERVAL '40 days', 'forfeited'),
('GL1/SR/10/2024', 'CASE/2024/290', 'Dubai', 15000.00, 5.0, 'Cosmetic products', 'Beauty Care', '200156789V', 'Reid Avenue, Colombo 07', '0759876543', 'City Clearers', 'C8010', '2024-11-15', NOW() - INTERVAL '50 days', 'forfeited'),

-- More Forfeited - Expired for Tender testing
('GL1/SR/11/2024', 'CASE/2024/301', 'UK', 120000.00, 60.0, 'Vintage furniture items', 'Antiques Ltd', '198712345V', 'Gregorys Road, Colombo 07', '0711112222', 'Express Clearers', 'C8011', '2024-11-01', NOW() - INTERVAL '60 days', 'forfeited'),
('GL1/SR/12/2024', 'CASE/2024/302', 'Japan', 85000.00, 40.0, 'Audio equipment', 'Sound Systems', '199023456V', 'Duplication Rd, Col 03', '0773334444', 'Pro Logistics', 'C8012', '2024-11-05', NOW() - INTERVAL '55 days', 'forfeited'),
('GL1/SR/13/2024', 'CASE/2024/303', 'Germany', 200000.00, 110.0, 'Medical supply samples', 'Health Care Pvt', '198945678V', 'Baseline Rd, Col 09', '0112223334', 'City Clearers', 'C8013', '2024-11-10', NOW() - INTERVAL '52 days', 'forfeited'),
('GL1/SR/14/2024', 'CASE/2024/304', 'Thailand', 45000.00, 30.0, 'Spices and food items', 'Foodie Paradise', '200178901V', 'Cross Street, Col 11', '0755556666', 'FastTrack Logistics', 'C8014', '2024-11-12', NOW() - INTERVAL '51 days', 'forfeited'),
('GL1/SR/15/2024', 'CASE/2024/305', 'Malaysia', 95000.00, 75.0, 'Hardware tools', 'Tools & More', '199556789V', 'Sangeraja Mawatha, Col 10', '0766667777', 'Self', 'C8015', '2024-11-18', NOW() - INTERVAL '42 days', 'forfeited'),

-- 5. Tendered Packages (Already in a tender)
('GL1/SR/16/2024', 'CASE/2024/316', 'China', 300000.00, 200.0, 'Building materials', 'Mega Builders', '198067890V', 'Nawala Road, Rajagiriya', '0718889999', 'Express Clearers', 'C9016', '2024-10-15', NOW() - INTERVAL '80 days', 'forfeited'),
('GL1/SR/17/2024', 'CASE/2024/317', 'India', 12000.00, 4.0, 'Leather bags', 'Fashion Way', '199178901V', 'Major Place, Col 04', '0770001111', 'City Clearers', 'C9017', '2024-10-20', NOW() - INTERVAL '75 days', 'forfeited'),
('GL1/SR/18/2024', 'CASE/2024/318', 'Dubai', 55000.00, 22.0, 'Perfumes and oils', 'Aroma World', '200234567V', 'Main St, Col 11', '0752223333', 'FastTrack Logistics', 'C9018', '2024-10-25', NOW() - INTERVAL '70 days', 'forfeited'),

-- Additional Packages to reach 20+
('GL1/SR/19/2025', '', 'Singapore', 25000.00, 10.0, 'Stationery items', 'Edu Mart', '200301234V', 'Havelock Rd, Col 5', '0754445555', 'Express Clearers', 'C1019', '2025-01-05', NOW() - INTERVAL '5 days', 'pending'),
('GL1/SR/20/2025', 'CASE/2025/120', 'China', 180000.00, 80.0, 'Electric fans', 'Cool Air', '199945678V', 'Pagoda Rd, Nugegoda', '0715556666', 'Pro Logistics', 'C1020', '2025-01-08', NOW() - INTERVAL '2 days', 'detained'),
('GL1/SR/21/2024', 'CASE/2024/320', 'Vietnam', 40000.00, 35.0, 'Handmade crafts', 'Heritage Shops', '198556789V', 'Galle Face Green', '0776667777', 'Self', 'C8021', '2024-11-28', NOW() - INTERVAL '38 days', 'forfeited');

-- Insert Package Items for all packages
-- We'll use a subquery to match SR numbers to package IDs
DO $$
DECLARE
    p_record RECORD;
BEGIN
    FOR p_record IN SELECT id, sr_number, description FROM packages LOOP
        INSERT INTO package_items (package_id, item_name, quantity, unit_value, category, reasons)
        VALUES (p_record.id, COALESCE('Main ' || p_record.description, 'Main Items for ' || p_record.sr_number), 1, 1000, 'General', 'Undisclosed');
        
        -- Add a second item for some packages
        IF p_record.sr_number LIKE '%/01/%' OR p_record.sr_number LIKE '%/08/%' OR p_record.sr_number LIKE '%/11/%' THEN
            INSERT INTO package_items (package_id, item_name, quantity, unit_value, category, reasons)
            VALUES (p_record.id, 'Secondary Item for ' || p_record.sr_number, 5, 200, 'Spare Parts', 'Weight mismatch');
        END IF;
    END LOOP;
END $$;

-- Link Forfeited Packages
-- Only the ones status='forfeited' should be in forfeited_packages table (if we want them to show in the manager)
INSERT INTO forfeited_packages (package_id, sr_number, consignee_name, forfeited_at, appeal_deadline, reason)
SELECT id, sr_number, consignee_name, entry_date + INTERVAL '14 days', entry_date + INTERVAL '44 days', 'Unclaimed after 14 days detention'
FROM packages 
WHERE status = 'forfeited';

-- Insert a Tender for the "tendered" packages
INSERT INTO tenders (tender_number, tender_date, forfeited_package_ids, created_by)
VALUES (
    'T/2025/JAN/01',
    NOW() - INTERVAL '5 days',
    ARRAY(
        SELECT fp.id::text
        FROM forfeited_packages fp
        JOIN packages p ON fp.package_id = p.id
        WHERE p.sr_number IN ('GL1/SR/16/2024', 'GL1/SR/17/2024', 'GL1/SR/18/2024')
    ),
    NULL
);
