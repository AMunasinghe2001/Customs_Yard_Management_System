-- ============================================================================
--  64 · Realtime, scoped to a yard — stopping the notification storm
--
--  03_realtime.sql announces "table X changed" to every listener. With one or
--  two clients that is exactly right. With 100 it is the app's worst scaling
--  problem, and it is worth being precise about why:
--
--    * one officer records one delivery in yard CED
--    * the AFTER STATEMENT trigger fires ONE pg_notify
--    * all 100 connected PCs receive it
--    * all 100 immediately re-run their dashboard queries
--
--  So a single click costs the server ~100 queries, arriving in the same
--  millisecond, each holding a pooled connection while it runs. The other 99
--  users see their screen stall — not because their own work was slow, but
--  because someone else saved a form. And most of that work is WASTED: a PC
--  showing yard GL1 has nothing to redraw when CED changes.
--
--  ── The fix, in two halves ─────────────────────────────────────────────────
--  This file is the server half: the notification now carries WHICH YARD the
--  change belongs to. The client half is in lib/core/db/pg_realtime.dart,
--  which drops a notification for a yard it is not showing, and debounces the
--  rest so a burst of ten becomes one refetch.
--
--  Together those turn ~100 queries per click into a handful.
--
--  ── Why the yard is read per-statement, not per-row ────────────────────────
--  These are FOR EACH STATEMENT triggers (03_realtime.sql explains why: a
--  500-row insert should wake listeners once, not 500 times). A statement-level
--  trigger has no NEW/OLD row, so the yard cannot simply be read off one.
--
--  Postgres 10+ gives statement triggers TRANSITION TABLES instead — the full
--  set of affected rows, queryable as a relation. The function collects the
--  DISTINCT yards actually touched, so a statement spanning two yards notifies
--  both, correctly.
--
--  A table WITHOUT a yard column notifies with yard = null, which every client
--  treats as "concerns everyone" and always acts on. That keeps shared tables
--  (profiles, package_categories, storage_rates) behaving exactly as before —
--  correctness first, and the filtering is a pure optimisation on top.
--
--  Run AFTER 03_realtime.sql. Idempotent — safe to re-run.
-- ============================================================================

set client_min_messages = warning;

-- ── The yard-aware trigger function ─────────────────────────────────────────
--  One function serves every table. It cannot name a column that may not
--  exist, so the yard is pulled out of the transition table dynamically:
--  to_jsonb(row) -> 'yard' is null on a table without the column, which is
--  exactly the "concerns everyone" case.
create or replace function public.notify_db_change_scoped()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  yards text[] := '{}';
  y     text;
begin
  -- Which transition table exists depends on the operation. DELETE has only
  -- the old rows, INSERT only the new; UPDATE has both and the new values are
  -- the ones a client should react to.
  if (tg_op = 'DELETE') then
    select array_agg(distinct v) into yards
    from (select to_jsonb(o) ->> 'yard' as v from old_rows o) s
    where v is not null;
  else
    select array_agg(distinct v) into yards
    from (select to_jsonb(n) ->> 'yard' as v from new_rows n) s
    where v is not null;
  end if;

  -- No yard column, or every affected row had a null yard: announce once with
  -- no yard, meaning "every client should refresh".
  if yards is null or array_length(yards, 1) is null then
    perform pg_notify('db_changes', json_build_object(
      'table', tg_table_name,
      'op',    tg_op,
      'yard',  null
    )::text);
    return null;
  end if;

  -- One notification per distinct yard touched. A statement almost always
  -- touches exactly one, so this is a single NOTIFY in practice.
  foreach y in array yards loop
    perform pg_notify('db_changes', json_build_object(
      'table', tg_table_name,
      'op',    tg_op,
      'yard',  y
    )::text);
  end loop;

  return null;
end;
$$;

comment on function public.notify_db_change_scoped() is
  'Announces that a table changed and in which yard, so a client showing '
  'another yard can ignore it. Still carries no row data: listeners re-query '
  'through their own RLS policies. Supersedes notify_db_change().';

-- ── Re-attach every watched table with transition tables ────────────────────
--  A trigger cannot gain REFERENCING clauses by replacing its function, so
--  each one is dropped and recreated.
--
--  ⚠️ The REFERENCING clause is per-operation: INSERT has no OLD, DELETE has
--  no NEW. One combined trigger cannot declare both for all three operations,
--  so each table gets three narrow triggers rather than one wide one. They
--  still fire once per statement, so the notification count is unchanged.
do $$
declare
  t text;
  watched text[] := array[
    'packages', 'package_items', 'warehouse_entries',
    'profiles', 'package_categories', 'storage_rates', 'audit_logs',
    'forfeited_packages', 'disposal_requests', 'disposal_request_items',
    'tender_bids', 'tender_revaluations', 'tender_committees',
    'unsold_proposals', 'tender_sale_items', 'tender_sales',
    'destructions', 'destruction_items'
  ];
begin
  foreach t in array watched loop
    if to_regclass('public.' || quote_ident(t)) is null then
      raise notice 'realtime: skipping %, table not found', t;
      continue;
    end if;

    -- Retire the unscoped trigger from 03_realtime.sql, and any earlier run
    -- of this file, so a table is never notified twice for one statement.
    execute format('drop trigger if exists %I on public.%I', 'notify_' || t, t);
    execute format('drop trigger if exists %I on public.%I', 'notify_ins_' || t, t);
    execute format('drop trigger if exists %I on public.%I', 'notify_upd_' || t, t);
    execute format('drop trigger if exists %I on public.%I', 'notify_del_' || t, t);

    execute format(
      'create trigger %I after insert on public.%I '
      'referencing new table as new_rows '
      'for each statement execute function public.notify_db_change_scoped()',
      'notify_ins_' || t, t);

    execute format(
      'create trigger %I after update on public.%I '
      'referencing new table as new_rows '
      'for each statement execute function public.notify_db_change_scoped()',
      'notify_upd_' || t, t);

    execute format(
      'create trigger %I after delete on public.%I '
      'referencing old table as old_rows '
      'for each statement execute function public.notify_db_change_scoped()',
      'notify_del_' || t, t);
  end loop;
end $$;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  Expect 54 rows (18 tables x 3 operations) and NO remaining 'notify_<table>'
--  triggers from 03_realtime.sql.
select count(*) filter (where tgname like 'notify\_ins\_%'
                           or tgname like 'notify\_upd\_%'
                           or tgname like 'notify\_del\_%') as scoped_triggers,
       count(*) filter (where tgname ~ '^notify_[^iud]')    as old_unscoped_left
from   pg_trigger
where  not tgisinternal and tgname like 'notify\_%';
