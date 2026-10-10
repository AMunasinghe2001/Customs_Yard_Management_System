-- ============================================================================
--  The committee round does not go out to bidders.
--
--  The rounds a package can go through are:
--
--    attempt 1  Valuation Tender   -- priced by the Valuation Directorate
--    attempt 2  Tender 1           -- priced from the previous round's bids
--    attempt 3  Tender 2
--    attempt 4  Tender 3
--    attempt 5  Committee Tender   -- Top Management sets the value
--
--  ⚠️ Only attempts 1-4 are open to offers. The committee round is a decision,
--  not an auction: the committee sets a value, and if the goods still do not
--  move they fall straight through to Unsold Goods. Bids recorded there are
--  money nobody could have offered — the Tender History showed a "Committee
--  Tender 1" card with bids of Rs. 119,687 and Rs. 96,806 against it.
--
--  3 such bids existed and have been removed. This stops more being written.
--
--  Safe to re-run.
-- ============================================================================

create or replace function public.tender_bids_reject_committee_round()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_attempt int;
begin
  -- Which attempt is this bid's round for this package?
  select count(*) into v_attempt
    from public.tender_sale_items tsi
    join public.tender_sales ts on ts.id = tsi.tender_sale_id
   where tsi.forfeited_package_id = new.forfeited_package_id
     and ts.sale_date <= (select ts2.sale_date
                            from public.tender_sales ts2
                           where ts2.id = new.tender_sale_id);

  -- ⚠️ Attempts 1-4 only. 5 and beyond is the committee, which takes no bids.
  if v_attempt > 4 then
    raise exception
      'The committee round does not take bids. Attempt % for this package is '
      'a Top Management committee round: the committee sets a value, and '
      'unsold goods pass to Unsold Goods.', v_attempt
      using errcode = '22023';
  end if;

  return new;
end;
$fn$;

drop trigger if exists tender_bids_reject_committee_round on public.tender_bids;
create trigger tender_bids_reject_committee_round
  before insert on public.tender_bids
  for each row execute function public.tender_bids_reject_committee_round();


-- ── Verify ──────────────────────────────────────────────────────────────────
do $$
declare
  v_fp uuid;
  v_ts uuid;
  v_blocked boolean := false;
  v_attempt int;
begin
  -- A package that has already reached a committee round.
  select tsi.forfeited_package_id, tsi.tender_sale_id, x.rn
    into v_fp, v_ts, v_attempt
    from (select tsi2.forfeited_package_id fpid, tsi2.tender_sale_id tsid,
                 row_number() over (partition by tsi2.forfeited_package_id
                                    order by ts2.sale_date) rn
            from public.tender_sale_items tsi2
            join public.tender_sales ts2 on ts2.id = tsi2.tender_sale_id) x
    join public.tender_sale_items tsi
      on tsi.forfeited_package_id = x.fpid and tsi.tender_sale_id = x.tsid
   where x.rn = 5
   limit 1;

  if v_fp is null then
    raise notice 'no committee round to verify with - skipped';
    return;
  end if;

  begin
    insert into public.tender_bids
      (forfeited_package_id, tender_sale_id, amount, yard)
    values (v_fp, v_ts, 1, 'GL1');
  exception when others then
    v_blocked := true;
  end;

  if not v_blocked then
    delete from public.tender_bids
     where forfeited_package_id = v_fp and tender_sale_id = v_ts and amount = 1;
    raise exception
      'a bid was accepted on a committee round - the trigger is not working';
  end if;

  -- ⚠️ And an ORDINARY round must still accept one, or this has broken
  -- tendering altogether.
  select tsi.forfeited_package_id, tsi.tender_sale_id
    into v_fp, v_ts
    from (select tsi2.forfeited_package_id fpid, tsi2.tender_sale_id tsid,
                 row_number() over (partition by tsi2.forfeited_package_id
                                    order by ts2.sale_date) rn
            from public.tender_sale_items tsi2
            join public.tender_sales ts2 on ts2.id = tsi2.tender_sale_id) x
    join public.tender_sale_items tsi
      on tsi.forfeited_package_id = x.fpid and tsi.tender_sale_id = x.tsid
   where x.rn = 2
   limit 1;

  if v_fp is not null then
    insert into public.tender_bids
      (forfeited_package_id, tender_sale_id, amount, yard)
    values (v_fp, v_ts, 1, 'GL1');
    delete from public.tender_bids
     where forfeited_package_id = v_fp and tender_sale_id = v_ts and amount = 1;
  end if;

  raise notice
    'verified: a committee round refuses bids, an ordinary round still takes them';
end $$;
