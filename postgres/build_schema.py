"""Concatenate the base schema + every migration into one runnable file.

The 76 migrations are already date-ordered and idempotent; running them in
sequence reproduces the live schema exactly. Consolidating them by hand would
mean re-deriving 88 ALTERs and inviting a transcription error, so this keeps
the migrations as the source of truth and just stitches them together.
"""
import io
import os
import re

import pathlib
ROOT = str(pathlib.Path(__file__).resolve().parent.parent)
MIG = os.path.join(ROOT, 'supabase', 'migrations')
OUT = os.path.join(ROOT, 'postgres', '02_schema.sql')

HEADER = """-- ============================================================================
--  02 · Schema — every table, function, policy and trigger
--
--  GENERATED. Do not edit by hand: it is the base schema followed by all
--  {n} migrations in date order, exactly as they were applied to Supabase.
--  Regenerate with scratchpad/build_schema.py after adding a migration.
--
--  Why stitched rather than consolidated: the migrations ARE the source of
--  truth, and they are idempotent and ordered. Hand-writing a single flat
--  schema would mean re-deriving 88 ALTERs, and one slip there is a column
--  silently missing in production.
--
--  Run AFTER 01_supabase_compat.sql — the migrations reference auth.uid(),
--  auth.users and the supabase_realtime publication, all of which that file
--  provides.
--
--  Safe to re-run: every statement is guarded (if not exists / or replace /
--  drop policy if exists).
-- ============================================================================

set client_min_messages = warning;

"""

# The base schema uses bare CREATE TABLE, which is not re-runnable. Guard it.
def make_rerunnable(sql: str) -> str:
    sql = re.sub(r'(?i)\bCREATE TABLE\s+(?!IF NOT EXISTS)',
                 'CREATE TABLE IF NOT EXISTS ', sql)
    sql = re.sub(r'(?i)\bCREATE INDEX\s+(?!IF NOT EXISTS)',
                 'CREATE INDEX IF NOT EXISTS ', sql)
    # ADD COLUMN is the other statement that is not re-runnable, and it bites
    # HARDER than the CREATEs: the base schema and the early migrations add
    # several of the same columns (warehouse_entries.package_item_id and .zone
    # are added in both), so the stitched file fails on a FIRST run, not just a
    # second one. Postgres accepts IF NOT EXISTS here, and it is a no-op when
    # the column is genuinely new.
    sql = re.sub(r'(?i)\bADD COLUMN\s+(?!IF NOT EXISTS)',
                 'ADD COLUMN IF NOT EXISTS ', sql)

    # CREATE TRIGGER has no IF NOT EXISTS in Postgres, so it needs an explicit
    # DROP in front — the base schema and the migrations define several of the
    # same triggers.
    sql = re.sub(
        r'(?i)\bCREATE TRIGGER\s+(\w+)([\s\S]*?\bON\s+([\w.]+))',
        lambda m: 'DROP TRIGGER IF EXISTS %s ON %s;\nCREATE TRIGGER %s%s'
                  % (m.group(1), m.group(3), m.group(1), m.group(2)),
        sql)
    # Seed rows would duplicate on a second run, so top-level INSERTs get an
    # ON CONFLICT DO NOTHING.
    #
    # ⚠️ Only OUTSIDE function bodies. An INSERT inside a `$$ ... $$` body is
    # program logic, not seed data: appending the clause there produced
    # `... ON CONFLICT DO NOTHING;\n end if;` — a syntax error — and would in
    # any case silently swallow writes the app depends on. Split the file on
    # dollar-quoted blocks and rewrite only the parts between them.
    def add_on_conflict(chunk: str) -> str:
        # Skip an INSERT that already states its own conflict behaviour.
        return re.sub(
            r'(?i)\bINSERT INTO\s+([\w."]+)((?:[^;\'"]|\'[^\']*\'|"[^"]*")*);',
            lambda m: m.group(0)
            if re.search(r'(?i)\bON\s+CONFLICT\b', m.group(2))
            else f'INSERT INTO {m.group(1)}{m.group(2)}\n  ON CONFLICT DO NOTHING;',
            chunk)

    # Walk the dollar-quoted blocks rather than re.split: split() also returns
    # every INNER capture group as its own piece, so the tag of `$fn$ ... $fn$`
    # came back as a bare "fn" that was then re-joined into the output,
    # producing `$fn$fn;` — a syntax error.
    out = []
    pos = 0
    for m in re.finditer(r'\$(\w*)\$[\s\S]*?\$\1\$', sql):
        out.append(add_on_conflict(sql[pos:m.start()]))
        out.append(m.group(0))  # function body: left exactly as written
        pos = m.end()
    out.append(add_on_conflict(sql[pos:]))
    sql = ''.join(out)

    # The base schema's 20 policies have no DROP before them, so a second run
    # would fail on "policy already exists". Emit the drop the migrations all
    # use, so the whole file stays re-runnable.
    def guard_policy(m):
        name, table = m.group(1), m.group(2)
        return ('DROP POLICY IF EXISTS %s ON %s;\n'
                'CREATE POLICY %s ON %s' % (name, table, name, table))

    def already_guarded(name, table, upto):
        needle = ('drop policy if exists %s on %s' % (name, table)).lower()
        return needle in upto.lower()

    out = []
    pos = 0
    for m in re.finditer(
            r'(?i)\bCREATE POLICY\s+("[^"]+"|\w+)\s+ON\s+([\w.]+)', sql):
        out.append(sql[pos:m.start()])
        name, table = m.group(1), m.group(2)
        if already_guarded(name, table, sql[max(0, m.start() - 400):m.start()]):
            out.append(m.group(0))
        else:
            out.append('DROP POLICY IF EXISTS %s ON %s;\n%s'
                       % (name, table, m.group(0)))
        pos = m.end()
    out.append(sql[pos:])
    sql = ''.join(out)
    return sql


