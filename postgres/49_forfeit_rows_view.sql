-- The yard's Forfeited table, as a view.
--
-- ⚠️ 122 lines of Dart, transcribed. `_buildForfeitRows` walked every
-- forfeited package with its items and warehouse entries — 42 forfeited rows
-- becoming 124 table rows, 97ms — and the table had NO pager at all, so all
-- 124 rendered at once.
--
-- The rule is genuinely intricate, and each clause is here because something
-- went wrong without it:
--
-- ⚠️ A row per forfeit EVENT, not per item. When a detained item is forfeited
--    in parts, each `[FORFEIT…` / `[CONFISCATED…` warehouse entry is its own
--    line with its own quantity and its own officer — that is the record of
--    what was actually taken and when.
--
-- ⚠️ A package-level forfeited row (item_id is null) is LEGACY and must not
--    blanket every item. Items are disposed individually, so one can be
--    forfeited while a sibling stays on Detain. Such a row therefore covers
--    only items with genuine forfeit evidence.
--
-- ⚠️ An item that reached a final disposition leaves the table — UNLESS it is
--    still inside the appeal lifecycle. A held item of a forfeit row, still
--    live, that is on hold or inside its window or already ruled on, stays
--    visible even if a stale `[FINAL:…]` entry lingers from earlier testing.
--    Dropping it would hide goods the yard still has to act on.
--
-- ⚠️ 'other' is TERMINAL. A final "Other" disposition sets status='other', so
--    such an item leaves the table like a sold or destroyed one — and
--    'other: <note>' is the same thing with a reason attached.
--
-- ⚠️ And a legacy row with no item detail still shows ONE summary line, kept
--    when nothing has been finalised or when the Appeal Directorate has ruled
--    Sale/Destroy and the yard has not yet sent the request. That last case is
--    a pending admin action: hiding it would strand the ruling.

-- ⚠️ And THREE more rules decide whether a forfeited record reaches the table
-- at all. They were a separate layer in the service, not in the row builder,
-- and every one of them is a way for goods to have moved on:
--
--   * a record already placed in a TENDER belongs to the tender pages
--   * one already SOLD or DESTROYED belongs to its outcome page
--   * an ITEM already in a disposal request has been handed on — matched on
--     (package_id, item_id) rather than the forfeited id, because a request
--     stores a row that may be a synthetic per-item one. A record stays while
--     ANY of its items is still unrequested: a multi-item forfeit can have one
--     item requested while another is on appeal hold.

drop view if exists public.forfeit_rows cascade;

