-- ============================================================================
-- 66 · Provision the least-privilege login used by every desktop client.
--
-- Run ONCE as a database administrator, then put the same password in the
-- .env next to each installed application:
--
--   PG_USER=yard_app
--   PG_PASSWORD=<the password below>
--
-- Choose a unique, strong password before running. Do not commit it, put it
-- in this SQL file, or use the postgres administrator password. The app checks
-- at startup and refuses a superuser / BYPASSRLS connection because either one
-- defeats the database's per-yard RLS policies.
-- ============================================================================

-- Replace ONLY this value before executing in pgAdmin.
create role yard_app login
  password 'postgres'
  nosuperuser nocreatedb nocreaterole inherit nobypassrls;

grant authenticated to yard_app;
grant connect on database "Customs_SR_DB" to yard_app;
grant usage on schema public, auth to yard_app;

grant select, insert, update, delete on all tables in schema public to yard_app;
grant usage, select on all sequences in schema public to yard_app;
grant execute on all functions in schema public to yard_app;
grant execute on all functions in schema auth to yard_app;
grant select on auth.users to yard_app;

-- Keep future schema changes usable without granting server administration.
alter default privileges in schema public
  grant select, insert, update, delete on tables to yard_app;
alter default privileges in schema public
  grant usage, select on sequences to yard_app;
alter default privileges in schema public
  grant execute on functions to yard_app;

-- Verification: both values MUST be false.
select rolname, rolsuper, rolbypassrls, rolcanlogin, rolinherit
from pg_roles
where rolname = 'yard_app';