parts = [None]  # placeholder for the header

base = os.path.join(ROOT, 'supabase', 'schema.sql')
if os.path.exists(base):
    body = io.open(base, encoding='utf-8').read()
    parts.append(
        '-- ' + '=' * 74 + '\n'
        '--  BASE SCHEMA (supabase/schema.sql)\n'
        '-- ' + '=' * 74 + '\n\n' + make_rerunnable(body) + '\n')

# Same-day migrations sort by FILENAME, which is not the order they were
# applied in. Alphabetically `20260611_taxes_and_delivery` comes before
# `20260611_tender_sale_items`, but the first ALTERs the table the second
# CREATEs — so a from-scratch build died on
# `relation "public.tender_sale_items" does not exist`.
#
# Rather than rename files (which would break anyone tracking what has already
# been applied), pin the few that must come earlier than their name implies.
# Anything not listed keeps its alphabetical position.
EARLY = {
    # creates tender_sale_items, which its same-day siblings then ALTER
    '20260611_tender_sale_items.sql': '20260611_a_tender_sale_items.sql',
    # adds destruction_items.package_item_id, which the same-day
    # `autofill_package_item` migration reads
    '20260625_destruction_per_di_item.sql':
        '20260625_a_destruction_per_di_item.sql',
}


def sort_key(name: str) -> str:
    return EARLY.get(name, name)


names = sorted((f for f in os.listdir(MIG) if f.endswith('.sql')), key=sort_key)

# The multi-yard migration lives OUTSIDE supabase/migrations (in migrations/)
# and the README says to run it afterwards. That order works on a database that
# already has data, but not on a fresh build: `20260620_seed_data.sql` inserts
# rows carrying a `yard` value, and the column does not exist until multi-yard
# has run. Fold it in ahead of the migrations that depend on it.
MULTI_YARD = os.path.join(ROOT, 'migrations', '001_multi_yard.sql')
YARD_ISOLATION = os.path.join(ROOT, 'migrations', '002_strict_yard_isolation.sql')
DATABASE_YARD_ISOLATION = os.path.join(
    ROOT, 'migrations', '003_database_yard_isolation.sql')
WAREHOUSE_QUERY_YARD_SCOPE = os.path.join(
    ROOT, 'migrations', '004_warehouse_query_yard_scope.sql')
DATABASE_WIDE_YARD_BOUNDARY = os.path.join(
    ROOT, 'migrations', '005_restrict_yard_staff_at_database.sql')
PROFILES_POLICY_RECURSION_FIX = os.path.join(
    ROOT, 'migrations', '006_profiles_policy_recursion_fix.sql')
DROP_ADMIN_PROFILES_POLICY = os.path.join(
    ROOT, 'migrations', '007_drop_admin_profiles_policy.sql')
WAREHOUSES_BELONG_TO_A_YARD = os.path.join(
    ROOT, 'migrations', '008_warehouses_belong_to_a_yard.sql')
WAREHOUSE_YARD_BOUNDARY = os.path.join(
    ROOT, 'migrations', '009_warehouse_yard_boundary.sql')
REMAINING_VIEWS_AS_CALLER = os.path.join(
    ROOT, 'migrations', '010_remaining_views_run_as_caller.sql')