create view public.forfeit_rows as
with
-- The three ways a forfeited record leaves this table.
tendered as (
  select unnest(t.forfeited_package_ids)::uuid as fp_id
    from public.tenders t
   where t.forfeited_package_ids is not null
),
gone as (
  select ti.forfeited_package_id as fp_id
    from public.tender_sale_items ti where ti.sold
  union
  select di.forfeited_package_id
    from public.destruction_items di where di.destroyed
),
requested_item as (
  -- ⚠️ Keyed on the ORIGINATING (package, item), not the forfeited id: a
  -- request stores a row that may be a synthetic per-item one.
  select distinct fp.package_id, fp.item_id
    from public.disposal_request_items dri
    join public.forfeited_packages fp on fp.id = dri.forfeited_package_id
   where fp.item_id is not null
),
requested_whole as (
  select distinct dri.forfeited_package_id as fp_id
    from public.disposal_request_items dri
),
-- The records still on this table.
live_fp as (
  select fp.*
    from public.forfeited_packages fp
   where fp.source = 'forfeit'
     and not exists (select 1 from tendered t where t.fp_id = fp.id)
     and not exists (select 1 from gone g where g.fp_id = fp.id)
     and (
       -- A record with items stays while ANY item is still unrequested.
       case
         when exists (select 1 from public.package_items pi
                       where pi.package_id = fp.package_id)
           then exists (
             select 1 from public.package_items pi
              where pi.package_id = fp.package_id
                and not exists (
                  select 1 from requested_item ri
                   where ri.package_id = fp.package_id
                     and ri.item_id = pi.id))
         -- A legacy record with no items is caught by the raw id.
         else not exists (select 1 from requested_whole rw
                           where rw.fp_id = fp.id)
       end
     )
),
-- Items with genuine forfeit evidence, for the package-level coverage rule.
forfeit_evidence as (
  select pi.id as item_id, pi.package_id
    from public.package_items pi
   where lower(trim(coalesce(pi.status, ''))) in
         ('forfeit', 'forfeited', 'forfiet', 'confiscated')
      or exists (
        select 1 from public.warehouse_entries we
         where we.package_item_id = pi.id
           and coalesce(we.is_returned, false)
           and (upper(trim(coalesce(we.return_notes, ''))) like '[FORFEIT%'
             or upper(trim(coalesce(we.return_notes, ''))) like '[CONFISCAT%'))
),
-- Every (forfeited row, item) pair the table could be about, with the flags
-- the rules read.
pair as (
  select
    fp.id as forfeited_package_id,
    fp.package_id,
    fp.sr_number,
    fp.consignee_name,
    fp.yard,
    fp.forfeited_at,
    fp.appeal_deadline,
    fp.appeal_hold,
    fp.held_item_ids,
    fp.appeal_decision,
    fp.item_appeal_decisions,
    pi.id as item_id,
    pi.item_name,
    pi.hs_code,
    pi.quantity,
    pi.status as item_status,
    pi.reasons as item_reasons,
    fp.reason as fp_reason,

    -- Does this forfeited row cover this item?
    (fp.item_id = pi.id
     or (fp.item_id is null
         and exists (select 1 from forfeit_evidence fe
                      where fe.item_id = pi.id))) as covers_item,

    -- Is the item still live? 'other' and 'other: <note>' are terminal.
    (lower(trim(coalesce(pi.status, ''))) not in
       ('sold', 'destroyed', 'released', 'returned', 're-export',
        're-exported', 'cleared', 'other')
     and lower(trim(coalesce(pi.status, ''))) not like 'other:%') as status_live,

    -- Has it been finalised by a warehouse entry?
    exists (select 1 from public.warehouse_entries we
             where we.package_item_id = pi.id
               and upper(trim(coalesce(we.return_notes, ''))) like '[FINAL:%')
      as has_final,

    -- The item's own decision, with the multi-item guard: a package-level
    -- decision never bleeds onto an item that has none of its own.
    case
      when nullif(trim(coalesce(
             fp.item_appeal_decisions -> pi.id::text ->> 'decision',
             '')), '') is not null
        then nullif(trim(
               fp.item_appeal_decisions -> pi.id::text ->> 'decision'), '')
      when (select count(*) from public.package_items pi2
             where pi2.package_id = fp.package_id) > 1
        then null
      else nullif(trim(coalesce(fp.appeal_decision, '')), '')
    end as item_decision

  from live_fp fp
  join public.package_items pi on pi.package_id = fp.package_id
),
flagged as (
  select
    p.*,
    -- Still inside the appeal lifecycle: on hold, or the window is open, or a
    -- decision is in.
    (p.covers_item
     and p.status_live
     and (coalesce(p.appeal_hold, false)
          or p.appeal_deadline >= now()
          or p.item_decision is not null)) as in_appeal_lifecycle
  from pair p
),
-- Items that survive the final-disposition cut.
live_pair as (
  select * from flagged
   where not (has_final and not in_appeal_lifecycle)
),

