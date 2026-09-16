-- ============================================================================
--  041 · Goods arrived on their outcome page ALREADY finished
--
--  ⚠️ THE BUG, reported directly: a perishable released (or destroyed) from
--  Perishable Goods landed on Released Goods / Destroyed Goods already
--  reading "Delivered" / "Destroyed", with no button left to press. The
--  officer never confirmed the hand-over, and there is no record that anyone
--  ever did -- the page simply asserted it.
--
--  Two separate causes, one shape:
--
--   1. Released Goods rendered `delivered: row.delivered ?? (entry == null)`.
--      A perishable released straight out of the yard has NO warehouse entry
--      by design (Perishable Goods skips warehousing), so `entry == null` was
--      true for every one of them -- and the fallback read that absence as
--      proof of hand-over. Fixed in Dart: the fallback is now plain `false`.
--
--   2. Destroyed Goods asked `package_items.status = 'destroyed'`. But that
--      is the field a Final Disposition of Destroy SETS in order to route the
--      item here in the first place (see migration 039). It is therefore true
--      for every row on the page by construction, so the question "has this
--      been destroyed yet?" always answered yes. Fixed in Dart by reading the
--      view's `is_destroyed` (which reads `destruction_items`, the record of
--      the ACT) instead.
--
--  But fixing the reads alone leaves the officer a button that cannot write.
--  Both hand-over paths key on `warehouse_entries.id`:
--  `yard_toggle_released_delivery(p_entry_id, ...)` raises 'no warehouse_entry
--  with id %' for an item that never had one -- and `destruction_items`
--  requires a `forfeited_package_id` (NOT NULL) plus a destruction batch,
--  neither of which a directly-destroyed perishable has.
--
--  So goods with no warehouse entry need a place of their own to record the
--  act. That is `package_item_handovers` below: ONE row per item, written
--  when the officer confirms, carrying who / when / the receipt.
--
--  ⚠️ Deliberately NOT done by fabricating a warehouse_entries row: that
--  table's `warehouse_id` and `hold_reason` are NOT NULL, so it would invent
--  a warehouse and a hold reason the goods never had. That is the same
--  reasoning postgres/70 and migration 039 already follow, and the user
--  explicitly rejected inventing those rows.
-- ============================================================================

set lock_timeout = '5s';

-- ── The record of the act, for goods with no entry to carry it ─────────────
create table if not exists public.package_item_handovers (
  package_item_id uuid primary key
    references public.package_items(id) on delete cascade,
  yard            text        not null,

  -- Which act this records. A release is handed to the owner; a destruction
  -- is carried out. One row per item either way: an item has exactly one
  -- final outcome, so it can only ever be handed over once.
  kind            text        not null
    check (kind in ('released', 'destroyed')),

  done            boolean     not null default false,
  done_at         timestamptz,
  done_by         uuid        references public.profiles(id),
  receipt_no      text,
  charge          numeric(14,2),
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists package_item_handovers_yard_idx
  on public.package_item_handovers (yard);

-- ── Per-yard isolation, the same shape every other table here uses ─────────
alter table public.package_item_handovers enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies
                  where schemaname = 'public'
                    and tablename = 'package_item_handovers'
                    and policyname = 'package_item_handovers_by_yard') then
    create policy package_item_handovers_by_yard
      on public.package_item_handovers
      for all
      using (
        public.auth_user_is_disposal()
        or yard = (select yard from public.profiles where id = auth.uid()))
      with check (
        public.auth_user_is_disposal()
        or yard = (select yard from public.profiles where id = auth.uid()));
  end if;
end $$;

grant select, insert, update on public.package_item_handovers to authenticated;

