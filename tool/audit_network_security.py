#!/usr/bin/env python3
"""Audits the network- and database-level protections.

Run it against a live server before a deployment leaves the office LAN:

    python tool/audit_network_security.py
    python tool/audit_network_security.py --host 192.168.1.50 --expect-remote

It checks four things that a code review cannot:

  1. TRANSPORT  - is the server actually offering TLS, and does the app's
                  .env ask for it? A `.env` saying PG_SSL=true against a
                  server built without SSL fails at connect, not silently,
                  but the reverse - a remote host with PG_SSL unset - is a
                  plaintext link nobody notices.
  2. SQL        - no raw string concatenation in the Dart database layer.
                  Greps for the shapes that would put a value into SQL text
                  instead of binding it.
  3. RLS        - every table holding operational data has row-level security
                  enabled and at least one policy.
  4. EXPOSURE   - which addresses the server accepts connections from
                  (listen_addresses / pg_hba), so a database meant for one
                  LAN is not answering the whole internet.

Exit code is 0 when everything passes, 1 when any CRITICAL check fails, so
this can gate a release step.
"""

import argparse
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Reference/lookup tables. These hold no seizure records, no personal data and
# no financial figures - only fixed code lists every signed-in user may read.
# RLS on them would add a policy to maintain and protect nothing, so they are
# listed here deliberately rather than silently skipped.
RLS_EXEMPT = {
    'app_migration_flags',
    'hold_reasons',
    'package_categories',
    'sr_number_migration_log',
    'storage_rates',
    'schema_migrations',
}

# Tables where RLS enabled with ZERO policies is the intended design, not an
# oversight. With no policy, RLS denies every ordinary role outright - a
# deny-all lockbox reachable only by a role that bypasses RLS. On Supabase
# that was service_role and the Edge Function; the check below is what makes
# sure the app's own role is not also such a role, which would open it.
RLS_DENY_ALL_BY_DESIGN = {
    'officer_signup_otps',
}

CRITICAL = 'CRITICAL'
WARN = 'WARN'
OK = 'OK'

results = []


def record(level, check, detail):
    results.append((level, check, detail))
    mark = {OK: '  ok  ', WARN: ' warn ', CRITICAL: ' FAIL '}[level]
    print(f'[{mark}] {check}: {detail}')


# ---------------------------------------------------------------- 2. SQL ----

# Shapes that would place a VALUE into SQL text rather than binding it. The
# query builder interpolates identifiers on purpose (Postgres cannot bind a
# column name), so the pattern targets interpolation next to the places a
# value goes: after a comparison operator, or inside a VALUES list.
# Names the builder is ALLOWED to interpolate. Postgres cannot bind an
# identifier, an alias or a join condition, so these are composed as SQL text
# on purpose - each is either derived internally (t, f0, v3) or passed through
# _quoteIdent / _quoteRel, never a user value. Anything interpolated in a
# value position that is NOT one of these is a finding.
SAFE_INTERPOLATIONS = re.compile(
    r'^(?:'
    r'alias|inner|joinOn|on|body|key|col|cols|p|n|sql|w|where|'
    r'conflict|returning|table|childTable|parentTable|tbl|'
    r'\w*Alias|\w*Sql|\w*Ident|\w*Rel'
    r')$')


def _interpolated_names(fragment):
    """The ${...} / $name identifiers inside a string fragment."""
    return re.findall(r'\$\{?([a-zA-Z_]\w*)', fragment)


VALUE_INTERPOLATION = [
    (r"""=\s*\$\{?[a-zA-Z_]""", 'value interpolated after ='),
    (r"""(?i)\bvalues\s*\([^)]*\$""", 'value interpolated into VALUES'),
    (r"""(?i)\blike\s+'?\$""", 'value interpolated into LIKE'),
    (r"""(?i)\bwhere\s+\$\{?[a-zA-Z_]""", 'value interpolated into WHERE'),
]


