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

alter view public.daily_stats set (security_invoker = true);
alter view public.password_rotation_status set (security_invoker = true);

-- Verification: NO view in public may bypass the caller's policies.
do $$
declare
  bad text;
begin
  select string_agg(c.relname, ', ') into bad
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'v'
     and not coalesce('security_invoker=true' = any (c.reloptions), false);

  if bad is not null then
    raise exception 'these views still run as their owner: %', bad;
  end if;
end $$;
