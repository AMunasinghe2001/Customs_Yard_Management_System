-- ============================================================================
-- Goods disposed under an "Other" status leave the yard like any others, and
-- nothing recorded when they did.
--
-- An "Other" disposition (handed to the Police, auctioned per an appeal
-- ruling, taken for Government use...) is a RULING. The goods physically
-- leaving is a second, later event — exactly the distinction already drawn
-- for re-exports and releases, each of which has its own delivered flag.
-- "Other" had none, so the Other Goods table could show a completed
-- disposition with no way to say whether the goods were still standing in
-- the warehouse.
--
-- ⚠️ NOT reusing yard_toggle_reexport_delivery. That function rejects any
-- entry whose tag is not a re-export, and writes `re_export_delivered` —
-- marking these goods re-exported, which they are not.
--
-- Safe to re-run.
-- ============================================================================

alter table public.warehouse_entries
  add column if not exists other_delivered boolean not null default false,
  add column if not exists other_delivered_at timestamptz,
  add column if not exists other_delivered_by uuid references public.profiles(id);

create or replace function public.yard_toggle_other_delivery(
  p_entry_id uuid,
  p_delivered boolean,
  p_receipt_no text default null,
  p_charge numeric default null,
  p_handed_at timestamptz default null
) returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_yard text;
  v_tag  text;
begin
  select p.yard,
         upper(substring(upper(trim(coalesce(w.return_notes, '')))
                         from '^\[([^\]]+)\]'))
    into v_yard, v_tag
    from public.warehouse_entries w
    join public.packages p on p.id = w.package_id
   where w.id = p_entry_id;

  if v_yard is null then
    raise exception 'no warehouse_entry with id %', p_entry_id;
  end if;

  -- The same guard the re-export function uses, for the same reason: a
  -- delivery flag written against the wrong kind of disposition is a
  -- record that cannot be told apart from a correct one.
  if v_tag is null or v_tag not in ('FINAL:OTHER', 'OTHER') then
    raise exception 'entry % is not an "Other" disposition (tag %)',
      p_entry_id, coalesce(v_tag, 'none');
  end if;

  if not (public.auth_user_is_disposal()
          or v_yard = (select yard from public.profiles where id = auth.uid())) then
    raise exception 'not authorized';
  end if;

  -- ⚠️ Does NOT close the warehouse entry: recording the disposition
  -- already closed it. Re-closing would overwrite returned_at with today.
  update public.warehouse_entries
     set other_delivered    = p_delivered,
         other_delivered_at =
           case when p_delivered then coalesce(p_handed_at, now()) end,
         other_delivered_by = case when p_delivered then auth.uid() end,
         handover_receipt_no = case when p_delivered then p_receipt_no
                                    else handover_receipt_no end,
         handover_charge     = case when p_delivered then p_charge
                                    else handover_charge end
   where id = p_entry_id;
end;
$function$;

revoke all on function public.yard_toggle_other_delivery(uuid, boolean, text, numeric, timestamptz) from public;
grant execute on function public.yard_toggle_other_delivery(uuid, boolean, text, numeric, timestamptz) to authenticated;

-- Verification.
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'warehouse_entries'
                    and column_name = 'other_delivered') then
    raise exception 'other_delivered column missing';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public'
                    and p.proname = 'yard_toggle_other_delivery') then
    raise exception 'yard_toggle_other_delivery missing';
  end if;
end $$;
