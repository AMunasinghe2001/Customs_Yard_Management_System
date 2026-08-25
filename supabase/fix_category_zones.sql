-- ============================================================================
--  Give every goods item a CATEGORY, and point each category at a real zone.
--
--  The seeded goods were admitted straight into zones 'A' / 'B' / 'C' with no
--  category, so the Items table showed nothing for them and the zones they
--  occupy matched no category at all.
--
--  This script:
--    1. Creates the categories the goods actually need, each targeting a REAL
--       `warehouse_zones` row (creating the zone if it does not exist yet).
--    2. Sets `package_items.category` on every item that has none, matched on
--       its HS chapter first, then on keywords in its name.
--    3. Re-points the existing 'A' / 'B' / 'C' warehouse entries at the zone
--       its item's category now names, so what the goods occupy and what the
--       category says agree.
--
--  Run AFTER:
--      20260832_warehouse_zones.sql
--      20260833_warehouse_zone_code.sql
--      20260834_category_zone_names.sql
--
--  Idempotent — re-running finds nothing left to change.
-- ============================================================================

set lock_timeout = '5s';

--  Deliberately NOT wrapped in BEGIN/COMMIT: the Supabase SQL editor already
--  runs a whole execution in one transaction, so a nested BEGIN is ignored and
--  any error rolls the ENTIRE run back — which is how an earlier attempt left
--  categories created but their zones missing. Each statement standing alone
--  means a failure costs only that statement.

-- ── 1. The categories, and the zone each one owns ───────────────────────────
--  One zone per category (the app enforces that in the picker), spread across
--  the warehouses so no single one takes everything.
DO $$
DECLARE
  spec record;
  v_wh      uuid;
  v_wh_code text;
  v_code    text;
  v_try     int;
  v_made    int := 0;
BEGIN
  FOR spec IN
    SELECT * FROM (VALUES
      -- category name              warehouse code, zone name,   capacity
      ('Vehicle Parts and Tyres',   'W01', 'Vehicle Parts',      3000),
      ('Machinery and Tools',       'W01', 'Machinery',          3000),
      ('Building Materials',        'W01', 'Building Materials', 3000),
      ('Electrical and Electronic', 'W02', 'Electrical',         3000),
      ('Household and Furniture',   'W02', 'Household',          3000),
      ('Textiles and Apparel',      'W02', 'Textiles',           3000),
      ('Chemicals and Paints',      'W03', 'Chemicals',          2000),
      ('Plastics and Rubber',       'W03', 'Plastics',           3000),
      ('Food and Consumables',      'W03', 'Food',               2000),
      ('General Goods',             'W03', 'General',            4000)
    ) AS t(cat_name, wh_code, zone_name, capacity)
  LOOP
    SELECT id INTO v_wh FROM public.warehouses WHERE code = spec.wh_code;
    -- Fall back to any warehouse so the script still runs on a differently
    -- coded database rather than silently skipping every category.
    IF v_wh IS NULL THEN
      SELECT id INTO v_wh FROM public.warehouses ORDER BY code LIMIT 1;
    END IF;
    CONTINUE WHEN v_wh IS NULL;

    -- The zone this category will target.
    --
    -- Checked explicitly rather than with ON CONFLICT: `warehouse_zones` has
    -- TWO unique keys — (warehouse_id, name) and (warehouse_id, code) — and an
    -- ON CONFLICT clause can only name one. A clash on the other raised an
    -- error that aborted the whole DO block, leaving later categories without
    -- their zones. A colliding code now takes a numeric suffix instead.
    IF EXISTS (SELECT 1 FROM public.warehouse_zones
                WHERE warehouse_id = v_wh AND name = spec.zone_name) THEN
      UPDATE public.warehouse_zones
         SET capacity = GREATEST(capacity, spec.capacity)
       WHERE warehouse_id = v_wh AND name = spec.zone_name;
    ELSE
      SELECT code INTO v_wh_code FROM public.warehouses WHERE id = v_wh;
      v_code := upper(v_wh_code || '-' ||
                      regexp_replace(spec.zone_name, '\s+', '', 'g'));
      v_try := 1;
      WHILE EXISTS (SELECT 1 FROM public.warehouse_zones
                     WHERE warehouse_id = v_wh AND code = v_code) LOOP
        v_try  := v_try + 1;
        v_code := upper(v_wh_code || '-' ||
                        regexp_replace(spec.zone_name, '\s+', '', 'g'))
                  || v_try::text;
      END LOOP;

      INSERT INTO public.warehouse_zones
        (warehouse_id, name, code, capacity, description)
      VALUES (v_wh, spec.zone_name, v_code, spec.capacity,
              'Zone for ' || spec.cat_name);
    END IF;

    -- The category itself. Matched by NAME without ON CONFLICT: this table
    -- may carry no unique constraint on `name`, and inferring one that does
    -- not exist would abort the whole script.
    IF EXISTS (SELECT 1 FROM public.package_categories
                WHERE name = spec.cat_name) THEN
      UPDATE public.package_categories
         SET target_warehouse_id = v_wh,
             target_zone         = spec.zone_name
       WHERE name = spec.cat_name;
    ELSE
      INSERT INTO public.package_categories
        (name, description, target_warehouse_id, target_zone)
      VALUES (spec.cat_name,
              'Goods of this kind are held in the ' || spec.zone_name
                || ' zone',
              v_wh, spec.zone_name);
    END IF;

    v_made := v_made + 1;
  END LOOP;

  RAISE NOTICE 'Ensured % categories, each with its own zone.', v_made;
