-- Indexes on the foreign keys every package embed filters by.
--
-- The query builder turns `packages(*, package_items(*), warehouse_entries(*,
-- warehouses(*)))` into a correlated subquery per embed -- one `where
-- package_id = p.id` per package row. With no index that is a sequential scan
-- of the whole child table, per package, per query.
--
-- ⚠️ It does not hurt today: 395 package_items and 332 warehouse_entries fit
-- in a page or two, so a scan costs 0.18ms and the planner is right to prefer
-- it. It is the shape that is wrong. These tables grow with every SR the
-- yards register, and `getAllPackages()` runs them across all twenty-eight
-- yards -- so the cost is (packages x child rows), which is the product of two
-- numbers that both only ever go up.
--
-- Adding them now, while the tables are small, means the change is free to
-- make and the planner will switch on its own once the scan stops winning.
--
-- Safe to re-run.

create index if not exists idx_package_items_package_id
  on public.package_items (package_id);

create index if not exists idx_warehouse_entries_package_id
  on public.warehouse_entries (package_id);

create index if not exists idx_warehouse_entries_warehouse_id
  on public.warehouse_entries (warehouse_id);

-- The disposition tables order by this and page with it.
create index if not exists idx_warehouse_entries_returned_by
  on public.warehouse_entries (returned_by)
  where returned_by is not null;

analyze public.package_items;
analyze public.warehouse_entries;

-- ── Verify ────────────────────────────────────────────────────────────────
-- Claims checked against the live database, so a migration that "ran fine"
-- but indexed nothing fails loudly here.
do $verify$
declare
  n int;
begin
  select count(*) into n from pg_indexes
   where schemaname = 'public'
     and indexname in ('idx_package_items_package_id',
                       'idx_warehouse_entries_package_id',
                       'idx_warehouse_entries_warehouse_id',
                       'idx_warehouse_entries_returned_by');
  if n <> 4 then
    raise exception 'expected 4 indexes, found %', n;
  end if;

  raise notice 'OK: 4 indexes present on the package-embed foreign keys';
  raise notice '    package_items rows     : %',
    (select count(*) from public.package_items);
  raise notice '    warehouse_entries rows : %',
    (select count(*) from public.warehouse_entries);
end
$verify$;
