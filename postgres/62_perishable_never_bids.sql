-- ============================================================================
--  62 · A perishable never takes bids
--
--  Perishable goods run one SPECIAL tender sale. If it fails they go straight
--  to the Top Management Directorate through Unsold Perishables -- there is no
--  re-valuation and no second round to price, because the goods are rotting.
--  `unsold_retender_pool` has said so since migration 44 (`source <>
--  'perishable'`), so Central Disposal's Unsold Tenders tab never lists one and
--  its Bids cell cannot reach one.
--
--  ⚠️ Nothing stopped the WRITE, though. `saveTenderRoundBids` takes any
--  forfeited package id, and 20 bids sit against 28 perishable packages in this
--  yard -- recorded through the special sale, on goods whose whole point is
--  that nobody re-prices them. Every one of them is a bid on a round that has
--  no successor.
--
--  ⚠️ The DELETE is deliberate and the count is asserted. These are not
--  history worth keeping: a perishable's bids are read by exactly one thing,
--  the re-valuation flow, and that flow is unreachable for perishables. Left
--  in place they would keep appearing in the popup as rounds an officer could
--  act on.
-- ============================================================================

set lock_timeout = '5s';

-- ── The rule, in the database ───────────────────────────────────────────────
create or replace function public.tender_bids_reject_perishable()
returns trigger
language plpgsql
as $fn$
declare
  v_source text;
begin
  select fp.source into v_source
    from public.forfeited_packages fp
   where fp.id = new.forfeited_package_id;

  if coalesce(v_source, '') = 'perishable' then
    raise exception
      'perishable goods take no bids: they run one special sale and go '
      'straight to the Top Management Directorate if it fails'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$fn$;

drop trigger if exists tender_bids_no_perishable on public.tender_bids;
create trigger tender_bids_no_perishable
  before insert or update on public.tender_bids
  for each row execute function public.tender_bids_reject_perishable();

-- ── Clear the bids that should never have been recorded ─────────────────────
delete from public.tender_bids b
 using public.forfeited_packages fp
 where fp.id = b.forfeited_package_id
   and coalesce(fp.source, '') = 'perishable';

-- ⚠️ And the re-valuations, for the same reason. There are none today, but a
-- perishable that acquired one would show a "re-valued" badge on a round that
-- can never run again.
delete from public.tender_revaluations tr
 using public.forfeited_packages fp
 where fp.id = tr.forfeited_package_id
   and coalesce(fp.source, '') = 'perishable';

-- ── Verify against live data ────────────────────────────────────────────────
do $verify$
declare
  n_bids   int;
  n_revals int;
  n_pool   int;
  ok       boolean;
begin
  select count(*) into n_bids
    from public.tender_bids b
    join public.forfeited_packages fp on fp.id = b.forfeited_package_id
   where coalesce(fp.source, '') = 'perishable';
  if n_bids > 0 then
    raise exception '% perishable bids survived the delete', n_bids;
  end if;

  select count(*) into n_revals
    from public.tender_revaluations tr
    join public.forfeited_packages fp on fp.id = tr.forfeited_package_id
   where coalesce(fp.source, '') = 'perishable';
  if n_revals > 0 then
    raise exception '% perishable re-valuations survived', n_revals;
  end if;

  -- ⚠️ The trigger must actually FIRE. A trigger that exists and does not
  -- reject is worse than none: the rule reads as enforced and is not.
  begin
    insert into public.tender_bids
      (forfeited_package_id, tender_sale_id, amount, yard)
    select fp.id, ts.id, 1, fp.yard
      from public.forfeited_packages fp
      cross join lateral (select id from public.tender_sales limit 1) ts
     where coalesce(fp.source, '') = 'perishable'
     limit 1;
    ok := false;
  exception when others then
    ok := sqlerrm like '%perishable goods take no bids%';
  end;
  if not ok then
    raise exception 'the trigger did not reject a perishable bid';
  end if;

  -- The pool has excluded perishables since migration 44; confirm it still
  -- does, since that is what keeps the UI from offering the cell at all.
  select count(*) into n_pool
    from public.unsold_retender_pool p
    join public.forfeited_packages fp on fp.id = p.forfeited_package_id
   where coalesce(fp.source, '') = 'perishable';
  if n_pool > 0 then
    raise exception '% perishables are in the re-tender pool', n_pool;
  end if;

  raise notice 'verified: a perishable takes no bids and no re-valuation';
end $verify$;
