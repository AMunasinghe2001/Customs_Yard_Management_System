-- ============================================================================
--  A final outcome is a DECISION, not a hand-over. The hand-over needs its own
--  record.
--
--  Sold goods already work this way: `tender_sale_items.is_delivered` says
--  whether the buyer has actually collected, and Mark Delivered on the yard's
--  table is what closes the warehouse entry. Until then the goods are still
--  physically in the yard and still accruing storage.
--
--  Top Management's four outcomes had no equivalent. A package ruled
--  "Government Use" on 3 July is decided -- but the goods sit in Warehouse 01
--  until somebody comes for them, and nothing recorded that they had. The yard
--  had no way to say "these have gone", and Central Disposal had no way to see
--  whether they had.
--
--  ⚠️ Two columns, mirroring the sold flow exactly:
--    delivered     -- has anyone taken them
--    delivered_at  -- when, so the storage charge stops at the right moment
--
--  Defaulted false: every existing decision is UNDELIVERED until someone says
--  otherwise. Backfilling "true" would assert a hand-over that nobody has
--  recorded, and the yard would lose the very list of what it still holds.
-- ============================================================================

set lock_timeout = '5s';

alter table public.unsold_proposals
  add column if not exists delivered boolean not null default false,
  add column if not exists delivered_at timestamptz;

-- ⚠️ The pair must stay consistent: delivered means a moment, and a moment
-- means delivered. A row with one and not the other cannot be read.
alter table public.unsold_proposals
  drop constraint if exists unsold_proposals_delivery_consistent;
alter table public.unsold_proposals
  add constraint unsold_proposals_delivery_consistent
  check ((delivered and delivered_at is not null)
         or (not delivered and delivered_at is null));

-- ── The toggle, as one statement ────────────────────────────────────────────
--  Same shape as disposal_toggle_delivery_status, so the yard and Central
--  Disposal both go through one place and cannot drift.
create or replace function public.disposal_toggle_outcome_delivery(
  p_proposal_id uuid,
  p_delivered   boolean)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  update public.unsold_proposals
     set delivered    = p_delivered,
         delivered_at = case when p_delivered then now() else null end,
         updated_at   = now()
   where id = p_proposal_id;

  if not found then
    raise exception 'no unsold_proposal with id %', p_proposal_id;
  end if;

  -- ⚠️ Delivered means the goods have LEFT. Close the warehouse entry the
  -- same way a sale does, or zone capacity and the storage charge keep
  -- counting goods that are no longer there.
  if p_delivered then
    update public.warehouse_entries w
       set is_returned  = true,
           returned_at  = now(),
           return_notes = '[FINAL:' || upper(
             (select proposal from public.unsold_proposals
               where id = p_proposal_id)) || ']',
           updated_at   = now()
      from public.forfeited_packages fp
      join public.unsold_proposals up on up.forfeited_package_id = fp.id
     where up.id = p_proposal_id
       and w.package_item_id = fp.item_id
       and coalesce(w.is_returned, false) = false;
  end if;
end;
$fn$;

grant execute on function public.disposal_toggle_outcome_delivery(uuid, boolean)
  to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  cols int;
  undelivered int;
begin
  select count(*) into cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'unsold_proposals'
     and column_name in ('delivered', 'delivered_at');
  if cols <> 2 then
    raise exception 'expected both delivery columns, found %', cols;
  end if;

  -- The constraint must actually refuse an inconsistent pair.
  begin
    update public.unsold_proposals
       set delivered = true, delivered_at = null
     where id = (select id from public.unsold_proposals limit 1);
    raise exception 'the consistency constraint did not fire';
  exception
    when check_violation then null;   -- refused, which is correct
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;

  if not exists (select 1 from pg_proc
                  where proname = 'disposal_toggle_outcome_delivery') then
    raise exception 'the toggle function was not created';
  end if;

  select count(*) into undelivered
    from public.unsold_proposals where not delivered;
  raise notice
    '% decided package(s) are awaiting hand-over, which is the yard''s list '
    'of what it still holds.', undelivered;
end
$verify$;
