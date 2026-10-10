-- ============================================================================
--  044 · A perishable ruled DESTROY sat on two pages, or on neither
--
--  ⚠️ THE RULE, given directly: "a perishable leaves the Perishable Goods
--  table the MOMENT the destroy decision arrives. It then sits on Destroyed
--  Goods as awaiting, until it is actually destroyed — and only then does
--  that table say Destroyed."
--
--  What happened instead, for CED/GL1/SR/22/2025 (Live Ornamental Fish):
--
--    * Top Management ruled `destroy` on 2025-09-23. The ruling is recorded
--      in `unsold_proposals`; it does NOT touch `package_items.status`,
--      which stays 'Perishable' until somebody records a Final Disposition.
--    * `perishable_rows` filters on that status alone (migrations 039/040),
--      so the item stayed on Perishable Goods.
--    * `disposition_rows` only turned a PROPOSAL into a row for
--      `re_export`, so the item reached Destroyed Goods never.
--
--  The goods were therefore on one page that should have let them go and
--  absent from the one that should have been waiting for them.
--
--  Two halves, and this file is the read side:
--
--    * postgres/70 now emits a DESTROYED row for a `destroy` ruling, the
--      same way it always did for `re_export`. Its `is_destroyed` reads
--      `destruction_items` — the record of the ACT — so the row arrives as
--      "Mark Destroyed" and only says Destroyed once it has been.
--    * This migration drops a ruled item from `perishable_rows`.
--
--  ⚠️ A DECISION, not an outcome. The item is still physically in the yard
--  and still perishing; what changed is that its fate is settled and the
--  Perishable page's job -- "these need a decision" -- is done for it. That
--  is the same reasoning migration 039 used for a Final Disposition.
-- ============================================================================

set lock_timeout = '5s';

do $$
declare
  body text;
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'perishable_rows') then
    raise exception 'perishable_rows does not exist';
  end if;

  select pg_get_viewdef('public.perishable_rows'::regclass, true) into body;
  if body like '%044_ruled%' then
    return; -- already carries the rule
  end if;

  -- ⚠️ Wrapped, not retyped. perishable_rows is built by postgres/36 and
  -- narrowed by migrations 039/040; restating it here would be a second
  -- copy to keep in step, and the two would drift the first time either
  -- side changed.
  --
  -- ⚠️ EVERY ruling, not just two.
  --
  -- This file first dropped only `destroy` and `re_export`, on my reading
  -- that the other four had nowhere to go. That was wrong, and the officer
  -- caught it with a screenshot: Government Use, Auction, Converted and
  -- Removed from the Premises all exist as pages. I had looked only in
  -- `disposition_rows`; those four read `exhausted_unsold` instead.
  --
  -- ⚠️ A ruled perishable does reach those four pages, and always did --
  -- just not by the view I first checked. They read `unsold_all_routes`,
  -- which is `exhausted_unsold UNION ALL unsold_perishables`, and the
  -- perishable arm has carried them since migration 017. Migration 045
  -- added a second, redundant arm and listed every ruled perishable twice;
  -- migration 046 removed it. Every ruling has a destination, so every
  -- ruling ends this page's interest.
  execute format(
    'create or replace view public.perishable_rows '
    'with (security_invoker = true) as '
    -- ⚠️ A BLOCK comment, not `--`. The whole statement is built as ONE
    -- line, so a line comment swallows everything after it -- the select,
    -- the wrap and the closing paren -- and Postgres reports only
    -- "syntax error at or near )".
    --
    -- The marker itself is what the guard above greps for, so it has to
    -- survive into the stored definition.
    -- ⚠️ A CTE, not `from (...) v`. The wrapped definition now BEGINS with
    -- its own `WITH agg AS (...)`, and `select ... from (WITH ...) v` is not
    -- valid SQL -- Postgres reports only "syntax error at or near )" at the
    -- very end, which points nowhere near the cause. Naming the base as a
    -- CTE of our own lets its leading WITH sit where a WITH is allowed.
    'with base as (%s) '
    '/* 044_ruled: a ruling with a destination ends this page''s interest */ '
    'select v.* from base v '
    'where not exists ('
    '  select 1 from public.unsold_proposals up '
    '    join public.forfeited_packages fp on fp.id = up.forfeited_package_id '
    '   where fp.item_id = v.item_id '
    '     and coalesce(trim(up.proposal), '''') <> '''')',
    rtrim(body, ';' || chr(10) || chr(13) || ' '));
end $$;

grant select on public.perishable_rows to authenticated, anon;

insert into public.schema_migrations (version, name)
values (44, '044_a_ruled_perishable_leaves_the_page')
on conflict (version) do nothing;

-- ── Verification ───────────────────────────────────────────────────────────
do $verify$
declare
  n_ruled_on_page int;
  n_destroy_rows  int;
begin
  -- No RULED item may still be offered for a decision here.
  select count(*) into n_ruled_on_page
    from public.perishable_rows pr
   where exists (
     select 1 from public.unsold_proposals up
       join public.forfeited_packages fp on fp.id = up.forfeited_package_id
      where fp.item_id = pr.item_id
        and coalesce(trim(up.proposal), '') <> '');
  if n_ruled_on_page > 0 then
    raise exception '% ruled item(s) still on Perishable Goods',
      n_ruled_on_page;
  end if;

  -- ⚠️ And nothing may fall between the two pages. Every item this view
  -- drops for a ruling must be findable on a disposition page.
  -- ⚠️ Either route counts: Destroyed / Re-exported (disposition_rows) or
  -- one of the four Final Outcome pages.
  --
  -- ⚠️ `unsold_all_routes`, NOT `exhausted_unsold`. That is the view the
  -- four pages actually read, and a perishable reaches them through its
  -- other arm, `unsold_perishables`. Checking `exhausted_unsold` alone is
  -- what made migration 045 look necessary.
  if exists (
    select 1
      from public.unsold_proposals up
      join public.forfeited_packages fp on fp.id = up.forfeited_package_id
      join public.package_items pi on pi.id = fp.item_id
     where coalesce(trim(up.proposal), '') <> ''
       and public.item_is_perishable(pi.id)
       and not exists (select 1 from public.disposition_rows d
                        where d.proposal_id = up.id)
       and not exists (select 1 from public.unsold_all_routes u
                        where u.proposal_id = up.id)) then
    raise exception 'a ruled perishable reaches no page at all';
  end if;

  -- And a destroy ruling must now reach Destroyed Goods.
  select count(*) into n_destroy_rows
    from public.disposition_rows
   where final_tag = 'DESTROYED' and source = 'proposal';
  raise notice 'PASS: no ruled perishable is awaiting a decision; % destroy '
               'ruling(s) now appear on Destroyed Goods', n_destroy_rows;
end $verify$;

-- A ruled item must appear on exactly ONE disposition page, not two.
do $verify2$
declare
  n_dup int;
begin
  select count(*) into n_dup from (
    select item_id from public.disposition_rows
     where item_id is not null
     group by item_id, final_tag
    having count(*) > 1) x;
  if n_dup > 0 then
    raise exception '% item(s) listed twice under one outcome', n_dup;
  end if;
  raise notice 'PASS: no item is listed twice under one outcome';
end $verify2$;
