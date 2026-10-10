-- ============================================================================
--  Create the zones the item categories point at but that do not exist.
--
--  `fix_category_zones.sql` created the CATEGORIES but several of their zones
--  are missing, so the Items table shows "Building Materials (not defined)"
--  and the category's Target Zone dropdown comes up blank.
--
--  Why the first run missed them: that script inserted the zone with
--  `ON CONFLICT (warehouse_id, name)`, but `warehouse_zones` ALSO carries a
--  unique index on `(warehouse_id, code)`. When the generated code collided
--  with an existing zone's, Postgres raised on the code index — which the
--  ON CONFLICT clause did not cover — and the whole DO block aborted partway,
--  leaving categories without their zones.
--
--  This script creates them one at a time, checking BOTH keys first, so a
--  clash can no longer take the run down with it.
--
--  Idempotent — re-running finds nothing left to create.
-- ============================================================================

set lock_timeout = '5s';

DO $$
DECLARE
  cat      record;
  v_code   text;
  v_try    int;
  v_made   int := 0;
BEGIN
  FOR cat IN
    SELECT DISTINCT c.target_warehouse_id AS wh,
                    trim(c.target_zone)   AS zone_name,
                    w.code                AS wh_code
      FROM public.package_categories c
      JOIN public.warehouses w ON w.id = c.target_warehouse_id
     WHERE c.target_zone IS NOT NULL
       AND trim(c.target_zone) <> ''
       -- Only the ones with no zone of their own.
       AND NOT EXISTS (
             SELECT 1 FROM public.warehouse_zones z
              WHERE z.warehouse_id = c.target_warehouse_id
                AND z.name = trim(c.target_zone))
  LOOP
    -- "<warehouse code>-<zone name>", uppercased and space-free. If that code
    -- is already taken by another zone, add a numeric suffix rather than fail.
    v_code := upper(cat.wh_code || '-' ||
                    regexp_replace(cat.zone_name, '\s+', '', 'g'));
    v_try := 1;
    WHILE EXISTS (SELECT 1 FROM public.warehouse_zones z
                   WHERE z.warehouse_id = cat.wh AND z.code = v_code) LOOP
      v_try  := v_try + 1;
      v_code := upper(cat.wh_code || '-' ||
                      regexp_replace(cat.zone_name, '\s+', '', 'g'))
                || v_try::text;
    END LOOP;

    INSERT INTO public.warehouse_zones
      (warehouse_id, name, code, capacity, description)
    VALUES (cat.wh, cat.zone_name, v_code, 3000,
            'Zone for the ' || cat.zone_name || ' category');

    v_made := v_made + 1;
    RAISE NOTICE 'Created zone % (%) in %', cat.zone_name, v_code, cat.wh_code;
  END LOOP;

  RAISE NOTICE 'Created % missing zone(s).', v_made;
END $$;

-- ── Move the goods into the zone their category names ───────────────────────
--  Now that every zone exists, the entries can follow their category.
UPDATE public.warehouse_entries we
   SET warehouse_id = c.target_warehouse_id,
       zone         = c.target_zone
  FROM public.package_items pi
  JOIN public.package_categories c ON c.name = pi.category
  JOIN public.warehouse_zones z    ON z.warehouse_id = c.target_warehouse_id
                                  AND z.name = c.target_zone
 WHERE we.package_item_id = pi.id
   AND we.is_returned = false
   AND (we.zone IS DISTINCT FROM c.target_zone
        OR we.warehouse_id IS DISTINCT FROM c.target_warehouse_id);

reset lock_timeout;

-- ── VERIFY: `zone_exists` must be true for every row ────────────────────────
SELECT c.name                                  AS category,
       w.name                                  AS warehouse,
       c.target_zone,
       (z.id IS NOT NULL)                      AS zone_exists,
       z.capacity,
       (SELECT count(*) FROM public.package_items pi
         WHERE pi.category = c.name)           AS goods,
       (SELECT coalesce(sum(we.item_count), 0)
          FROM public.warehouse_entries we
         WHERE we.warehouse_id = c.target_warehouse_id
           AND trim(we.zone)   = c.target_zone
           AND we.is_returned  = false)        AS items_in_zone
  FROM public.package_categories c
  LEFT JOIN public.warehouses w      ON w.id = c.target_warehouse_id
  LEFT JOIN public.warehouse_zones z ON z.warehouse_id = c.target_warehouse_id
                                    AND z.name = c.target_zone
 WHERE c.target_zone IS NOT NULL
 ORDER BY zone_exists, w.name, c.target_zone;
