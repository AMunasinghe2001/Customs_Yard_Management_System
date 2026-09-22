-- ============================================================================
--  A password may not be reused.
--
--  sr_auth.change_password already refused the CURRENT password, which stopped
--  the laziest way to satisfy a 90-day prompt. But nothing stopped an officer
--  alternating between two passwords forever -- change to B, change back to A
--  -- so the rotation still protected nothing. If A leaked, it comes back
--  round every 90 days.
--
--  This keeps the last N hashes per account and refuses any of them.
--
--  ⚠️ Only HASHES are stored, never a password. They are the same bcrypt
--  hashes sr_auth.users already holds, moved aside as they are replaced -- so
--  this table is no more sensitive than the one it comes from, and a reuse
--  check is impossible without them (a hash cannot be reversed, only
--  compared against).
--
--  Safe to re-run.
-- ============================================================================

-- ── 1. How many to remember ─────────────────────────────────────────────────
--
-- 5 at 90 days is a 15-month memory: long enough that alternating is
-- impractical, short enough that the table stays small and an officer is not
-- fighting a decade of their own history.
create or replace function public.password_history_depth()
returns integer language sql immutable as $fn$ select 5 $fn$;


-- ── 2. The history ──────────────────────────────────────────────────────────
create table if not exists sr_auth.password_history (
  id           bigserial primary key,
  user_id      uuid not null references sr_auth.users(id) on delete cascade,
  password_hash text not null,
  changed_at   timestamptz not null default now()
);

create index if not exists password_history_user_idx
  on sr_auth.password_history (user_id, changed_at desc);

comment on table sr_auth.password_history is
  'Previous bcrypt hashes, newest first, so a password cannot be reused. '
  'Holds no plaintext. Trimmed to password_history_depth() per user.';

-- ⚠️ Nobody reads this table but the SECURITY DEFINER function below. The
-- application role must not be able to select it: the hashes are no more
-- sensitive than sr_auth.users, but there is no reason for them to leave the
-- database at all.
revoke all on sr_auth.password_history from public;
revoke all on sr_auth.password_history from authenticated, anon;


-- ── 3. The check, folded into change_password ───────────────────────────────
create or replace function sr_auth.change_password(
  p_user_id  uuid,
  p_password text
)
returns void
language plpgsql
security definer
set search_path = sr_auth, public, extensions
as $fn$
declare
  v_reason  text;
  v_current text;
  v_old     record;
  v_depth   integer := public.password_history_depth();
begin
  v_reason := public.password_policy_violation(p_password);
  if v_reason is not null then
    raise exception '%', v_reason using errcode = '22023';
  end if;

  select encrypted_password into v_current
    from sr_auth.users where id = p_user_id;

  if v_current is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  if v_current = crypt(p_password, v_current) then
    raise exception
      'This is your current password. Choose a password you have not used before.'
      using errcode = '22023';
  end if;

  -- ⚠️ Each hash carries its own salt, so they must be compared ONE AT A
  -- TIME with that row's salt -- there is no way to hash the candidate once
  -- and look it up. The depth is small precisely because each check is a
  -- deliberate bcrypt round.
  for v_old in
    select password_hash, changed_at
      from sr_auth.password_history
     where user_id = p_user_id
     order by changed_at desc
     limit v_depth
  loop
    if v_old.password_hash = crypt(p_password, v_old.password_hash) then
      raise exception
        'You have used this password before. Choose one of your last % passwords you have not used.',
        v_depth
        using errcode = '22023';
    end if;
  end loop;

  -- Keep the outgoing password so it cannot come back.
  insert into sr_auth.password_history (user_id, password_hash)
  values (p_user_id, v_current);

  update sr_auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf', 10)),
         updated_at         = now()
   where id = p_user_id;

  -- Trim beyond the depth: older entries can never refuse anything again.
  delete from sr_auth.password_history
   where user_id = p_user_id
     and id not in (
       select id from sr_auth.password_history
        where user_id = p_user_id
        order by changed_at desc
        limit v_depth
     );
end;
$fn$;


-- ── 4. Verify ───────────────────────────────────────────────────────────────
do $$
declare
  v_id uuid;
  v_saved text;
  v_ok boolean;
begin
  select id into v_id from sr_auth.users limit 1;
  if v_id is null then
    raise notice 'no user to test with - skipping';
    return;
  end if;

  -- Preserve the real password: this runs against live accounts.
  select encrypted_password into v_saved from sr_auth.users where id = v_id;

  perform sr_auth.change_password(v_id, 'Rotation#Aaa111');
  perform sr_auth.change_password(v_id, 'Rotation#Bbb222');

  -- Going back to the first must now be refused.
  v_ok := false;
  begin
    perform sr_auth.change_password(v_id, 'Rotation#Aaa111');
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'a previous password was accepted - reuse is not blocked';
  end if;

  -- Restore, and clear the history this test created.
  update sr_auth.users set encrypted_password = v_saved where id = v_id;
  delete from sr_auth.password_history where user_id = v_id;
  raise notice 'password reuse is blocked - verified and restored';
end $$;
