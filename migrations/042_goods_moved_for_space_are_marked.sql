-- ============================================================================
--  042 · Goods that are not where their category says they should be
--
--  ⚠️ THE GAP, reported directly: when a warehouse or a zone is full, the
--  officer is offered another one and the goods go there instead. Afterwards
--  NOTHING says so. The warehouse page shows a row like any other, and the
--  only way to know these goods were displaced is to remember it — so a month
--  later nobody can tell a deliberate placement from an overflow, and nobody
--  knows which goods to move back when space frees up.
--
--  The category's own target (package_category_targets, migration 037) is the
--  intended home. A capacity override sends goods somewhere else, and the two
--  columns below record that it happened, where they were meant to go, and
--  why — written at the moment the officer accepts the alternative.
--
--  ⚠️ Deliberately NOT inferred by comparing warehouse_id against the
--  category target at read time. Targets are editable (migration 038): a yard
--  that retargets a category afterwards would make every ordinary row look
--  displaced, and a yard that retargets it TO the overflow warehouse would
--  hide a real displacement. What happened at admission is a fact about that
--  admission, so it is stored on the entry.
-- ============================================================================

set lock_timeout = '5s';

alter table public.warehouse_entries
  add column if not exists moved_for_space boolean not null default false,
  -- Where the category said these goods belonged. Null when the intended
  -- warehouse could not be resolved at the time (a category with no target).
  --
  -- ⚠️ NO foreign key, deliberately. `warehouse_entries.warehouse_id` already
  -- references `warehouses`, and the app's PostgREST-style embed resolves
  -- `warehouses(*)` by finding the ONE foreign key between the two tables. A
  -- second FK makes that ambiguous and the query builder refuses it outright
  -- ("no unique foreign key between warehouse_entries and warehouses"),
  -- which would break all 44 call sites that embed a warehouse -- the entire
  -- warehouse system -- rather than just this feature.
  --
  -- The trade is a column the database will not police. That is acceptable
  -- here: it is a historical note about an admission, read only for display,
  -- and a warehouse that is later deleted should leave the note intact
  -- (`on delete set null` would erase the very fact being recorded).
  add column if not exists intended_warehouse_id uuid,
  add column if not exists intended_zone text,
  -- What was full: the warehouse, or just the zone. Free text so the reason
  -- reads the way the officer was told it, e.g. "Warehouse 02 · Zone B full
  -- (500/500)".
  add column if not exists moved_reason text;

-- ⚠️ Partial: only the displaced rows are ever queried by this flag, and they
-- are a small minority of a large table.
create index if not exists warehouse_entries_moved_for_space_idx
  on public.warehouse_entries (moved_for_space)
  where moved_for_space;

comment on column public.warehouse_entries.moved_for_space is
  'True when these goods were admitted somewhere other than their category''s '
  'target because that target was full. Set at admission; never inferred.';

-- ── Surface it on the row the warehouse page reads ─────────────────────────
--
-- ⚠️ Re-wrapped rather than retyped, and guarded, exactly like migration 016:
-- warehouse_rows is built elsewhere and carries columns this file has no
-- business restating. Re-running this file after any change to that view
-- restores the wrap.
do $$
declare
  body text;
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'warehouse_rows') then
    return;
  end if;
  select pg_get_viewdef('public.warehouse_rows'::regclass, true) into body;
  if body like '%moved_for_space%' then
    return;
  end if;
  execute format(
    'create or replace view public.warehouse_rows '
    'with (security_invoker = true) as '
    'select v.*, '
    '  coalesce(w5.moved_for_space, false) as moved_for_space, '
    '  w5.intended_warehouse_id, '
    '  w5.intended_zone, '
    '  w5.moved_reason, '
    '  iw.name as intended_warehouse_name '
    'from (%s) v '
    'left join public.warehouse_entries w5 on w5.id = v.entry_id '
    'left join public.warehouses iw on iw.id = w5.intended_warehouse_id',
    rtrim(body, ';' || chr(10) || chr(13) || ' '));
end $$;

-- ── Verification ───────────────────────────────────────────────────────────
do $verify$
declare
  c text;
begin
  foreach c in array array['moved_for_space', 'intended_warehouse_id',
                           'intended_zone', 'moved_reason'] loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public'
                      and table_name = 'warehouse_entries'
                      and column_name = c) then
      raise exception 'warehouse_entries is missing %', c;
    end if;
  end loop;

  -- Nothing may arrive already flagged: the column is new, so every existing
  -- entry must read as an ordinary placement.
  if exists (select 1 from public.warehouse_entries where moved_for_space) then
    raise exception 'existing rows were flagged as displaced';
  end if;

  raise notice 'PASS: warehouse_entries records a capacity move, and no '
               'existing row claims to be one';
end $verify$;

do $verify2$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relname = 'warehouse_rows') then
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'warehouse_rows'
                      and column_name = 'moved_for_space') then
      raise exception 'warehouse_rows is missing moved_for_space';
    end if;
    if not exists (select 1 from pg_class c
                     join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relname = 'warehouse_rows'
                      and 'security_invoker=true' = any (c.reloptions)) then
      raise exception 'warehouse_rows lost security_invoker';
    end if;
    raise notice 'PASS: warehouse_rows carries the displacement, and still '
                 'runs as the caller';
  end if;
end $verify2$;
