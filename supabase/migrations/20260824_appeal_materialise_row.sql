-- ============================================================================
--  Let the Appeal Directorate lodge an appeal against Detain / Abandoned /
--  "Other" goods, not just forfeits.
--
--  Those three statuses carry NO `forfeited_packages` row until something acts
--  on them, so the appeal portal lists them as synthetic rows. The appeal RPCs
--  (`set_appeal_hold`, `release_appeal_with_decision`) take a real uuid, so the
--  first appeal against such goods has to create the row.
--
--  The appeal role only holds SELECT on `forfeited_packages`, so the insert
--  cannot be done from the client. This SECURITY DEFINER function does it, and
--  is the ONLY way the appeal role can write that table.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

create or replace function public.appeal_ensure_forfeited_row(
  p_package_id uuid,
  p_item_id    uuid,
  p_source     text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id       uuid;
  v_pkg      record;
  v_qty      int;
  v_entry    date;
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  -- Only the three no-row statuses may be materialised this way; a genuine
  -- forfeit always has its row already.
  if p_source not in ('detain', 'abandoned', 'other') then
    raise exception 'unsupported source: %', p_source;
  end if;

  -- Already created by an earlier appeal?
  select id into v_id
    from public.forfeited_packages
   where package_id = p_package_id
     and item_id    = p_item_id
     and source     = p_source
   limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select p.sr_number, p.consignee_name, p.reason, p.yard,
         coalesce(p.entry_date::date, p.created_at::date) as entry_date
    into v_pkg
    from public.packages p
   where p.id = p_package_id;
  if v_pkg is null then
    raise exception 'package not found';
  end if;

  select quantity into v_qty
    from public.package_items where id = p_item_id;

  v_entry := v_pkg.entry_date;

  insert into public.forfeited_packages (
    package_id, item_id, entry_qty, sr_number, consignee_name,
    forfeited_at, appeal_deadline, reason, yard, source)
  values (
    p_package_id, p_item_id, v_qty, v_pkg.sr_number, v_pkg.consignee_name,
    v_entry,
    -- The same 30-day window the synthetic row was showing: entry + 30 days.
    v_entry + interval '30 days',
    coalesce(v_pkg.reason, 'Appeal lodged'),
    v_pkg.yard,
    p_source)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function
  public.appeal_ensure_forfeited_row(uuid, uuid, text) to authenticated;

reset lock_timeout;
