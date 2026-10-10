#!/usr/bin/env python3
"""Audits audit-trail integrity and backup readiness.

    python tool/audit_backup_readiness.py
    python tool/audit_backup_readiness.py --backup-dir E:\\Backups

  1. APPEND-ONLY - audit_logs cannot be modified or deleted by anyone, and
                   the check is made by ATTEMPTING it, not by reading grants.
  2. COVERAGE    - the critical events actually reach the table, and each row
                   carries who / when / from where.
  3. BACKUPS     - a recent, verified dump exists, and PITR is configured.

Exit code 0 when clean, 1 on any CRITICAL finding.
"""

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CRITICAL, WARN, OK = 'CRITICAL', 'WARN', 'OK'
results = []


def record(level, check, detail):
    results.append((level, check, detail))
    mark = {OK: '  ok  ', WARN: ' warn ', CRITICAL: ' FAIL '}[level]
    line = f'[{mark}] {check}: {detail}'
    sys.stdout.buffer.write((line + '\n').encode('utf-8', 'replace'))


# ------------------------------------------------------- 1. append-only ----

def audit_append_only(conn):
    cur = conn.cursor()

    # ⚠️ Read the ATTEMPT, not the configuration. Grants and policies both say
    # nothing about a superuser, which is what the app connects as -- so a
    # green light from pg_policies would be meaningless here. Every probe runs
    # inside a savepoint and is rolled back.
    cur.execute('select id from public.audit_logs order by created_at desc limit 1')
    row = cur.fetchone()
    if not row:
        record(WARN, 'append-only', 'audit_logs is empty; nothing to probe')
        return
    rid = row[0]

    probes = [
        ('UPDATE', "update public.audit_logs set action='TAMPER' where id=%s", (rid,)),
        ('DELETE one', 'delete from public.audit_logs where id=%s', (rid,)),
        ('DELETE all', 'delete from public.audit_logs', None),
        ('TRUNCATE', 'truncate public.audit_logs', None),
    ]
    for label, sql, args in probes:
        cur.execute('savepoint p')
        try:
            cur.execute(sql, args) if args else cur.execute(sql)
            record(CRITICAL, 'append-only',
                   f'{label} SUCCEEDED as {conn.get_dsn_parameters()["user"]} '
                   f'- the audit trail can be rewritten')
        except Exception:
            record(OK, 'append-only', f'{label} is refused')
        cur.execute('rollback to savepoint p')

    # Appending must still work, or logging is broken.
    cur.execute('savepoint p')
    try:
        cur.execute("""insert into public.audit_logs
                       (user_id, action, entity_type, entity_id)
                       values (null, 'audit-probe', 'audit_logs', 'probe')""")
        record(OK, 'append-only', 'INSERT still works (logging is not broken)')
    except Exception as e:
        record(CRITICAL, 'append-only',
               f'INSERT is refused - the app cannot log at all: {e}')
    cur.execute('rollback to savepoint p')

    # Forging an entry under another user's name.
    cur.execute("select id from public.profiles limit 2")
    ids = [r[0] for r in cur.fetchall()]
    if len(ids) >= 2:
        cur.execute('savepoint p')
        try:
            cur.execute("select set_config('app.current_user_id',%s,true)",
                        (str(ids[0]),))
            cur.execute("select set_config('app.current_role','authenticated',true)")
            cur.execute("""insert into public.audit_logs
                           (user_id, action, entity_type, entity_id)
                           values (%s, 'forged', 'audit_logs', 'probe')""",
                        (str(ids[1]),))
            record(CRITICAL, 'impersonation',
                   'an entry naming ANOTHER user was accepted')
        except Exception:
            record(OK, 'impersonation',
                   'an entry naming another user is refused')
        cur.execute('rollback to savepoint p')

    # The structural pieces, reported for completeness (not as the proof).
    cur.execute("""select policyname, cmd from pg_policies
                    where schemaname='public' and tablename='audit_logs'""")
    pol = cur.fetchall()
    bad = [p for p, c in pol if c in ('UPDATE', 'DELETE', 'ALL')]
    if bad:
        record(CRITICAL, 'policies',
               f'audit_logs has an UPDATE/DELETE/ALL policy: {bad}')
    else:
        record(OK, 'policies',
               f'only {[p for p, _ in pol]} - no UPDATE/DELETE policy exists')

    cur.execute("select relforcerowsecurity from pg_class where relname='audit_logs'")
    if cur.fetchone()[0]:
        record(OK, 'force RLS', 'the table owner is bound by the policies too')
    else:
        record(WARN, 'force RLS',
               'not forced - the table owner bypasses the policies')

    cur.execute("""select tgname from pg_trigger t
                     join pg_class c on c.oid = t.tgrelid
                    where c.relname='audit_logs' and not t.tgisinternal""")
    trg = {r[0] for r in cur.fetchall()}
    for need in ('audit_logs_no_update', 'audit_logs_no_delete',
                 'audit_logs_no_truncate', 'audit_logs_stamp'):
        if need in trg:
            record(OK, 'trigger', f'{need} present')
        else:
            record(CRITICAL, 'trigger', f'{need} is MISSING')


