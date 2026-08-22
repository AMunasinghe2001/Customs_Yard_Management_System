-- ============================================================================
--  Seed: appeal scenarios across EVERY status.
--
--  The 30-day appeal window is no longer forfeit-only — Detain, Abandoned and
--  "Other" goods are frozen for the same 30 days, counted from their ENTRY
--  DATE. This gives you something to look at in each state:
--
--    A. IN THE WINDOW  (chip "Appealing · Nd", actions blocked)
--         · a Detain package        · an Abandoned package
--         · an "Other" package      · a Forfeit package
--       Entry dates are set a few days ago so the window is genuinely live.
--
--    B. WINDOW PASSED  (chip "Enabled", actions allowed)
--         one package per status, entered well over 30 days ago.
--
--    C. APPEAL LODGED  — ON APPEAL HOLD, one per status
--       (Forfeit · Detain · Abandoned · Other). These show "On Appeal Hold"
--       and cannot be sold or destroyed.
--
--    D. APPEAL DECIDED — the four outcomes, spread across the statuses:
--       Forfeit→RELEASE · Detain→SALE · Abandoned→DESTROY · Other→RE-EXPORT.
--
--  ADDITIVE and idempotent: it creates its OWN SRs (GL1/SR/6x/2026) and never
--  touches existing data. Re-running updates the same rows rather than
--  duplicating them. Delete them again with the query at the bottom.
-- ============================================================================

set lock_timeout = '5s';

-- ── PRE-FLIGHT ───────────────────────────────────────────────────────────────
DO $$
DECLARE missing text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='forfeited_packages'
       AND column_name='appeal_hold')
  THEN missing := missing || ' forfeited_packages.appeal_hold (20260613_appeal_directorate.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='forfeited_packages'
       AND column_name='appeal_decision')
  THEN missing := missing || ' forfeited_packages.appeal_decision (20260614_appeal_decision.sql)'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='forfeited_packages'
       AND column_name='source')
  THEN missing := missing || ' forfeited_packages.source'; END IF;

  IF missing <> '' THEN
    RAISE EXCEPTION E'Run these migrations first:%', missing;
  END IF;
END $$;

-- ── SEED ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_yard   text := 'GL1';
  v_off    uuid;
  v_wh     uuid;
  v_zone   text;

  -- One scenario per row: SR suffix, goods, HS, qty, unit value, status,
  -- how many days ago it entered, and which appeal state to put it in.
  r        record;

  v_pkg    uuid;
  v_item   uuid;
  v_entry  uuid;
  v_fp     uuid;
  v_sr     text;
  v_case   text;
  v_entdt  date;
  v_n      int := 0;
