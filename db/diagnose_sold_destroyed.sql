-- ── DIAGNOSTIC: why don't Sold / Destroyed show anything? ────────────────────
-- Run in the Supabase SQL Editor. Blocks A and B are the decisive ones.

-- ── A. Does the FINAL entry exist, and is it attached to the RIGHT package? ──
--    Every sold/destroyed item must have BOTH:
--      * a returned entry tagged [FINAL:SOLD] / [FINAL:DESTROYED]
--      * package_items.status = 'sold' / 'destroyed'
SELECT 'A. final entries' AS check,
       p.sr_number,
       p.yard              AS pkg_yard,
       w.yard              AS entry_yard,
       w.is_returned,
       pi.status           AS item_status,
       w.hold_reason,
       w.item_count,
       left(w.return_notes, 34) AS note
  FROM public.warehouse_entries w
  JOIN public.packages p       ON p.id  = w.package_id
  LEFT JOIN public.package_items pi ON pi.id = w.package_item_id
 WHERE w.return_notes LIKE '[FINAL:SOLD]%'
    OR w.return_notes LIKE '[FINAL:DESTROYED]%'
 ORDER BY p.sr_number;

-- ── B. THE APP'S ACTUAL QUERY ────────────────────────────────────────────────
--    getAllPackages() selects packages + nested warehouse_entries. If a
--    package shows entries = 0 here, the UI can never render it.
--    final_entries MUST be > 0 for SR 36-41.
SELECT 'B. app query view' AS check,
       p.sr_number,
       p.yard,
       count(w.id)                                                  AS all_entries,
       count(w.id) FILTER (WHERE w.return_notes LIKE '[FINAL:%')    AS final_entries,
       count(w.id) FILTER (WHERE NOT w.is_returned)                 AS still_held
  FROM public.packages p
  LEFT JOIN public.warehouse_entries w ON w.package_id = p.id
 WHERE p.sr_number LIKE '%/36/%' OR p.sr_number LIKE '%/37/%'
    OR p.sr_number LIKE '%/38/%' OR p.sr_number LIKE '%/39/%'
    OR p.sr_number LIKE '%/40/%' OR p.sr_number LIKE '%/41/%'
 GROUP BY p.id, p.sr_number, p.yard
 ORDER BY p.sr_number;

-- ── C. Non-nullable columns the Dart parser casts (must all be 0) ────────────
--    WarehouseEntryModel.fromJson casts hold_reason as String and item_count
--    as int — a NULL in either throws and hides the WHOLE package.
SELECT 'C. nulls (must be 0)' AS check,
       count(*) FILTER (WHERE hold_reason  IS NULL) AS null_hold_reason,
       count(*) FILTER (WHERE item_count   IS NULL) AS null_item_count,
       count(*) FILTER (WHERE warehouse_id IS NULL) AS null_warehouse_id,
       count(*) FILTER (WHERE admitted_at  IS NULL) AS null_admitted_at
  FROM public.warehouse_entries;

-- ── D. The warehouses join: PackageModel needs warehouses(*) to resolve ──────
--    If warehouse_id points at a row that no longer exists, the join yields
--    NULL and warehouseName falls back to '' (not fatal, but worth seeing).
SELECT 'D. orphan warehouse_id' AS check, count(*) AS orphans
  FROM public.warehouse_entries w
  LEFT JOIN public.warehouses wh ON wh.id = w.warehouse_id
 WHERE wh.id IS NULL;

-- ── E. Item status totals ────────────────────────────────────────────────────
SELECT 'E. item statuses' AS check, status, count(*)
  FROM public.package_items
 GROUP BY status
 ORDER BY count(*) DESC;