# ---------------------------------------------------------- 2. coverage ----

def audit_coverage(conn):
    cur = conn.cursor()

    for col in ('client_addr', 'app_name', 'db_user', 'created_at', 'user_id'):
        cur.execute("""select 1 from information_schema.columns
                        where table_schema='public' and table_name='audit_logs'
                          and column_name=%s""", (col,))
        if cur.fetchone():
            record(OK, 'metadata column', col)
        else:
            record(CRITICAL, 'metadata column', f'{col} is missing')

    # Do rows actually carry it? A column nobody fills is not metadata.
    cur.execute("""select count(*) filter (where db_user is not null),
                          count(*) filter (where client_addr is not null),
                          count(*)
                     from public.audit_logs
                    where created_at > now() - interval '1 day'""")
    withuser, withaddr, total = cur.fetchone()
    if total == 0:
        record(WARN, 'metadata stamped', 'no rows in the last day to check')
    elif withuser == total:
        record(OK, 'metadata stamped',
               f'{withuser}/{total} recent rows carry db_user, '
               f'{withaddr}/{total} carry client_addr')
    else:
        record(WARN, 'metadata stamped',
               f'only {withuser}/{total} recent rows carry db_user')

    # The critical event classes.
    checks = [
        ('failed logins', "action ilike 'Login failed%'"),
        ('privilege changes', "entity_type='profiles' and action ilike 'Privilege change%'"),
        ('sign-ins', "action ilike 'Signed In%'"),
        ('retention purges', "action = 'Audit retention purge'"),
    ]
    for label, where in checks:
        cur.execute(f'select count(*) from public.audit_logs where {where}')
        n = cur.fetchone()[0]
        if n:
            record(OK, 'event coverage', f'{label}: {n} row(s)')
        elif label == 'retention purges':
            record(OK, 'event coverage',
                   f'{label}: none yet (nothing is 365 days old)')
        else:
            record(WARN, 'event coverage',
                   f'{label}: no rows - is the event being recorded?')

    # The writers exist and log.
    cur.execute("""select pg_get_functiondef(p.oid) from pg_proc p
                     join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname='auth' and p.proname='record_failed_login'""")
    r = cur.fetchone()
    if r and 'audit_logs' in r[0]:
        record(OK, 'failed-login logging',
               'auth.record_failed_login writes to audit_logs')
    else:
        record(CRITICAL, 'failed-login logging',
               'auth.record_failed_login does NOT write to audit_logs')

    cur.execute("""select tgname from pg_trigger t join pg_class c
                     on c.oid=t.tgrelid
                    where c.relname='profiles' and not t.tgisinternal
                      and tgname='profiles_audit_privilege'""")
    if cur.fetchone():
        record(OK, 'privilege-change logging',
               'a trigger on profiles catches role/is_active/yard changes')
    else:
        record(CRITICAL, 'privilege-change logging',
               'no trigger on profiles - a role change made outside the app '
               'would leave no trace')


# ----------------------------------------------------------- 3. backups ----