-- ── The write: an officer confirms the act ─────────────────────────────────
--
-- Shaped like `yard_toggle_released_delivery`, and refusing the same things:
-- it will not record a hand-over for an item that is not actually finished,
-- and it will not let one yard write another's row.
create or replace function public.yard_mark_item_handover(
  p_item_id    uuid,
  p_kind       text,
  p_receipt_no text default null,
  p_charge     numeric default null,
  p_handed_at  timestamptz default null,
  p_notes      text default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $h$
declare
  v_yard   text;
  v_status text;
begin
  select coalesce(pi.yard, p.yard), lower(trim(coalesce(pi.status, '')))
    into v_yard, v_status
    from public.package_items pi
    join public.packages p on p.id = pi.package_id
   where pi.id = p_item_id;

  if v_yard is null then
    raise exception 'no package_item with id %', p_item_id;
  end if;

  if p_kind not in ('released', 'destroyed') then
    raise exception 'unknown handover kind %', p_kind;
  end if;

  -- ⚠️ The item's status must already BE the outcome being handed over.
  -- Without this the function would happily record the hand-over of goods
  -- still sitting in the yard undecided.
  if v_status <> p_kind then
    raise exception 'item % is % , not %', p_item_id, v_status, p_kind;
  end if;

  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = auth.uid())) then
    raise exception 'not authorized';
  end if;

  insert into public.package_item_handovers as h
    (package_item_id, yard, kind, done, done_at, done_by,
     receipt_no, charge, notes)
  values
    (p_item_id, v_yard, p_kind, true, coalesce(p_handed_at, now()), auth.uid(),
     p_receipt_no, p_charge, p_notes)
  on conflict (package_item_id) do update
     set done       = true,
         kind       = excluded.kind,
         done_at    = excluded.done_at,
         done_by    = excluded.done_by,
         receipt_no = coalesce(excluded.receipt_no, h.receipt_no),
         charge     = coalesce(excluded.charge, h.charge),
         notes      = coalesce(excluded.notes, h.notes),
         updated_at = now();
end;
$h$;

revoke all on function public.yard_mark_item_handover(
  uuid, text, text, numeric, timestamptz, text) from public;
grant execute on function public.yard_mark_item_handover(
  uuid, text, text, numeric, timestamptz, text) to authenticated;

-- ── Teach disposition_rows to read it ──────────────────────────────────────
--
-- ⚠️ Re-wrapped, not retyped: the view is built by postgres/70 and carries
-- several columns this file has no business restating. Wrapping it keeps ONE
-- definition of the row and lets this migration add only what it owns.
--
-- ⚠️ This wrap must survive a later `create or replace view` on
-- disposition_rows -- which is exactly how `is_perishable` (migration 016)
-- was silently lost when postgres/70 recreated the view. Re-running THIS
-- file after any such change restores it; the guard below makes that safe.
do $$
declare
  body text;
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'disposition_rows') then
    return;
  end if;
  select pg_get_viewdef('public.disposition_rows'::regclass, true) into body;
  if body like '%item_handover_done%' then
    return; -- already carries it
  end if;
  execute format(
    'create or replace view public.disposition_rows '
    'with (security_invoker = true) as '
    'select d.*, '
    '  coalesce((select h.done from public.package_item_handovers h '
    '             where h.package_item_id = d.item_id), false) '
    '    as item_handover_done, '
    '  (select h.done_at from public.package_item_handovers h '
    '    where h.package_item_id = d.item_id) '
    '    as item_handover_at, '
    '  (select h.receipt_no from public.package_item_handovers h '
    '    where h.package_item_id = d.item_id) '
    '    as item_handover_receipt '
    'from (%s) d', rtrim(body, ';' || chr(10) || chr(13) || ' '));
end $$;

grant select on public.disposition_rows to authenticated, anon;

-- ── Verification ───────────────────────────────────────────────────────────
-- Every column this migration and its predecessors promise must be present.
-- ⚠️ is_perishable is checked HERE too: it has already been lost once, to a
-- plain `create or replace view` that did not know migration 016 had wrapped
-- it, and the only symptom was a filter chip quietly disappearing.
do $verify2$
declare
  c text;
begin
  foreach c in array array['is_perishable', 'is_destroyed',
                           'item_handover_done'] loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public'
                      and table_name = 'disposition_rows'
                      and column_name = c) then
      raise exception 'disposition_rows is missing %', c;
    end if;
  end loop;

  if not exists (select 1 from pg_class c2
                   join pg_namespace n on n.oid = c2.relnamespace
                  where n.nspname = 'public' and c2.relname = 'disposition_rows'
                    and 'security_invoker=true' = any (c2.reloptions)) then
    raise exception 'disposition_rows lost security_invoker';
  end if;

  raise notice 'PASS: disposition_rows carries is_perishable, is_destroyed '
               'and item_handover_done, and still runs as the caller';
end $verify2$;

-- Nothing may arrive already handed over: this table starts empty, so every
-- released/destroyed item must currently read as NOT handed over.
do $verify3$
declare
  n int;
begin
  select count(*) into n from public.package_item_handovers where done;
  raise notice 'item-level hand-overs recorded so far: %', n;
end $verify3$;
