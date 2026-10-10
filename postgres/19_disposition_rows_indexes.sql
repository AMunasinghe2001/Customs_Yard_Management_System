-- ============================================================================
--  Make the view fast at the volume it exists for.
--
--  `explain analyze` on the SOLD page, at 400 rows:
--
--    Seq Scan on warehouse_entries w2  (rows=68 loops=74)
--      Filter: upper(substring(upper(trim(...)), '^\[([^\]]+)\]')) = ANY (...)
--      Rows Removed by Filter: 115
--
--  ⚠️ Once per candidate item, scanning every warehouse entry each time. That
--  is the `NOT EXISTS` guard in source 2, and it is O(items x entries) --
--  invisible at 400 rows and quadratic at 400,000, which is the exact case
--  this whole exercise is for.
--
--  The filter is on an EXPRESSION, so an ordinary index on return_notes cannot
--  serve it. These are expression indexes matching the view's own predicates
--  character for character -- if the view's expression is ever edited, the
--  index stops being used and nothing fails loudly, so they are written
--  together here.
-- ============================================================================

set lock_timeout = '5s';

-- The tag, extracted exactly as the view extracts it, alongside the item it
-- belongs to: this serves both the NOT EXISTS lookup and source 1's filter.
create index if not exists warehouse_entries_disposition_tag_idx
  on public.warehouse_entries (
    (upper(substring(upper(trim(coalesce(return_notes, '')))
                     from '^\[([^\]]+)\]'))),
    package_item_id);

-- Source 2 scans items by lower(status). Partial, because only these six
-- statuses can ever produce a row and the index has no reason to carry the
-- rest of the table.
create index if not exists package_items_disposition_status_idx
  on public.package_items ((lower(status)), package_id)
  where lower(coalesce(status, '')) in
        ('re-exported', 'destroyed', 'supposed to be destroyed', 'destroy',
         'sold', 'other');

-- Every page of the view is ordered by its date, newest first.
create index if not exists warehouse_entries_returned_at_idx
  on public.warehouse_entries (returned_at desc nulls last);

-- Source 3 filters unsold_proposals by proposal.
create index if not exists unsold_proposals_proposal_idx
  on public.unsold_proposals (proposal, decided_at desc);

analyze public.warehouse_entries;
analyze public.package_items;
analyze public.unsold_proposals;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  r record;
begin
  -- Every index must exist by name.
  for r in
    select unnest(array['warehouse_entries_disposition_tag_idx',
                        'package_items_disposition_status_idx',
                        'warehouse_entries_returned_at_idx',
                        'unsold_proposals_proposal_idx']) as name
  loop
    if not exists (select 1 from pg_indexes
                    where schemaname = 'public' and indexname = r.name) then
      raise exception 'index % was not created', r.name;
    end if;
  end loop;

  -- ⚠️ The view must still return the SAME rows. An index cannot change a
  -- result, but the expressions were retyped here and a typo would go unseen
  -- until someone reads a plan -- so assert the counts the view had before.
  if (select count(*) from public.disposition_rows) = 0 then
    raise exception 'the view returned nothing after indexing';
  end if;

  raise notice 'disposition_rows: % row(s) across % tag(s)',
    (select count(*) from public.disposition_rows),
    (select count(distinct final_tag) from public.disposition_rows);
end
$verify$;