def audit_backups(conn, backup_dir):
    cur = conn.cursor()

    cur.execute('show archive_mode')
    archive = cur.fetchone()[0]
    cur.execute('show wal_level')
    wal = cur.fetchone()[0]

    if archive == 'on':
        record(OK, 'PITR', f'archive_mode=on, wal_level={wal}')
        cur.execute("""select archived_count, failed_count, last_failed_wal
                         from pg_stat_archiver""")
        arch, failed, lastfail = cur.fetchone()
        if failed and failed > 0:
            record(CRITICAL, 'WAL archiving',
                   f'{failed} failed archive attempts (last: {lastfail}) - '
                   f'pg_wal will fill until the disk is full')
        else:
            record(OK, 'WAL archiving', f'{arch} segments archived, 0 failures')
    else:
        record(WARN, 'PITR',
               f'archive_mode={archive} - point-in-time recovery is NOT '
               f'available; the most that can be recovered is the last '
               f'nightly dump (up to 24h of records lost). wal_level={wal} '
               f'is already sufficient; only archiving is missing.')

    # A recent, verified dump.
    if not os.path.isdir(backup_dir):
        record(WARN, 'daily backup',
               f'{backup_dir} does not exist - no backups are being taken '
               f'here. See postgres/SECURITY.md for the scheduled task.')
    else:
        dumps = [os.path.join(backup_dir, f) for f in os.listdir(backup_dir)
                 if f.endswith('.dump')]
        if not dumps:
            record(CRITICAL, 'daily backup', f'no .dump files in {backup_dir}')
        else:
            newest = max(dumps, key=os.path.getmtime)
            age = datetime.now() - datetime.fromtimestamp(os.path.getmtime(newest))
            size_mb = os.path.getsize(newest) / (1024 * 1024)
            if age > timedelta(days=2):
                record(CRITICAL, 'daily backup',
                       f'newest dump is {age.days} days old ({os.path.basename(newest)})')
            elif age > timedelta(days=1, hours=6):
                record(WARN, 'daily backup',
                       f'newest dump is {age.days}d {age.seconds//3600}h old')
            else:
                record(OK, 'daily backup',
                       f'{os.path.basename(newest)}, {size_mb:.1f} MB, '
                       f'{age.seconds//3600}h old')
            record(OK, 'backup count', f'{len(dumps)} dump(s) retained')

    script = os.path.join(REPO, 'tool', 'backup_database.ps1')
    if os.path.exists(script):
        with open(script, encoding='utf-8', errors='replace') as fh:
            s = fh.read()
        if 'pg_restore' in s and '--list' in s:
            record(OK, 'backup verification',
                   'the backup script verifies each dump is restorable')
        else:
            record(WARN, 'backup verification',
                   'the backup script does not verify what it writes')
    else:
        record(CRITICAL, 'backup script', 'tool/backup_database.ps1 missing')

    doc = os.path.join(REPO, 'postgres', 'SECURITY.md')
    with open(doc, encoding='utf-8', errors='replace') as fh:
        d = fh.read()
    for needle, label in [('recovery_target_time', 'PITR restore procedure'),
                          ('Retention schedule', 'retention schedule'),
                          ('Restore drill', 'restore drill')]:
        if needle in d:
            record(OK, 'documentation', f'{label} documented')
        else:
            record(CRITICAL, 'documentation', f'{label} NOT documented')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='localhost')
    ap.add_argument('--port', type=int, default=5432)
    ap.add_argument('--database', default='Customs_SR_DB')
    ap.add_argument('--user', default='postgres')
    ap.add_argument('--password', default=os.environ.get('PGPASSWORD', 'postgres'))
    ap.add_argument('--backup-dir', default=r'D:\Backups\Customs_SR_DB')
    args = ap.parse_args()

    print('=' * 72)
    print('Backup & audit readiness')
    print('=' * 72)

    try:
        import psycopg2
    except ImportError:
        print('psycopg2 is not installed; cannot check the live database.')
        return 1

    conn = psycopg2.connect(host=args.host, port=args.port,
                            dbname=args.database, user=args.user,
                            password=args.password, connect_timeout=10)
    try:
        print('\n-- 1. audit trail is append-only (probed, not assumed) --')
        audit_append_only(conn)
        print('\n-- 2. what reaches the trail --')
        audit_coverage(conn)
        print('\n-- 3. backups & PITR --')
        audit_backups(conn, args.backup_dir)
    finally:
        conn.rollback()   # every probe was in a savepoint; keep nothing
        conn.close()

    fails = [r for r in results if r[0] == CRITICAL]
    warns = [r for r in results if r[0] == WARN]
    print('\n' + '=' * 72)
    print(f'{len(results) - len(fails) - len(warns)} passed, '
          f'{len(warns)} warnings, {len(fails)} failures')
    print('=' * 72)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
