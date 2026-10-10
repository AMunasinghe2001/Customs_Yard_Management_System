-- ============================================================================
--  03 · Realtime — LISTEN/NOTIFY in place of Supabase channels
--
--  Supabase streamed row changes over a websocket. Postgres has the same idea
--  built in: NOTIFY sends a message on a named channel, and any connection
--  that has issued LISTEN receives it.
--
--  What the app actually needs is smaller than what Supabase delivered. Every
--  one of the 19 onPostgresChanges callbacks ignores its payload and just
--  fires a refresh trigger:
--
--      callback: (_) => ref.read(...notifier).trigger(),
--
--  So the notification only has to say WHICH TABLE changed. It deliberately
--  carries no row data — that also keeps it under the 8000-byte NOTIFY limit,
--  which a wide row with a long description could otherwise exceed, and avoids
--  leaking rows to a listener whose RLS policies would have hidden them.
--
--  The app LISTENs on one channel, 'db_changes', and re-reads through the
--  normal RLS-checked queries. See PgRealtime in lib/core/db/pg_realtime.dart.
--
--  Run AFTER 02_schema.sql — the tables must exist.
--  Idempotent — safe to re-run.
-- ============================================================================

set client_min_messages = warning;

-- ── The trigger function ────────────────────────────────────────────────────
--  pg_notify() rather than the NOTIFY statement, because the payload is built
--  at run time. TG_TABLE_NAME and TG_OP come from the trigger context.
--
--  Returns NULL: this is an AFTER trigger, so the return value is discarded,
--  and returning NULL makes that explicit.
create or replace function public.notify_db_change()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform pg_notify(
    'db_changes',
    json_build_object(
      'table', TG_TABLE_NAME,
      'op',    TG_OP
    )::text
  );
  return null;
end;
$$;

comment on function public.notify_db_change() is
  'Announces that a table changed, without the row. Listeners re-query through '
  'their own RLS policies rather than trusting a pushed payload.';

-- ── Attach it to the 18 tables the app watches ──────────────────────────────
--  FOR EACH STATEMENT, not FOR EACH ROW: a 500-row insert should wake the
--  listeners once, not 500 times. The app reloads the whole list either way,
--  so per-row notifications would be 499 wasted round trips.
--
--  The table list mirrors the 11 channels in lib/core/providers.dart. A table
--  that does not exist is skipped with a notice rather than failing the run,
--  so this file survives a schema that is a migration or two behind.
do $$
declare
  t text;
  watched text[] := array[
    -- packages-realtime
    'packages', 'package_items', 'warehouse_entries',
    -- profiles / categories / storage rates / audit
    'profiles', 'package_categories', 'storage_rates', 'audit_logs',
    -- disposal
    'forfeited_packages', 'disposal_requests', 'disposal_request_items',
    -- tenders
    'tender_bids', 'tender_revaluations', 'tender_committees',
    'unsold_proposals', 'tender_sale_items', 'tender_sales',
    -- destruction
    'destructions', 'destruction_items'
  ];
begin
  foreach t in array watched loop
    if to_regclass('public.' || quote_ident(t)) is null then
      raise notice 'realtime: skipping %, table not found', t;
      continue;
    end if;

    execute format('drop trigger if exists %I on public.%I',
                   'notify_' || t, t);
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each statement execute function public.notify_db_change()',
      'notify_' || t, t);
  end loop;
end $$;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  Expect 18 rows. Anything missing is a table the schema has not created yet.
select count(*) as notify_triggers_installed
from   pg_trigger
where  not tgisinternal
and    tgname like 'notify\_%';
