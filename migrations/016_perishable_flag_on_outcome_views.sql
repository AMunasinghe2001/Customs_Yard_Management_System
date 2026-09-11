-- ============================================================================
-- Perishable goods reach the Sold, Unsold and Final Outcome tables alongside
-- everything else, and nothing on those rows says so.
--
-- A perishable runs ONE special tender sale — no re-valuation, no second
-- round, no committee — so a reader scanning those tables cannot tell why a
-- row has one tender behind it and its neighbour has four. The tender pages
-- already mark them; these did not.
--
-- ⚠️ The flag goes in the VIEW, not in Dart, because these pages are
-- server-paged: the filter has to narrow the query, or the pager would go on
-- counting rows the screen had just removed.
--
-- ⚠️ `forfeited_packages.source` is the authority (postgres/07 made
-- 'perishable' a real source). `package_items.nature` is the fallback for
-- goods sold or released straight out of the yard without ever reaching a
-- forfeited record. Both agree on all 8 rows in this database; keeping both
-- means a route that skips one is still caught.
--
-- Safe to re-run.
-- ============================================================================

-- ⚠️ plpgsql with a dynamic fallback, not plain SQL.
--
-- `package_items.nature` is added by postgres/06, which is applied by hand
-- and is NOT folded into 02_schema.sql — so on the fresh database that file
-- stands a new server up, the column does not exist and a static reference
-- to it fails to parse the whole function. Checking the catalogue first
-- keeps the fallback where the column is present and skips it where it is
-- not, instead of making 02_schema.sql depend on another manual file.
create or replace function public.item_is_perishable(p_item_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  hit boolean;
begin
  -- The authority: postgres/07 made 'perishable' a real forfeited source.
  select exists (select 1 from public.forfeited_packages fp
                  where fp.item_id = p_item_id
                    and lower(trim(coalesce(fp.source, ''))) = 'perishable')
    into hit;
  if hit then
    return true;
  end if;

  -- Fallback for goods sold or released straight out of the yard, which
  -- never reach a forfeited record.
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'package_items'
                and column_name = 'nature') then
    execute 'select lower(trim(coalesce(nature, ''''))) = ''perishable'' '
            'from public.package_items where id = $1'
      into hit using p_item_id;
    return coalesce(hit, false);
  end if;
  return false;
end;
$function$;

revoke all on function public.item_is_perishable(uuid) from public;
grant execute on function public.item_is_perishable(uuid) to authenticated;

-- ── disposition_rows: Sold / Destroyed / Re-exported / Released ────────────
do $$
declare
  body text;
begin
  -- Rebuild the view with one extra column, keeping its definition exactly
  -- as it stands rather than retyping it — that is how two copies drift.
  -- ⚠️ Guarded. disposition_rows is created by postgres/18, applied by
  -- hand and not folded into 02_schema.sql, so on a fresh database it does
  -- not exist yet. Failing here would break the file that stands a new
  -- server up.
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'disposition_rows') then
    return;
  end if;
  select pg_get_viewdef('public.disposition_rows'::regclass, true) into body;
  if body like '%is_perishable%' then
    return; -- already carries it
  end if;
  execute format(
    'create or replace view public.disposition_rows '
    'with (security_invoker = true) as '
    'select d.*, public.item_is_perishable(d.item_id) as is_perishable '
    'from (%s) d', rtrim(body, ';' || chr(10) || chr(13) || ' '));
end $$;

-- ── exhausted_unsold: the Unsold page and its Final Outcome tabs ───────────
do $$
declare
  body text;
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'exhausted_unsold') then
    return;
  end if;
  select pg_get_viewdef('public.exhausted_unsold'::regclass, true) into body;
  if body like '%is_perishable%' then
    return;
  end if;
  execute format(
    'create or replace view public.exhausted_unsold '
    'with (security_invoker = true) as '
    'select u.*, public.item_is_perishable(u.item_id) as is_perishable '
    'from (%s) u', rtrim(body, ';' || chr(10) || chr(13) || ' '));
end $$;

-- ── Verification ────────────────────────────────────────────────────────────
do $$
declare
  v text;
begin
  foreach v in array array['disposition_rows', 'exhausted_unsold'] loop
    -- Only assert about a view that actually exists here; see above.
    if not exists (select 1 from pg_class c
                     join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relname = v) then
      continue;
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = v
                      and column_name = 'is_perishable') then
      raise exception '% is missing is_perishable', v;
    end if;
    -- Both views must still run as the caller: recreating one drops the
    -- flag, and without it every per-yard policy under it is bypassed.
    if not exists (select 1 from pg_class c
                     join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relname = v
                      and 'security_invoker=true' = any (c.reloptions)) then
      raise exception '% must run as the caller', v;
    end if;
  end loop;
end $$;