BEGIN
  SELECT id INTO v_off FROM public.profiles
   WHERE yard = v_yard ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN
    SELECT id INTO v_off FROM public.profiles ORDER BY created_at LIMIT 1;
  END IF;
  IF v_off IS NULL THEN
    RAISE EXCEPTION 'No profile found — create a yard officer first.';
  END IF;

  SELECT id INTO v_wh FROM public.warehouses
   WHERE yard = v_yard ORDER BY name LIMIT 1;
  IF v_wh IS NULL THEN
    SELECT id INTO v_wh FROM public.warehouses ORDER BY name LIMIT 1;
  END IF;
  IF v_wh IS NULL THEN
    RAISE EXCEPTION 'No warehouse found — create one first.';
  END IF;
  -- `zone` is a plain text column on warehouse_entries (there is no zones
  -- table); reuse whatever zone this warehouse already holds goods in.
  SELECT zone INTO v_zone FROM public.warehouse_entries
   WHERE warehouse_id = v_wh AND zone IS NOT NULL
   ORDER BY admitted_at DESC LIMIT 1;

  FOR r IN
    SELECT * FROM (VALUES
      -- sr , goods                    , hs          , qty, val  , status     , days_ago, state
      (61, 'Ceramic Floor Tiles'       , '6907.21.00', 240,  1850, 'Detain'   ,  4, 'window'),
      (62, 'Polyester Curtain Fabric'  , '5407.61.00', 180,  2400, 'Abandoned',  7, 'window'),
      (63, 'Assorted Hand Tools'       , '8205.59.00',  95,  3100, 'Other'    ,  9, 'window'),
      (64, 'Stainless Steel Sinks'     , '7324.10.00',  60,  8700, 'Forfeit'  , 12, 'window'),
      (65, 'Copper Wire Coils'         , '7408.11.00', 130,  5400, 'Detain'   , 95, 'passed'),
      (66, 'Plastic Storage Crates'    , '3923.10.00', 320,   950, 'Abandoned', 88, 'passed'),
      (67, 'Garden Hose Reels'         , '3917.32.00', 140,  1650, 'Other'    , 76, 'passed'),
      (68, 'Aluminium Window Frames'   , '7610.10.00',  75,  6200, 'Forfeit'  , 70, 'passed'),
      -- APPEAL LODGED (hold) — one per status, all inside their window.
      (69, 'Industrial Bearings'       , '8482.10.00', 200,  4300, 'Forfeit'  , 15, 'hold'),
      (70, 'Rubber Conveyor Belting'   , '4010.12.00',  55,  9100, 'Detain'   , 11, 'hold'),
      (71, 'Woven Polypropylene Sacks' , '6305.33.00', 500,   420, 'Abandoned',  8, 'hold'),
      (72, 'Assorted Ceramic Basins'   , '6910.10.00',  70,  5300, 'Other'    , 13, 'hold'),
      -- APPEAL DECIDED — the four outcomes, spread across the statuses.
      (73, 'Laminated Glass Sheets'    , '7007.29.00',  40,  7800, 'Forfeit'  , 45, 'dec_release'),
      (74, 'Printed Circuit Boards'    , '8534.00.00', 160,  5600, 'Detain'   , 48, 'dec_sale'),
      (75, 'Expired Latex Paint'       , '3209.10.00',  90,  1200, 'Abandoned', 52, 'dec_destroy'),
      (76, 'Marine Diesel Filters'     , '8421.23.00', 110,  3400, 'Other'    , 55, 'dec_reexport')
    ) AS t(sr, goods, hs, qty, val, status, days_ago, state)
  LOOP
    v_sr    := 'GL1/SR/' || r.sr || '/2026';
    v_case  := 'GL1/CASE/2026/' || (600 + r.sr);
    v_entdt := (now() - make_interval(days => r.days_ago))::date;

    -- ── package ──────────────────────────────────────────────────────────
    SELECT id INTO v_pkg FROM public.packages WHERE sr_number = v_sr;
    IF v_pkg IS NULL THEN
      v_pkg := gen_random_uuid();
      INSERT INTO public.packages (
        id, sr_number, case_number, yard, origin_country, declared_value,
        weight_kg, total_item_count, description, container_number,
        consignee_name, consignee_nic, consignee_address, consignee_phone,
        declarant_name, cusdec_no, cusdec_date, entry_date, reason, status,
        inspected_by, inspected_at, created_at, updated_at)
      VALUES (
        v_pkg, v_sr, v_case, v_yard, 'China', r.qty * r.val, r.qty * 1.4,
        r.qty, r.goods, 'APLU' || (4400000 + r.sr),
        'Appeal Test Traders ' || r.sr,
        '9' || (100000000 + r.sr * 7)::text || 'V',
        (100 + r.sr) || ', Industrial Road, Colombo 15',
        '07' || (10000000 + r.sr * 13)::text,
        'Lanka Clearing Services',
        'CUSDEC/2026/' || (1600 + r.sr), (v_entdt - 1)::text,
        v_entdt, 'Pending Inquiry', 'pending',
        v_off, v_entdt, v_entdt, v_entdt);
    ELSE
      -- Keep the entry date in step when re-running.
      UPDATE public.packages
         SET entry_date = v_entdt, created_at = v_entdt
       WHERE id = v_pkg;
    END IF;

    -- ── item ─────────────────────────────────────────────────────────────
    SELECT id INTO v_item FROM public.package_items
     WHERE package_id = v_pkg AND item_name = r.goods;
    IF v_item IS NULL THEN
      v_item := gen_random_uuid();
      INSERT INTO public.package_items (
        id, package_id, yard, item_name, goods_description, quantity,
        unit_of_measure, unit_value, hs_code, category, is_prohibited,
        status, reasons, created_at)
      VALUES (
        v_item, v_pkg, v_yard, r.goods,
        r.goods || ' — appeal window test consignment',
        r.qty, 'Pieces', r.val, r.hs, 'General Cargo', false,
        r.status,
        CASE r.status
          WHEN 'Detain' THEN 'Pending Inquiry'
          ELSE 'Supposed to be Sold / Auction'
        END,
        v_entdt);
    END IF;

    -- ── warehouse entry (still HELD) ─────────────────────────────────────
    SELECT id INTO v_entry FROM public.warehouse_entries
     WHERE package_id = v_pkg AND package_item_id = v_item
       AND NOT is_returned;
    IF v_entry IS NULL THEN
      v_entry := gen_random_uuid();
      INSERT INTO public.warehouse_entries (
        id, package_id, package_item_id, warehouse_id, yard, zone, hold_reason,
        item_count, admitted_by, admitted_at, daily_rate, is_returned,
        created_at, updated_at)
      VALUES (
        v_entry, v_pkg, v_item, v_wh, v_yard, COALESCE(v_zone, 'A'),
        CASE r.status
          WHEN 'Detain' THEN 'Pending Inquiry'
          ELSE 'Supposed to be Sold / Auction'
        END,
        r.qty, v_off, v_entdt, 50, false, v_entdt, v_entdt);
    ELSE
      UPDATE public.warehouse_entries
         SET admitted_at = v_entdt WHERE id = v_entry;
    END IF;

    -- ── forfeited_packages row ───────────────────────────────────────────
    --  A Forfeit always has one. Detain / Abandoned / "Other" normally do NOT
    --  (the app synthesises their appeal rows) — but the moment an appeal is
    --  lodged or decided, the row must exist, exactly as
    --  `appeal_ensure_forfeited_row` creates it at runtime. So: create one for
    --  every forfeit, and for any other status carrying an appeal state.
    --  The plain 'window' / 'passed' non-forfeit rows are deliberately left
    --  WITHOUT a row, which is what exercises the synthetic path.
    IF r.status = 'Forfeit'
       OR (r.state <> 'window' AND r.state <> 'passed') THEN
      SELECT id INTO v_fp FROM public.forfeited_packages
       WHERE package_id = v_pkg AND item_id = v_item;
      IF v_fp IS NULL THEN
        v_fp := gen_random_uuid();
        INSERT INTO public.forfeited_packages (
          id, package_id, item_id, entry_qty, sr_number, consignee_name,
          forfeited_at, appeal_deadline, reason, yard, source, created_at)
        VALUES (
          v_fp, v_pkg, v_item, r.qty, v_sr,
          'Appeal Test Traders ' || r.sr,
          v_entdt, v_entdt + interval '30 days',
          CASE r.status
            WHEN 'Forfeit' THEN 'Forfeited to the state'
            ELSE 'Appeal lodged'
          END,
          v_yard, lower(r.status), v_entdt);
      ELSE
        UPDATE public.forfeited_packages
           SET forfeited_at    = v_entdt,
               appeal_deadline = v_entdt + interval '30 days'
         WHERE id = v_fp;
      END IF;

      -- ── appeal state ───────────────────────────────────────────────────
      CASE r.state
        WHEN 'hold' THEN
          UPDATE public.forfeited_packages
             SET appeal_hold      = true,
                 appeal_hold_note = 'Appeal lodged by the consignee; '
                                    'disposal blocked pending review.',
                 held_item_ids    = ARRAY[v_item]::uuid[],
                 appeal_decision  = NULL,
                 appeal_decided_at = NULL
           WHERE id = v_fp;

        WHEN 'dec_release' THEN
          UPDATE public.forfeited_packages
             SET appeal_hold         = false,
                 held_item_ids       = '{}',
                 appeal_decision     = 'RELEASE',
                 appeal_decision_note = 'Documents produced; released to owner.',
                 appeal_decided_at   = now() - interval '3 days',
                 item_appeal_decisions =
                   jsonb_build_object(v_item::text, 'RELEASE')
           WHERE id = v_fp;

        WHEN 'dec_sale' THEN
          UPDATE public.forfeited_packages
             SET appeal_hold         = false,
                 held_item_ids       = '{}',
                 appeal_decision     = 'SALE',
                 appeal_decision_note = 'Appeal rejected; approved for sale.',
                 appeal_decided_at   = now() - interval '4 days',
                 item_appeal_decisions =
                   jsonb_build_object(v_item::text, 'SALE')
           WHERE id = v_fp;

        WHEN 'dec_destroy' THEN
          UPDATE public.forfeited_packages
             SET appeal_hold         = false,
                 held_item_ids       = '{}',
                 appeal_decision     = 'DESTROY',
                 appeal_decision_note = 'Goods unfit for sale; destroy.',
                 appeal_decided_at   = now() - interval '5 days',
                 item_appeal_decisions =
                   jsonb_build_object(v_item::text, 'DESTROY')
           WHERE id = v_fp;

        WHEN 'dec_reexport' THEN
          UPDATE public.forfeited_packages
             SET appeal_hold         = false,
                 held_item_ids       = '{}',
                 appeal_decision     = 'RE-EXPORT',
                 appeal_decision_note = 'Shipper to re-export at own cost.',
                 appeal_decided_at   = now() - interval '6 days',
                 item_appeal_decisions =
                   jsonb_build_object(v_item::text, 'RE-EXPORT')
           WHERE id = v_fp;

        ELSE
          -- 'window' / 'passed': plain forfeit, no hold and no decision.
          UPDATE public.forfeited_packages
             SET appeal_hold           = false,
                 appeal_hold_note      = NULL,
                 held_item_ids         = '{}',
                 appeal_decision       = NULL,
                 appeal_decision_note  = NULL,
                 appeal_decided_at     = NULL,
                 item_appeal_decisions = '{}'::jsonb
           WHERE id = v_fp;
      END CASE;
    END IF;

    v_n := v_n + 1;
    RAISE NOTICE '  % · % · % · entered % (% days ago) · %',
      v_sr, r.goods, r.status, v_entdt, r.days_ago, r.state;
  END LOOP;

  RAISE NOTICE 'seeded % appeal-scenario goods', v_n;
