-- The Appeal Directorate's two tabs, as a view.
--
-- ⚠️ Both tabs fetched every forfeited package in the country — through
-- `packages -> package_items -> warehouse_entries -> warehouses`, ~208ms —
-- then expanded, filtered and paged the result in Dart with
-- `pageSlice(rows, page, kClientPageSize)`. Client-side paging still loads
-- everything; it only renders less.
--
-- FIVE rules decide what the directorate sees, and every one of them ran in
-- Dart. They are transcribed here from the model, not reinvented.
--
-- 1. `source = 'forfeit'` only. Detain / Abandoned / Other goods carry no
--    forfeited row until something acts on them.
--
-- 2. ⚠️ EXPANDED to one row per ITEM. The same SR appears once per item, so
--    each can be decided separately. A package-level row (item_id is null)
--    does NOT mean every item was forfeited — items are disposed individually
--    — so only genuinely forfeited items are expanded out of one.
--
-- 3. ⚠️ Genuinely forfeited means the ITEM says so: its status is
--    forfeit/forfeited/forfiet/confiscated, or a returned warehouse entry
--    carries a `[FORFEIT…` / `[CONFISCAT…` note. Same rule as the yard's own
--    Forfeited table (PackageModel.isItemForfeited), so the two stay in
--    lock-step.
--
-- 4. Packages every item of which is FINALISED are dropped: there is nothing
--    left to appeal. Finalised means a `[FINAL:` warehouse entry, or a
--    terminal status (sold / destroyed / re-exported / released).
--
-- 5. ⚠️ A MULTI-ITEM package must not let its package-level `appeal_decision`
--    bleed onto an item with no entry of its own in `item_appeal_decisions`.
--    Deciding one item — or a stale package-level value left by the old flow
--    — would otherwise mark every sibling decided, and the directorate would
--    never see them again.
--
-- The hold is per item too: a hold freezes goods even after the window
-- closes, which is the opposite of what the deadline does.
--
--   Active  = no decision, and (still in the window OR on hold)
--   Decided = a decision exists
--
-- Between them they do NOT cover everything: a package whose window closed
-- with no decision and no hold is on neither tab, which is correct — the yard
-- may act on it and the directorate has nothing left to do.

drop view if exists public.appeal_rows cascade;

