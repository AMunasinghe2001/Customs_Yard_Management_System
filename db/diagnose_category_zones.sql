-- ============================================================================
--  Why do goods sit in zones A / B / C that no item category points at?
--
--  Two separate things decide where goods live:
--
--    package_items.category      -> the category NAME an officer picked
--    package_categories          -> that category's target warehouse + zone
--    warehouse_entries.zone      -> where the goods ACTUALLY went
--
--  The seeded goods were admitted straight into 'A' / 'B' / 'C' without a
--  category, so the Items table has nothing to show for them.
--
--  NOTE: the Supabase SQL editor only shows the LAST statement's results.
--  Highlight ONE query and press Run.
-- ============================================================================

-- === 1. How many goods have no category at all? ===
select count(*)                                                as goods,
       count(*) filter (where category is null
                           or trim(category) = '')             as without_category,
       count(distinct category) filter (where category is not null
                                          and trim(category) <> '')
                                                               as distinct_categories
  from public.package_items;

--
-- === 2. The zones goods actually occupy, vs what categories point at ===
--  `category_points_here` false means goods are in a zone no category targets.
--  Grouped in a subquery FIRST, then the category is looked up against the
--  grouped columns. Doing the lookup inline fails with
--  "42803: subquery uses ungrouped column we.zone" — the outer query groups by
--  trim(we.zone), so the raw column is no longer available to it.
select z.warehouse,
       z.zone,
       z.entries,
       z.items,
       exists (select 1 from public.package_categories c
                where c.target_warehouse_id = z.warehouse_id
                  and c.target_zone = z.zone) as category_points_here
  from (
    select w.name             as warehouse,
           we.warehouse_id    as warehouse_id,
           trim(we.zone)      as zone,
           count(*)           as entries,
           sum(we.item_count) as items
      from public.warehouse_entries we
      join public.warehouses w on w.id = we.warehouse_id
     where we.is_returned = false
       and we.zone is not null
       and trim(we.zone) <> ''
     group by w.name, we.warehouse_id, trim(we.zone)
  ) z
 order by z.warehouse, z.zone;

--
-- === 3. Goods without a category, and where they are held ===
select p.sr_number,
       pi.item_name,
       pi.quantity,
       pi.category,
       w.name       as warehouse,
       we.zone
  from public.package_items pi
  join public.packages p on p.id = pi.package_id
  left join public.warehouse_entries we on we.package_item_id = pi.id
                                       and we.is_returned = false
  left join public.warehouses w on w.id = we.warehouse_id
 where pi.category is null or trim(pi.category) = ''
 order by p.sr_number, pi.item_name;

--
-- === 4. Every category, and whether its zone exists ===
select c.name          as category,
       w.name          as warehouse,
       c.target_zone,
       (z.id is not null) as zone_exists,
       z.capacity,
       (select count(*) from public.package_items pi
         where pi.category = c.name)          as goods_using_it
  from public.package_categories c
  left join public.warehouses w      on w.id = c.target_warehouse_id
  left join public.warehouse_zones z on z.warehouse_id = c.target_warehouse_id
                                    and z.name = c.target_zone
 order by w.name, c.target_zone;
