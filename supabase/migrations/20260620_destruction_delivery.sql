-- ============================================================================
--  Destroyed-package delivery tracking.
--
--  Destroyed packages can also be physically delivered out (like sold ones), so
--  the Destroyed Packages tables (Central + yard) show a Delivered / Pending
--  status and the details popup gets a "Mark Delivered" button — mirroring the
--  Sold Packages flow.
--
--  1. Adds `delivered` / `delivered_at` to destruction_items.
--  2. Adds a toggle RPC (yard OR Central Disposal may flip it), mirroring
--     disposal_toggle_delivery_status for sold packages.
--
--  Idempotent — safe to re-run. ⚠️ CLOSE THE APP FIRST (brief table lock).
-- ============================================================================

-- 1. ── Columns ──────────────────────────────────────────────────────────────
alter table public.destruction_items
  add column if not exists delivered     boolean not null default false;
alter table public.destruction_items
  add column if not exists delivered_at   timestamptz;

-- 2. ── Toggle RPC ────────────────────────────────────────────────────────────
create or replace function public.disposal_toggle_destruction_delivery(
  p_item_id uuid,
  p_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yard text;
begin
  select yard into v_yard from public.destruction_items where id = p_item_id;
  if v_yard is null then
    raise exception 'destruction item not found';
  end if;
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = auth.uid())) then
    raise exception 'not authorized';
  end if;
  update public.destruction_items
     set delivered = p_delivered,
         delivered_at = case when p_delivered then now() else null end
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_toggle_destruction_delivery(uuid, boolean)
  to authenticated;

-- Done.
