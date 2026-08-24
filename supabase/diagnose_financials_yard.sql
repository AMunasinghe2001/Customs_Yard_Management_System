-- ============================================================================
--  Why does selecting a yard on Financials / Expenses show nothing?
--
--  Neither `packages` nor `warehouse_entries` exposes a yard on its Dart model,
--  so the app derives a goods item's yard from its SR NUMBER's prefix:
--
--      GL1/SR/01/2025  ->  GL1
--
--  If a row shows up under "All Yards" but vanishes under its own yard, the
--  prefix is not what the dropdown emits. The dropdown emits the yard CODE
--  exactly as spelled in lib/core/yards.dart:
--
--      GL1 GL2 RCT CVT BQ NNR JCT PREV BAGG RTF BIA HMB TRINCO
--      KURU CSL DAMB MIDIGO KALK TRANSCO SEREN TRIGO
--
--  NOTE: the Supabase SQL editor only shows the LAST statement's results.
--  Highlight ONE query and press Run.
-- ============================================================================

-- === 1. What prefixes actually exist, and do they match a known yard? ===
--  `matches_a_yard = false` is the bug: those rows can never be filtered to a
--  yard, because no dropdown option equals their prefix.
select split_part(p.sr_number, '/', 1)          as sr_prefix,
       count(distinct p.id)                     as packages,
       count(pi.id)                             as goods_items,
       split_part(p.sr_number, '/', 1) in (
         'GL1','GL2','RCT','CVT','BQ','NNR','JCT','PREV','BAGG','RTF','BIA',
         'HMB','TRINCO','KURU','CSL','DAMB','MIDIGO','KALK','TRANSCO',
         'SEREN','TRIGO')                       as matches_a_yard
  from public.packages p
  left join public.package_items pi on pi.package_id = p.id
 group by sr_prefix
 order by goods_items desc;

--
-- === 2. The GL1 goods the Financials page should list ===
--  A row appears only when SOMETHING is recorded against it — a storage
--  charge, a deposit, a sale, or a cost. Rows with nothing are hidden.
select p.sr_number,
       pi.item_name                             as goods,
       pi.quantity,
       coalesce(p.destroying_deposit, 0)        as package_deposit,
       (select coalesce(sum(fe.amount), 0)
          from public.financial_expenses fe
         where fe.package_item_id = pi.id)      as costs_recorded,
       (select count(*) from public.warehouse_entries we
         where we.package_id = p.id)            as warehouse_entries
  from public.packages p
  join public.package_items pi on pi.package_id = p.id
 where p.sr_number like 'GL1/%'
 order by p.sr_number, pi.item_name;

--
-- === 3. Does ANY package carry a destroying deposit? ===
--  All zero means backfill_destroying_deposit.sql has not been run, and the
--  Expenses tab will list nothing regardless of the yard chosen.
select count(*)                                     as packages,
       count(*) filter (where coalesce(destroying_deposit, 0) > 0)
                                                    as with_a_deposit,
       coalesce(sum(destroying_deposit), 0)         as total_deposits
  from public.packages;

--
-- === 4. Are any costs recorded at all? ===
--  Zero rows means seed_disposal_expenses.sql has not been run, so the
--  Destruction / Advertising / Refund columns are all empty.
select kind,
       count(*)                as entries,
       count(package_item_id)  as attributed_to_goods,
       coalesce(sum(amount),0) as total
  from public.financial_expenses
 group by kind
 order by kind;
