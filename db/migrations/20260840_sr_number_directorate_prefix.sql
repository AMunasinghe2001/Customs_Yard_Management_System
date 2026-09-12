-- ============================================================================
--  Re-write every existing SR number to carry its directorate prefix.
--
--      GL1/SR/62/2026   ->   CED/GL1/SR/62/2026
--
--  ⚠️ READ THIS BEFORE RUNNING. `sr_number` is a human-facing key, not just a
--  column. It is printed on the barcode/QR labels physically stuck to goods
--  sitting in the warehouses, and it appears in already-generated PDFs and in
--  audit-log detail blobs. Re-writing it means the paper in the yard no longer
--  matches the database until those labels are reprinted.
--
--  The safeguards below exist because of that:
--    * every old->new pair is kept in `public.sr_number_migration_log`,
--    * the whole thing runs in ONE transaction (all rows or none),
--    * a rollback script ships alongside it:
--        supabase/rollback_sr_number_directorate_prefix.sql
--    * it is idempotent — rows already carrying a prefix are skipped, so a
--      second run is a no-op rather than CED/CED/GL1/...
--
--  Yards under two directorates (NNR, Katunayaka, Rathmalana, Mattala) have no
--  single right answer from the yard alone. They are resolved by the LOWEST
--  sort_order directorate, and every such row is flagged `was_ambiguous` in the
--  log so ICT can review and correct them from the portal afterwards.
-- ============================================================================

set lock_timeout = '10s';

-- ── The audit trail / rollback source ───────────────────────────────────────
create table if not exists public.sr_number_migration_log (
  id            bigserial primary key,
  table_name    text not null,
  row_id        uuid not null,
  old_sr_number text not null,
  new_sr_number text not null,
  was_ambiguous boolean not null default false,
  migrated_at   timestamptz not null default now()
);

create index if not exists sr_number_migration_log_row_idx
  on public.sr_number_migration_log (table_name, row_id);

-- ── The rewrite ─────────────────────────────────────────────────────────────
do $mig$
declare
  v_updated int := 0;
  v_skipped int := 0;
  v_unknown int := 0;
begin
  -- A row is "already migrated" when its first segment names a directorate.
  -- Everything else with a recognisable <YARD>/SR/<n>/<yyyy> shape is a target.
  create temporary table _sr_map on commit drop as
  select
      p.id                                   as package_id,
      p.sr_number                            as old_sr,
      d.sr_prefix || '/' || p.sr_number      as new_sr,
      -- More than one directorate for this yard => the choice was a guess.
      (select count(*) from public.yard_directorates yd2
        where yd2.yard_code = y.code) > 1    as ambiguous
    from public.packages p
    join public.yards y
      on y.sr_prefix = split_part(p.sr_number, '/', 1)
    -- Lowest sort_order wins when a yard sits under several directorates.
    join lateral (
      select d2.sr_prefix, d2.sort_order
        from public.yard_directorates yd
        join public.directorates d2 on d2.code = yd.directorate_code
       where yd.yard_code = y.code
       order by d2.sort_order
       limit 1
    ) d on true
   where split_part(p.sr_number, '/', 2) = 'SR'
     and not exists (
       select 1 from public.directorates d3
        where d3.sr_prefix = split_part(p.sr_number, '/', 1)
     );

  select count(*) into v_updated from _sr_map;

  -- Rows we deliberately leave alone, reported so the run is auditable.
  select count(*) into v_skipped
    from public.packages p
   where exists (select 1 from public.directorates d
                  where d.sr_prefix = split_part(p.sr_number, '/', 1));

  select count(*) into v_unknown
    from public.packages p
   where split_part(p.sr_number, '/', 2) = 'SR'
     and not exists (select 1 from public.yards y
                      where y.sr_prefix = split_part(p.sr_number, '/', 1))
     and not exists (select 1 from public.directorates d
                      where d.sr_prefix = split_part(p.sr_number, '/', 1));

  insert into public.sr_number_migration_log
        (table_name, row_id, old_sr_number, new_sr_number, was_ambiguous)
  select 'packages', package_id, old_sr, new_sr, ambiguous from _sr_map;

  update public.packages p
     set sr_number = m.new_sr
    from _sr_map m
   where p.id = m.package_id;

  -- `forfeited_packages` denormalises the SR number; keep the two in step.
  insert into public.sr_number_migration_log
        (table_name, row_id, old_sr_number, new_sr_number, was_ambiguous)
  select 'forfeited_packages', f.id, m.old_sr, m.new_sr, m.ambiguous
    from public.forfeited_packages f
    join _sr_map m on m.package_id = f.package_id
   where f.sr_number = m.old_sr;

  update public.forfeited_packages f
     set sr_number = m.new_sr
    from _sr_map m
   where f.package_id = m.package_id
     and f.sr_number = m.old_sr;

  raise notice 'SR migration: % rewritten, % already prefixed, % unknown-prefix (left alone)',
    v_updated, v_skipped, v_unknown;
end
$mig$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
-- Ambiguous rows for ICT to review (a yard under two directorates).
select old_sr_number, new_sr_number
  from public.sr_number_migration_log
 where was_ambiguous
 order by id;

-- Anything still without a directorate prefix.
select sr_number
  from public.packages p
 where not exists (select 1 from public.directorates d
                    where d.sr_prefix = split_part(p.sr_number, '/', 1))
 order by sr_number
 limit 50;
