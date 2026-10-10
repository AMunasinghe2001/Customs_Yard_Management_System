-- ============================================================================
-- Warehouses and their zones had NO yard column, so every yard saw every
-- warehouse in the system. GL2, which has never had a warehouse added to it,
-- showed GL1's four ("Warehouse 01/02/03", "Open Area 01") plus 18 zones and
-- 72,000 units of capacity that do not exist in that yard.
--
-- Reading them was never yard-scoped either: "All can view warehouses" grants
-- SELECT to any authenticated user, and warehouse_zones inherits its yard
-- through its parent warehouse.
--
-- The workaround in warehousesForYardProvider derived the association from
-- warehouse_entries.yard, which cannot work for a NEW yard: a warehouse only
-- appeared once goods were stored in it, and goods cannot be stored in a
-- warehouse that is not offered. The column is the fix.
--
-- BACKFILL: every existing warehouse is GL1's. All 333 warehouse_entries rows
-- across all four warehouses carry yard 'GL1' and no other yard has ever
-- written one, so the assignment is unambiguous rather than a guess.
--
-- Safe to re-run.
-- ============================================================================

alter table public.warehouses
  add column if not exists yard text;

-- Derive each warehouse's yard from the entries written against it. Only when
-- EXACTLY ONE yard has used it — a warehouse two yards had written to would
-- have no right answer, and silently picking one would hand a yard another
-- yard's goods. There are none today; the guard is for a re-run on a database
-- where that is no longer true.
update public.warehouses w
   set yard = sole.yard
  from (
    select warehouse_id, min(yard) as yard
      from public.warehouse_entries
     where yard is not null
     group by warehouse_id
    having count(distinct yard) = 1
  ) as sole
 where w.id = sole.warehouse_id
   and w.yard is null;

-- A warehouse no yard has ever used cannot be placed by evidence. Leave it
-- NULL rather than guessing: an unplaced warehouse shows in NO yard, which is
-- the safe direction — it can be assigned in the admin panel, whereas a wrong
-- guess quietly exposes one yard's storage to another.
do $$
declare
  unplaced int;
begin
  select count(*) into unplaced from public.warehouses where yard is null;
  if unplaced > 0 then
    raise notice '% warehouse(s) have no entries and stay unassigned', unplaced;
  end if;
end $$;

create index if not exists warehouses_yard_idx on public.warehouses (yard);

-- ── Reads: a yard sees only its own warehouses ──────────────────────────────
-- The old policy granted every authenticated user every warehouse.
drop policy if exists "All can view warehouses" on public.warehouses;
drop policy if exists warehouses_yard_select on public.warehouses;
create policy warehouses_yard_select on public.warehouses
  for select using (yard = public.auth_user_yard());

-- ── Writes: an admin manages warehouses in their OWN yard ───────────────────
-- The replaced policy read profiles INLINE, the pattern that raises 42P17
-- (see migration 007), and granted every admin every yard. Both go.
drop policy if exists "Admins can manage warehouses" on public.warehouses;
drop policy if exists warehouses_yard_write on public.warehouses;
create policy warehouses_yard_write on public.warehouses
  for all
  using (yard = public.auth_user_yard())
  with check (yard = public.auth_user_yard());

-- ── Zones follow their warehouse ────────────────────────────────────────────
-- warehouse_zones has no yard of its own; it inherits through warehouse_id.
-- The parent lookup goes through a SECURITY DEFINER helper so that reading a
-- zone does not re-enter the warehouses policies.
create or replace function public.warehouse_yard(p_warehouse_id uuid)
returns text
language sql
stable
security definer
set search_path = public, extensions
as $function$
  select yard from public.warehouses where id = p_warehouse_id;
$function$;

revoke all on function public.warehouse_yard(uuid) from public;
grant execute on function public.warehouse_yard(uuid) to authenticated;

drop policy if exists warehouse_zones_read on public.warehouse_zones;
drop policy if exists warehouse_zones_admin_write on public.warehouse_zones;
drop policy if exists warehouse_zones_yard_select on public.warehouse_zones;
create policy warehouse_zones_yard_select on public.warehouse_zones
  for select using (
    public.warehouse_yard(warehouse_id) = public.auth_user_yard()
  );

drop policy if exists warehouse_zones_yard_write on public.warehouse_zones;
create policy warehouse_zones_yard_write on public.warehouse_zones
  for all
  using (public.warehouse_yard(warehouse_id) = public.auth_user_yard())
  with check (public.warehouse_yard(warehouse_id) = public.auth_user_yard());

alter table public.warehouses enable row level security;
alter table public.warehouse_zones enable row level security;

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  bad text;
  mixed int;
begin
  -- No policy on either table may read profiles inline (42P17).
  select string_agg(c.relname || '.' || p.polname, ', ') into bad
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('warehouses', 'warehouse_zones')
     and (
       pg_get_expr(p.polqual, p.polrelid) ilike '%from profiles%'
       or pg_get_expr(p.polwithcheck, p.polrelid) ilike '%from profiles%'
     );
  if bad is not null then
    raise exception 'policies still read profiles inline: %', bad;
  end if;

  -- The backfill must not have handed one yard another yard's warehouse.
  select count(*) into mixed
    from public.warehouses w
    join public.warehouse_entries e on e.warehouse_id = w.id
   where w.yard is not null
     and e.yard is not null
     and e.yard <> w.yard;
  if mixed > 0 then
    raise exception '% entrie(s) sit in a warehouse belonging to another yard', mixed;
  end if;
end $$;

-- ── warehouse_contents: the one view migration 003 missed ───────────────────
-- It joins warehouse_entries, warehouses, packages and profiles with no yard
-- filter, and without security_invoker it runs as its OWNER — so the policies
-- above would not apply to it and any authenticated caller could read every
-- yard's stock through it. Nothing in the app queries it, which is why it went
-- unnoticed; making it run as the caller closes the hole rather than leaving a
-- bypass in the schema for the next query that finds it.
alter view public.warehouse_contents set (security_invoker = true);

do $$
begin
  if not exists (
    select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'warehouse_contents'
       and 'security_invoker=true' = any (c.reloptions)
  ) then
    raise exception 'warehouse_contents must run as the caller';
  end if;
end $$;