YARD_INDEX_COMPLETENESS = os.path.join(
    ROOT, 'migrations', '011_yard_index_completeness.sql')
RLS_HELPERS_EVALUATED_ONCE = os.path.join(
    ROOT, 'migrations', '012_rls_helpers_evaluated_once.sql')
OTHER_GOODS_HANDOVER = os.path.join(
    ROOT, 'migrations', '013_other_goods_handover.sql')
PAST_YARD_STAFF_VISIBLE = os.path.join(
    ROOT, 'migrations', '014_past_yard_staff_visible.sql')
WAREHOUSE_ROWS_APPEAL_STATE = os.path.join(
    ROOT, 'migrations', '015_warehouse_rows_appeal_state.sql')
PERISHABLE_FLAG_ON_OUTCOME_VIEWS = os.path.join(
    ROOT, 'migrations', '016_perishable_flag_on_outcome_views.sql')
UNSOLD_INCLUDES_PERISHABLES = os.path.join(
    ROOT, 'migrations', '017_unsold_includes_perishables.sql')
EXPIRED_PASSWORD_LOCKS_SESSION = os.path.join(
    ROOT, 'migrations', '018_expired_password_locks_the_session.sql')
# ⚠️ postgres/47 is applied by hand on an existing server, so it was never
# folded in here — and 015 reads the view it defines. Without it 02_schema.sql,
# the ONE file that stands a new server up, fails on a fresh database.
ITEM_APPEAL_OUTCOMES = os.path.join(
    ROOT, 'postgres', '47_item_appeal_outcomes_view.sql')
def emit(label: str, body: str) -> None:
    parts.append(
        '\n-- ' + '=' * 74 + '\n'
        f'--  {label}\n'
        '-- ' + '=' * 74 + '\n\n' + make_rerunnable(body) + '\n')


# Inserted before the first migration that needs `yard` to exist.
_yard_done = False
for name in names:
    if not _yard_done and name >= '20260620_seed_data.sql':
        if os.path.exists(MULTI_YARD):
            emit('migrations/001_multi_yard.sql (folded in — adds the yard '
                 'column the seed data below writes to)',
                 io.open(MULTI_YARD, encoding='utf-8').read())
        _yard_done = True

    body = io.open(os.path.join(MIG, name), encoding='utf-8').read()
    # Migrations are already guarded, with a handful of exceptions that would
    # fail on a second run; guard_policy skips any that already have a DROP.
    emit(name, body)

# Strict per-yard RLS goes LAST: it locks every table down to the caller's own
# yard, so anything that runs after it would be filtered by policies rather
# than seeing the whole table.
if os.path.exists(YARD_ISOLATION):
    emit('migrations/002_strict_yard_isolation.sql (folded in)',
         io.open(YARD_ISOLATION, encoding='utf-8').read())

# This must be last: it makes the reporting views obey the policies installed
# above, including when a later schema migration recreated one of those views.
if os.path.exists(DATABASE_YARD_ISOLATION):
    emit('migrations/003_database_yard_isolation.sql (folded in)',
         io.open(DATABASE_YARD_ISOLATION, encoding='utf-8').read())

if os.path.exists(WAREHOUSE_QUERY_YARD_SCOPE):
    emit('migrations/004_warehouse_query_yard_scope.sql (folded in)',
         io.open(WAREHOUSE_QUERY_YARD_SCOPE, encoding='utf-8').read())

if os.path.exists(DATABASE_WIDE_YARD_BOUNDARY):
    emit('migrations/005_restrict_yard_staff_at_database.sql (folded in)',
         io.open(DATABASE_WIDE_YARD_BOUNDARY, encoding='utf-8').read())

if os.path.exists(PROFILES_POLICY_RECURSION_FIX):
    emit('migrations/006_profiles_policy_recursion_fix.sql (folded in)',
         io.open(PROFILES_POLICY_RECURSION_FIX, encoding='utf-8').read())

# The base schema's admin policy reads profiles inline, so it recurses the way
# 006's did — and it grants cross-yard access that 002 meant to remove. The
# drop must come after the base schema that creates it.
if os.path.exists(DROP_ADMIN_PROFILES_POLICY):
    emit('migrations/007_drop_admin_profiles_policy.sql (folded in)',
         io.open(DROP_ADMIN_PROFILES_POLICY, encoding='utf-8').read())