END $$;

-- ── 2. Categorise every item that has none ──────────────────────────────────
--  HS chapter first (it is the authoritative classification), then keywords in
--  the goods name for anything the chapter did not settle.
UPDATE public.package_items pi
   SET category = CASE
     -- ── By HS chapter ──────────────────────────────────────────────
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          IN ('84','85')                    THEN 'Electrical and Electronic'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          IN ('86','87','88','89')          THEN 'Vehicle Parts and Tyres'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          IN ('72','73','74','76','82','83') THEN 'Machinery and Tools'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          IN ('68','69','70')               THEN 'Building Materials'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          IN ('28','29','32','34','38')     THEN 'Chemicals and Paints'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          IN ('39','40')                    THEN 'Plastics and Rubber'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          BETWEEN '50' AND '63'             THEN 'Textiles and Apparel'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          IN ('44','94')                    THEN 'Household and Furniture'
     WHEN left(regexp_replace(coalesce(pi.hs_code, ''), '\D', '', 'g'), 2)
          BETWEEN '01' AND '24'             THEN 'Food and Consumables'

     -- ── By keyword, for anything the HS code did not settle ─────────
     WHEN pi.item_name ~* '(tyre|tire|vehicle|brake|clutch|crankshaft|engine|gasket|bearing|filter|wiper|axle|piston)' THEN 'Vehicle Parts and Tyres'
     WHEN pi.item_name ~* '(paint|thinner|solvent|chemical|adhesive|lubricant|acid|resin)' THEN 'Chemicals and Paints'
     WHEN pi.item_name ~* '(cable|wire|switch|electr|electronic|lamp|light|battery|keyboard|mouse|laptop|hub|circuit|pcb|charger|adapter)' THEN 'Electrical and Electronic'
     WHEN pi.item_name ~* '(chair|table|furniture|sofa|drawer|cabinet|linen|dinner|cutlery|pot|crockery|melamine|ceiling fan)' THEN 'Household and Furniture'
     WHEN pi.item_name ~* '(fabric|textile|cloth|garment|curtain|sack|net|apparel|cotton|polyester|nylon)' THEN 'Textiles and Apparel'
     WHEN pi.item_name ~* '(tile|cement|steel|roofing|sanitary|basin|bathroom|conduit|pipe)' THEN 'Building Materials'
     WHEN pi.item_name ~* '(plastic|pvc|rubber|polypropylene|crate|bottle|hose|mat)' THEN 'Plastics and Rubber'
     WHEN pi.item_name ~* '(tool|jack|machine|equipment|instrument|hardware|spanner)' THEN 'Machinery and Tools'
     WHEN pi.item_name ~* '(food|noodle|juice|beverage|snack|grocer|edible)' THEN 'Food and Consumables'
     -- Toys, cosmetics and stationery are consumer goods, not foodstuffs.
     WHEN pi.item_name ~* '(toy|perfum|cosmetic|stationer|carton|tape|foil)' THEN 'General Goods'
     ELSE 'General Goods'
   END
 WHERE pi.category IS NULL OR trim(pi.category) = '';

-- ── 3. Move the goods into the zone their category names ────────────────────
--  Only entries still held, and only where the category resolves to a real
--  zone — a returned entry is history and must not be rewritten.
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

-- ── VERIFY 1: every category, its zone, and how many goods use it ───────────
SELECT c.name                                  AS category,
       w.name                                  AS warehouse,
       c.target_zone,
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
 ORDER BY w.name, c.target_zone;

-- ── VERIFY 2: nothing should be listed — every item now has a category ──────
-- SELECT count(*) AS goods_without_category
--   FROM public.package_items
--  WHERE category IS NULL OR trim(category) = '';
