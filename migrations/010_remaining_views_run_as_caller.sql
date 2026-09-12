-- ============================================================================
-- The last two views that ignored RLS.
--
-- A view without `security_invoker` runs as its OWNER, so the policies that
-- scope a yard officer to their own yard never apply to it. `daily_stats`
-- aggregates `packages` across EVERY yard; `password_rotation_status` reports
-- on accounts. Neither is queried by the app today, which is why they went
-- unnoticed — but an unscoped view is a leak waiting for the first caller,
-- exactly like warehouse_contents was (migration 008).
--
-- Safe to re-run.
-- ============================================================================

-- ⚠️ Guarded. `password_rotation_status` is defined in postgres/52, which
-- is applied separately and is NOT folded into 02_schema.sql — so on a fresh
-- database this migration runs before the view exists. Failing there would
-- break the one file used to stand a new server up.
do $$
declare
  v text;
begin
  foreach v in array array['daily_stats', 'password_rotation_status'] loop
    if exists (select 1 from pg_class c
                 join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public' and c.relname = v
                  and c.relkind = 'v') then
      -- Same exclusion as the verification below: an extension's view is
      -- not ours to alter.
      if not exists (select 1 from pg_depend d
                       join pg_class c2 on c2.oid = d.objid
                       join pg_namespace n2 on n2.oid = c2.relnamespace
                      where n2.nspname = 'public' and c2.relname = v
                        and d.classid = 'pg_class'::regclass
                        and d.deptype = 'e') then
        execute format('alter view public.%I set (security_invoker = true)', v);
      end if;
    end if;
  end loop;
end $$;

-- Verification: NO view in public may bypass the caller's policies.
do $$
declare
  bad text;
begin
  -- ⚠️ EXTENSION-owned views are excluded, and must be.
  --
  -- A server with pg_stat_statements installed into `public` has two views
  -- there that belong to the extension, not to this project: they cannot be
  -- altered without owning the extension, and they carry no application data
  -- for a policy to protect. Without this the check failed on exactly such a
  -- server and took the whole schema build down with it — a deployment
  -- blocked by a rule about views the rule was never meant to cover.
  select string_agg(c.relname, ', ') into bad
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'v'
     and not exists (select 1 from pg_depend d
                      where d.objid = c.oid
                        and d.classid = 'pg_class'::regclass
                        and d.deptype = 'e')
     and not coalesce('security_invoker=true' = any (c.reloptions), false);

  if bad is not null then
    raise exception 'these views still run as their owner: %', bad;
  end if;
end $$;
