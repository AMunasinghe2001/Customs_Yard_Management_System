-- ============================================================================
--  Zones get their own CODE, alongside the name.
--
--  A warehouse has a name and a code (Warehouse 01 / W01); its zones read the
--  same way — "Zone A" / "W01-A" — so the admin table can show one column set
--  for both levels.
--
--  Backfills from the zone's name, prefixed with its warehouse's code, which
--  is what an operator would have written anyway.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.warehouse_zones
  add column if not exists code text;

-- Backfill: "<warehouse code>-<zone name>", uppercased and space-free.
update public.warehouse_zones z
   set code = upper(w.code || '-' || regexp_replace(z.name, '\s+', '', 'g'))
  from public.warehouses w
 where w.id = z.warehouse_id
   and (z.code is null or trim(z.code) = '');

-- One code per warehouse. Names were already unique per warehouse; codes are
-- too, so either identifies a zone within its warehouse.
create unique index if not exists warehouse_zones_code_uniq
  on public.warehouse_zones(warehouse_id, code)
 where code is not null;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select w.name as warehouse, w.code as warehouse_code,
       z.name as zone, z.code as zone_code, z.capacity
  from public.warehouse_zones z
  join public.warehouses w on w.id = z.warehouse_id
 order by w.code, z.name;
