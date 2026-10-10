-- ============================================================================
--  FIX: allow a yard (not just the Central Disposal Directorate) to toggle the
--  delivery status of its own sold packages from the yard Sold Packages table.
--  Run if you already ran 20260611_tender_sale_sold_price.sql — it only
--  REPLACES disposal_toggle_delivery_status. (Previously yard admins got
--  "not authorized / P0001".)
-- ============================================================================

create or replace function public.disposal_toggle_delivery_status(
  p_item_id uuid,
  p_is_delivered boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yard text;
begin
  select yard into v_yard from public.tender_sale_items where id = p_item_id;
  if v_yard is null then
    raise exception 'tender sale item not found';
  end if;
  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = auth.uid())) then
    raise exception 'not authorized';
  end if;
  update public.tender_sale_items
     set is_delivered = p_is_delivered,
         delivered_at = case when p_is_delivered then now() else null end
   where id = p_item_id;
end;
$$;

grant execute on function public.disposal_toggle_delivery_status(uuid, boolean)
  to authenticated;

-- Done.
