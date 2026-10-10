-- Insert dummy forfeited packages data
-- This script adds test data to help visualize the forfeited packages screen

-- First, get some existing packages to use as references
-- You may need to adjust the package IDs based on what actually exists in your packages table

-- Insert packages still within appeal period (forfeited 15-20 days ago)
INSERT INTO forfeited_packages (id, package_id, sr_number, consignee_name, forfeited_at, appeal_deadline, reason, created_at, updated_at)
VALUES
  (
    gen_random_uuid(),
    (SELECT id FROM packages LIMIT 1 OFFSET 0),
    'SR-2026-00105',
    'ABC Trading Company Ltd',
    NOW() - INTERVAL '15 days',
    NOW() + INTERVAL '15 days',
    'Non-compliant documentation',
    NOW(),
    NOW()
  ),
  (
    gen_random_uuid(),
    (SELECT id FROM packages LIMIT 1 OFFSET 1),
    'SR-2026-00106',
    'XYZ Imports Pvt Ltd',
    NOW() - INTERVAL '18 days',
    NOW() + INTERVAL '12 days',
    'Expired permits',
    NOW(),
    NOW()
  ),
  (
    gen_random_uuid(),
    (SELECT id FROM packages LIMIT 1 OFFSET 2),
    'SR-2026-00107',
    'Global Logistics Co',
    NOW() - INTERVAL '20 days',
    NOW() + INTERVAL '10 days',
    'Restricted items detected',
    NOW(),
    NOW()
  ),
  -- Insert packages with expired appeals (forfeited 35-45 days ago)
  (
    gen_random_uuid(),
    (SELECT id FROM packages LIMIT 1 OFFSET 3),
    'SR-2026-00102',
    'Prime Importers Inc',
    NOW() - INTERVAL '35 days',
    NOW() - INTERVAL '5 days',
    'Missing customs declaration',
    NOW(),
    NOW()
  ),
  (
    gen_random_uuid(),
    (SELECT id FROM packages LIMIT 1 OFFSET 4),
    'SR-2026-00103',
    'Metro Trade Solutions',
    NOW() - INTERVAL '40 days',
    NOW() - INTERVAL '10 days',
    'Undervalued goods',
    NOW(),
    NOW()
  ),
  (
    gen_random_uuid(),
    (SELECT id FROM packages LIMIT 1 OFFSET 5),
    'SR-2026-00104',
    'Universal Shipping Ltd',
    NOW() - INTERVAL '45 days',
    NOW() - INTERVAL '15 days',
    'Prohibited items found',
    NOW(),
    NOW()
  );

-- Verify the inserts
SELECT 
  id,
  sr_number,
  consignee_name,
  forfeited_at,
  appeal_deadline,
  CASE 
    WHEN appeal_deadline < NOW() THEN 'EXPIRED'
    ELSE 'APPEALING'
  END as status,
  EXTRACT(DAY FROM (appeal_deadline - NOW()))::int as days_remaining
FROM forfeited_packages
ORDER BY forfeited_at DESC;
