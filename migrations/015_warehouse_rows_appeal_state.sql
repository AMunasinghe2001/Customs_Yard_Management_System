-- ============================================================================
-- The Warehouses table can now be narrowed by appeal state, and that filter
-- has to run in SQL like every other one on the page.
--
-- ⚠️ Filtering it in Dart would break the pager. The page reads ONE page of
-- rows and takes its total from the server, so narrowing the twenty rows on
-- screen would leave the pager counting rows it had just removed — the exact
-- trap the comment above `pageRows` warns about.
--
-- Appeal state is NOT a package status: a DETAINED item can be appealing, on
-- hold, or decided, so the two questions narrow independently and the view
-- has to carry both.
--
-- ⚠️ The inner query is postgres/48 verbatim. Retyping it by hand is how the
-- two drift; this wraps it and adds three columns.
--
-- Safe to re-run.
-- ============================================================================

drop view if exists public.warehouse_rows cascade;

create view public.warehouse_rows
with (security_invoker = true) as
select
  r.*,
  -- Null for an entry with no item (a whole-package admission): there is no
  -- appeal to be in any state, and false would read as "enabled".
  ao.decision as appeal_decision,
  ao.on_hold  as appeal_on_hold,
  -- The three states the filter offers, resolved once here so the screen and
  -- the query cannot disagree about what "decided" means.
  -- ⚠️ FOUR states, and 'enabled' is the last of them.
  --
  -- An appeal can only be lodged inside the first 30 days. So:
  --   appealing — still inside that window; nobody may act yet
  --   hold      — the Directorate froze it past the deadline
  --   decided   — a ruling exists; the window no longer applies
  --   enabled   — the window CLOSED with no appeal, so the YARD may now
  --               act: a final disposition, or send the goods for sale
  --
  -- ⚠️ The window was missing here, so goods still inside their 30 days
  -- fell through to 'enabled' — and the filter returned rows whose own
  -- chip read "Appealing". Same rule as `isWithinAppealWindow`: the clock
  -- runs from the ENTRY DATE and lasts 30 days.
  case
    when r.package_item_id is null then null
    when coalesce(ao.on_hold, false) then 'hold'
    when coalesce(trim(ao.decision), '') <> '' then 'decided'
    when now() < (date_trunc('day', r.admitted_at at time zone 'Asia/Colombo')
                  + interval '30 days') at time zone 'Asia/Colombo'
      then 'appealing'
    else 'enabled'
  end as appeal_state
from (
select
  we.id as entry_id,
  we.warehouse_id,
  we.package_id,
  we.package_item_id,
  p.sr_number,
  p.consignee_name,
  we.hold_reason,
  we.item_count,
  we.admitted_at,

  -- The goods on this row.
  pi.item_name,

  -- ⚠️ Normalised. 'Forfiet' is a typo that reached the data; folding it here
  -- keeps the filter's one choice from matching only half its rows.
  case
    when lower(trim(coalesce(pi.status, ''))) = 'forfiet' then 'Forfeit'
    else pi.status
  end as item_status,

  -- The package-level status the 'confiscated' filter reads.
  p.status as package_status,
  lower(coalesce(p.status, '')) = 'confiscated' as is_package_confiscated,

  -- Both of the year filter's answers, so it can match either.
  extract(year from we.admitted_at at time zone 'Asia/Colombo')::text
    as admitted_year,
  substring(p.sr_number, '(20[0-9]{2})') as sr_year,

  -- A warehouse facility is shared, but an entry belongs to exactly one
  -- yard. Exposing this lets every yard-bound query narrow in SQL.
  p.yard

from public.warehouse_entries we
join public.packages p on p.id = we.package_id
left join public.package_items pi on pi.id = we.package_item_id
where
  not coalesce(we.is_returned, false)
  -- Goods with a final disposition have left the yard.
  and lower(trim(coalesce(pi.status, ''))) not in
      ('released', 'returned', 'sold', 're-export', 're-exported',
       'destroy', 'destroyed', 'other')
) r
left join public.item_appeal_outcomes ao on ao.item_id = r.package_item_id;

comment on view public.warehouse_rows is
  'Live warehouse entries — not returned, and not goods that have left the '
  'yard under a final disposition — with the item status, hold reason, both '
  'year values and the appeal state the Warehouses page filters on.';

-- Verification: only the three documented states may be produced.
do $$
declare
  bad text;
begin
  select string_agg(distinct appeal_state, ', ') into bad
    from public.warehouse_rows
   where appeal_state is not null
     and appeal_state not in ('appealing', 'enabled', 'hold', 'decided');
  if bad is not null then
    raise exception 'unexpected appeal_state: %', bad;
  end if;
end $$;
