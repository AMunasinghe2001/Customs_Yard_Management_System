-- ============================================================================
--  Allow 'release' as a tender-disposal outcome.
--  The yard Tender Disposals "Record Disposal" popup gains a Release option
--  (goods released back to the owner). Widen the CHECK constraint to accept it.
-- ============================================================================

alter table public.tender_disposals
  drop constraint if exists tender_disposals_disposal_type_check;

alter table public.tender_disposals
  add constraint tender_disposals_disposal_type_check
  check (disposal_type in ('sold', 're_export', 'govt_use', 'destroy', 'other', 'release'));

-- Done.
