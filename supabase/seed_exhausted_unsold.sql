-- ============================================================================
--  Seed: packages that have exhausted EVERY avenue, so the DG's
--  "Unsold Packages" tab has something to decide on.
--
--  A package reaches that tab only after FIVE tenders have all failed:
--
--      1. Valuation Tender   (priced by the Valuation Directorate)
--      2. Tender 1           ─┐
--      3. Tender 2            ├─ each priced from the previous round's bids
--      4. Tender 3           ─┘
--         → High Panel appoints a tender committee
--         → the committee records its own valuation
--         → the ADG submits that figure as the tender price
--      5. Committee-priced tender   ← THE ROUND THIS SCRIPT ADDS
--
--  Only if round 5 ALSO goes unsold does the DG decide the final outcome
--  (destroy / remand / government use / auction).
--
--  Before this script the seed stopped at step 4 + the ADG's submission, so
--  no package ever satisfied the last condition.
--
--  ADDITIVE and idempotent: it never clears anything and never touches a
--  package that is not already at the "ADG submitted" stage. Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- ── PRE-FLIGHT ───────────────────────────────────────────────────────────────
DO $$
DECLARE missing text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
     WHERE table_schema='public' AND table_name='tender_committees')
  THEN missing := missing || ' tender_committees (20260718_tender_committees.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tender_committees'
       AND column_name='submitted_value')
  THEN missing := missing || ' tender_committees.submitted_value (20260820_committee_valuation.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
     WHERE table_schema='public' AND table_name='unsold_proposals')
  THEN missing := missing || ' unsold_proposals (20260821_unsold_proposals.sql)'; END IF;

  IF missing <> '' THEN
    RAISE EXCEPTION E'Run these migrations first:%', missing;
  END IF;
END $$;

-- ── THE COMMITTEE-PRICED FINAL TENDER ────────────────────────────────────────
DO $$
DECLARE
  v_yard    text := 'GL1';
  v_off     uuid;
  f         record;
  v_sale    uuid;
  v_price   numeric;   -- the ADG's submitted price (what round 5 was offered at)
  v_qty     int;
  v_seq     int := 0;
  v_n       int := 0;
  v_created timestamptz;  -- when the final round was placed
  v_saledt  date;         -- the day it was held
