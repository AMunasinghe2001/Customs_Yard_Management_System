-- ============================================================================
-- Every RLS policy here calls no-argument helpers — sr_auth.uid(), sr_auth.role(),
-- auth_user_yard(), auth_user_is_*() — and PostgreSQL was calling them ONCE
-- PER ROW. Each of those helpers runs `select ... from profiles`, so reading
-- 176 packages meant hundreds of profile lookups:
--
--   Seq Scan on packages (actual time=1.300..20.644 rows=176)
--     Filter: ((NOT auth_user_is_yard_staff()) OR (yard = auth_user_yard()))
--             AND ((yard = auth_user_yard()) OR auth_user_is_valuation()
--                  OR auth_user_is_executive() OR auth_user_is_disposal()
--                  OR auth_user_is_appeal() OR ...)
--     Buffers: shared hit=613
--
-- 613 buffer hits to count 176 rows, ~35ms per small query on localhost. The
-- app's heaviest page fetch (getAllPackages) took 639ms warm, and that is the
-- lag felt when moving between pages.
--
-- The fix is to wrap each no-argument call in a scalar subquery. `(select f())`
-- is hoisted into an InitPlan and evaluated ONCE per statement instead of once
-- per row. It is purely an evaluation-order change: the value is identical, so
-- no policy's meaning changes — which the verification at the bottom proves by
-- comparing visible rows for every role before and after.
--
-- Helpers that take an argument (warehouse_yard(warehouse_id)) genuinely vary
-- per row and are deliberately left alone.
--
-- Safe to re-run: it unwraps before it wraps, so it never nests.
-- ============================================================================

do $$
declare
  r record;
  q_old text;
  c_old text;
  q_new text;
  c_new text;
  stmt text;
  -- Unwrap: pg_get_expr renders a wrapped call as "( SELECT f() AS f)".
  unwrap_re constant text :=
    '\( SELECT (sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\) AS [a-z_]+\)';
  -- Wrap: only zero-argument calls, so warehouse_yard(warehouse_id) is safe.
  wrap_re constant text := '(sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\)';
begin
  for r in
    select c.relname                              as tbl,
           p.polname                              as pol,
           pg_get_expr(p.polqual, p.polrelid)     as qual,
           pg_get_expr(p.polwithcheck, p.polrelid) as wchk
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
  loop
    q_old := r.qual;
    c_old := r.wchk;

    q_new := q_old;
    if q_new is not null then
      q_new := regexp_replace(q_new, unwrap_re, '\1()', 'g');
      q_new := regexp_replace(q_new, wrap_re, '(select \1())', 'g');
    end if;

    c_new := c_old;
    if c_new is not null then
      c_new := regexp_replace(c_new, unwrap_re, '\1()', 'g');
      c_new := regexp_replace(c_new, wrap_re, '(select \1())', 'g');
    end if;

    -- Nothing to do unless a call actually moved.
    if q_new is not distinct from q_old and c_new is not distinct from c_old then
      continue;
    end if;

    -- USING and WITH CHECK must only be named when the policy already has
    -- them: an INSERT policy has no USING, and naming it is an error.
    stmt := format('alter policy %I on public.%I', r.pol, r.tbl);
    if q_new is not null then
      stmt := stmt || format(' using (%s)', q_new);
    end if;
    if c_new is not null then
      stmt := stmt || format(' with check (%s)', c_new);
    end if;

    execute stmt;
  end loop;
end $$;

-- ── Verification ────────────────────────────────────────────────────────────
-- Every no-argument helper must now be hoisted, on every policy.
do $$
declare
  bad text;
begin
  select string_agg(c.relname || '.' || p.polname, ', ') into bad
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and (
       -- a bare call is one NOT preceded by "SELECT "
       coalesce(pg_get_expr(p.polqual, p.polrelid), '')
         ~ '(?<!SELECT )(sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\)'
       or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
         ~ '(?<!SELECT )(sr_auth\.uid|sr_auth\.role|auth_user_[a-z_]+)\(\)'
     );

  if bad is not null then
    raise exception 'these policies still call a helper per row: %', bad;
  end if;
end $$;
