-- ============================================================================
--  043 · The database says which migrations it has had
--
--  ⚠️ THE RISK THIS CLOSES, and it grows with every branch: the app is about
--  to be installed at several offices against one cloud database, and
--  updates will be published from time to time. Some of those updates need a
--  schema change. Today NOTHING records which of the 42 migrations a given
--  database has actually had — they are applied by hand, in order, from
--  memory.
--
--  That fails in two directions, and both are silent:
--
--    * A migration is MISSED. The new app reads a column that is not there.
--      The officer sees "column ... does not exist" from whichever screen
--      happens to touch it first — which is exactly what
--      `column "*" does not exist` looked like, and that took a full
--      investigation to trace back to its cause.
--
--    * A branch updates BEFORE the database does. Every PC at that office
--      breaks at once, during working hours, and the only fix is to find
--      somebody who can run SQL against production.
--
--  So: the database states its own schema version, the app knows the minimum
--  it needs, and a mismatch is reported in plain words by the app rather
--  than discovered as a stray Postgres error three screens later.
--
--  ⚠️ This does NOT run migrations by itself. An app that silently alters a
--  customs database from a branch PC is a far worse idea than one that
--  refuses to start: schema changes stay a deliberate act by whoever
--  administers the server.
-- ============================================================================

set lock_timeout = '5s';

create table if not exists public.schema_migrations (
  -- The migration's number, e.g. 43. Ordered, gapless in practice, and the
  -- thing the app compares against.
  version     integer     primary key,
  -- The file it came from, so a reader can find it in the repo.
  name        text        not null,
  applied_at  timestamptz not null default now(),
  -- Who ran it. Null when applied as the superuser outside the app.
  applied_by  text        default current_user
);

comment on table public.schema_migrations is
  'One row per applied migration. The app checks the highest version here '
  'against the minimum it needs and refuses to run against a database that '
  'is behind, rather than failing later with a missing-column error.';

-- ⚠️ Readable by everyone who can sign in: the check runs BEFORE a session
-- is established, and a yard officer must be able to be told their database
-- is behind. It carries no data about goods or people.
alter table public.schema_migrations enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies
                  where schemaname = 'public'
                    and tablename = 'schema_migrations'
                    and policyname = 'schema_migrations_read_all') then
    create policy schema_migrations_read_all
      on public.schema_migrations for select using (true);
  end if;
end $$;

grant select on public.schema_migrations to authenticated, anon;

-- ── Backfill: this database plainly has everything up to 042 ───────────────
--
-- ⚠️ Recorded as a fact, not a guess. Each entry below is checked against
-- something that migration actually created, so a database that skipped one
-- does not get credited with it. Anything that cannot be proven is left out,
-- and the administrator applies it the ordinary way.
do $backfill$
declare
  has_col boolean;
begin
  -- 037: per-yard category targets
  if exists (select 1 from information_schema.tables
              where table_schema = 'public'
                and table_name = 'package_category_targets') then
    insert into public.schema_migrations (version, name)
    values (37, '037_category_targets_are_per_yard')
    on conflict (version) do nothing;
  end if;

  -- 039/040: perishable_rows excludes finalised items
  if exists (select 1 from information_schema.views
              where table_schema = 'public' and table_name = 'perishable_rows')
     and pg_get_viewdef('public.perishable_rows'::regclass, true) like '%sold%'
  then
    insert into public.schema_migrations (version, name) values
      (39, '039_perishable_rows_hides_finalised_items'),
      (40, '040_perishable_rows_also_hides_sold')
    on conflict (version) do nothing;
  end if;

  -- 041: item-level hand-overs
  if exists (select 1 from information_schema.tables
              where table_schema = 'public'
                and table_name = 'package_item_handovers') then
    insert into public.schema_migrations (version, name)
    values (41, '041_item_level_handover_for_entryless_goods')
    on conflict (version) do nothing;
  end if;

  -- 042: displaced goods
  select exists (select 1 from information_schema.columns
                  where table_schema = 'public'
                    and table_name = 'warehouse_entries'
                    and column_name = 'moved_for_space')
    into has_col;
  if has_col then
    insert into public.schema_migrations (version, name)
    values (42, '042_goods_moved_for_space_are_marked')
    on conflict (version) do nothing;
  end if;
end $backfill$;

-- This migration itself.
insert into public.schema_migrations (version, name)
values (43, '043_the_database_records_its_own_version')
on conflict (version) do nothing;

-- ── The one question the app asks ──────────────────────────────────────────
--
-- A function rather than a raw select, so the app has one name to call and
-- the answer cannot be confused with an empty table (no rows = version 0).
create or replace function public.schema_version()
returns integer
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(max(version), 0)::integer from public.schema_migrations;
$$;

revoke all on function public.schema_version() from public;
grant execute on function public.schema_version() to authenticated, anon;

-- ── Verification ───────────────────────────────────────────────────────────
do $verify$
declare
  v integer;
begin
  select public.schema_version() into v;
  if v < 43 then
    raise exception 'schema_version() reports %, expected at least 43', v;
  end if;
  raise notice 'PASS: this database reports schema version %', v;
end $verify$;