BEGIN
  SELECT id INTO v_off FROM public.profiles
   WHERE yard = v_yard ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN
    SELECT id INTO v_off FROM public.profiles ORDER BY created_at LIMIT 1;
  END IF;

  FOR f IN
    SELECT fp.id, fp.item_id, fp.yard, p.sr_number,
           pi.item_name, pi.quantity,
           tc.submitted_value, tc.submitted_at,
           (SELECT count(*) FROM public.tender_sale_items t
             WHERE t.forfeited_package_id = fp.id) AS rounds_so_far
      FROM public.forfeited_packages fp
      JOIN public.packages p            ON p.id  = fp.package_id
      JOIN public.tender_committees tc  ON tc.forfeited_package_id = fp.id
      LEFT JOIN public.package_items pi ON pi.id = fp.item_id
     -- Only packages the ADG has already submitted a committee valuation for …
     WHERE tc.submitted_value IS NOT NULL
       AND tc.submitted_at IS NOT NULL
       -- … that are still wholly unsold …
       AND NOT EXISTS (
             SELECT 1 FROM public.tender_sale_items t
              WHERE t.forfeited_package_id = fp.id AND t.sold)
       -- … and have NOT yet been tendered again at the committee price.
       AND NOT EXISTS (
             SELECT 1
               FROM public.tender_sale_items t
               JOIN public.tender_sales s ON s.id = t.tender_sale_id
              WHERE t.forfeited_package_id = fp.id
                AND s.created_at > tc.submitted_at)
     ORDER BY p.sr_number, pi.item_name
  LOOP
    v_seq   := v_seq + 1;
    v_qty   := COALESCE(f.quantity, 1);
    v_price := f.submitted_value;

    -- The round was PLACED an hour after the ADG submitted the price (the app
    -- recognises "the committee-priced tender ran" precisely by created_at >
    -- submitted_at) and HELD two days later.
    v_created := f.submitted_at + interval '1 hour';
    v_saledt  := (v_created + interval '2 days')::date;

    -- The sale day must already be past, or the round counts as a PENDING
    -- tender instead of an unsold one and the package never reaches the DG.
    -- If the seed's submission was too recent for that, pull the sale day back
    -- AND move the submission back with it — created_at must stay after
    -- submitted_at or the whole chain breaks.
    IF v_saledt > (now() - interval '2 days')::date THEN
      v_saledt  := (now() - interval '3 days')::date;
      v_created := now() - interval '5 days';

      UPDATE public.tender_committees
         SET submitted_at = v_created - interval '1 hour',
             committee_valued_at =
               LEAST(COALESCE(committee_valued_at, v_created),
                     v_created - interval '2 hours')
       WHERE forfeited_package_id = f.id;
    END IF;

    -- One sale row PER PACKAGE: a shared row could not sit after every
    -- package's own submission time at once.
    SELECT id INTO v_sale FROM public.tender_sales
     WHERE sale_number = 'GL1/TS/2026/F' || lpad(v_seq::text, 2, '0');

    IF v_sale IS NULL THEN
      v_sale := gen_random_uuid();
      INSERT INTO public.tender_sales (
        id, sale_number, sale_date, serial, year, tender_type, yard,
        sale_time, created_by, created_at)
      VALUES (
        v_sale, 'GL1/TS/2026/F' || lpad(v_seq::text, 2, '0'),
        v_saledt, (f.rounds_so_far + 1)::text, 2026, 'general_cargo',
        v_yard, '10:00', v_off, v_created);
    END IF;

    INSERT INTO public.tender_sale_items (
      id, tender_sale_id, forfeited_package_id, package_item_id, yard,
      sold, sold_price, applied_taxes, is_delivered, created_at)
    VALUES (
      gen_random_uuid(), v_sale, f.id, f.item_id, v_yard,
      false, 0, '[]'::jsonb, false, v_created)
    ON CONFLICT DO NOTHING;

    -- Bids came in BELOW even the committee's reduced price — which is why
    -- this last attempt failed too and the goods now need a DG decision.
    INSERT INTO public.tender_bids
      (id, forfeited_package_id, tender_sale_id, amount, yard, created_by, created_at)
    SELECT gen_random_uuid(), f.id, v_sale,
           round((v_price * v_qty * x)::numeric, 2), v_yard, v_off,
           v_saledt + interval '9 hours'
      FROM unnest(ARRAY[0.58, 0.44, 0.31]) AS x;

    v_n := v_n + 1;
    RAISE NOTICE '  % · % → round % held % at LKR %, unsold',
      f.sr_number, COALESCE(f.item_name, '?'), f.rounds_so_far + 1,
      v_saledt, round(v_price * v_qty, 2);
  END LOOP;

  IF v_n = 0 THEN
    RAISE NOTICE 'Nothing to do: no package is at the "ADG submitted" stage '
                 'without an already-run final tender. Submit a committee '
                 'valuation from the High Panel portal first.';
  ELSE
    RAISE NOTICE 'Added the committee-priced FINAL tender for % package(s).', v_n;
  END IF;
END $$;

reset lock_timeout;

-- ── VERIFY: exactly what the DG's Unsold Packages tab should now list ────────
--  Every row here has 5 unsold rounds, a submitted committee value, and a
--  round created after that submission.
SELECT p.sr_number,
       pi.item_name,
       count(DISTINCT tsi.tender_sale_id)            AS tender_rounds,
       bool_and(NOT tsi.sold)                        AS all_unsold,
       tc.submitted_value                            AS adg_submitted_value,
       max(ts.created_at) > tc.submitted_at          AS final_tender_ran,
       up.proposal                                   AS dg_decision
  FROM public.forfeited_packages fp
  JOIN public.packages p              ON p.id  = fp.package_id
  LEFT JOIN public.package_items pi   ON pi.id = fp.item_id
  JOIN public.tender_committees tc    ON tc.forfeited_package_id = fp.id
  JOIN public.tender_sale_items tsi   ON tsi.forfeited_package_id = fp.id
  JOIN public.tender_sales ts         ON ts.id = tsi.tender_sale_id
  LEFT JOIN public.unsold_proposals up ON up.forfeited_package_id = fp.id
 WHERE tc.submitted_value IS NOT NULL
 GROUP BY p.sr_number, pi.item_name, tc.submitted_value, tc.submitted_at,
          up.proposal
HAVING bool_and(NOT tsi.sold)
   AND count(DISTINCT tsi.tender_sale_id) > 4
   AND max(ts.created_at) > tc.submitted_at
 ORDER BY p.sr_number, pi.item_name;
