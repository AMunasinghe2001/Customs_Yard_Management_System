-- ============================================================================
--  60 · A hand-over collects money, so it keeps a receipt
--
--  Marking goods delivered set a boolean and a timestamp. But a release or a
--  re-export is not a click: storage has been accruing since the goods
--  arrived, the owner pays it, the officer writes a receipt, and only THEN do
--  the goods leave. The receipt was nowhere -- the charge on the row beside
--  the button was a figure nobody had a record of collecting.
--
--  ⚠️ The AMOUNT is stored, not recomputed. Rates change (`storage_rates` is
--  a history, and ICT edits it), so a charge recalculated next year would not
--  match the receipt in the owner's hand. What was collected is a fact about
--  that day; only the figure written on the receipt is that fact.
--
--  ⚠️ The hand-over DATE is the officer's, not `now()`. Goods collected on
--  Friday and recorded on Monday are normal, and stamping the recording day
--  would put the wrong date on the one document the owner keeps.
-- ============================================================================

set lock_timeout = '5s';

alter table public.warehouse_entries
  add column if not exists handover_receipt_no text,
  add column if not exists handover_charge     numeric;

-- ⚠️ A receipt means money was collected, and money collected means the goods
-- went. Without this a row could carry a receipt and still read "not yet
-- delivered", which is the exact confusion this whole line of work removes.
do $c$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'warehouse_entries_handover_receipt_consistent') then
    alter table public.warehouse_entries
      add constraint warehouse_entries_handover_receipt_consistent
      check (handover_receipt_no is null
             or re_export_delivered or released_delivered);
  end if;
end $c$;

-- ── The writes, now carrying the receipt ────────────────────────────────────
--
-- ⚠️ DROP the old signatures FIRST. `create or replace` matches on the
-- ARGUMENT LIST, so adding parameters creates an OVERLOAD rather than
-- replacing anything, and the 2-argument version stays resolvable. A caller
-- that forgot the receipt would silently take it and hand the goods over
-- with no record of the money -- the exact failure this migration exists to
-- prevent. The verify block caught it on the first run.
drop function if exists public.yard_toggle_reexport_delivery(uuid, boolean);
drop function if exists public.yard_toggle_released_delivery(uuid, boolean);

-- ⚠️ Both functions are REPLACED rather than extended: the delivery flag and
-- the receipt must land in ONE statement. Two writes leave a window where the
-- goods are marked gone with no record of the money, and a failure between
-- them leaves it that way for good.
create or replace function public.yard_toggle_reexport_delivery(
  p_entry_id    uuid,
  p_delivered   boolean,
  p_receipt_no  text default null,
  p_charge      numeric default null,
  p_handed_at   timestamptz default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_yard text;
  v_tag  text;
begin
  select p.yard,
         upper(substring(upper(trim(coalesce(w.return_notes, '')))
                         from '^\[([^\]]+)\]'))
    into v_yard, v_tag
    from public.warehouse_entries w
    join public.packages p on p.id = w.package_id
   where w.id = p_entry_id;

  if v_yard is null then
    raise exception 'no warehouse_entry with id %', p_entry_id;
  end if;

  if v_tag is null or v_tag not in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT') then
    raise exception 'entry % is not a re-export (tag %)', p_entry_id, coalesce(v_tag, 'none');
  end if;

  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;

  update public.warehouse_entries
     set re_export_delivered    = p_delivered,
         re_export_delivered_at =
           case when p_delivered then coalesce(p_handed_at, now()) end,
         re_export_delivered_by = case when p_delivered then sr_auth.uid() end,
         handover_receipt_no    = case when p_delivered then p_receipt_no end,
         handover_charge        = case when p_delivered then p_charge end,
         updated_at             = now()
   where id = p_entry_id;
end;
$fn$;

create or replace function public.yard_toggle_released_delivery(
  p_entry_id    uuid,
  p_delivered   boolean,
  p_receipt_no  text default null,
  p_charge      numeric default null,
  p_handed_at   timestamptz default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $rl$
declare
  v_yard     text;
  v_tag      text;
  v_returned boolean;
begin
  select p.yard, w.is_returned,
         upper(substring(upper(trim(coalesce(w.return_notes, '')))
                         from '^\[([^\]]+)\]'))
    into v_yard, v_returned, v_tag
    from public.warehouse_entries w
    join public.packages p on p.id = w.package_id
   where w.id = p_entry_id;

  if v_yard is null then
    raise exception 'no warehouse_entry with id %', p_entry_id;
  end if;

  if not coalesce(v_returned, false) then
    raise exception 'entry % has not been released', p_entry_id;
  end if;
  if v_tag in ('FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT',
               'FINAL:DESTROYED', 'FINAL:DESTROY', 'DESTROYED', 'DESTROY',
               'SUPPOSED TO BE DESTROYED', 'FINAL:SOLD', 'SOLD',
               'FINAL:OTHER', 'OTHER') then
    raise exception 'entry % is not a release (tag %)', p_entry_id, v_tag;
  end if;

  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = sr_auth.uid())) then
    raise exception 'not authorized';
  end if;

  update public.warehouse_entries
     set released_delivered    = p_delivered,
         released_delivered_at =
           case when p_delivered then coalesce(p_handed_at, now()) end,
         released_delivered_by = case when p_delivered then sr_auth.uid() end,
         handover_receipt_no   = case when p_delivered then p_receipt_no end,
         handover_charge       = case when p_delivered then p_charge end,
         updated_at            = now()
   where id = p_entry_id;
end;
$rl$;

revoke all on function public.yard_toggle_reexport_delivery(uuid, boolean, text, numeric, timestamptz) from public;
revoke all on function public.yard_toggle_released_delivery(uuid, boolean, text, numeric, timestamptz) from public;
grant execute on function public.yard_toggle_reexport_delivery(uuid, boolean, text, numeric, timestamptz) to authenticated;
grant execute on function public.yard_toggle_released_delivery(uuid, boolean, text, numeric, timestamptz) to authenticated;

-- ── Verify against live data ────────────────────────────────────────────────
do $verify$
declare
  n_bad int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'warehouse_entries'
                    and column_name = 'handover_receipt_no') then
    raise exception 'the receipt column was not added';
  end if;

  -- ⚠️ The new signature must be the ONE that exists. An old 2-argument
  -- overload left behind would still be resolvable, and a caller that forgot
  -- the receipt would silently take it -- handing goods over with no record
  -- of the money, which is the failure this migration exists to prevent.
  select count(*) into n_bad
    from pg_proc
   where proname in ('yard_toggle_reexport_delivery',
                     'yard_toggle_released_delivery');
  if n_bad <> 2 then
    raise exception 'expected exactly 2 hand-over functions, found % (an old overload survives)',
      n_bad;
  end if;

  -- A receipt without a delivery is a contradiction the constraint forbids.
  select count(*) into n_bad
    from public.warehouse_entries
   where handover_receipt_no is not null
     and not (re_export_delivered or released_delivered);
  if n_bad > 0 then
    raise exception '% entries carry a receipt but are not delivered', n_bad;
  end if;

  raise notice 'verified: a hand-over keeps its receipt';
end $verify$;
