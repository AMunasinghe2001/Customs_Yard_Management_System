-- ============================================================================
--  Detained Goods has no pager at all -- it renders the whole yard.
--
--  Every other list in the app pages; this one, Abandoned and Other do not.
--  They fetch `livePackagesProvider` (every package, every item, every
--  warehouse entry) and build one row per HELD ITEM in Dart, then hand the
--  entire list to DataTable2. At 43 rows that is invisible. At ten thousand it
--  is a page that never finishes laying out -- worse than the paged screens
--  were, because there the cost was at least bounded by what came back.
--
--  ⚠️ A row here is an ITEM, not a package: CED/GL1/SR/67/2026 appears twice on
--  the screenshot, once for its Ceramic Floor Tiles and once for its Copper
--  Wire Coils, because detention is decided per item.
--
--  The rule, from `_itemIsDetained`:
--    1. The item's status is detain / detained / held.
--    2. NO warehouse entry for it carries a "settled" note -- one starting
--       [FINAL:, [ABANDONED], [OTHER] or [FORFEIT. Detention is a HOLDING
--       status, not a disposition: there is no [DETAIN] event to look for, so
--       what marks the end of it is the arrival of some other disposition.
--
--  ⚠️ The live entry is the one that is NOT returned; it carries the qty, the
--  hold reason and the admitting officer. Where none exists the item's own
--  values stand in, so a detained item that never reached a warehouse still
--  shows a quantity and a reason rather than blanks.
--
--  ⚠️ `hold_reason` IS the Post Status Activity the filter matches on, and its
--  fallback must be spelled exactly as kDetainActivities has it or the row
--  could never be selected. 'Pending Inquiry' is that spelling.
-- ============================================================================

set lock_timeout = '5s';

drop view if exists public.held_goods_rows;

create view public.held_goods_rows as
-- ── DETAINED: one row per held item ────────────────────────────────────────
select
  ('D:' || pi.id::text)                      as row_key,
  'DETAINED'::text                           as kind,
  null::uuid                                 as event_entry_id,
  null::text                                 as disposition,
  false                                      as completed,
  pi.id                                      as item_id,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.item_name,
  pi.hs_code,
  pi.status,
  -- The live holding entry, when there is one.
  live.id                                    as entry_id,
  coalesce(live.item_count, pi.quantity)     as quantity,
  coalesce(nullif(trim(live.hold_reason), ''),
           nullif(trim(pi.reasons), ''),
           'Pending Inquiry')                as reason,
  coalesce(ap.full_name, ap.badge_number, '—') as officer,
  coalesce(live.admitted_at, p.entry_date, p.created_at) as held_at,
  -- The appeal clock the page's chip reads. Null when no forfeiture row
  -- exists, which is the ordinary case for goods still under inquiry.
  fp.appeal_deadline,
  fp.appeal_hold,
  fp.appeal_decision,
  -- Whether it has already gone to Central Disposal in a disposal request.
  (dri.forfeited_package_id is not null)     as sent
from public.package_items pi
join public.packages p on p.id = pi.package_id
-- The entry still holding the goods: not returned, newest first.
left join lateral (
  select w.id, w.item_count, w.hold_reason, w.admitted_at, w.admitted_by
    from public.warehouse_entries w
   where w.package_item_id = pi.id
     and coalesce(w.is_returned, false) = false
   order by w.admitted_at desc
   limit 1) live on true
left join public.profiles ap on ap.id = live.admitted_by
left join lateral (
  select f.id, f.appeal_deadline, f.appeal_hold, f.appeal_decision
    from public.forfeited_packages f
   where f.package_id = p.id and f.item_id = pi.id
   order by f.forfeited_at desc
   limit 1) fp on true
left join lateral (
  select d.forfeited_package_id
    from public.disposal_request_items d
   where d.forfeited_package_id = fp.id
   limit 1) dri on true
where lower(trim(coalesce(pi.status, ''))) in ('detain', 'detained', 'held')
  -- ⚠️ Rule 2: no settled note anywhere for this item. Detention ends when
  -- some OTHER disposition is recorded against the goods.
  and not exists (
    select 1 from public.warehouse_entries w2
     where w2.package_item_id = pi.id
       and (upper(trim(coalesce(w2.return_notes, ''))) like '[FINAL:%'
         or upper(trim(coalesce(w2.return_notes, ''))) like '[ABANDONED]%'
         or upper(trim(coalesce(w2.return_notes, ''))) like '[OTHER]%'
         or upper(trim(coalesce(w2.return_notes, ''))) like '[FORFEIT%'))

union all

-- ── ABANDONED (1): one row per [ABANDONED] disposition EVENT ───────────────
--  Repeatable per item: a partial abandonment is its own event, and each is
--  its own row, which is why these are keyed by the entry rather than by the
--  item.
select
  ('AE:' || w.id::text)                      as row_key,
  'ABANDONED'::text                          as kind,
  w.id                                       as event_entry_id,
  null::text                                 as disposition,
  false                                      as completed,
  pi.id                                      as item_id,
  p.id                                       as package_id,
  p.sr_number,
  p.consignee_name,
  p.yard,
  pi.item_name,
  pi.hs_code,
  pi.status,
  w.id                                       as entry_id,
  w.item_count                               as quantity,
  coalesce(nullif(trim(w.hold_reason), ''),
           nullif(trim(pi.reasons), ''), '—') as reason,
  coalesce(rp.full_name, rp.badge_number, '—') as officer,
  coalesce(w.returned_at, w.admitted_at)     as held_at,
  fp.appeal_deadline, fp.appeal_hold, fp.appeal_decision,
  (dri.forfeited_package_id is not null)     as sent
from public.warehouse_entries w
join public.package_items pi on pi.id = w.package_item_id
join public.packages p       on p.id = pi.package_id
left join public.profiles rp on rp.id = w.returned_by
left join lateral (
  select f.id, f.appeal_deadline, f.appeal_hold, f.appeal_decision
    from public.forfeited_packages f
   where f.package_id = p.id and f.item_id = pi.id
   order by f.forfeited_at desc limit 1) fp on true
left join lateral (
  select d.forfeited_package_id from public.disposal_request_items d
   where d.forfeited_package_id = fp.id limit 1) dri on true
where w.is_returned
  and upper(trim(coalesce(w.return_notes, ''))) like '[ABANDONED]%'
  -- Finalised items have moved on.
  and not exists (
    select 1 from public.warehouse_entries w3
     where w3.package_item_id = pi.id
       and upper(trim(coalesce(w3.return_notes, ''))) like '[FINAL:%')

union all

-- ── ABANDONED (2): form-level status, with no event of its own ─────────────
--  The item was marked abandoned on the SR form and no [ABANDONED] entry was
--  ever written, so the held entry supplies the context.
select
  ('AS:' || pi.id::text)                     as row_key,
  'ABANDONED'::text                          as kind,
  null::uuid                                 as event_entry_id,
  null::text                                 as disposition,
  false                                      as completed,
  pi.id, p.id, p.sr_number, p.consignee_name, p.yard,
  pi.item_name, pi.hs_code, pi.status,
  ctx.id                                     as entry_id,
  coalesce(ctx.item_count, pi.quantity)      as quantity,
  coalesce(nullif(trim(ctx.hold_reason), ''),
           nullif(trim(pi.reasons), ''), '—') as reason,
  coalesce(ap.full_name, ap.badge_number, '—') as officer,
  coalesce(ctx.admitted_at, p.entry_date, p.created_at) as held_at,
  fp.appeal_deadline, fp.appeal_hold, fp.appeal_decision,
  (dri.forfeited_package_id is not null)     as sent
from public.package_items pi
join public.packages p on p.id = pi.package_id
left join lateral (
  select w.id, w.item_count, w.hold_reason, w.admitted_at, w.admitted_by
    from public.warehouse_entries w
   where w.package_item_id = pi.id
   order by w.admitted_at limit 1) ctx on true
left join public.profiles ap on ap.id = ctx.admitted_by
left join lateral (
  select f.id, f.appeal_deadline, f.appeal_hold, f.appeal_decision
    from public.forfeited_packages f
   where f.package_id = p.id and f.item_id = pi.id
   order by f.forfeited_at desc limit 1) fp on true
left join lateral (
  select d.forfeited_package_id from public.disposal_request_items d
   where d.forfeited_package_id = fp.id limit 1) dri on true
where lower(trim(coalesce(pi.status, ''))) = 'abandoned'
  and not exists (
    select 1 from public.warehouse_entries w2
     where w2.package_item_id = pi.id
       and upper(trim(coalesce(w2.return_notes, ''))) like '[ABANDONED]%')
  and not exists (
    select 1 from public.warehouse_entries w3
     where w3.package_item_id = pi.id
       and upper(trim(coalesce(w3.return_notes, ''))) like '[FINAL:%')

union all

-- -- OTHER (1): one row per [OTHER] disposition EVENT -----------------------
select
  ('OE:' || w.id::text)                      as row_key,
  'OTHER'::text                              as kind,
  w.id                                       as event_entry_id,
  -- The custom label typed into the dialog, taken from after the tag.
  coalesce(nullif(trim(substring(w.return_notes from ':\s*([^\]]+)\]')), ''),
           'Other')                          as disposition,
  false                                      as completed,
  pi.id, p.id, p.sr_number, p.consignee_name, p.yard,
  pi.item_name, pi.hs_code, pi.status,
  w.id                                       as entry_id,
  w.item_count                               as quantity,
  coalesce(nullif(trim(w.hold_reason), ''),
           nullif(trim(pi.reasons), ''), '-') as reason,
  coalesce(rp.full_name, rp.badge_number, '-') as officer,
  coalesce(w.returned_at, w.admitted_at)     as held_at,
  fp.appeal_deadline, fp.appeal_hold, fp.appeal_decision,
  (dri.forfeited_package_id is not null)     as sent
from public.warehouse_entries w
join public.package_items pi on pi.id = w.package_item_id
join public.packages p       on p.id = pi.package_id
left join public.profiles rp on rp.id = w.returned_by
left join lateral (
  select f.id, f.appeal_deadline, f.appeal_hold, f.appeal_decision
    from public.forfeited_packages f
   where f.package_id = p.id and f.item_id = pi.id
   order by f.forfeited_at desc limit 1) fp on true
left join lateral (
  select d.forfeited_package_id from public.disposal_request_items d
   where d.forfeited_package_id = fp.id limit 1) dri on true
where w.is_returned
  and (upper(trim(coalesce(w.return_notes, ''))) like '[OTHER:%'
    or upper(trim(coalesce(w.return_notes, ''))) like '[OTHER]%'
    or upper(trim(coalesce(w.return_notes, ''))) like '[OTHER %')
  and not exists (
    select 1 from public.warehouse_entries w3
     where w3.package_item_id = pi.id
       and upper(trim(coalesce(w3.return_notes, ''))) like '[FINAL:%')

union all

-- -- OTHER (2): form-level "Other" status with no event of its own ----------
--  The explicit 'Other' / 'Other: ...' marker always qualifies. A LEGACY
--  free-text status -- any status that is not one of the known system ones --
--  qualifies only while the item is actually HELD in a warehouse, so a stray
--  typo in the status field cannot masquerade as an Other package.
select
  ('OS:' || pi.id::text)                     as row_key,
  'OTHER'::text                              as kind,
  null::uuid                                 as event_entry_id,
  case when lower(trim(pi.status)) like 'other:%'
         then nullif(trim(substring(pi.status from ':(.*)$')), '')
       else 'Other' end                      as disposition,
  false                                      as completed,
  pi.id, p.id, p.sr_number, p.consignee_name, p.yard,
  pi.item_name, pi.hs_code, pi.status,
  ctx.id                                     as entry_id,
  coalesce(ctx.item_count, pi.quantity)      as quantity,
  coalesce(nullif(trim(ctx.hold_reason), ''),
           nullif(trim(pi.reasons), ''), '-') as reason,
  coalesce(ap.full_name, ap.badge_number, '-') as officer,
  coalesce(ctx.admitted_at, p.entry_date, p.created_at) as held_at,
  fp.appeal_deadline, fp.appeal_hold, fp.appeal_decision,
  (dri.forfeited_package_id is not null)     as sent
from public.package_items pi
join public.packages p on p.id = pi.package_id
left join lateral (
  select w.id, w.item_count, w.hold_reason, w.admitted_at, w.admitted_by
    from public.warehouse_entries w
   where w.package_item_id = pi.id
   order by w.admitted_at limit 1) ctx on true
left join public.profiles ap on ap.id = ctx.admitted_by
left join lateral (
  select f.id, f.appeal_deadline, f.appeal_hold, f.appeal_decision
    from public.forfeited_packages f
   where f.package_id = p.id and f.item_id = pi.id
   order by f.forfeited_at desc limit 1) fp on true
left join lateral (
  select d.forfeited_package_id from public.disposal_request_items d
   where d.forfeited_package_id = fp.id limit 1) dri on true
where (
    lower(trim(coalesce(pi.status, ''))) = 'other'
    or lower(trim(coalesce(pi.status, ''))) like 'other:%'
    or (coalesce(trim(pi.status), '') <> ''
        and lower(trim(pi.status)) not in ('detain','detained','held','forfeit','forfiet','forfeited','confiscated','abandoned','released','returned','cleared','re-export','re-exported','reexport','destroy','destroyed','sold','sale','inspecting','pending')
        and exists (select 1 from public.warehouse_entries wl
                     where wl.package_item_id = pi.id
                       and coalesce(wl.is_returned, false) = false)))
  and not exists (
    select 1 from public.warehouse_entries w2
     where w2.package_item_id = pi.id
       and (upper(trim(coalesce(w2.return_notes, ''))) like '[OTHER:%'
         or upper(trim(coalesce(w2.return_notes, ''))) like '[OTHER]%'
         or upper(trim(coalesce(w2.return_notes, ''))) like '[OTHER %'))
  and not exists (
    select 1 from public.warehouse_entries w3
     where w3.package_item_id = pi.id
       and upper(trim(coalesce(w3.return_notes, ''))) like '[FINAL:%')

union all

-- -- OTHER (3): the COMPLETED [FINAL:OTHER] outcome -------------------------
--  Read-only records, like Released and Sold on their own pages. They are the
--  one exception to "nothing finalised may be listed": the page shows them as
--  finished with no action offered, which is what `completed` carries.
select
  ('OF:' || w.id::text)                      as row_key,
  'OTHER'::text                              as kind,
  w.id                                       as event_entry_id,
  coalesce(nullif(trim(substring(w.return_notes from U&'\2014' || '\s*(.+)$')), ''),
           'Other')                          as disposition,
  true                                       as completed,
  pi.id, p.id, p.sr_number, p.consignee_name, p.yard,
  pi.item_name, pi.hs_code, pi.status,
  w.id                                       as entry_id,
  w.item_count                               as quantity,
  coalesce(nullif(trim(w.hold_reason), ''),
           nullif(trim(pi.reasons), ''), '-') as reason,
  coalesce(rp.full_name, rp.badge_number, '-') as officer,
  coalesce(w.returned_at, w.admitted_at)     as held_at,
  fp.appeal_deadline, fp.appeal_hold, fp.appeal_decision,
  (dri.forfeited_package_id is not null)     as sent
from public.warehouse_entries w
join public.package_items pi on pi.id = w.package_item_id
join public.packages p       on p.id = pi.package_id
left join public.profiles rp on rp.id = w.returned_by
left join lateral (
  select f.id, f.appeal_deadline, f.appeal_hold, f.appeal_decision
    from public.forfeited_packages f
   where f.package_id = p.id and f.item_id = pi.id
   order by f.forfeited_at desc limit 1) fp on true
left join lateral (
  select d.forfeited_package_id from public.disposal_request_items d
   where d.forfeited_package_id = fp.id limit 1) dri on true
where w.is_returned
  and upper(trim(coalesce(w.return_notes, ''))) like '[FINAL:OTHER]%';

grant select on public.held_goods_rows to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
  bad int;
  n   int;
begin
  -- ⚠️ Scoped BY KIND. The view serves three pages now, so a check written
  -- against the whole view fails on rows that were never meant to satisfy it.
  select count(*) into bad
    from public.held_goods_rows h
    join public.package_items pi on pi.id = h.item_id
   where h.kind = 'DETAINED'
     and lower(trim(coalesce(pi.status, '')))
         not in ('detain', 'detained', 'held');
  if bad <> 0 then
    raise exception '% DETAINED row(s) are not detained at all', bad;
  end if;

  -- An ABANDONED row is either an [ABANDONED] event or a form-level status.
  select count(*) into bad
    from public.held_goods_rows h
    join public.package_items pi on pi.id = h.item_id
   where h.kind = 'ABANDONED'
     and h.event_entry_id is null
     and lower(trim(coalesce(pi.status, ''))) <> 'abandoned';
  if bad <> 0 then
    raise exception '% ABANDONED row(s) have neither an event nor the status',
      bad;
  end if;

  -- ⚠️ Nothing that has moved on may still be listed as held. This is the
  -- whole of rule 2, and getting it wrong means the page offers actions on
  -- goods that were forfeited or disposed of weeks ago.
  select count(*) into bad
    from public.held_goods_rows h
   where h.kind = 'DETAINED'
     and exists (
     select 1 from public.warehouse_entries w
      where w.package_item_id = h.item_id
        and (upper(trim(coalesce(w.return_notes, ''))) like '[FINAL:%'
          or upper(trim(coalesce(w.return_notes, ''))) like '[ABANDONED]%'
          or upper(trim(coalesce(w.return_notes, ''))) like '[OTHER]%'
          or upper(trim(coalesce(w.return_notes, ''))) like '[FORFEIT%'));
  if bad <> 0 then
    raise exception '% settled item(s) are still listed as detained', bad;
  end if;

  -- ⚠️ Nothing finalised may appear on ANY of these pages: a [FINAL:] entry
  -- means the goods already have an outcome, and offering an action on them
  -- would let an officer dispose of the same goods twice.
  select count(*) into bad
    from public.held_goods_rows h
   where not h.completed
     and exists (
     select 1 from public.warehouse_entries w
      where w.package_item_id = h.item_id
        and upper(trim(coalesce(w.return_notes, ''))) like '[FINAL:%');
  if bad <> 0 then
    raise exception '% finalised item(s) are still listed as actionable', bad;
  end if;

  -- A completed row must never be actionable, and only OTHER has them.
  if exists (select 1 from public.held_goods_rows
              where completed and kind <> 'OTHER') then
    raise exception 'a completed row appeared on a page with no such state';
  end if;

  -- ⚠️ The ROW KEY must be unique, not the item id: an item can legitimately
  -- appear more than once when it was abandoned in several partial events,
  -- and each of those is its own row on the page.
  select count(*) into bad from (
    select row_key from public.held_goods_rows
     group by row_key having count(*) > 1) d;
  if bad <> 0 then
    raise exception '% duplicated row key(s)', bad;
  end if;

  -- A DETAINED item, though, is one row: detention is a state, not an event.
  select count(*) into bad from (
    select item_id from public.held_goods_rows where kind = 'DETAINED'
     group by item_id having count(*) > 1) d;
  if bad <> 0 then
    raise exception '% detained item(s) appear more than once', bad;
  end if;

  -- Every row needs a quantity, a reason and a date: the table has a column
  -- for each and a blank one reads as missing data rather than as a state.
  if exists (select 1 from public.held_goods_rows
              where quantity is null or reason is null or held_at is null) then
    raise exception 'a held row is missing its quantity, reason or date';
  end if;

  select count(*) into n from public.held_goods_rows;
  raise notice '% held row(s), % already sent to Central Disposal',
    n, (select count(*) from public.held_goods_rows where sent);
  for r in
    select kind, count(*) as c
      from public.held_goods_rows group by kind order by kind
  loop
    raise notice '  % -- % row(s)', rpad(r.kind, 12), r.c;
  end loop;
end
$verify$;
