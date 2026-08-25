-- ============================================================================
--  The categories still read "(not defined)". Find out EXACTLY why.
--
--  The app calls a zone "not defined" when it cannot find a `warehouse_zones`
--  row where BOTH match:
--
--      z.warehouse_id == category.target_warehouse_id
--      z.name         == category.target_zone
--
--  So a mismatch is one of three things: the zone row is genuinely absent, it
--  sits under a DIFFERENT warehouse, or the names differ by case/whitespace.
--
--  NOTE: the Supabase SQL editor only shows the LAST statement's results.
--  Highlight ONE query and press Run.
-- ============================================================================

-- === 1. THE ANSWER: what is wrong with each unresolved category ===
--  Run this one first. `diagnosis` names the actual problem per row.
select c.name                                   as category,
       w.name                                   as warehouse,
       '[' || c.target_zone || ']'              as target_zone_raw,
       length(c.target_zone)                    as zone_name_length,
       case
         when c.target_zone is null or trim(c.target_zone) = ''
           then 'No zone set on the category'
         when exists (select 1 from public.warehouse_zones z
                       where z.warehouse_id = c.target_warehouse_id
                         and z.name = c.target_zone)
           then 'OK — resolves'
         when exists (select 1 from public.warehouse_zones z
                       where z.warehouse_id = c.target_warehouse_id
                         and lower(trim(z.name)) = lower(trim(c.target_zone)))
           then 'Name differs by CASE or WHITESPACE'
         when exists (select 1 from public.warehouse_zones z
                       where lower(trim(z.name)) = lower(trim(c.target_zone)))
           then 'Zone exists but under a DIFFERENT warehouse'
         else 'Zone row genuinely does not exist'
       end                                      as diagnosis
  from public.package_categories c
  left join public.warehouses w on w.id = c.target_warehouse_id
 order by diagnosis, c.name;

--
-- === 2. Every zone that exists, exactly as stored ===
--  Square brackets reveal stray spaces; `name_length` reveals invisible ones.
select w.name                     as warehouse,
       w.code                     as wh_code,
       '[' || z.name || ']'       as zone_name_raw,
       length(z.name)             as name_length,
       z.code                     as zone_code,
       z.capacity
  from public.warehouse_zones z
  join public.warehouses w on w.id = z.warehouse_id
 order by w.code, z.name;

--
-- === 3. Did the categories actually get a warehouse? ===
--  A null target_warehouse_id can never resolve, whatever the zone says.
select c.name                                as category,
       c.target_warehouse_id,
       (c.target_warehouse_id is null)        as warehouse_missing,
       c.target_zone
  from public.package_categories c
 order by warehouse_missing desc, c.name;

--
-- === 4. Are the RLS policies letting this session write zones at all? ===
--  `warehouse_zones` is admin-write. If the SQL editor runs as a role the
--  policy does not admit, an INSERT silently affects zero rows.
select policyname, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public' and tablename = 'warehouse_zones'
 order by policyname;

--
-- === 5. Row counts, to confirm what the scripts actually created ===
select (select count(*) from public.warehouse_zones)      as zones,
       (select count(*) from public.package_categories)   as categories,
       (select count(*) from public.package_categories c
         where c.target_zone is not null
           and not exists (select 1 from public.warehouse_zones z
                            where z.warehouse_id = c.target_warehouse_id
                              and z.name = c.target_zone))
                                                          as unresolved;
