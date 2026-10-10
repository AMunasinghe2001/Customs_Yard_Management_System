-- ============================================================================
--  Backfill: taxes on already-sold goods
--
--  `tender_sale_items.applied_taxes` is a jsonb array of
--      [{"name": "VAT", "percentage": 18, "amount": 30267.00}, ...]
--  written when an item is marked sold. Items sold before taxes were
--  configured carry an empty array, so every Sold table shows "Tax: Rs 0.00".
--
--  This applies whatever ACTIVE rates are configured in `disposal_taxes` (the
--  Central Disposal > Taxes tab) to each sold item's `sold_price` and stores
--  the resulting array. Nothing is hard-coded: change a rate on that tab and
--  re-run, and the new rate is what gets written.
--
--  The seed block below is a FALLBACK only — it fires solely when no active
--  tax exists at all, so a configured list (e.g. VAT 18% + PAL 10%) is used
--  as-is and never added to.
--
--  Only rows whose applied_taxes is empty are touched, so re-running is safe
--  and anything captured through the app is left alone.
-- ============================================================================

set lock_timeout = '5s';

-- ── PRE-FLIGHT ───────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
     WHERE table_schema='public' AND table_name='disposal_taxes')
  THEN
    RAISE EXCEPTION
      'Run db/migrations/20260611_disposal_taxes.sql first.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='tender_sale_items'
       AND column_name='applied_taxes')
  THEN
    RAISE EXCEPTION
      'Run db/migrations/20260611_tender_sale_sold_price.sql first.';
  END IF;
END $$;

-- ── 1. Fallback: only if NO active tax is configured at all ─────────────────
--  With VAT/PAL (or any other rates) already set up on the Taxes tab this
--  inserts nothing.
INSERT INTO public.disposal_taxes (name, percentage, is_active)
SELECT * FROM (VALUES
  ('VAT', 18.00, true)
) AS t(name, percentage, is_active)
WHERE NOT EXISTS (
  SELECT 1 FROM public.disposal_taxes WHERE is_active
);

-- Show what will actually be applied.
DO $$
DECLARE v_list text;
BEGIN
  SELECT string_agg(name || ' ' || percentage || '%', ' + ' ORDER BY name)
    INTO v_list FROM public.disposal_taxes WHERE is_active;
  RAISE NOTICE 'applying active taxes: %', coalesce(v_list, '(none)');
END $$;

-- ── 2. Apply them to sold items that carry no taxes yet ─────────────────────
with rates as (
  select jsonb_agg(
           jsonb_build_object('name', name, 'percentage', percentage)
           order by name) as list
    from public.disposal_taxes
   where is_active
),
computed as (
  select t.id,
         (select jsonb_agg(
                   jsonb_build_object(
                     'name',       r->>'name',
                     'percentage', (r->>'percentage')::numeric,
                     -- amount = sold_price x percentage / 100, to the cent
                     'amount',     round(
                                     t.sold_price
                                     * (r->>'percentage')::numeric / 100.0, 2)
                   ))
            from jsonb_array_elements((select list from rates)) r
         ) as taxes
    from public.tender_sale_items t
   where t.sold
     and coalesce(t.sold_price, 0) > 0
     and (t.applied_taxes is null
          or jsonb_array_length(coalesce(t.applied_taxes, '[]'::jsonb)) = 0)
)
update public.tender_sale_items t
   set applied_taxes = c.taxes
  from computed c
 where t.id = c.id
   and c.taxes is not null;

-- ── 3. Same for destroyed items, which also carry applied_taxes ─────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='destruction_items'
       AND column_name='applied_taxes')
  THEN
    with rates as (
      select jsonb_agg(
               jsonb_build_object('name', name, 'percentage', percentage)
               order by name) as list
        from public.disposal_taxes
       where is_active
    ),
    computed as (
      select d.id,
             (select jsonb_agg(
                       jsonb_build_object(
                         'name',       r->>'name',
                         'percentage', (r->>'percentage')::numeric,
                         'amount',     round(
                                         d.destroyed_price
                                         * (r->>'percentage')::numeric / 100.0,
                                         2)
                       ))
                from jsonb_array_elements((select list from rates)) r
             ) as taxes
        from public.destruction_items d
       where d.destroyed
         and coalesce(d.destroyed_price, 0) > 0
         and (d.applied_taxes is null
              or jsonb_array_length(coalesce(d.applied_taxes,'[]'::jsonb)) = 0)
    )
    update public.destruction_items d
       set applied_taxes = c.taxes
      from computed c
     where d.id = c.id
       and c.taxes is not null;
  END IF;
END $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select p.sr_number,
       pi.item_name                        as goods,
       t.sold_price,
       t.applied_taxes,
       round(coalesce((
         select sum((x->>'amount')::numeric)
           from jsonb_array_elements(t.applied_taxes) x), 0), 2) as tax_total,
       round(t.sold_price + coalesce((
         select sum((x->>'amount')::numeric)
           from jsonb_array_elements(t.applied_taxes) x), 0), 2) as grand_total
  from public.tender_sale_items t
  join public.forfeited_packages f on f.id = t.forfeited_package_id
  join public.packages p           on p.id = f.package_id
  left join public.package_items pi on pi.id = f.item_id
 where t.sold
 order by p.sr_number, pi.item_name;

-- Anything still without taxes?
select count(*) filter (where jsonb_array_length(
                                coalesce(applied_taxes,'[]'::jsonb)) = 0)
         as sold_without_taxes,
       count(*) as sold_total
  from public.tender_sale_items
 where sold;