END $$;

reset lock_timeout;

-- ── VERIFY ───────────────────────────────────────────────────────────────────
SELECT p.sr_number,
       pi.item_name                                   AS goods,
       pi.status                                      AS goods_status,
       p.entry_date,
       (p.entry_date + 30)                            AS window_closes,
       CASE WHEN p.entry_date + 30 > current_date
            THEN 'Appealing (' || (p.entry_date + 30 - current_date) || 'd)'
            ELSE 'Enabled' END                        AS appeal_chip,
       fp.appeal_hold,
       fp.appeal_decision
  FROM public.packages p
  JOIN public.package_items pi ON pi.package_id = p.id
  LEFT JOIN public.forfeited_packages fp
         ON fp.package_id = p.id AND fp.item_id = pi.id
 WHERE p.sr_number LIKE 'GL1/SR/6%/2026'
    OR p.sr_number LIKE 'GL1/SR/7%/2026'
 ORDER BY p.sr_number;

-- ── UNDO (run only if you want these test rows gone) ─────────────────────────
-- delete from public.forfeited_packages
--  where package_id in (select id from public.packages
--                        where sr_number ~ '^GL1/SR/(6[1-9]|7[0-6])/2026$');
-- delete from public.warehouse_entries
--  where package_id in (select id from public.packages
--                        where sr_number ~ '^GL1/SR/(6[1-9]|7[0-6])/2026$');
-- delete from public.package_items
--  where package_id in (select id from public.packages
--                        where sr_number ~ '^GL1/SR/(6[1-9]|7[0-6])/2026$');
-- delete from public.packages
--  where sr_number ~ '^GL1/SR/(6[1-9]|7[0-6])/2026$';
