-- ============================================================================
--  01 · Authentication and session state
--
--  ⚠️ This is STANDARD PostgreSQL. `auth` is a schema this project creates
--  and owns, like `public`; nothing here needs Supabase, and the only two
--  extensions used (uuid-ossp, pgcrypto) ship with PostgreSQL itself.
--
--  The name `auth` is kept because all 73 RLS policies are written against
--  these three symbols:
--
--      sr_auth.uid()   -> the signed-in user's id
--      sr_auth.role()  -> 'authenticated' / 'anon'
--      sr_auth.users   -> the account table
--
--  Keeping the names means **the policies do not have to be rewritten at
--  all**. Rewriting 73 access-control rules by hand would have been 73
--  chances to widen access by accident, and a policy that is wrong is silent
--  — it does not fail, it just shows one yard another yard's goods.
--
--  How a session is established: the app sets a session variable right after
--  connecting (see PgDatabase._applySession, which calls sr_auth.begin_session):
--
--      select set_config('app.current_user_id', '<uuid>', false);
--      select set_config('app.current_role',    'authenticated', false);
--
--  `sr_auth.uid()` reads that variable. Signed out it is '', so `sr_auth.uid()`
--  returns NULL and every user-scoped policy denies — the safe default.
--
--  Run this FIRST, before the schema.
--  Idempotent — safe to re-run.
-- ============================================================================

create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

create schema if not exists sr_auth;

-- ── sr_auth.users ──────────────────────────────────────────────────────────────
--  The account table. Only the columns the app and the schema's foreign keys
--  actually reference are kept.
--
--  `encrypted_password` holds a bcrypt hash from pgcrypto's crypt(); the app
--  never sees a plaintext password after sign-up.
create table if not exists sr_auth.users (
  id                  uuid primary key default uuid_generate_v4(),
  email               text unique not null,
  encrypted_password  text,
  email_confirmed_at  timestamptz,
  last_sign_in_at     timestamptz,
  failed_login_attempts integer not null default 0,
  locked_until        timestamptz,
  raw_user_meta_data  jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

alter table sr_auth.users
  add column if not exists failed_login_attempts integer not null default 0,
  add column if not exists locked_until timestamptz;

create index if not exists auth_users_email_idx on sr_auth.users(lower(email));

-- ── sr_auth.uid() ──────────────────────────────────────────────────────────────
--  The signed-in user, or NULL when nobody is.
--
--  `current_setting(..., true)` — the `true` means "return NULL if unset"
--  rather than raising, which matters because a fresh connection has no
--  setting until the app declares one.
create or replace function sr_auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('app.current_user_id', true), '')::uuid;
$$;

-- ── sr_auth.role() ─────────────────────────────────────────────────────────────
--  'authenticated' once a user is set, 'anon' otherwise. Nine policies test
--  this to mean "any signed-in officer may read".
create or replace function sr_auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('app.current_role', true), ''),
    case
      when nullif(current_setting('app.current_user_id', true), '') is null
        then 'anon'
      else 'authenticated'
    end
  );
$$;

-- ── sr_auth.email() ────────────────────────────────────────────────────────────
--  Not used by any policy today, but cheap to provide and the obvious thing
--  for a future one to reach for.
create or replace function sr_auth.email()
returns text
language sql
stable
as $$
  select u.email from sr_auth.users u where u.id = sr_auth.uid();
$$;

-- ── supabase_realtime publication ───────────────────────────────────────────
--  Eleven migrations run `alter publication supabase_realtime add table ...`.
--  Creating the publication lets those migrations run UNCHANGED — the point of
--  this whole file. Nothing reads the publication here; realtime is delivered
--  by LISTEN/NOTIFY triggers instead (see 03_realtime.sql), and the
--  publication's member list is exactly the set of tables that need one.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime')
  then
    create publication supabase_realtime;
  end if;
end $$;

-- ── The grant target roles ──────────────────────────────────────────────────
--  The schema carries 36 `grant ... to authenticated / anon / service_role`
--  statements, so those three roles have to exist or every one of the grants
--  fails and takes its migration down with it.
--
--  ⚠️ NOLOGIN. Nothing ever connects AS these roles — the app connects as its
--  own user (yard_app). They exist only to give the grants a target and to
--  keep the 73 policies readable as written.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

-- The connecting user must hold these to inherit what is granted to them.
do $$
begin
  execute format('grant anon, authenticated, service_role to %I', current_user);
exception
  -- Already a member, or not permitted to self-grant: neither is fatal.
  when others then null;
end $$;

grant usage on schema public to anon, authenticated, service_role;

-- ── Readable by everyone; only the app's own role writes ────────────────────
grant usage on schema sr_auth to public;
grant select on sr_auth.users to public;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  With nothing set, uid() is NULL and role() is 'anon'.
select sr_auth.uid()                              as uid_when_signed_out,
       sr_auth.role()                             as role_when_signed_out;
