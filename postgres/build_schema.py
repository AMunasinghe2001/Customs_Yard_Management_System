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
    # Seed rows would duplicate on a second run.
    sql = re.sub(r'(?i)\bINSERT INTO\s+(\w+)([^;]*);',
                 lambda m: f'INSERT INTO {m.group(1)}{m.group(2)}\n  ON CONFLICT DO NOTHING;',
                 sql)

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

names = sorted(f for f in os.listdir(MIG) if f.endswith('.sql'))
for name in names:
    body = io.open(os.path.join(MIG, name), encoding='utf-8').read()
    # Migrations are already guarded, with a handful of exceptions that would
    # fail on a second run; guard_policy skips any that already have a DROP.
    body = make_rerunnable(body)
    parts.append(
        '\n-- ' + '=' * 74 + '\n'
        f'--  {name}\n'
        '-- ' + '=' * 74 + '\n\n' + body + '\n')

parts[0] = HEADER.format(n=len(names))

io.open(OUT, 'w', encoding='utf-8').write(''.join(parts))
print(f'wrote {OUT}: {len(names)} migrations, '
      f'{sum(len(p.splitlines()) for p in parts)} lines')
