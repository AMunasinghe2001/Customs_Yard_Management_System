-- ============================================================================
--  A log row remembers the role its actor held AT THE TIME.
--
--  ⚠️ `audit_logs` stores only user_id, and the Activity Log reads the role by
--  joining profiles — so it always shows the role the person holds TODAY. When
--  an officer is promoted to SDDC, every action they ever took retroactively
--  becomes an SDDC action. That is a false record: the trail says a yard
--  administrator did things that an officer did, and the promotion date
--  disappears from the history entirely.
--
--  An audit trail must say what was true when the action happened.
--
--  ⚠️ The historical rows CANNOT be recomputed exactly. The only evidence of
--  past roles is the 'Privilege change' entries the trigger wrote, and those
--  cover some accounts and not others. So the backfill walks that evidence
--  where it exists and falls back to today's role where it does not -- and
--  records which rows were a guess, rather than presenting all of it as
--  equally certain.
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. The column ───────────────────────────────────────────────────────────
alter table public.audit_logs add column if not exists actor_role text;

comment on column public.audit_logs.actor_role is
  'The role the actor held WHEN the action happened. Never read the role by '
  'joining profiles: that renames every historical action after a promotion '
  '(migration 029).';

-- Rows backfilled from a guess rather than from evidence are marked, so a
-- later reader can tell the difference.
alter table public.audit_logs add column if not exists actor_role_inferred boolean;


-- ── 2. Stamp it on every new row ────────────────────────────────────────────
--
-- ⚠️ A TRIGGER, not the call sites. recordLog is one of many writers -- the
-- failed-login function, the privilege trigger and several services all
-- insert here -- and a column filled by the caller is a column that is
-- sometimes empty.
create or replace function public.audit_logs_stamp_actor_role()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  if new.actor_role is null and new.user_id is not null then
    select role into new.actor_role
      from public.profiles where id = new.user_id;
  end if;
  return new;
end;
$fn$;

drop trigger if exists audit_logs_stamp_actor_role on public.audit_logs;
create trigger audit_logs_stamp_actor_role
  before insert on public.audit_logs
  for each row execute function public.audit_logs_stamp_actor_role();


-- ── 3. Backfill what can be known ───────────────────────────────────────────
--
-- ⚠️ The append-only trigger blocks UPDATE on audit_logs, so this runs with
-- the guard disabled for the duration -- the ONE legitimate reason to touch
-- history is adding a column that was missing, and the action, actor and
-- timestamp are untouched.
do $$
declare
  r record;
  v_role text;
  v_inferred boolean;
  v_count int := 0;
  v_guessed int := 0;
begin
  -- ⚠️ Three separate guards, not one: audit_logs_no_update, _no_delete and
  -- _no_truncate. Only the UPDATE guard is stood down, and only to add a
  -- column that was missing -- the action, actor and timestamp are untouched.
  alter table public.audit_logs disable trigger audit_logs_no_update;

  for r in
    select id, user_id, created_at
      from public.audit_logs
     where actor_role is null and user_id is not null
     order by created_at
  loop
    -- The earliest privilege change AFTER this row tells us what the role was
    -- BEFORE that change -- which is the role held when this row was written.
    -- ⚠️ `from` is nested INSIDE `role`, not at the top level:
    -- {"role": {"to": "admin", "from": "officer"}}. Reading details->>'from'
    -- returned null for every row, so the first run marked all 1010 as
    -- inferred while the evidence was sitting right there.
    select pc.details->'role'->>'from' into v_role
      from public.audit_logs pc
     where pc.action like 'Privilege change%'
       and pc.entity_id = r.user_id::text
       and pc.created_at > r.created_at
       and pc.details ? 'role'
       and pc.details->'role' ? 'from'
     order by pc.created_at
     limit 1;

    if v_role is null then
      -- No later change recorded, so the role has not moved since: today's
      -- value IS the value of the day.
      select role into v_role from public.profiles where id = r.user_id;
      v_inferred := true;
      v_guessed := v_guessed + 1;
    else
      v_inferred := false;
    end if;

    update public.audit_logs
       set actor_role = v_role, actor_role_inferred = v_inferred
     where id = r.id;
    v_count := v_count + 1;
  end loop;

  alter table public.audit_logs enable trigger audit_logs_no_update;

  raise notice '% row(s) stamped, % of them inferred from today''s role',
    v_count, v_guessed;
exception when others then
  -- Never leave the append-only guard off.
  alter table public.audit_logs enable trigger audit_logs_no_update;
  raise;
end $$;


-- ── 4. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_id uuid;
  v_before text;
  v_after text;
  v_null int;
begin
  select count(*) into v_null
    from public.audit_logs where user_id is not null and actor_role is null;
  if v_null > 0 then
    raise exception '% row(s) still have no actor_role', v_null;
  end if;

  -- ⚠️ The actual promotion case: stamp a row, change the role, and the row
  -- must still say what it said.
  select id into v_id from public.profiles where role = 'officer' limit 1;
  if v_id is null then
    raise notice 'no officer to verify with - skipped';
    return;
  end if;

  insert into public.audit_logs (user_id, action, entity_type, entity_id)
  values (v_id, 'Migration 029 self-check', 'auth', 'migration');

  select actor_role into v_before from public.audit_logs
   where action = 'Migration 029 self-check' and user_id = v_id
   order by created_at desc limit 1;

  update public.profiles set role = 'admin' where id = v_id;
  select actor_role into v_after from public.audit_logs
   where action = 'Migration 029 self-check' and user_id = v_id
   order by created_at desc limit 1;
  update public.profiles set role = 'officer' where id = v_id;

  if v_before is distinct from 'officer' then
    raise exception 'the row was stamped %, expected officer',
      coalesce(v_before,'NULL');
  end if;
  if v_after is distinct from v_before then
    raise exception
      'the promotion rewrote history: the row said % and now says %',
      v_before, v_after;
  end if;

  raise notice
    'verified: a promotion does not rename past actions (1 self-check row '
    'left in the trail)';
end $$;