# Gives warehouses (and, through them, zones) a yard, replacing the policies
# that showed every yard's storage to every other yard. After the base schema
# that creates those policies.
if os.path.exists(WAREHOUSES_BELONG_TO_A_YARD):
    emit('migrations/008_warehouses_belong_to_a_yard.sql (folded in)',
         io.open(WAREHOUSES_BELONG_TO_A_YARD, encoding='utf-8').read())

# 005's restrictive boundary applies itself to tables that have a `yard`
# column, so it could not cover warehouses (008 added the column later) or
# warehouse_zones (no yard column at all). Must come after 008.
if os.path.exists(WAREHOUSE_YARD_BOUNDARY):
    emit('migrations/009_warehouse_yard_boundary.sql (folded in)',
         io.open(WAREHOUSE_YARD_BOUNDARY, encoding='utf-8').read())

# Last: every view must run as the caller, including ones a later migration
# recreated, or it silently bypasses every policy above.
if os.path.exists(REMAINING_VIEWS_AS_CALLER):
    emit('migrations/010_remaining_views_run_as_caller.sql (folded in)',
         io.open(REMAINING_VIEWS_AS_CALLER, encoding='utf-8').read())

# Every yard-filtered table needs an index on `yard`, or each yard's reads
# scan the whole table. Runs last so it sees every column added above.
if os.path.exists(YARD_INDEX_COMPLETENESS):
    emit('migrations/011_yard_index_completeness.sql (folded in)',
         io.open(YARD_INDEX_COMPLETENESS, encoding='utf-8').read())

# Truly last: it rewrites whatever policies exist above, so every policy any
# earlier migration created must already be in place.
# Adds a column and an RPC, so it must run BEFORE 012 rewrites the policies
# that guard them. Emitted after, but 012 touches only policy expressions.
if os.path.exists(OTHER_GOODS_HANDOVER):
    emit('migrations/013_other_goods_handover.sql (folded in)',
         io.open(OTHER_GOODS_HANDOVER, encoding='utf-8').read())

# Widens the profiles read policy, so it must land BEFORE 012 hoists the
# helper calls inside it.
if os.path.exists(PAST_YARD_STAFF_VISIBLE):
    emit('migrations/014_past_yard_staff_visible.sql (folded in)',
         io.open(PAST_YARD_STAFF_VISIBLE, encoding='utf-8').read())

# Recreates warehouse_rows, so it must come AFTER postgres/48 defines it and
# after 003 sets security_invoker on the reporting views.
if os.path.exists(ITEM_APPEAL_OUTCOMES):
    emit('postgres/47_item_appeal_outcomes_view.sql (folded in)',
         io.open(ITEM_APPEAL_OUTCOMES, encoding='utf-8').read())

if os.path.exists(WAREHOUSE_ROWS_APPEAL_STATE):
    emit('migrations/015_warehouse_rows_appeal_state.sql (folded in)',
         io.open(WAREHOUSE_ROWS_APPEAL_STATE, encoding='utf-8').read())

# Wraps disposition_rows and exhausted_unsold, so every migration that
# recreates either of them must already have run.
if os.path.exists(PERISHABLE_FLAG_ON_OUTCOME_VIEWS):
    emit('migrations/016_perishable_flag_on_outcome_views.sql (folded in)',
         io.open(PERISHABLE_FLAG_ON_OUTCOME_VIEWS, encoding='utf-8').read())

# Unions the two views above, so it must follow 016 (which adds the
# is_perishable column this reads) and both hand-applied source views.
if os.path.exists(UNSOLD_INCLUDES_PERISHABLES):
    emit('migrations/017_unsold_includes_perishables.sql (folded in)',
         io.open(UNSOLD_INCLUDES_PERISHABLES, encoding='utf-8').read())

# Redefines auth.uid() and auth.role(), so it must come after every policy
# that uses them has been created -- it changes what they return, not their
# shape, but replaying it earlier would be replaced by 01_supabase_compat.
if os.path.exists(EXPIRED_PASSWORD_LOCKS_SESSION):
    emit('migrations/018_expired_password_locks_the_session.sql (folded in)',
         io.open(EXPIRED_PASSWORD_LOCKS_SESSION, encoding='utf-8').read())

if os.path.exists(RLS_HELPERS_EVALUATED_ONCE):
    emit('migrations/012_rls_helpers_evaluated_once.sql (folded in)',
         io.open(RLS_HELPERS_EVALUATED_ONCE, encoding='utf-8').read())

parts[0] = HEADER.format(n=len(names))

io.open(OUT, 'w', encoding='utf-8').write(''.join(parts))
print(f'wrote {OUT}: {len(names)} migrations, '
      f'{sum(len(p.splitlines()) for p in parts)} lines')
