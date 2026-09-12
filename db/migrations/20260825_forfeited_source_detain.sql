-- ============================================================================
--  Forfeited-package SOURCE: add 'detain'
--  Run after 20260616_forfeited_source_other.sql.
--
--  The 30-day appeal window now covers EVERY status, so a DETAINED package can
--  have an appeal lodged against it. Lodging one materialises a
--  forfeited_packages row (see `appeal_ensure_forfeited_row` in
--  20260824_appeal_materialise_row.sql), and that row's `source` is 'detain'.
--
--  The existing check constraint only allowed forfeit / abandoned / other, so
--  the insert failed with:
--    23514 ... violates check constraint "forfeited_packages_source_check"
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.forfeited_packages
  drop constraint if exists forfeited_packages_source_check;

alter table public.forfeited_packages
  add constraint forfeited_packages_source_check
    check (source in ('forfeit', 'abandoned', 'other', 'detain'));

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select conname, pg_get_constraintdef(oid) as definition
  from pg_constraint
 where conrelid = 'public.forfeited_packages'::regclass
   and conname = 'forfeited_packages_source_check';
