-- ============================================================================
--  049 · ICT owns the sale levies, the way it already owns the storage rate
--
--  ⚠️ THE BUG: adding a levy in ICT → Rates & Taxes failed with
--
--      new row violates row-level security policy for table "disposal_taxes"
--
--  The levy editor lives in the ICT console (screens/ict/system_rates_tab.dart)
--  and nowhere else -- the Disposal portal has no screen for it. But the only
--  write policies on the table were
--
--      disposal_taxes_manage             ALL   auth_user_is_disposal()
--      "disposal users can manage taxes" ALL   auth_user_is_disposal()
--
--  so an ICT officer was shown a control that the database was always going
--  to refuse. The screen and the policy disagreed about whose job this is.
--
--  ⚠️ `storage_rates`, edited on the SAME TAB, was already moved to ICT:
--
--      storage_rates_ict_insert / _update / _delete   auth_user_is_ict()
--
--  Two settings side by side on one page, one of them writable. That is the
--  asymmetry this file removes; it is not a new permission so much as the
--  half of an earlier change that was never finished.
--
--  ⚠️ DISPOSAL KEEPS ITS WRITE ACCESS. The levies decide what is charged on
--  a sale that Central Disposal conducts, and removing their ability to
--  correct a rate mid-process would be a bigger change than the one being
--  asked for -- made silently, in a migration about something else. If that
--  is wanted it should be its own decision.
--
--  Reading is unchanged: any signed-in user may read, because every sale
--  screen needs the rates to show a total.
--
--  Safe to re-run.
-- ============================================================================

do $$
begin
  if to_regclass('public.disposal_taxes') is null then
    raise notice 'SKIP: no disposal_taxes table here';
    return;
  end if;

  -- ── Insert ──────────────────────────────────────────────────────────────
  --
  -- ⚠️ Named per-command rather than one FOR ALL policy, matching how
  -- storage_rates is written. A single ALL policy cannot later be narrowed
  -- for one verb -- say, letting ICT add a levy but never delete one -- and
  -- that is exactly the shape a rate table tends to grow into.
  drop policy if exists disposal_taxes_ict_insert on public.disposal_taxes;
  create policy disposal_taxes_ict_insert on public.disposal_taxes
    for insert to authenticated
    with check (public.auth_user_is_ict());

  drop policy if exists disposal_taxes_ict_update on public.disposal_taxes;
  create policy disposal_taxes_ict_update on public.disposal_taxes
    for update to authenticated
    using (public.auth_user_is_ict())
    with check (public.auth_user_is_ict());

  drop policy if exists disposal_taxes_ict_delete on public.disposal_taxes;
  create policy disposal_taxes_ict_delete on public.disposal_taxes
    for delete to authenticated
    using (public.auth_user_is_ict());

  raise notice 'PASS: ICT may now manage the sale levies';
end $$;

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n_ict      int;
  n_disposal int;
  n_read     int;
begin
  select count(*) into n_ict from pg_policies
   where tablename = 'disposal_taxes'
     and cmd in ('INSERT', 'UPDATE', 'DELETE')
     and coalesce(with_check, qual, '') like '%auth_user_is_ict%';

  -- ⚠️ Checked as well as the new one. A migration that quietly removed
  -- Disposal's access while claiming to add ICT's would be the kind of
  -- change nobody notices until a sale cannot be recorded.
  select count(*) into n_disposal from pg_policies
   where tablename = 'disposal_taxes'
     and coalesce(with_check, qual, '') like '%auth_user_is_disposal%';

  select count(*) into n_read from pg_policies
   where tablename = 'disposal_taxes' and cmd = 'SELECT';

  if n_ict < 3 then
    raise exception 'expected 3 ICT write policies, found %', n_ict;
  end if;
  if n_disposal = 0 then
    raise exception 'Disposal lost its access to the levies';
  end if;
  if n_read = 0 then
    raise exception 'nobody can read the levies - every sale total needs them';
  end if;

  raise notice 'PASS: % ICT write, % disposal, % read policy(ies)',
    n_ict, n_disposal, n_read;
end $verify$;
