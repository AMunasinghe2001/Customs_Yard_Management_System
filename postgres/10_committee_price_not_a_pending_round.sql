-- ============================================================================
--  A committee's price is not a re-valuation waiting for a next tender.
--
--  `tender_revaluations` rows carry the RESERVE PRICE OF THE ROUND THEY ARE
--  KEYED TO. A row with `tender_sale_id IS NULL` therefore means one thing:
--  a price has been set for a round that has not been placed yet.
--
--  The committee price was being written BOTH onto tender_committees
--  (submitted_value, which is where the UI reads it) AND as one of these
--  pending rows. The screen then had two facts to render from one price:
--
--      Committee Tender 1   LKR 26,676,100   -- from tender_committees
--      Committee Tender 2   sealed           -- from the pending re-valuation
--
--  ⚠️ There is only ever ONE committee round. It is the last attempt a
--  package gets, and on these packages it is already over: every one of them
--  carries a decided unsold_proposal (converted / auction / government use /
--  removed from premises). A "next tender" cannot follow a final outcome, so
--  the phantom row announced a round that can never happen.
--
--  The UI now refuses to draw that tile in either case (a decided package, or
--  a pending figure equal to the committee's). This removes the cause: the
--  duplicate rows themselves. The committee's own submitted_value is
--  untouched, so nothing is lost -- the price is still on the record, in the
--  one place that owns it.
-- ============================================================================

set lock_timeout = '5s';

delete from public.tender_revaluations r
 using public.tender_committees tc
 where r.tender_sale_id is null
   and tc.forfeited_package_id = r.forfeited_package_id
   and tc.submitted_value is not null
   and abs(r.valuation_cost - tc.submitted_value) < 0.01;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  dupes     int;
  on_final  int;
  committees_kept int;
begin
  -- No pending row may repeat its own committee's price any more.
  select count(*) into dupes
    from public.tender_revaluations r
    join public.tender_committees tc
      on tc.forfeited_package_id = r.forfeited_package_id
   where r.tender_sale_id is null
     and tc.submitted_value is not null
     and abs(r.valuation_cost - tc.submitted_value) < 0.01;
  if dupes <> 0 then
    raise exception 'still % pending row(s) repeating a committee price', dupes;
  end if;

  -- And none may sit on a package whose outcome is already decided.
  select count(*) into on_final
    from public.tender_revaluations r
    join public.unsold_proposals up
      on up.forfeited_package_id = r.forfeited_package_id
   where r.tender_sale_id is null;
  if on_final <> 0 then
    raise notice
      'NOTE: % pending re-valuation(s) remain on decided packages; they do '
      'not repeat a committee price, so they were left alone.', on_final;
  end if;

  -- ⚠️ Every committee price is still on the record.
  select count(*) into committees_kept
    from public.tender_committees where submitted_value is not null;
  raise notice 'committee prices intact: %', committees_kept;
end
$verify$;
