-- ============================================================================
--  Per-item appeal hold on forfeited_packages
--  Adds a held_item_ids UUID[] column so the Appeal Directorate can hold
--  individual items within a multi-item package, not the whole package at once.
--  The package-level appeal_hold boolean is kept for backward-compat but is
--  no longer used by the hold RPC — instead it mirrors (held_item_ids != '{}').
-- ============================================================================

-- 1. New column: array of package_item IDs currently on hold
alter table public.forfeited_packages
  add column if not exists held_item_ids uuid[] not null default '{}';

-- 2. Migrate existing holds: if appeal_hold=true and we don't know which item,
--    leave held_item_ids empty (the UI will show correct state via the flag).

-- 3. Replace set_appeal_hold RPC with per-item version
--    p_item_id: the specific package_item.id to hold/release, or NULL to
--    hold/release ALL items (backward-compat for single-item packages).
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

  if p_hold then
    if p_item_id is not null then
      -- Add item to held set (avoid duplicates)
      if not (v_item_ids @> array[p_item_id]) then
        v_new_ids := v_item_ids || array[p_item_id];
      else
        v_new_ids := v_item_ids;
      end if;
    else
      -- p_item_id null → not used in new flow, keep existing
      v_new_ids := v_item_ids;
    end if;
  else
    if p_item_id is not null then
      -- Remove specific item from held set
      select array_agg(x) into v_new_ids
        from unnest(v_item_ids) x
       where x <> p_item_id;
      if v_new_ids is null then v_new_ids := '{}'; end if;
    else
      -- Release all
      v_new_ids := '{}';
    end if;
  end if;

  update public.forfeited_packages
     set held_item_ids  = v_new_ids,
         -- keep legacy flag in sync (true if any item held)
         appeal_hold    = (array_length(v_new_ids, 1) > 0),
         appeal_hold_note = case
           when array_length(v_new_ids, 1) > 0 then p_note
           else null
         end,
         appeal_held_at = case
           when array_length(v_new_ids, 1) > 0 then coalesce(appeal_held_at, now())
           else null
         end,
         appeal_held_by = case
           when array_length(v_new_ids, 1) > 0 then coalesce(appeal_held_by, auth.uid())
           else null
         end
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.set_appeal_hold(uuid, boolean, text, uuid) to authenticated;