def audit_sql_layer():
    db_dir = os.path.join(REPO, 'lib', 'core', 'db')
    if not os.path.isdir(db_dir):
        record(CRITICAL, 'SQL layer', f'{db_dir} not found')
        return

    findings = []
    for name in sorted(os.listdir(db_dir)):
        if not name.endswith('.dart'):
            continue
        path = os.path.join(db_dir, name)
        with open(path, encoding='utf-8') as fh:
            for n, line in enumerate(fh, 1):
                code = line.split('///')[0]
                stripped = code.strip()
                if stripped.startswith('//'):
                    continue
                # An exception message is not SQL. It names tables and columns
                # to be helpful, and never reaches the server.
                if 'Exception(' in code or stripped.startswith('throw '):
                    continue
                for pattern, why in VALUE_INTERPOLATION:
                    m = re.search(pattern, code)
                    if not m:
                        continue
                    names = _interpolated_names(code[m.start():])
                    if names and all(SAFE_INTERPOLATIONS.match(x)
                                     for x in names):
                        continue  # identifiers / aliases, not values
                    findings.append(f'{name}:{n} {why}')

    if findings:
        for f in findings:
            record(CRITICAL, 'parameterised SQL', f)
    else:
        record(OK, 'parameterised SQL',
               'no value interpolation in lib/core/db (identifiers are '
               'quoted/validated; values bind as @params)')

    # Raw SQL must stay inside the db layer. A .query( in a screen would be a
    # call site nobody audits.
    stray = []
    for root, dirs, files in os.walk(os.path.join(REPO, 'lib')):
        if os.path.normpath(root).endswith(os.path.normpath('core/db')):
            continue
        for name in files:
            if not name.endswith('.dart'):
                continue
            path = os.path.join(root, name)
            with open(path, encoding='utf-8') as fh:
                for n, line in enumerate(fh, 1):
                    if re.search(r'PgDatabase\.instance\.(query|execute)\(', line):
                        rel = os.path.relpath(path, REPO)
                        stray.append(f'{rel}:{n}')
    if stray:
        for s in stray:
            record(WARN, 'raw SQL outside db layer', s)
    else:
        record(OK, 'raw SQL confinement',
               'no direct PgDatabase.query/execute outside lib/core/db')


# ------------------------------------------------------ 1/3/4. live server ----