create view public.appeal_rows as
with
-- Rule 3: which items are genuinely forfeited.
forfeited_item as (
  select
    pi.id as item_id,
    pi.package_id,
    pi.item_name,
    pi.quantity,
    pi.created_at
  from public.package_items pi
  where lower(coalesce(pi.status, '')) in
        ('forfeit', 'forfeited', 'forfiet', 'confiscated')
     or exists (
       select 1 from public.warehouse_entries we
        where we.package_item_id = pi.id
          and coalesce(we.is_returned, false)
          and (upper(trim(coalesce(we.return_notes, ''))) like '[FORFEIT%'
            or upper(trim(coalesce(we.return_notes, ''))) like '[CONFISCAT%'))
),
-- Rule 4: a package with nothing left to appeal.
finalised_package as (
  select pi.package_id
    from public.package_items pi
   group by pi.package_id
  having bool_and(
    lower(coalesce(pi.status, '')) in
      ('sold', 'destroyed', 're-exported', 'released')
    or exists (select 1 from public.warehouse_entries we
                where we.package_item_id = pi.id
                  and upper(trim(coalesce(we.return_notes, '')))
                      like '[FINAL:%'))
),
item_count as (
  select package_id, count(*) as n from public.package_items group by package_id
),
-- Rule 2: one row per item.
expanded as (
  select
    fp.id as forfeited_package_id,
    chosen.item_id,
    chosen.item_name,
    fp.package_id,
    fp.sr_number,
    fp.consignee_name,
    fp.yard,
    fp.source,
    fp.entry_qty,
    fp.forfeited_at,
    fp.appeal_deadline,
    fp.appeal_decided_at,
    fp.appeal_hold,
    fp.held_item_ids,
    fp.appeal_decision,
    fp.item_appeal_decisions,
    coalesce(ic.n, 0) as package_item_count
  from public.forfeited_packages fp
  left join item_count ic on ic.package_id = fp.package_id
  cross join lateral (
    -- ⚠️ Which items this forfeited row becomes, transcribed from the Dart
    -- rather than from the comment above it -- the two disagree, and the code
    -- is what the directorate has been seeing.
    --
    -- The comment says "a per-item FP already names its single item so it is
    -- kept as-is". The code says otherwise: `items` is the package's WHOLE
    -- item list unless the row is package-level AND the package holds more
    -- than one item, so a per-item row expands across all of them, with
    -- `itemId` overwritten per row. On the live data that is what the Appeal
    -- Directorate sees -- SR/52/2026 has one forfeited row and shows three
    -- appeal rows, one per item.
    select *
      from (
        -- The package's items, when the row is per-item (whatever it names)
        -- or the package holds exactly one.
        select pi.id as item_id, pi.item_name, 0 as ord
          from public.package_items pi
         where pi.package_id = fp.package_id
           and (fp.item_id is not null or coalesce(ic.n, 0) <= 1)

        union all

        -- A package-level row over a multi-item package expands into its
        -- GENUINELY forfeited items only: items are disposed individually, so
        -- such a row does not mean every item was forfeited.
        select fi.item_id, fi.item_name, 1 as ord
          from forfeited_item fi
         where fp.item_id is null
           and coalesce(ic.n, 0) > 1
           and fi.package_id = fp.package_id

        union all

        -- ⚠️ And when neither yields anything -- a package with no items
        -- recorded, or a package-level row whose package has no genuinely
        -- forfeited item -- the row still appears, unexpanded. Dropping it
        -- would hide an appeal the directorate is holding.
        select null::uuid, null::text, 2 as ord
         where not exists (select 1 from public.package_items pi2
                            where pi2.package_id = fp.package_id
                              and (fp.item_id is not null
                                   or coalesce(ic.n, 0) <= 1))
           and not exists (select 1 from forfeited_item fi2
                            where fi2.package_id = fp.package_id
                              and fp.item_id is null
                              and coalesce(ic.n, 0) > 1)
      ) c
  ) chosen
  where fp.source = 'forfeit'
    and fp.package_id not in (select package_id from finalised_package)
),
resolved as (
  select
    e.*,
    -- The goods name the table and its search read.
    coalesce(e.item_name, (
      select i2.item_name
        from public.package_items i2
       where i2.package_id = e.package_id
       order by i2.created_at
       limit 1)) as goods_name,

    -- Rule 5: the decision, resolved per item.
    case
      -- A per-item entry always wins.
      when e.item_id is not null
       and nullif(trim(coalesce(
             e.item_appeal_decisions -> e.item_id::text ->> 'decision',
             '')), '') is not null
        then nullif(trim(
               e.item_appeal_decisions -> e.item_id::text ->> 'decision'), '')
      -- ⚠️ Multi-item package, no entry for THIS item: no decision.
      when e.item_id is not null and e.package_item_count > 1
        then null
      -- Single-item or unknown package: the package-level column stands in.
      else nullif(trim(coalesce(e.appeal_decision, '')), '')
    end as decision,

    -- The hold, resolved per item.
    case
      when e.item_id is not null
       and coalesce(array_length(e.held_item_ids, 1), 0) > 0
        then e.item_id = any(e.held_item_ids)
      else coalesce(e.appeal_hold, false)
    end as is_held,

    e.appeal_deadline < now() as is_expired

  from expanded e
),
-- ⚠️ ONE row per (package, item), whatever the table holds.
--
-- A package can carry SEVERAL forfeited rows, and each expands into the same
-- items, so an SR with three of them over three items rendered nine times.
-- The row carrying the most appeal state wins, so a hold or a decision is
-- never the copy that gets dropped — losing one would show the directorate an
-- appeal as undecided after it had ruled.
deduped as (
  select distinct on (r.package_id, coalesce(r.item_id::text, ''))
    r.*
  from resolved r
  order by
    r.package_id,
    coalesce(r.item_id::text, ''),
    -- decision outranks hold, as in the Dart: 2 + 1.
    ((case when r.decision is not null then 2 else 0 end)
     + (case when r.is_held then 1 else 0 end)) desc,
    -- A stable tiebreak, so the same row wins every time the view is read.
    r.forfeited_package_id
)
select
  r.forfeited_package_id,
  -- ⚠️ Now that a (package, item) appears once, the pair IS the key. It was
  -- the forfeited id plus the item, which let two forfeited rows over the
  -- same item both claim a place.
  r.package_id::text || ':' || coalesce(r.item_id::text, '') as row_key,
  r.item_id,
  r.package_id,
  r.sr_number,
  r.consignee_name,
  r.yard,
  r.source,
  r.entry_qty,
  r.forfeited_at,
  r.appeal_deadline,
  r.appeal_decided_at,
  r.goods_name,
  r.decision,
  r.is_held,
  r.is_expired,
  (r.decision is not null) as has_decision,
  -- ⚠️ A hold outranks the deadline: an expired package on hold is still the
  -- directorate's work, and dropping it would strand the appeal.
  (r.decision is null and (not r.is_expired or r.is_held)) as is_active,
  -- What the Active tab's third stat chip counts.
  (r.decision is null and not r.is_expired and not r.is_held)
    as in_appeal_window
