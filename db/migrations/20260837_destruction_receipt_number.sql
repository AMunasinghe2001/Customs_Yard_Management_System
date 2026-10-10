-- ============================================================================
--  Destruction items get a RECEIPT NUMBER.
--
--  A sale records `tender_sale_items.receipt_number` when the goods are marked
--  sold. A destruction had no equivalent, so the Destroyed report could not
--  show the receipt the destruction was recorded against.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.destruction_items
  add column if not exists receipt_number text;

-- ── Backfill from `notes` ───────────────────────────────────────────────────
--  `disposal_mark_destruction_item_destroyed` stored the receipt in `notes`
--  for want of a column of its own. Carry those across so existing rows report
--  their receipt, and leave `notes` alone (it may hold other text too).
update public.destruction_items
   set receipt_number = trim(notes)
 where receipt_number is null
   and notes is not null
   and trim(notes) <> '';

-- ── Record the receipt in its own column from now on ────────────────────────
--  `disposal_mark_destruction_item_destroyed` also writes the [FINAL:DESTROYED]
--  warehouse entry and flips the item's status (see 20260630_destruction_price
--  .sql). Re-declaring the whole function here would be a copy that silently
--  drifts from it, so instead a TRIGGER mirrors `notes` into the new column —
--  the RPC keeps writing `notes` exactly as it does today, and nothing else
--  about it changes.
create or replace function public.destruction_items_sync_receipt()
returns trigger
language plpgsql
as $$
begin
  -- Only fill it in; never overwrite a receipt set deliberately.
  if new.receipt_number is null
     and new.notes is not null
     and trim(new.notes) <> '' then
    new.receipt_number := trim(new.notes);
  end if;
  return new;
end;
$$;

drop trigger if exists destruction_items_receipt_sync on public.destruction_items;
create trigger destruction_items_receipt_sync
  before insert or update of notes on public.destruction_items
  for each row execute function public.destruction_items_sync_receipt();

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select count(*)                                   as destruction_items,
       count(receipt_number)                      as with_receipt,
       count(*) filter (where destroyed)          as destroyed
  from public.destruction_items;
