-- ============================================================================
--  Backfill: Destroying Deposit for every existing SR
--
--  The deposit is PACKAGE-level — one figure per SR — so this sets exactly one
--  value per `packages` row. It is derived from the goods' declared worth
--  (sum of quantity x unit_value across the package's items) so the figures
--  look plausible rather than uniform:
--
--      deposit = 5% of the package's goods value,
--                rounded to the nearest LKR 500,
--                clamped to LKR 5,000 .. LKR 250,000
--
--  A package with no items (or no values) falls back to LKR 10,000.
--
--  Only rows where destroying_deposit IS NULL are touched, so re-running is
--  safe and anything entered by hand is left alone.
--
--  Run AFTER 20260826_destroying_deposit.sql.
-- ============================================================================

set lock_timeout = '5s';

-- ── PRE-FLIGHT ───────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='packages'
       AND column_name='destroying_deposit')
  THEN
    RAISE EXCEPTION
      'Run supabase/migrations/20260826_destroying_deposit.sql first.';
  END IF;
END $$;

-- ── BACKFILL ────────────────────────────────────────────────────────────────
with goods_value as (
  select p.id,
         coalesce(sum(pi.quantity * pi.unit_value), 0) as total_value
    from public.packages p
    left join public.package_items pi on pi.package_id = p.id
   group by p.id
)
update public.packages p
   set destroying_deposit = case
         when g.total_value <= 0 then 10000
         else least(
                greatest(round((g.total_value * 0.05) / 500) * 500, 5000),
                250000)
       end
  from goods_value g
 where p.id = g.id
   and p.destroying_deposit is null;

-- ── REPORT ──────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_total  int;
  v_filled int;
BEGIN
  select count(*), count(destroying_deposit)
    into v_total, v_filled
    from public.packages;
  RAISE NOTICE 'destroying deposit: % of % SRs now carry a value',
    v_filled, v_total;
END $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  One row per SR, newest first.
select p.sr_number,
       count(pi.id)                                   as goods_items,
       coalesce(sum(pi.quantity * pi.unit_value), 0)  as goods_value,
       p.destroying_deposit
  from public.packages p
  left join public.package_items pi on pi.package_id = p.id
 group by p.id, p.sr_number, p.destroying_deposit, p.entry_date
 order by p.entry_date desc nulls last, p.sr_number
 limit 40;

-- Spread of the values that were written.
select min(destroying_deposit) as min_deposit,
       round(avg(destroying_deposit)) as avg_deposit,
       max(destroying_deposit) as max_deposit,
       count(*) filter (where destroying_deposit is null) as still_null
  from public.packages;
