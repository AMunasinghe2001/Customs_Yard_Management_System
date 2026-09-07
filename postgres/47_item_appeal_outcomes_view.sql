-- What the Appeal Directorate has ruled about each goods ITEM, whatever the
-- goods are.
--
-- ⚠️ Four screens read this — Warehouses, Detained, Abandoned and Other — to
-- decide whether goods may move: a DECISION releases them early, a HOLD keeps
-- them frozen past the deadline. It was
-- `forfeited_packages.select('*')`: every column of every forfeited row,
-- 171ms, to build a map of two values per item.
--
-- ⚠️ And it could not resolve the rule it was applying. `appealDecisionForItem`
-- needs the package's ITEM COUNT to know whether a package-level decision may
-- stand in for a missing per-item one — and `select('*')` embeds no package,
-- so `packageDetails` was always null and the multi-item guard could never
-- fire. A decision on one item therefore reported every sibling decided,
-- which is the exact bleed the model documents and defends against.
--
-- This is `appeal_rows`'s resolution without its membership: that view is the
-- Appeal PORTAL's feed and is `source = 'forfeit'` only, while a ruling can
-- exist against detained, abandoned and other goods too — 65 of them on the
-- live data, which would simply have vanished from these four screens.
--
--   decision  the per-item entry in item_appeal_decisions, else the
--             package-level column, and NEVER the package-level column for an
--             item of a multi-item package that has no entry of its own
--   on_hold   per item when held_item_ids names any, else the package-level
--             appeal_hold

drop view if exists public.item_appeal_outcomes cascade;

create view public.item_appeal_outcomes as
with item_count as (
  select package_id, count(*) as n
    from public.package_items
   group by package_id
),
-- Every (forfeited row, item) a ruling could be about.
candidate as (
  -- A per-item row speaks for its own item.
  select fp.id as fp_id, fp.package_id, fp.item_id
    from public.forfeited_packages fp
   where fp.item_id is not null

  union

  -- A package-level row: its per-item map names the items it ruled on...
  select fp.id, fp.package_id, k::uuid
    from public.forfeited_packages fp
   cross join lateral jsonb_object_keys(
     case jsonb_typeof(fp.item_appeal_decisions)
       when 'object' then fp.item_appeal_decisions
       else '{}'::jsonb
     end) as k
   where fp.item_id is null

  union

  -- ...and its held list names the items it froze.
  select fp.id, fp.package_id, h
    from public.forfeited_packages fp
   cross join lateral unnest(coalesce(fp.held_item_ids, '{}')) as h
   where fp.item_id is null
),
resolved as (
  select
    c.item_id,
    -- ⚠️ The multi-item guard, which the Dart could never apply here.
    case
      when nullif(trim(coalesce(
             fp.item_appeal_decisions -> c.item_id::text ->> 'decision',
             '')), '') is not null
        then nullif(trim(
               fp.item_appeal_decisions -> c.item_id::text ->> 'decision'), '')
      when coalesce(ic.n, 0) > 1
        then null
      else nullif(trim(coalesce(fp.appeal_decision, '')), '')
    end as decision,
    case
      when coalesce(array_length(fp.held_item_ids, 1), 0) > 0
        then c.item_id = any(fp.held_item_ids)
      else coalesce(fp.appeal_hold, false)
    end as on_hold,
    fp.appeal_decided_at
  from candidate c
  join public.forfeited_packages fp on fp.id = c.fp_id
  left join item_count ic on ic.package_id = c.package_id
)
-- ⚠️ One row per ITEM. Several forfeited rows can name the same item, and the
-- one carrying a ruling must win: a decision outranks a hold, and both outrank
-- silence. Dropping the wrong copy would tell a yard the goods are free to
-- move when the directorate has frozen them.
select distinct on (r.item_id)
  r.item_id,
  r.decision,
  r.on_hold
from resolved r
order by
  r.item_id,
  ((case when r.decision is not null then 2 else 0 end)
   + (case when r.on_hold then 1 else 0 end)) desc,
  r.appeal_decided_at desc nulls last;

comment on view public.item_appeal_outcomes is
  'One row per goods item the Appeal Directorate has ruled on or frozen, '
  'whatever the source. A package-level decision never bleeds onto an item '
  'of a multi-item package that has no entry of its own.';


-- ── Does it say what the four screens were being told? ───────────────────
do $verify$
declare
  n_rows     int;
  n_decided  int;
  n_held     int;
  n_sources  int;
  bad        int;
begin
  select count(*),
         count(*) filter (where decision is not null),
         count(*) filter (where on_hold)
    into n_rows, n_decided, n_held
    from public.item_appeal_outcomes;

  -- ⚠️ Rulings exist against every source, not just forfeits. Reading this
  -- from the Appeal portal's own feed would have dropped 65 of them.
  select count(distinct coalesce(fp.source, '')) into n_sources
    from public.forfeited_packages fp
    join public.item_appeal_outcomes o
      on o.item_id = fp.item_id
      or fp.item_appeal_decisions ? o.item_id::text
   where o.decision is not null or o.on_hold;
  if n_sources < 2 then
    raise exception 'outcomes come from only % source(s) -- the view is '
                    'narrowed to one kind of goods', n_sources;
  end if;

  -- One row per item, or a screen reads whichever copy it happened to get.
  select count(*) into bad from (
    select item_id from public.item_appeal_outcomes
     group by item_id having count(*) > 1) d;
  if bad <> 0 then
    raise exception '% item(s) appear twice', bad;
  end if;

  -- The bleed rule, stated the other way round.
  select count(*) into bad
    from public.item_appeal_outcomes o
    join public.package_items pi on pi.id = o.item_id
   where o.decision is not null
     and (select count(*) from public.package_items pi2
           where pi2.package_id = pi.package_id) > 1
     and not exists (
       select 1 from public.forfeited_packages fp
        where fp.package_id = pi.package_id
          and nullif(trim(coalesce(
                fp.item_appeal_decisions -> o.item_id::text ->> 'decision',
                '')), '') is not null);
  if bad <> 0 then
    raise exception '% item(s) inherit a package-level decision across '
                    'siblings', bad;
  end if;

  -- Nothing is recorded that names no ruling at all.
  select count(*) into bad
    from public.item_appeal_outcomes
   where decision is null and not on_hold;
  if bad <> 0 then
    raise notice '% item(s) carry neither a decision nor a hold', bad;
  end if;

  raise notice 'item_appeal_outcomes: % item(s) — % decided, % on hold',
    n_rows, n_decided, n_held;
end
$verify$;
