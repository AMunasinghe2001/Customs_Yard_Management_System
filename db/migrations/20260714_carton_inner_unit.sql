-- ============================================================================
--  Carton inner contents
-- ----------------------------------------------------------------------------
--  When a package item's unit is "Cartons", the registration form also captures
--  what each carton contains (inner unit type) and how many of that inner unit.
--  NULL for any item whose unit is not Cartons.
-- ============================================================================

alter table public.package_items
  add column if not exists inner_unit text;

alter table public.package_items
  add column if not exists inner_quantity int;
