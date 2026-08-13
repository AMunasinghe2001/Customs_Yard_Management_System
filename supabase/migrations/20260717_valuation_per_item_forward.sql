-- ============================================================================
--  Per-item valuation forwarding
--  Run after 20260617_valuation_directorate.sql.
--
--  Until now the Valuation Directorate valued & forwarded a whole disposal
--  REQUEST at once (disposal_requests.valuation_status). This lets a single
--  ITEM be valued and forwarded on its own: each disposal_request_item carries
--  its own `forwarded` flag, and Central Disposal's feeds gate on that flag.
--  A "Forward All" still forwards every item of a request in one go.
--  Idempotent where practical — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Per-item forwarded flag ──────────────────────────────────────────────
alter table public.disposal_request_items
  add column if not exists forwarded boolean not null default false;

-- Backfill: items of requests already forwarded count as forwarded.
update public.disposal_request_items i
   set forwarded = true
  from public.disposal_requests r
 where i.request_id = r.id
   and r.valuation_status = 'forwarded'
   and i.forwarded = false;

-- 2. ── Set ONE item's cost (Valuation Directorate) ──────────────────────────
create or replace function public.valuation_set_item_cost(
  p_item_id uuid,
  p_cost    numeric
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;
  update public.disposal_request_items
     set valuation_cost = p_cost
   where id = p_item_id;
end;
$$;

grant execute on function public.valuation_set_item_cost(uuid, numeric)
  to authenticated;

-- 3. ── Forward ONE valued item to Central Disposal ──────────────────────────
create or replace function public.valuation_forward_item(
  p_item_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request uuid;
  v_cost    numeric;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  select request_id, valuation_cost into v_request, v_cost
    from public.disposal_request_items
   where id = p_item_id;

  if v_request is null then
    raise exception 'item not found';
  end if;
  if v_cost is null then
    raise exception 'valuation_incomplete';  -- this item still needs a cost
  end if;

  update public.disposal_request_items
     set forwarded = true
   where id = p_item_id;

  -- Keep the request-level status coherent: forwarded once any item is; and
  -- record who/when valued it (first forward wins for the timestamp).
  update public.disposal_requests
     set valuation_status = 'forwarded',
         valued_at = coalesce(valued_at, now()),
         valued_by = coalesce(valued_by, auth.uid())
   where id = v_request;
end;
$$;

grant execute on function public.valuation_forward_item(uuid) to authenticated;

-- 4. ── Forward EVERY item of a request (bulk) — all must be valued ──────────
create or replace function public.valuation_forward_all(
  p_request_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_missing int;
begin
  if not public.auth_user_is_valuation() then
    raise exception 'not authorized';
  end if;

  select count(*) into v_missing
    from public.disposal_request_items
   where request_id = p_request_id
     and valuation_cost is null;
  if v_missing > 0 then
    raise exception 'valuation_incomplete';
  end if;

  update public.disposal_request_items
     set forwarded = true
   where request_id = p_request_id;

  update public.disposal_requests
     set valuation_status = 'forwarded',
         valued_at = coalesce(valued_at, now()),
         valued_by = coalesce(valued_by, auth.uid())
   where id = p_request_id;
end;
$$;

grant execute on function public.valuation_forward_all(uuid) to authenticated;