-- ── 1. A row per forfeit EVENT ───────────────────────────────────────────
event_row as (
  select
    lp.forfeited_package_id,
    lp.package_id,
    lp.item_id,
    we.id as entry_id,
    lp.sr_number,
    lp.consignee_name,
    lp.yard,
    lp.item_name,
    lp.hs_code,
    we.item_count as qty,
    -- ⚠️ The SR ENTRY date, not the warehouse return date: forfeited_at is
    -- set to the package entry date on forfeiture, and the 30-day appeal
    -- window counts from there.
    lp.forfeited_at as forfeited_date,
    lp.appeal_deadline,
    coalesce(pr.full_name, pr.badge_number, '—') as officer,
    lp.item_status,
    lp.item_decision,
    -- The Post Status Activity column and its filter: the ENTRY's hold reason
    -- first, then the item's, then the forfeited record's -- so the column is
    -- never blank.
    coalesce(nullif(trim(we.hold_reason), ''),
             nullif(trim(lp.item_reasons), ''),
             nullif(trim(lp.fp_reason), ''), '—') as reason,
    -- The table reads most-recently-forfeited first, by the moment the
    -- forfeit was actually RECORDED where there is one.
    coalesce(we.returned_at, lp.forfeited_at) as sort_moment,
    1 as row_kind
  from live_pair lp
  join public.warehouse_entries we on we.package_item_id = lp.item_id
  left join public.profiles pr on pr.id = we.returned_by
  where coalesce(we.is_returned, false)
    and (upper(trim(coalesce(we.return_notes, ''))) like '[FORFEIT%'
      or upper(trim(coalesce(we.return_notes, ''))) like '[CONFISCATED%')
),

-- ── 2. A form-level forfeit, or a covered live item, with no event ───────
item_row as (
  select
    lp.forfeited_package_id,
    lp.package_id,
    lp.item_id,
    (select we2.id from public.warehouse_entries we2
      where we2.package_item_id = lp.item_id
      order by we2.admitted_at limit 1) as entry_id,
    lp.sr_number,
    lp.consignee_name,
    lp.yard,
    lp.item_name,
    lp.hs_code,
    lp.quantity as qty,
    lp.forfeited_at as forfeited_date,
    lp.appeal_deadline,
    '—' as officer,
    lp.item_status,
    lp.item_decision,
    coalesce(nullif(trim(lp.item_reasons), ''),
             nullif(trim(lp.fp_reason), ''), '—') as reason,
    lp.forfeited_at as sort_moment,
    2 as row_kind
  from live_pair lp
  where (lower(trim(coalesce(lp.item_status, '')))
           in ('forfiet', 'forfeit', 'forfeited')
         or (lp.covers_item and lp.status_live))
    -- Only when this item produced no forfeit event of its own.
    and not exists (
      select 1 from public.warehouse_entries we
       where we.package_item_id = lp.item_id
         and coalesce(we.is_returned, false)
         and (upper(trim(coalesce(we.return_notes, ''))) like '[FORFEIT%'
           or upper(trim(coalesce(we.return_notes, ''))) like '[CONFISCATED%'))
),

detailed as (
  select * from event_row
  union all
  select * from item_row
),

-- ── 3. The legacy summary row ────────────────────────────────────────────
-- For a forfeited row that produced no detailed line at all.
summary_row as (
  select
    fp.id as forfeited_package_id,
    fp.package_id,
    (select pi.id from public.package_items pi
      where pi.package_id = fp.package_id
      order by pi.created_at limit 1) as item_id,
    (select we.id from public.warehouse_entries we
      where we.package_id = fp.package_id
      order by we.admitted_at limit 1) as entry_id,
    fp.sr_number,
    fp.consignee_name,
    fp.yard,
    coalesce((select pi.item_name from public.package_items pi
               where pi.package_id = fp.package_id
               order by pi.created_at limit 1),
             'Multiple/Unspecified') as item_name,
    (select pi.hs_code from public.package_items pi
      where pi.package_id = fp.package_id
      order by pi.created_at limit 1) as hs_code,
    coalesce((select sum(pi.quantity) from public.package_items pi
               where pi.package_id = fp.package_id), 0)::int as qty,
    fp.forfeited_at as forfeited_date,
    fp.appeal_deadline,
    '—' as officer,
    (select pi.status from public.package_items pi
      where pi.package_id = fp.package_id
      order by pi.created_at limit 1) as item_status,
    nullif(trim(coalesce(fp.appeal_decision, '')), '') as item_decision,
    coalesce(nullif(trim(fp.reason), ''), '—') as reason,
    fp.forfeited_at as sort_moment,
    3 as row_kind
  from live_fp fp
  where not exists (select 1 from detailed d
                     where d.forfeited_package_id = fp.id)
    and (
      -- Nothing has been finalised...
      not exists (
        select 1 from public.package_items pi
          join public.warehouse_entries we on we.package_item_id = pi.id
         where pi.package_id = fp.package_id
           and upper(trim(coalesce(we.return_notes, ''))) like '[FINAL:%')
      -- ...or the Appeal Directorate ruled Sale/Destroy and the yard has not
      -- sent the request yet. ⚠️ A pending ADMIN action: hiding it would
      -- strand the ruling.
      or upper(coalesce(fp.appeal_decision, '')) in ('SALE', 'DESTROY')
      or exists (
        select 1
          from jsonb_each(
            case jsonb_typeof(fp.item_appeal_decisions)
              when 'object' then fp.item_appeal_decisions
              else '{}'::jsonb
            end) as d(k, v)
         where upper(coalesce(v ->> 'decision', '')) in ('SALE', 'DESTROY'))
    )
)

