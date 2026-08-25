-- ============================================================================
--  Warehouse ZONES, each with its own capacity.
--
--  Capacity used to be a single number on `warehouses`, and nothing enforced
--  it: goods were admitted with no check at all, which is how Warehouse 01
--  reached 128% full. Space is really organised zone by zone, so that is where
--  the number belongs.
--
--    * A zone belongs to one warehouse and carries its own capacity.
--    * A WAREHOUSE's capacity is the SUM of its zones — never entered directly.
--    * `warehouse_entries.zone` already names the zone an entry sits in; it now
--      matches `warehouse_zones.name` within that warehouse.
--
--  `warehouses.capacity` is KEPT so nothing that still reads it breaks, but it
--  stops being the source of truth — the app sums the zones instead.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── The zones ────────────────────────────────────────────────────────────
create table if not exists public.warehouse_zones (
  id           uuid primary key default gen_random_uuid(),
  warehouse_id uuid    not null references public.warehouses(id) on delete cascade,
  -- Short label as it appears on a warehouse entry: 'A', 'B', 'Cold Room' …
  name         text    not null,
  description  text,
  capacity     integer not null default 500 check (capacity >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- One zone name per warehouse; the pair is what an entry resolves against.
  constraint warehouse_zones_name_uniq unique (warehouse_id, name)
);

create index if not exists warehouse_zones_warehouse_idx
  on public.warehouse_zones(warehouse_id);

alter table public.warehouse_zones enable row level security;

-- 2. ── RLS: everyone reads, admins write ────────────────────────────────────
--    Zones are reference data — the SR form must read them to place goods, and
--    every capacity view needs them. Only an admin may change the layout.
drop policy if exists warehouse_zones_read on public.warehouse_zones;
create policy warehouse_zones_read on public.warehouse_zones
  for select using (auth.role() = 'authenticated');

drop policy if exists warehouse_zones_admin_write on public.warehouse_zones;
create policy warehouse_zones_admin_write on public.warehouse_zones
  for all
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p
                       where p.id = auth.uid() and p.role = 'admin'));

-- 3. ── Backfill from the zones already in use ───────────────────────────────
--    Every distinct `warehouse_entries.zone` becomes a real zone. Its capacity
--    starts at the parent warehouse's old figure divided evenly among them, so
--    the totals carry over and an over-full warehouse still reads as over-full
--    rather than being silently reset.
insert into public.warehouse_zones (warehouse_id, name, capacity)
select z.warehouse_id,
       z.zone,
       greatest(
         1,
         coalesce(w.capacity, 500) / greatest(1, count(*) over (
           partition by z.warehouse_id))
       )::int
  from (
    select distinct we.warehouse_id, trim(we.zone) as zone
      from public.warehouse_entries we
     where we.zone is not null
       and trim(we.zone) <> ''
       and upper(trim(we.zone)) <> 'N/A'
  ) z
  join public.warehouses w on w.id = z.warehouse_id
on conflict (warehouse_id, name) do nothing;

-- 4. ── A warehouse with no zones in use gets one default zone ───────────────
--    Otherwise it would show zero capacity and accept nothing.
insert into public.warehouse_zones (warehouse_id, name, capacity, description)
select w.id, 'A', coalesce(w.capacity, 500),
       'Default zone (created when zones were introduced)'
  from public.warehouses w
 where not exists (select 1 from public.warehouse_zones z
                    where z.warehouse_id = w.id)
on conflict (warehouse_id, name) do nothing;

reset lock_timeout;

-- ── VERIFY: each warehouse, its zones, and the capacity they now total ──────
select w.name                                   as warehouse,
       w.code,
       count(z.id)                              as zones,
       string_agg(z.name, ', ' order by z.name) as zone_names,
       coalesce(sum(z.capacity), 0)             as zone_capacity_total,
       w.capacity                               as legacy_capacity
  from public.warehouses w
  left join public.warehouse_zones z on z.warehouse_id = w.id
 group by w.id, w.name, w.code, w.capacity
 order by w.code;
