-- ── Appeal decision on release ───────────────────────────────────────────────
-- When the Appeal Directorate lifts an appeal hold (appeal processed), it must
-- record what the owning yard should do next with the package: Release the
-- goods to the owner, Sell, Destroy, Re-export or Other. This decision is stored
-- on the forfeited package so the yard can act on it.

alter table public.forfeited_packages
  add column if not exists appeal_decision      text,
  add column if not exists appeal_decision_note text,
  add column if not exists appeal_decided_at    timestamptz,
  add column if not exists appeal_decided_by    uuid references public.profiles(id);

-- Lift an appeal hold AND record the directorate's decision in one call.
-- Decision is one of: RELEASE, SALE, DESTROY, RE-EXPORT, OTHER (free text for
-- OTHER is carried in p_note). Appeal-role only; SECURITY DEFINER.
create or replace function public.release_appeal_with_decision(
  p_forfeited_id uuid,
  p_decision     text,
  p_note         text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.auth_user_is_appeal() then
    raise exception 'not authorized';
  end if;

  if not exists (select 1 from public.forfeited_packages where id = p_forfeited_id) then
    raise exception 'forfeited package not found';
  end if;

  update public.forfeited_packages
     set appeal_hold           = false,
         appeal_hold_note      = null,
         appeal_held_at        = null,
         appeal_held_by        = null,
         appeal_decision       = p_decision,
         appeal_decision_note  = p_note,
         appeal_decided_at     = now(),
         appeal_decided_by     = auth.uid()
   where id = p_forfeited_id;
end;
$$;

grant execute on function public.release_appeal_with_decision(uuid, text, text) to authenticated;