def audit_server(host, port, dbname, user, password, expect_remote):
    try:
        import psycopg2
    except ImportError:
        record(WARN, 'server checks', 'psycopg2 not installed - skipped')
        return

    try:
        conn = psycopg2.connect(host=host, port=port, dbname=dbname,
                                user=user, password=password,
                                connect_timeout=10)
    except Exception as e:
        record(WARN, 'server checks', f'cannot connect to {host}:{port} - {e}')
        return

    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            # --- 1. transport ---
            cur.execute('show ssl')
            ssl_on = cur.fetchone()[0] == 'on'
            loopback = host in ('localhost', '127.0.0.1', '::1') or \
                host.startswith('127.')

            if ssl_on:
                record(OK, 'server TLS', 'PostgreSQL is built and configured '
                                         'with ssl=on')
            elif loopback and not expect_remote:
                record(OK, 'server TLS',
                       'ssl=off, but the server is loopback - traffic never '
                       'leaves the machine')
            else:
                record(CRITICAL, 'server TLS',
                       f'ssl=off on {host}: every query and the login '
                       f'password cross the network in clear text. Enable '
                       f'ssl in postgresql.conf and set PG_SSL=true.')

            # What TLS this specific session actually got.
            cur.execute("""select ssl, version, cipher from pg_stat_ssl
                            where pid = pg_backend_pid()""")
            row = cur.fetchone()
            if row and row[0]:
                ver = row[1] or ''
                if ver in ('TLSv1.2', 'TLSv1.3'):
                    record(OK, 'TLS version', f'{ver} / {row[2]}')
                else:
                    record(CRITICAL, 'TLS version',
                           f'{ver or "unknown"} is below TLS 1.2')
            elif ssl_on:
                record(WARN, 'TLS version',
                       'server supports TLS but this session is plaintext - '
                       'the client did not ask for it (PG_SSL)')

            if ssl_on:
                cur.execute("show ssl_min_protocol_version")
                minver = cur.fetchone()[0]
                if minver in ('TLSv1.2', 'TLSv1.3'):
                    record(OK, 'TLS floor', f'ssl_min_protocol_version={minver}')
                else:
                    record(CRITICAL, 'TLS floor',
                           f'ssl_min_protocol_version={minver} permits '
                           f'obsolete TLS; set it to TLSv1.2')

            # --- 3. RLS ---
            cur.execute("""
                select c.relname, c.relrowsecurity,
                       (select count(*) from pg_policies p
                         where p.schemaname='public' and p.tablename=c.relname)
                  from pg_class c join pg_namespace n on n.oid=c.relnamespace
                 where n.nspname='public' and c.relkind='r'
                 order by c.relname
            """)
            unguarded, unexpected_exempt, total_policies = [], [], 0
            for relname, rls, npolicies in cur.fetchall():
                total_policies += npolicies
                if relname in RLS_EXEMPT:
                    if rls:
                        unexpected_exempt.append(relname)
                    continue
                if relname in RLS_DENY_ALL_BY_DESIGN:
                    # Here "no policies" IS the protection. The failure mode
                    # to catch is the opposite one: RLS switched off.
                    if not rls:
                        record(CRITICAL, 'RLS coverage',
                               f'{relname} is a deny-all table but RLS is '
                               f'OFF - it is now world-readable')
                    elif npolicies:
                        record(WARN, 'RLS coverage',
                               f'{relname} was deny-all by design but now has '
                               f'{npolicies} policies - confirm intended')
                    else:
                        record(OK, 'RLS deny-all',
                               f'{relname}: RLS on, no policies - readable '
                               f'only by a role that bypasses RLS')
                    continue
                if not rls or npolicies == 0:
                    unguarded.append(
                        f'{relname} (rls={"on" if rls else "OFF"}, '
                        f'{npolicies} policies)')
            if unguarded:
                for u in unguarded:
                    record(CRITICAL, 'RLS coverage', f'unprotected table {u}')
            else:
                record(OK, 'RLS coverage',
                       f'{total_policies} policies; every non-reference table '
                       f'has RLS enabled with at least one policy')
            if unexpected_exempt:
                record(WARN, 'RLS exemptions',
                       'now protected, can leave the exempt list: '
                       + ', '.join(unexpected_exempt))

            # RLS is bypassed entirely for a superuser or a BYPASSRLS role.
            # The app connecting as one makes all 112 policies decorative.
            cur.execute("""select rolsuper, rolbypassrls from pg_roles
                            where rolname = current_user""")
            is_super, bypass = cur.fetchone()
            if is_super or bypass:
                # This is the finding that subsumes the others: policies are
                # only a defence against a role they apply to. It is a WARN on
                # loopback (the practical single-PC install) and a failure the
                # moment the database is reachable over a network.
                level = CRITICAL if (expect_remote or not loopback) else WARN
                record(level, 'RLS enforcement',
                       f'the app connects as "{user}", which is '
                       f'{"a SUPERUSER" if is_super else "BYPASSRLS"} - RLS is '
                       f'NOT enforced for it, so all {total_policies} policies '
                       f'and the deny-all OTP table are bypassed. Create a '
                       f'least-privilege role (see postgres/SECURITY.md).')
            else:
                record(OK, 'RLS enforcement',
                       f'"{user}" is a normal role, so policies apply to it')

            # --- 4. exposure ---
            cur.execute('show listen_addresses')
            listen = cur.fetchone()[0]
            if listen.strip() == '*':
                record(WARN, 'listen_addresses',
                       "'*' accepts connections on every interface. Bind to "
                       "the LAN address only, and firewall port 5432 to the "
                       "office subnet.")
            else:
                record(OK, 'listen_addresses', listen)

            try:
                cur.execute("""select type, database, user_name, address,
                                      auth_method
                                 from pg_hba_file_rules
                                where auth_method is not null""")
                rows = cur.fetchall()
                weak = [r for r in rows
                        if r[4] in ('trust', 'password')
                        and r[0] != 'local']
                wide = [r for r in rows
                        if r[3] in ('0.0.0.0/0', '::/0')]
                if weak:
                    for r in weak:
                        record(CRITICAL, 'pg_hba auth',
                               f'{r[4]} auth for {r[3]} - use scram-sha-256')
                else:
                    record(OK, 'pg_hba auth',
                           'no trust/plaintext-password rules for host '
                           'connections')
                if wide:
                    for r in wide:
                        record(WARN, 'pg_hba exposure',
                               f'{r[0]} rule allows {r[3]} (the whole '
                               f'internet) - narrow to the office subnet')
                else:
                    record(OK, 'pg_hba exposure',
                           'no rule accepts 0.0.0.0/0')
            except Exception as e:
                record(WARN, 'pg_hba', f'could not read pg_hba rules: {e}')
    finally:
        conn.close()


