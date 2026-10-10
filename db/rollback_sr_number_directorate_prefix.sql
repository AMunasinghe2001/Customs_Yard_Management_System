-- ============================================================================
--  ROLLBACK for 20260840_sr_number_directorate_prefix.sql
--
--  Puts every SR number back the way it was, using the old->new pairs the
--  migration recorded in `public.sr_number_migration_log`.
--
--  Run this if the prefixed numbers turn out to be wrong — most likely because
--  the barcode/QR labels already on the goods, or an existing stack of printed
--  reports, need to keep matching the database.
--
--  Safe to run more than once: a row whose SR number no longer equals the
--  migration's `new_sr_number` is left alone, so a partial rollback followed by
--  a full one does the right thing.
--
--  Afterwards the log is left in place on purpose — it is the evidence of what
--  happened. Clear it only once you are sure you will not roll back again:
--      truncate public.sr_number_migration_log;
-- ============================================================================

set lock_timeout = '10s';

do $rb$
declare
  v_pkg int := 0;
  v_fp  int := 0;
begin
  with undo as (
    select distinct on (row_id) row_id, old_sr_number, new_sr_number
      from public.sr_number_migration_log
     where table_name = 'packages'
     order by row_id, id desc
  )
  update public.packages p
     set sr_number = u.old_sr_number
    from undo u
   where p.id = u.row_id
     and p.sr_number = u.new_sr_number;
  get diagnostics v_pkg = row_count;

  with undo as (
    select distinct on (row_id) row_id, old_sr_number, new_sr_number
      from public.sr_number_migration_log
     where table_name = 'forfeited_packages'
     order by row_id, id desc
  )
  update public.forfeited_packages f
     set sr_number = u.old_sr_number
    from undo u
   where f.id = u.row_id
     and f.sr_number = u.new_sr_number;
  get diagnostics v_fp = row_count;

  raise notice 'Rollback: % packages, % forfeited_packages restored', v_pkg, v_fp;
end
$rb$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select count(*) filter (where exists (
         select 1 from public.directorates d
          where d.sr_prefix = split_part(p.sr_number, '/', 1))) as still_prefixed,
       count(*) as total
  from public.packages p;
