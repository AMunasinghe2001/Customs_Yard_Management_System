-- ============================================================================
--  A directorate is not inside a yard.
--
--  ⚠️ `profiles.yard` defaults to 'GL1', so EVERY account created without an
--  explicit yard silently became a Grey Line 1 account -- including ICT,
--  Valuation, Appeal, Central Disposal and Top Management, none of which
--  belong to a yard at all. The Activity Log then printed "Grey Line 1"
--  beside an ICT sign-in, which is simply untrue: those officers work in
--  their directorate, and yard staff are separate people.
--
--  A directorate touches a yard only through the SR records it reads, and
--  that relationship is already carried by the PACKAGE's yard -- never by the
--  officer's.
--
--  ⚠️ Verified before writing this: the yard-scoping RLS policies exempt
--  directorates. `yard_staff_boundary` applies only when
--  auth_user_is_yard_staff(), and each directorate has its own *_read_all
--  policy that does not consult the yard. A Valuation session saw the same
--  176 packages with yard = NULL as it did with yard = 'GL1'.
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. Stop the default from claiming new accounts ──────────────────────────
--
-- ⚠️ The default is REMOVED rather than changed. A yard account is always
-- created with an explicit yard (ICT picks it when provisioning), so the
-- default only ever served to put a wrong answer on directorate rows.
alter table public.profiles alter column yard drop default;

comment on column public.profiles.yard is
  'The yard an OFFICER or yard ADMIN belongs to. NULL for directorate roles '
  '(ict, valuation, appeal, disposal, executive) -- they are not part of a '
  'yard. Do not add a default: it silently mislabels every directorate '
  'account (see migration 027).';


-- ── 2. Clear the yard the default wrongly assigned ──────────────────────────
do $$
declare
  v_count int;
begin
  with cleared as (
    update public.profiles
       set yard = null, updated_at = now()
     where role in ('ict', 'valuation', 'appeal', 'disposal', 'executive')
       and yard is not null
    returning 1
  )
  select count(*) into v_count from cleared;
  raise notice '% directorate account(s) no longer claim a yard', v_count;
end $$;


-- ── 3. Keep it that way ─────────────────────────────────────────────────────
--
-- ⚠️ A CHECK rather than a trigger: it states the rule where anyone reading
-- the table will see it, and it cannot be skipped by a direct write.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'profiles_directorate_has_no_yard') then
    alter table public.profiles
      add constraint profiles_directorate_has_no_yard
      check (
        role not in ('ict', 'valuation', 'appeal', 'disposal', 'executive')
        or yard is null
      );
  end if;
end $$;


-- ── 4. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_bad int;
  v_id uuid;
begin
  select count(*) into v_bad
    from public.profiles
   where role in ('ict','valuation','appeal','disposal','executive')
     and yard is not null;
  if v_bad > 0 then
    raise exception '% directorate account(s) still carry a yard', v_bad;
  end if;

  -- The constraint must actually refuse one.
  select id into v_id from public.profiles where role = 'ict' limit 1;
  if v_id is not null then
    begin
      update public.profiles set yard = 'GL1' where id = v_id;
      raise exception
        'a directorate account can still be given a yard - the check '
        'constraint is not doing its job';
    exception when check_violation then
      null;  -- exactly what should happen
    end;
  end if;

  -- ⚠️ And a YARD account must still be able to have one, or this has broken
  -- the thing the column is actually for.
  select id into v_id from public.profiles where role = 'officer' limit 1;
  if v_id is not null then
    update public.profiles set yard = yard where id = v_id;
  end if;

  raise notice 'verified: directorates carry no yard, yard staff still do';
end $$;
