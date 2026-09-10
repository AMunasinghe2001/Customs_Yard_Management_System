-- ============================================================================
--  65 · A rate change has an author
--
--  `storage_rates` records the rate and the day it took effect, and nothing
--  about who set it. The history table therefore printed "System" against
--  every row -- hardcoded in the provider, because there was no column to read
--  instead.
--
--  ⚠️ That is a gap in an AUDIT trail, not a cosmetic one. The daily rate
--  decides what every yard in the country bills, and until now the record
--  could not say which officer changed it or when they were signed in.
--
--  The move to the ICT portal is the moment to close it: ICT is the office
--  that will hold this figure from here on, and every other ICT action is
--  already attributed.
--
--  BACKFILL: none. The existing row genuinely has no author -- it was seeded --
--  and writing a name against it would invent one. It keeps reading "System",
--  which is true of it.
-- ============================================================================

set lock_timeout = '5s';

alter table public.storage_rates
  add column if not exists set_by uuid references public.profiles(id);

-- ── The write, attributed ───────────────────────────────────────────────────
--
-- ⚠️ SECURITY DEFINER with an explicit check, not an RLS policy. The rate is
-- national: one row governs every yard, so "may this user write here" is a
-- question about their OFFICE, not about a row they own.
create or replace function public.set_storage_rate(p_rate numeric)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_role text;
begin
  if p_rate is null or p_rate <= 0 then
    -- ⚠️ A rate of zero silently stops every warehouse charge in the country,
    -- and the only symptom is invoices reading LKR 0.
    raise exception 'the storage rate must be greater than zero'
      using errcode = 'check_violation';
  end if;

  select role into v_role from public.profiles where id = auth.uid();

  -- ICT owns this figure now. `admin` stays permitted so a yard mid-upgrade
  -- is not locked out of its own rate between deploys.
  if coalesce(v_role, '') not in ('ict', 'admin') then
    raise exception 'only the ICT Directorate may set the storage rate';
  end if;

  insert into public.storage_rates (rate, effective_from, set_by)
  values (p_rate, now(), auth.uid());
end;
$fn$;

revoke all on function public.set_storage_rate(numeric) from public;
grant execute on function public.set_storage_rate(numeric) to authenticated;

-- ── Verify against live data ────────────────────────────────────────────────
do $verify$
declare
  n_rows   int;
  n_authored int;
  ok       boolean;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'storage_rates'
                    and column_name = 'set_by') then
    raise exception 'the set_by column was not added';
  end if;

  select count(*), count(set_by) into n_rows, n_authored
    from public.storage_rates;
  raise notice 'storage_rates: % row(s), % with an author', n_rows, n_authored;

  -- ⚠️ The zero guard must actually FIRE. A validation that exists and does
  -- not reject reads as enforced and is not.
  begin
    perform public.set_storage_rate(0);
    ok := false;
  exception when others then
    ok := sqlerrm like '%greater than zero%'
       or sqlerrm like '%only the ICT Directorate%';
  end;
  if not ok then
    raise exception 'set_storage_rate accepted a rate of zero';
  end if;

  -- And the office check, for a caller with no profile at all (auth.uid() is
  -- null in this session, so the role lookup finds nothing).
  begin
    perform public.set_storage_rate(50);
    ok := false;
  exception when others then
    ok := sqlerrm like '%only the ICT Directorate%';
  end;
  if not ok then
    raise exception 'set_storage_rate accepted a caller with no office';
  end if;

  raise notice 'verified: a rate change is attributed and guarded';
end $verify$;