select
  d.*,
  -- ⚠️ What the header's "Actionable" chip counts: the yard may act
  -- once the 30-day window has passed OR the Appeal Directorate has ruled --
  -- there is no need to wait out the window in that case.
  (d.appeal_deadline < now() or d.item_decision is not null) as is_actionable
from (
  select * from detailed
  union all
  select * from summary_row
) d;

comment on view public.forfeit_rows is
  'The yard Forfeited table: one row per forfeit EVENT, else per covered live '
  'item, else one summary row per forfeited record. Transcribed from '
  '_buildForfeitRows.';


-- ── Against the Dart it replaces ─────────────────────────────────────────
do $verify$
declare
  n_rows      int;
  n_fp        int;
  n_events    int;
  n_items     int;
  n_summary   int;
  bad         int;
begin
  select count(*),
         count(*) filter (where row_kind = 1),
         count(*) filter (where row_kind = 2),
         count(*) filter (where row_kind = 3)
    into n_rows, n_events, n_items, n_summary
    from public.forfeit_rows;

  select count(*) into n_fp
    from public.forfeited_packages where source = 'forfeit';

  -- Only genuine forfeits reach this table.
  select count(*) into bad
    from public.forfeit_rows r
    join public.forfeited_packages fp on fp.id = r.forfeited_package_id
   where fp.source <> 'forfeit';
  if bad <> 0 then
    raise exception '% non-forfeit row(s) reached the forfeited table', bad;
  end if;

  -- ⚠️ An item never produces BOTH an event row and an item row: the item
  -- row exists precisely for items that produced no event.
  select count(*) into bad from (
    select item_id
      from public.forfeit_rows
     where row_kind in (1, 2) and item_id is not null
     group by item_id
    having count(*) filter (where row_kind = 1) > 0
       and count(*) filter (where row_kind = 2) > 0) d;
  if bad <> 0 then
    raise exception '% item(s) have both an event row and a fallback row', bad;
  end if;

  -- ⚠️ A summary row exists only when its record produced nothing else.
  select count(*) into bad
    from public.forfeit_rows s
   where s.row_kind = 3
     and exists (select 1 from public.forfeit_rows d
                  where d.forfeited_package_id = s.forfeited_package_id
                    and d.row_kind < 3);
  if bad <> 0 then
    raise exception '% summary row(s) duplicate a detailed row', bad;
  end if;

  -- ⚠️ A terminal item never appears unless the appeal lifecycle holds it.
  select count(*) into bad
    from public.forfeit_rows r
   where r.row_kind < 3
     and (lower(trim(coalesce(r.item_status, '')))
            in ('sold', 'destroyed', 'released', 'returned', 're-export',
                're-exported', 'cleared', 'other')
          or lower(trim(coalesce(r.item_status, ''))) like 'other:%');
  if bad <> 0 then
    raise exception '% finished item(s) are still on the forfeited table', bad;
  end if;

  raise notice 'forfeit_rows: % row(s) from % forfeited record(s) '
               '(% event, % item, % summary)',
    n_rows, n_fp, n_events, n_items, n_summary;
end
$verify$;
