-- ============================================================================
--  68 · Finish the 10.10.71.15 setup
--
--  The schema is applied (32 tables, 132 RLS policies) and `yard_app` has its
--  grants and its membership of `authenticated`. Two things are left, and both
--  need a decision rather than a script:
--
--    1. yard_app's password — chosen by you, never committed here.
--    2. The first ICT account — nothing can sign in until one exists.
--
--  Run as an administrator (the `postgres` role) in pgAdmin on the server.
-- ============================================================================


-- ── 1. The application password ─────────────────────────────────────────────
--
-- ⚠️ Replace the placeholder. Do NOT reuse the postgres administrator
-- password: the whole point of yard_app is that it is a SEPARATE identity that
-- cannot bypass RLS, and sharing the password gives back in convenience what
-- the separate role was created to take away.
--
-- The same value goes in PG_PASSWORD in the .env beside each branch's .exe.

alter role yard_app with password 'PUT-A-LONG-RANDOM-PASSWORD-HERE';

-- Confirm it was stored as SCRAM, not the legacy md5.
select rolname,
       substring(rolpassword for 14) as hash_kind   -- expect SCRAM-SHA-256
  from pg_authid
 where rolname = 'yard_app';


-- ── 2. The first ICT account ────────────────────────────────────────────────
--
-- ⚠️ `profiles` is empty, so no one can sign in at all — including ICT, which
-- is the portal that provisions everybody else. This is the bootstrap: one
-- account, created directly, from which every other account is made through
-- the app.
--
-- Replace the e-mail and the password. The password must satisfy the same
-- rule the app enforces (12..24 characters, upper, lower, digit, symbol, no
-- common word) or the officer cannot re-enter it on their next rotation.

do $$
declare
  v_email text := 'ict@customs.gov.lk';          -- ⚠️ change
  v_password text := 'PUT-A-REAL-PASSWORD-HERE'; -- ⚠️ change
  v_id uuid;
  v_violation text;
begin
  -- Refuse a password the app itself would reject, rather than creating an
  -- account whose holder is locked out of their own rotation.
  v_violation := public.password_policy_violation(v_password);
  if v_violation is not null then
    raise exception 'ICT password rejected: %', v_violation;
  end if;

  insert into auth.users (email, encrypted_password, email_confirmed_at)
  values (lower(trim(v_email)),
          crypt(v_password, gen_salt('bf', 10)),
          now())
  on conflict (email) do update set email = excluded.email
  returning id into v_id;

  -- ⚠️ `username` is UNIQUE on its lowercase form
  -- (profiles_username_lower_idx), and `on conflict (id)` does not catch
  -- that — a second run with a different e-mail would fail on the username
  -- instead, which reads like a database fault rather than "this account
  -- already exists". Checked first, so the message says which.
  if exists (select 1 from public.profiles
              where lower(username) = 'ict.admin' and id <> v_id) then
    raise exception
      'An account already holds the username ict.admin. Use the app to '
      'manage it, or choose another username here.';
  end if;

  insert into public.profiles (id, full_name, username, role, job_role,
                               is_active, created_at, updated_at)
  values (v_id,
          'ICT Directorate (System Administrator)',
          'ict.admin',
          'ict',
          'ICT_ADMIN',
          true,
          now(),
          now())
  on conflict (id) do update
    set role = 'ict', is_active = true, updated_at = now();

  raise notice 'ICT account ready: % (%)', v_email, v_id;
end $$;


-- ── 3. Verify ───────────────────────────────────────────────────────────────
select p.full_name, p.role, p.job_role, p.is_active, u.email
  from public.profiles p
  join auth.users u on u.id = p.id;


-- ── 4. Optional, but recommended before this port is exposed ────────────────
--
-- ⚠️ pg_hba.conf currently ends with a `host ... 0.0.0.0/0 scram-sha-256`
-- rule. `host` accepts a PLAINTEXT connection as readily as a TLS one, so a
-- client with PG_SSL=false still gets through and the encryption the server
-- offers is optional in practice.
--
-- Change that line to `hostssl` and reload:
--
--     hostssl  all  all  0.0.0.0/0  scram-sha-256
--     select pg_reload_conf();
--
-- Narrow 0.0.0.0/0 to the branch offices' own addresses wherever the ISP
-- gives them a static one — a source-restricted rule is worth more than
-- anything else on this list. See postgres/67_internet_deployment.md.
