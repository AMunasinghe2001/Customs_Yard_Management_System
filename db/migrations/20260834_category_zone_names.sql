-- ============================================================================
--  Item categories point at a zone by NAME.
--
--  The category form used to offer a hardcoded "Zone 1 … Zone 10" list that
--  had nothing to do with the real zones, and stored the label verbatim
--  ("Zone 3"). Now it lists the actual rows of `warehouse_zones`, so
--  `package_categories.target_zone` must hold the zone's own NAME.
--
--  This normalises the legacy values:
--    1. Strip the "Zone " prefix where the warehouse has a zone by the bare
--       name ("Zone 3" -> "3" when zone "3" exists).
--    2. Otherwise create the missing zone, so a category that was pointing
--       somewhere keeps pointing there rather than silently losing its target.
--
--  Run AFTER 20260832_warehouse_zones.sql and 20260833_warehouse_zone_code.sql.
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── "Zone 3" -> "3" where that zone already exists ───────────────────────
update public.package_categories c
   set target_zone = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
 where c.target_zone is not null
   and c.target_zone ~ '^[Zz]one\s+'
   and exists (
     select 1 from public.warehouse_zones z
      where z.warehouse_id = c.target_warehouse_id
        and z.name = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
   );

-- 2. ── Create any zone a category still names but the warehouse lacks ───────
--    Capacity starts at 500 — the admin sets the real figure; leaving the
--    category pointing at nothing would be worse than a placeholder.
insert into public.warehouse_zones (warehouse_id, name, code, capacity, description)
select distinct
       c.target_warehouse_id,
       trim(regexp_replace(c.target_zone, '^[Zz]one\s+', '')),
       upper(w.code || '-' ||
             regexp_replace(
               trim(regexp_replace(c.target_zone, '^[Zz]one\s+', '')),
               '\s+', '', 'g')),
       500,
       'Created from an item category that referenced it'
  from public.package_categories c
  join public.warehouses w on w.id = c.target_warehouse_id
 where c.target_zone is not null
   and trim(c.target_zone) <> ''
   and not exists (
     select 1 from public.warehouse_zones z
      where z.warehouse_id = c.target_warehouse_id
        and z.name = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
   )
on conflict (warehouse_id, name) do nothing;

-- 3. ── Now every category can be normalised ─────────────────────────────────
update public.package_categories c
   set target_zone = trim(regexp_replace(c.target_zone, '^[Zz]one\s+', ''))
 where c.target_zone is not null
   and c.target_zone ~ '^[Zz]one\s+';

reset lock_timeout;

-- ── VERIFY: every category's zone should resolve to a real one ──────────────
select c.name                          as category,
       w.name                          as warehouse,
       c.target_zone,
       (z.id is not null)              as zone_exists,
       z.capacity
  from public.package_categories c
  left join public.warehouses w      on w.id = c.target_warehouse_id
  left join public.warehouse_zones z on z.warehouse_id = c.target_warehouse_id
                                    and z.name = c.target_zone
 where c.target_zone is not null
 order by w.code, c.target_zone;
