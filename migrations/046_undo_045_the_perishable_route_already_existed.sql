-- ============================================================================
--  046 · Undo 045 — the perishable route into the outcome pages already
--        existed, and adding a second one listed every ruled perishable twice
--
--  ⚠️ MY MISTAKE, caught by the officer with a screenshot: Converted Goods
--  showed "Liquid Milk Cartons" twice, and marking one row Delivered marked
--  both — because they were two rows for ONE proposal.
--
--  Migration 045 added a perishable branch to `exhausted_unsold`, on the
--  finding that a perishable cannot satisfy that view's `tender_count > 3`.
--  That finding was correct. The conclusion was not: the yard's Final
--  Outcome pages do not read `exhausted_unsold` at all.
--
--      getExhaustedUnsoldPaged(..., includeAllRoutes: true)
--        -> reads `unsold_all_routes`
--        -> which is  exhausted_unsold  UNION ALL  unsold_perishables
--
--  `unsold_perishables` is the perishable route, and it has carried both
--  ruled perishables all along (migration 017 added it for exactly this
--  reason -- "splitting them there only hid the perishables entirely").
--
--  So 045 did not open a closed door; it added a second door beside an open
--  one:
--
--      exhausted_unsold    convert -> 2   (1 normal + 1 perishable, from 045)
--      unsold_perishables  convert -> 1   (the same perishable)
--      unsold_all_routes   convert -> 3   <- what the officer saw
--
--  ⚠️ Delivery is recorded against the PROPOSAL, not against the row, which
--  is why marking one delivered marked both. That is correct behaviour for
--  one ruling; the fault was showing one ruling as two rows.
--
--  This file removes the 045 branch. Migration 044 stays as it is: a ruled
--  perishable still leaves Perishable Goods, and it still reaches its
--  outcome page -- by the route that was always there.
--
--  ⚠️ RUN THE SOURCE FILES, do not unwrap the stored definition. My first
--  attempt at this file recovered the pre-045 body with a regex over
--  pg_get_viewdef. 045 wrapped the original as `select * from (<original>)
--  base`, but its own union branch ALSO ended in `) b2`, so a greedy match
--  for `from \((.*)\) base` ran past the real closing paren and produced a
--  body that still parsed, still had 18 columns, passed both verifications
--  -- and returned zero rows. The two source files below are the definition;
--  anything reconstructed from the database is a guess.
--
--  So this migration is a marker and a guard only. Apply it as:
--
--      psql -f postgres/23_exhausted_unsold_view.sql
--      psql -f migrations/016_perishable_flag_on_outcome_views.sql
--      psql -f migrations/046_undo_045_the_perishable_route_already_existed.sql
--
--  ⚠️ In that order. postgres/23 does `drop view; create view`, which
--  discards 016's is_perishable wrap, so 016 must follow it -- the same
--  ordering trap that lost is_perishable once already.
-- ============================================================================

set lock_timeout = '5s';

-- ── The two source files above must already have run ──────────────────────
do $$
declare
  body text;
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'exhausted_unsold') then
    raise exception 'exhausted_unsold does not exist -- run '
      'postgres/23_exhausted_unsold_view.sql first';
  end if;

  select pg_get_viewdef('public.exhausted_unsold'::regclass, true) into body;

  if body like '%045_perishable%' then
    raise exception '045''s branch is still in exhausted_unsold -- rerun '
      'postgres/23_exhausted_unsold_view.sql then '
      'migrations/016_perishable_flag_on_outcome_views.sql, then this file';
  end if;

  -- 016 must have been re-applied after 23 dropped the view.
  if body not like '%is_perishable%' then
    raise exception 'exhausted_unsold lost its is_perishable column -- rerun '
      'migrations/016_perishable_flag_on_outcome_views.sql';
  end if;
end $$;

insert into public.schema_migrations (version, name)
values (46, '046_undo_045_the_perishable_route_already_existed')
on conflict (version) do nothing;

-- ── Verification ───────────────────────────────────────────────────────────
do $verify$
declare
  n_cols int;
  n_dup  int;
  n_eu   int;
begin
  select count(*) into n_cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'exhausted_unsold';
  if n_cols <> 18 then
    raise exception 'exhausted_unsold has % columns, expected 18', n_cols;
  end if;

  -- ⚠️ A column count is not enough -- the broken rebuild had 18 columns and
  -- no rows. The normal-goods route must still return the packages it did
  -- before 045, so assert the view is not empty.
  select count(*) into n_eu from public.exhausted_unsold;
  if n_eu = 0 then
    raise exception 'exhausted_unsold returns no rows at all -- the normal '
      'goods route is broken, not just 045''s branch';
  end if;

  -- ⚠️ THE POINT: one ruling, one row, on the view the pages actually read.
  select count(*) into n_dup from (
    select proposal_id from public.unsold_all_routes
     where proposal_id is not null
     group by proposal_id having count(*) > 1) x;
  if n_dup > 0 then
    raise exception '% ruling(s) still listed twice on the outcome pages',
      n_dup;
  end if;

  raise notice 'PASS: exhausted_unsold returns % row(s) and every ruling '
               'appears exactly once on the pages the yard reads', n_eu;
end $verify$;

-- And 044's promise must still hold: no ruled perishable is stranded.
do $verify2$
declare
  n_orphan int;
begin
  select count(*) into n_orphan
    from public.unsold_proposals up
    join public.forfeited_packages fp on fp.id = up.forfeited_package_id
    join public.package_items pi on pi.id = fp.item_id
   where public.item_is_perishable(pi.id)
     and coalesce(trim(up.proposal), '') <> ''
     and not exists (select 1 from public.unsold_all_routes u
                      where u.proposal_id = up.id)
     and not exists (select 1 from public.disposition_rows d
                      where d.proposal_id = up.id);
  if n_orphan > 0 then
    raise exception '% ruled perishable(s) reach no page', n_orphan;
  end if;
  raise notice 'PASS: every ruled perishable still reaches a page';
end $verify2$;
