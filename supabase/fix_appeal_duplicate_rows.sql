-- ============================================================================
--  One SR showing the same goods over and over in the Appeal Directorate.
--
--  The portal expands a PACKAGE-level `forfeited_packages` row (item_id IS
--  NULL) into one row per package item, because such a row stands for the
--  whole package. That is right when there is ONE of them. When an SR has
--  several — an older package-level row plus newer per-item ones, or the same
--  package forfeited more than once — every one of them expands into every
--  item and the list multiplies:
--
--      3 package-level rows x 3 items = 9 rows for 3 goods
--
--  This script normalises the table to ONE row per (package, item):
--
--    1. A package-level row is replaced by per-item rows, one for each item
--       genuinely forfeited, carrying its appeal state across.
--    2. Exact duplicates of the same (package, item) collapse to the row that
--       carries the most appeal state (a hold or a decision always wins over
--       an untouched row); ties break on the newest.
--
--  Run `diagnose_appeal_duplicates.sql` query 1 first to see what will change.
--  Idempotent — re-running finds nothing left to do.
-- ============================================================================

set lock_timeout = '5s';

BEGIN;

-- ── 1. Package-level rows → one row per genuinely-forfeited item ─────────────
DO $$
DECLARE
  fp        record;
  it        record;
  v_made    int := 0;
  v_dropped int := 0;
BEGIN
  FOR fp IN
    SELECT f.*
      FROM public.forfeited_packages f
     WHERE f.item_id IS NULL
       -- Only worth splitting when the package actually holds items.
       AND EXISTS (SELECT 1 FROM public.package_items pi
                    WHERE pi.package_id = f.package_id)
  LOOP
    FOR it IN
      SELECT pi.id, pi.quantity
        FROM public.package_items pi
       WHERE pi.package_id = fp.package_id
    LOOP
      -- Never create a second row for an item that already has one.
      IF EXISTS (SELECT 1 FROM public.forfeited_packages x
                  WHERE x.package_id = fp.package_id
                    AND x.item_id    = it.id) THEN
        CONTINUE;
      END IF;

      INSERT INTO public.forfeited_packages (
        id, package_id, item_id, entry_qty, sr_number, consignee_name,
        forfeited_at, appeal_deadline, reason, yard, source,
        appeal_hold, appeal_hold_note, appeal_held_at, held_item_ids,
        appeal_decision, appeal_decision_note, appeal_decided_at,
        created_at)
      VALUES (
        gen_random_uuid(), fp.package_id, it.id,
        COALESCE(fp.entry_qty, it.quantity),
        fp.sr_number, fp.consignee_name,
        fp.forfeited_at, fp.appeal_deadline, fp.reason, fp.yard, fp.source,
        fp.appeal_hold, fp.appeal_hold_note, fp.appeal_held_at,
        -- The hold named the package's items; scope it to THIS item.
        CASE WHEN fp.appeal_hold THEN ARRAY[it.id]::uuid[] ELSE NULL END,
        fp.appeal_decision, fp.appeal_decision_note, fp.appeal_decided_at,
        fp.created_at);

      v_made := v_made + 1;
    END LOOP;

    DELETE FROM public.forfeited_packages WHERE id = fp.id;
    v_dropped := v_dropped + 1;
  END LOOP;

  RAISE NOTICE 'Split % package-level rows into % per-item rows.',
    v_dropped, v_made;
END $$;

-- ── 2. Collapse duplicates of the same (package, item) ──────────────────────
--  Keep the row carrying the most appeal state: a decision beats a hold, a
--  hold beats an untouched row, and the newest breaks a tie. Losing rows are
--  deleted, so an appeal already recorded is never the one thrown away.
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY package_id, item_id
           ORDER BY (appeal_decision IS NOT NULL) DESC,
                    appeal_hold                   DESC,
                    created_at                    DESC,
                    id                            DESC
         ) AS rn
    FROM public.forfeited_packages
   WHERE item_id IS NOT NULL
)
DELETE FROM public.forfeited_packages fp
 USING ranked r
 WHERE fp.id = r.id
   AND r.rn > 1;

COMMIT;

reset lock_timeout;

-- ── VERIFY: nothing should be listed ────────────────────────────────────────
SELECT p.sr_number,
       count(*)                                       as fp_rows,
       count(*) filter (where fp.item_id is null)     as package_level_rows,
       (select count(*) from public.package_items pi
         where pi.package_id = p.id)                  as items_in_package
  FROM public.forfeited_packages fp
  JOIN public.packages p on p.id = fp.package_id
 GROUP BY p.sr_number, p.id
HAVING count(*) filter (where fp.item_id is null) > 0
    OR count(*) > (select count(*) from public.package_items pi
                    where pi.package_id = p.id)
 ORDER BY p.sr_number;
