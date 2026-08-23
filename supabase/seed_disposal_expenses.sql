-- ============================================================================
--  Sample destruction + advertising costs, so the Financials tab and Central
--  Disposal's Expenses tab have something to show.
--
--  Costs are posted PER GOODS ITEM. The refund is NOT seeded — it is derived:
--
--      refund = destroying_deposit - (destruction + advertising)
--
--  Run AFTER:
--      20260826_destroying_deposit.sql   (packages.destroying_deposit)
--      20260827_financial_expenses.sql   (the table)
--      20260830_expenses_per_goods.sql   (package_item_id + unique index)
--      backfill_destroying_deposit.sql   (so every SR carries a deposit)
--
--  Idempotent: re-running UPDATES the same rows rather than adding more.
-- ============================================================================

set lock_timeout = '5s';

-- ── PRE-FLIGHT ───────────────────────────────────────────────────────────────
DO $$
DECLARE missing text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='financial_expenses'
       AND column_name='package_item_id')
  THEN missing := missing ||
    ' financial_expenses.package_item_id (20260830_expenses_per_goods.sql)';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='packages'
       AND column_name='destroying_deposit')
  THEN missing := missing ||
    ' packages.destroying_deposit (20260826_destroying_deposit.sql)';
  END IF;

  IF missing <> '' THEN
    RAISE EXCEPTION E'Run these first:%', missing;
  END IF;
END $$;

-- ── POST THE COSTS ───────────────────────────────────────────────────────────
DO $$
DECLARE
  g          record;
  v_off      uuid;
  v_seq      int := 0;
  v_deposit  numeric;
  v_share    numeric;
  v_destroy  numeric;
  v_advert   numeric;
  v_n        int := 0;
BEGIN
  SELECT id INTO v_off FROM public.profiles ORDER BY created_at LIMIT 1;

  FOR g IN
    SELECT pi.id                AS item_id,
           pi.item_name,
           pi.quantity,
           p.sr_number,
           p.destroying_deposit,
           (SELECT sum(q.quantity) FROM public.package_items q
             WHERE q.package_id = p.id) AS total_qty
      FROM public.package_items pi
      JOIN public.packages p ON p.id = pi.package_id
     WHERE COALESCE(p.destroying_deposit, 0) > 0
     ORDER BY p.sr_number, pi.item_name
     LIMIT 40
  LOOP
    v_seq := v_seq + 1;

    -- The deposit is a PACKAGE value; apportion it to this item by quantity,
    -- exactly the way the app does when it builds the per-goods ledger.
    v_share := CASE WHEN COALESCE(g.total_qty, 0) > 0
                    THEN g.quantity::numeric / g.total_qty
                    ELSE 1 END;
    v_deposit := COALESCE(g.destroying_deposit, 0) * v_share;

    -- Vary the costs so the tab shows all three shapes: a healthy refund, a
    -- small one, and one case where the costs OVERRUN the deposit.
    CASE (v_seq % 4)
      WHEN 0 THEN            -- overrun: costs exceed the deposit
        v_destroy := round(v_deposit * 0.80, 2);
        v_advert  := round(v_deposit * 0.45, 2);
      WHEN 1 THEN            -- most of the deposit comes back
        v_destroy := round(v_deposit * 0.18, 2);
        v_advert  := round(v_deposit * 0.07, 2);
      WHEN 2 THEN            -- about half comes back
        v_destroy := round(v_deposit * 0.35, 2);
        v_advert  := round(v_deposit * 0.15, 2);
      ELSE                   -- advertised but never destroyed
        v_destroy := 0;
        v_advert  := round(v_deposit * 0.12, 2);
    END CASE;

    -- Upserts on (package_item_id, kind) — re-running corrects the figure
    -- instead of double-counting it against the deposit.
    INSERT INTO public.financial_expenses
      (kind, amount, description, sr_number, package_item_id,
       incurred_on, created_by)
    VALUES
      ('destruction_expense', v_destroy,
       'Destruction of ' || g.item_name, g.sr_number, g.item_id,
       (now() - interval '10 days')::date, v_off)
    ON CONFLICT (package_item_id, kind)
    DO UPDATE SET amount      = excluded.amount,
                  description = excluded.description,
                  updated_at  = now();

    INSERT INTO public.financial_expenses
      (kind, amount, description, sr_number, package_item_id,
       incurred_on, created_by)
    VALUES
      ('advertising_expense', v_advert,
       'Tender advertising for ' || g.item_name, g.sr_number, g.item_id,
       (now() - interval '12 days')::date, v_off)
    ON CONFLICT (package_item_id, kind)
    DO UPDATE SET amount      = excluded.amount,
                  description = excluded.description,
                  updated_at  = now();

    v_n := v_n + 1;
  END LOOP;

  RAISE NOTICE 'Costs posted for % goods items.', v_n;
END $$;

-- Historical hand-entered refunds are now DERIVED, so any left over would be
-- counted twice. Clear them.
DELETE FROM public.financial_expenses WHERE kind = 'refund';

reset lock_timeout;

-- ── VERIFY: the per-goods ledger, refund derived the way the app derives it ──
SELECT p.sr_number,
       pi.item_name AS goods,
       round(COALESCE(p.destroying_deposit, 0)
             * (pi.quantity::numeric /
                NULLIF((SELECT sum(q.quantity) FROM public.package_items q
                         WHERE q.package_id = p.id), 0)), 2) AS deposit,
       COALESCE(d.amount, 0)                                 AS destruction,
       COALESCE(a.amount, 0)                                 AS advertising,
       GREATEST(round(COALESCE(p.destroying_deposit, 0)
             * (pi.quantity::numeric /
                NULLIF((SELECT sum(q.quantity) FROM public.package_items q
                         WHERE q.package_id = p.id), 0)), 2)
             - COALESCE(d.amount, 0) - COALESCE(a.amount, 0), 0) AS refund
  FROM public.package_items pi
  JOIN public.packages p ON p.id = pi.package_id
  LEFT JOIN public.financial_expenses d
         ON d.package_item_id = pi.id AND d.kind = 'destruction_expense'
  LEFT JOIN public.financial_expenses a
         ON a.package_item_id = pi.id AND a.kind = 'advertising_expense'
 WHERE d.id IS NOT NULL OR a.id IS NOT NULL
 ORDER BY p.sr_number, pi.item_name;