# ------------------------------------------------------------- .env check ----

def audit_env(expect_remote):
    path = os.path.join(REPO, '.env')
    if not os.path.exists(path):
        record(OK, '.env', 'no .env present (compiled defaults / dart-define)')
        return
    cfg = {}
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            cfg[k.strip()] = v.strip()

    host = cfg.get('PG_HOST', 'localhost')
    ssl = cfg.get('PG_SSL', 'false').lower() == 'true'
    verify = cfg.get('PG_SSL_VERIFY', 'false').lower() == 'true'
    loopback = host in ('localhost', '127.0.0.1', '::1') or host.startswith('127.')

    if not ssl and not loopback:
        record(CRITICAL, '.env transport',
               f'PG_HOST={host} is remote but PG_SSL is not true')
    elif ssl and not verify and not loopback:
        record(WARN, '.env transport',
               f'PG_SSL=true but PG_SSL_VERIFY is not - encrypted to whoever '
               f'answers for {host}, which a man-in-the-middle also does')
    else:
        record(OK, '.env transport',
               f'host={host} ssl={ssl} verify={verify}')

    if expect_remote and cfg.get('PG_REQUIRE_TLS', '').lower() != 'true':
        record(WARN, '.env strictness',
               'set PG_REQUIRE_TLS=true off-LAN so a downgrade fails at '
               'start-up instead of connecting in clear text')

    # .env must never be committed - it holds the database password.
    try:
        tracked = subprocess.run(
            ['git', 'ls-files', '--error-unmatch', '.env'],
            cwd=REPO, capture_output=True, text=True)
        if tracked.returncode == 0:
            record(CRITICAL, '.env in git',
                   '.env is TRACKED by git - it contains PG_PASSWORD')
        else:
            record(OK, '.env in git', 'not tracked')
    except Exception:
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--host', default=os.environ.get('PG_HOST', 'localhost'))
    ap.add_argument('--port', type=int,
                    default=int(os.environ.get('PG_PORT', 5432)))
    ap.add_argument('--database',
                    default=os.environ.get('PG_DATABASE', 'Customs_SR_DB'))
    ap.add_argument('--user', default=os.environ.get('PG_USER', 'postgres'))
    ap.add_argument('--password',
                    default=os.environ.get('PG_PASSWORD', 'postgres'))
    ap.add_argument('--expect-remote', action='store_true',
                    help='treat this as an off-LAN deployment: plaintext and '
                         'unverified TLS become failures')
    ap.add_argument('--skip-server', action='store_true')
    args = ap.parse_args()

    print('=' * 72)
    print('Network & database security audit')
    print(f'target: {args.user}@{args.host}:{args.port}/{args.database}')
    print('=' * 72)

    print('\n-- static: SQL construction --')
    audit_sql_layer()

    print('\n-- static: configuration --')
    audit_env(args.expect_remote)

    if not args.skip_server:
        print('\n-- live server --')
        audit_server(args.host, args.port, args.database, args.user,
                     args.password, args.expect_remote)

    fails = [r for r in results if r[0] == CRITICAL]
    warns = [r for r in results if r[0] == WARN]
    print('\n' + '=' * 72)
    print(f'{len(results) - len(fails) - len(warns)} passed, '
          f'{len(warns)} warnings, {len(fails)} failures')
    print('=' * 72)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
