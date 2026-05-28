-- Add RLS policy for admins to manage warehouses
-- This fixes the "row-level security policy" error when adding/editing warehouses

CREATE POLICY "Admins can manage warehouses" ON warehouses
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );
