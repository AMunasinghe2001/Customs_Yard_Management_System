-- ============================================================================
--  Why does one SR appear many times over in the Appeal Directorate?
--
--  The portal expands each `forfeited_packages` row into one row per package
--  item. That is correct for a PACKAGE-level row (item_id IS NULL), which
--  stands for the whole package. But if an SR has SEVERAL package-level rows,
--  each one expands into every item and the list multiplies:
--
--      3 package-level rows x 3 items = 9 rows for 3 goods
--
--  Run query 1. Any SR with `package_level_rows > 1` is duplicated.
--
--  NOTE: the Supabase SQL editor only shows the LAST statement's results.
--  Highlight ONE query and press Run.
-- ============================================================================

-- === 1. SRs with more than one forfeited_packages row ===
--  `package_level_rows` is the number that expand into EVERY item. More than
--  one of those is the duplication.
select p.sr_number,
       fp.source,
       count(*)                                        as fp_rows,
       count(*) filter (where fp.item_id is null)      as package_level_rows,
       count(*) filter (where fp.item_id is not null)  as per_item_rows,
       (select count(*) from public.package_items pi
         where pi.package_id = p.id)                   as items_in_package,
       -- What the portal will actually render.
       count(*) filter (where fp.item_id is null)
         * (select count(*) from public.package_items pi
             where pi.package_id = p.id)
       + count(*) filter (where fp.item_id is not null) as rows_shown
  from public.forfeited_packages fp
  join public.packages p on p.id = fp.package_id
 group by p.sr_number, p.id, fp.source
having count(*) > 1
 order by rows_shown desc, p.sr_number;

--
-- === 2. The duplicate rows themselves, for one SR ===
--  Change the SR number to whichever query 1 flagged.
select fp.id,
       fp.source,
       fp.item_id,
       pi.item_name,
       fp.forfeited_at,
       fp.appeal_deadline,
       fp.appeal_hold,
       fp.appeal_decision,
       fp.created_at
  from public.forfeited_packages fp
  join public.packages p            on p.id  = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
 where p.sr_number = 'GL1/SR/28/2026'
 order by fp.created_at;

--
-- === 3. Totals, before and after ===
select count(*)                                   as forfeited_rows,
       count(distinct (package_id, coalesce(item_id::text, 'PKG')))
                                                  as distinct_targets,
       count(*) - count(distinct (package_id, coalesce(item_id::text, 'PKG')))
                                                  as exact_duplicates
  from public.forfeited_packages;