from deduped r;

comment on view public.appeal_rows is
  'One row per forfeited ITEM for the Appeal Directorate: the decision and '
  'the hold resolved per item, and whether the row is active or decided. '
  'A multi-item package never lets its package-level decision bleed onto an '
  'item that has none.';


-- ── Does it admit the same rows the Dart admitted? ───────────────────────
-- ⚠️ Checked against the live data. A row that falls out of the Active tab
-- is an appeal nobody is looking at.
do $verify$
declare
  n_rows     int;
  n_active   int;
  n_decided  int;
  n_window   int;
  n_held     int;
  bad        int;
begin
  select count(*),
         count(*) filter (where is_active),
         count(*) filter (where has_decision),
         count(*) filter (where in_appeal_window),
         count(*) filter (where is_active and is_held)
    into n_rows, n_active, n_decided, n_window, n_held
    from public.appeal_rows;

  -- Only genuine forfeits.
  select count(*) into bad
    from public.appeal_rows where source <> 'forfeit';
  if bad <> 0 then
    raise exception '% non-forfeit row(s) reached the appeal feed', bad;
  end if;

  -- Active and decided must never overlap: a decided appeal is finished.
  select count(*) into bad
    from public.appeal_rows where is_active and has_decision;
  if bad <> 0 then
    raise exception '% row(s) are both active and decided', bad;
  end if;

  -- ⚠️ The bleed rule, stated the other way round: no row may report a
  -- decision inherited from a package-level column while its package holds
  -- more than one item and it has no per-item entry.
  select count(*) into bad
    from public.appeal_rows r
    join public.forfeited_packages fp on fp.id = r.forfeited_package_id
   where r.has_decision
     and r.item_id is not null
     and (select count(*) from public.package_items pi
           where pi.package_id = fp.package_id) > 1
     and nullif(trim(coalesce(
           fp.item_appeal_decisions -> r.item_id::text ->> 'decision',
           '')), '') is null;
  if bad <> 0 then
    raise exception '% row(s) inherit a package-level decision across '
                    'siblings', bad;
  end if;

  -- A held row is active whatever its deadline says.
  select count(*) into bad
    from public.appeal_rows
   where is_held and not has_decision and not is_active;
  if bad <> 0 then
    raise exception '% held appeal(s) fell off the active tab', bad;
  end if;

  -- The row key really identifies a row.
  select count(*) into bad from (
    select row_key from public.appeal_rows group by row_key having count(*) > 1
  ) d;
  if bad <> 0 then
    raise exception '% duplicate row key(s): the pager would skip rows', bad;
  end if;

  -- The window chip counts a subset of active, never more.
  if n_window > n_active then
    raise exception 'in_appeal_window (%) exceeds active (%)',
      n_window, n_active;
  end if;

  raise notice 'appeal_rows: % row(s) — % active (% in window, % held), % decided',
    n_rows, n_active, n_window, n_held, n_decided;
end
$verify$;
