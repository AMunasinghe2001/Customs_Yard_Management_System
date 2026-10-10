-- ============================================================================
-- Unsold perishables never reached the yard's Unsold Goods page, nor any of
-- the four Final Outcome pages.
--
-- The two routes are deliberately different (postgres/23 and /32):
--
--   normal goods  → 4+ failed tenders → committee re-valuation → proposal
--   perishable    → ONE failed Special Tender Sale → proposal
--
-- `exhausted_unsold` encodes the FIRST route, and its two gate conditions --
-- `tender_count > 3` and a `tender_committees` row -- are conditions a
-- perishable can never satisfy, by design: goods that spoil cannot wait for
-- the long route. So every unsold perishable was filtered out of the page
-- that is supposed to list unsold goods.
--
-- In this database that hid 9 packages, two of which the Top Management
-- Directorate had ALREADY ruled on ('destroy' and 'convert'). The rulings
-- were recorded; the yard had no page that could show them.
--
-- ⚠️ Fixed with a UNION view rather than by loosening `exhausted_unsold`.
-- Relaxing its gates would let a normal package through before its committee
-- has valued it, which is the very thing those gates exist to prevent. The
-- two routes stay separately defined and are joined only for DISPLAY.
--
-- ⚠️ The Top Management dashboard keeps reading the two views SEPARATELY
-- (its Unsold tab and its Perishables tab), because there the distinction is
-- the whole point -- one tab is deciding after a committee valuation, the
-- other after a single spoiled sale. This view is for the pages that ask
-- "what is unsold in this yard", where the answer is both.
--
-- Safe to re-run.
-- ============================================================================

-- ── The union both routes present to the yard's pages ─────────────────────
--
-- Column shape is `exhausted_unsold`'s, because that is what the pages,
-- filters and pager already read. Perishables have no committee, so the two
-- committee columns are NULL for them -- which is accurate, not missing
-- data: there was no committee to value them.
--
-- ⚠️ Guarded on BOTH sources existing. `exhausted_unsold` comes from
-- postgres/23 and `unsold_perishables` from postgres/32; both are applied by
-- hand and neither is folded into 02_schema.sql, so on the fresh database
-- that file stands a new server up they are absent. Creating a view over a
-- missing table would fail there and break the one file that has to work.
do $outer$
begin
if to_regclass('public.exhausted_unsold') is null
   or to_regclass('public.unsold_perishables') is null then
  return;
end if;

execute $ddl$
create or replace view public.unsold_all_routes
with (security_invoker = true) as
  select
    forfeited_package_id,
    package_id,
    item_id,
    sr_number,
    consignee_name,
    yard,
    entry_qty,
    forfeited_at,
    item_name,
    case_number,
    tender_count,
    submitted_value,
    submitted_at,
    proposal_id,
    proposal,
    decided_at,
    delivered,
    is_perishable
  from public.exhausted_unsold

  union all

  select
    forfeited_package_id,
    package_id,
    item_id,
    sr_number,
    consignee_name,
    yard,
    entry_qty,
    forfeited_at,
    item_name,
    case_number,
    tender_count,
    -- No committee on this route. NULL says so; 0 would read as "valued at
    -- nothing", which is a different and wrong statement.
    null::numeric  as submitted_value,
    null::timestamptz as submitted_at,
    proposal_id,
    proposal,
    decided_at,
    delivered,
    true as is_perishable
  from public.unsold_perishables
$ddl$;

execute $c$comment on view public.unsold_all_routes is
  'Every unsold package in a yard, by either route: the committee route '
  '(exhausted_unsold) and the single-special-sale perishable route '
  '(unsold_perishables). is_perishable says which. Display only -- the two '
  'source views stay separate for the Top Management decision tabs.'$c$;

execute 'grant select on public.unsold_all_routes to authenticated';
end
$outer$;

-- ── Verification ──────────────────────────────────────────────────────────
do $$
declare
  n_union int;
  n_parts int;
  n_peri  int;
begin
  -- Nothing to verify where the sources -- and so the view -- do not exist.
  if to_regclass('public.unsold_all_routes') is null then
    return;
  end if;

  -- The view must run as the caller, or every per-yard policy beneath it is
  -- bypassed and one yard reads another's unsold goods.
  if not exists (select 1 from pg_class c
                   join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'unsold_all_routes'
                    and 'security_invoker=true' = any (c.reloptions)) then
    raise exception 'unsold_all_routes must run as the caller';
  end if;

  select count(*) into n_union from public.unsold_all_routes;
  select (select count(*) from public.exhausted_unsold)
       + (select count(*) from public.unsold_perishables) into n_parts;
  if n_union <> n_parts then
    raise exception 'unsold_all_routes has % rows, its two sources have %',
      n_union, n_parts;
  end if;

  -- A package must not arrive by both routes: exhausted_unsold requires a
  -- committee, unsold_perishables requires source='perishable' and no
  -- committee is ever created for one. If that ever overlaps, a package
  -- would be listed twice and counted twice by the pager.
  if exists (select forfeited_package_id
               from public.unsold_all_routes
              group by forfeited_package_id having count(*) > 1) then
    raise exception 'a package reached unsold_all_routes by both routes';
  end if;

  -- Every perishable-route row must be flagged, or the page's filter and
  -- its row tint would disagree with the route the row actually took.
  select count(*) into n_peri from public.unsold_all_routes where is_perishable;
  if n_peri < (select count(*) from public.unsold_perishables) then
    raise exception 'perishable rows lost their flag in the union';
  end if;
end $$;
