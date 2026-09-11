-- ============================================================================
-- Every yard-scoped read filters on `yard`, so every table carrying that
-- column needs an index on it. Three were missing: without one, each query
-- from any yard sequentially scans the whole table, and the cost grows with
-- the number of yards using the system rather than with one yard's data.
--
-- These three are empty today, which is exactly when to add the index: it is
-- free now, and the seq scan would only start hurting once the tenders
-- workflow is in real use across several yards.
--
-- Safe to re-run.
-- ============================================================================

-- ⚠️ CREATES the missing ones rather than naming three by hand.
--
-- Listing the three that happened to be missing on THIS database made the
-- migration a snapshot of one server. On a fresh database — the one case
-- that matters, because 02_schema.sql is what stands a new server up —
-- twelve more were missing and the verification below failed the whole
-- file. Deriving the list means the rule holds wherever it runs.
do $$
declare
  t text;
begin
  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name
     where c.table_schema = 'public'
       and c.column_name = 'yard'
       and tb.table_type = 'BASE TABLE'
       and not exists (
         select 1 from pg_indexes i
          where i.schemaname = 'public'
            and i.tablename = c.table_name
            and i.indexdef like '%(yard%'
       )
  loop
    execute format('create index if not exists %I on public.%I (yard)',
                   t || '_yard_idx', t);
  end loop;
end $$;

-- Verification: no BASE TABLE with a `yard` column may be left unindexed on
-- it. Catches the next table that adds the column and forgets the index.
do $$
declare
  missing text;
begin
  select string_agg(c.table_name, ', ') into missing
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
   where c.table_schema = 'public'
     and c.column_name = 'yard'
     and tb.table_type = 'BASE TABLE'
     and not exists (
       select 1 from pg_indexes i
        where i.schemaname = 'public'
          and i.tablename = c.table_name
          and i.indexdef like '%(yard%'
     );

  if missing is not null then
    raise exception 'yard column is not indexed on: %', missing;
  end if;
end $$;
