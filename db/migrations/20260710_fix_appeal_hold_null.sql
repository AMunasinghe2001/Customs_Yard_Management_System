-- ============================================================================
--  FIX: set_appeal_hold set appeal_hold = NULL when releasing the last held
--  item, violating the NOT NULL constraint on forfeited_packages.appeal_hold.
--
--  BUG: the RPC synced the legacy boolean flag with
--       appeal_hold = (array_length(v_new_ids, 1) > 0)
--  In PostgreSQL, array_length('{}', 1) returns NULL (not 0) for an empty
--  array, so releasing the last held item made the expression NULL > 0 = NULL,
--  and the UPDATE tried to store appeal_hold = NULL → error 23502:
--    null value in column "appeal_hold" ... violates not-null constraint
--  This surfaced when the Appeal Directorate pressed "Confirm & Release Hold"
--  (or unheld an item), because that path clears held_item_ids to '{}'.
--
--  FIX: use cardinality(), which returns 0 (not NULL) for an empty array, so
--  the flag is always a real boolean. Same substitution in the note/date/by
--  CASE expressions for consistency.
-- ============================================================================

create or replace function public.set_appeal_hold(
  p_forfeited_id uuid,
  p_hold         boolean,
  p_note         text    default null,
  p_item_id      uuid    default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deadline    timestamptz;
  v_item_ids    uuid[];
  v_new_ids     uuid[];
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select appeal_deadline, held_item_ids
    into v_deadline, v_item_ids
    from public.forfeited_packages
   where id = p_forfeited_id;

  if v_deadline is null then
    raise exception 'forfeited package not found';
  end if;

  if p_hold and v_deadline < now() then
    raise exception 'appeal_window_passed';
  end if;

  v_item_ids := coalesce(v_item_ids, '{}');

  if p_hold then
    if p_item_id is not null then
      -- Add item to held set (avoid duplicates).
      if not (v_item_ids @> array[p_item_id]) then
        v_new_ids := v_item_ids || array[p_item_id];
      else
        v_new_ids := v_item_ids;
      end if;
    else
      -- p_item_id null → not used in new flow, keep existing.
      v_new_ids := v_item_ids;
    end if;
  else
    if p_item_id is not null then
      -- Remove specific item from held set.
      select array_agg(x) into v_new_ids
        from unnest(v_item_ids) x
       where x <> p_item_id;
      if v_new_ids is null then v_new_ids := '{}'; end if;
    else
      -- Release all.
      v_new_ids := '{}';
    end if;
  end if;

  update public.forfeited_packages
     set held_item_ids  = v_new_ids,
         -- cardinality() → 0 (not NULL) for '{}', so the flag is never NULL.
         appeal_hold    = (cardinality(v_new_ids) > 0),
         appeal_hold_note = case
           when cardinality(v_new_ids) > 0 then p_note
           else null
         end,
         appeal_held_at = case
           when cardinality(v_new_ids) > 0 then coalesce(appeal_held_at, now())
           else null
         end,
         appeal_held_by = case
           when cardinality(v_new_ids) > 0 then coalesce(appeal_held_by, auth.uid())
           else null
         end
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.set_appeal_hold(uuid, boolean, text, uuid) to authenticated;

-- ── Per-item appeal decisions ───────────────────────────────────────────────
-- The Appeal Directorate decides ONE item at a time, but the decision was being
-- written to the package-level appeal_decision column — so deciding one item of
-- a multi-item package wrongly marked EVERY item decided (it vanished from the
-- Appeal list and every yard row showed "→ Sell"). Mirror the per-item hold
-- design: store decisions in a jsonb map keyed by item id.
alter table public.forfeited_packages
  add column if not exists item_appeal_decisions jsonb not null default '{}'::jsonb;

-- release_appeal_with_decision now takes p_item_id. When given, it records the
-- decision for that ONE item (jsonb map) and releases only that item's hold —
-- leaving siblings untouched. When null (legacy / single-item), it keeps the old
-- package-level behaviour.
create or replace function public.release_appeal_with_decision(
  p_forfeited_id uuid,
  p_decision     text,
  p_note         text default null,
  p_item_id      uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_ids uuid[];
  v_new_ids  uuid[];
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  select coalesce(held_item_ids, '{}') into v_item_ids
    from public.forfeited_packages
   where id = p_forfeited_id;
  if v_item_ids is null then
    raise exception 'forfeited package not found';
  end if;

  if p_item_id is not null then
    -- Remove ONLY this item from the held set (siblings keep their holds).
    select coalesce(array_agg(x), '{}') into v_new_ids
      from unnest(v_item_ids) x
     where x <> p_item_id;

    update public.forfeited_packages
       set item_appeal_decisions = coalesce(item_appeal_decisions, '{}'::jsonb)
             || jsonb_build_object(
                  p_item_id::text,
                  jsonb_build_object(
                    'decision',    p_decision,
                    'note',        p_note,
                    'decided_at',  now(),
                    'decided_by',  auth.uid()
                  )),
           held_item_ids = v_new_ids,
           appeal_hold   = (cardinality(v_new_ids) > 0),
           appeal_hold_note = case
             when cardinality(v_new_ids) > 0 then appeal_hold_note else null end,
           appeal_held_at = case
             when cardinality(v_new_ids) > 0 then appeal_held_at else null end,
           appeal_held_by = case
             when cardinality(v_new_ids) > 0 then appeal_held_by else null end
     where id = p_forfeited_id;
  else
    -- Legacy package-level decision (single-item / no item id supplied).
    update public.forfeited_packages
       set appeal_hold      = false,
           held_item_ids    = '{}',
           appeal_hold_note  = null,
           appeal_held_at    = null,
           appeal_held_by    = null,
           appeal_decision   = p_decision,
           appeal_decision_note = p_note,
           appeal_decided_at = now(),
           appeal_decided_by = auth.uid()
     where id = p_forfeited_id;
  end if;
end;
$$;

grant execute on function public.release_appeal_with_decision(uuid, text, text, uuid) to authenticated;

-- Repair any rows the old buggy RPC may already have left with a NULL
-- appeal_hold (e.g. a failed "release last item" attempt): a NULL flag means
-- "no items held" → set it to a real boolean derived from held_item_ids.
update public.forfeited_packages
   set appeal_hold = (cardinality(coalesce(held_item_ids, '{}')) > 0)
 where appeal_hold is null;

-- Clear STALE package-level appeal decisions on MULTI-ITEM packages: the old
-- flow wrote one item's decision to the whole package, so a sibling with no
-- decision inherited it (e.g. deciding 34567rtyu marked erty "Sell" too). Now
-- that decisions are per-item (item_appeal_decisions), the package-level column
-- must not bleed across a multi-item package — clear it so undecided siblings
-- return to the appeal window. Single-item packages keep it (valid fallback).
update public.forfeited_packages fp
   set appeal_decision      = null,
       appeal_decision_note = null,
       appeal_decided_at    = null,
       appeal_decided_by    = null
 where fp.appeal_decision is not null
   and (select count(*) from public.package_items pi
         where pi.package_id = fp.package_id) > 1;
