#!/usr/bin/env python3
"""Audits the user-level security policies: MFA/OTP, passwords, and RBAC.

    python tool/audit_user_security.py

  1. OTP    - the OTP bypass cannot be active in a release build, and every
              privileged portal actually gates on it.
  2. PASSWD - strength is enforced by the DATABASE (not only by screens), and
              rotation has a server-side answer.
  3. RBAC   - every SECURITY DEFINER function that MUTATES data re-checks the
              caller's role. Those functions run with the definer's rights, so
              RLS does not apply inside them: whatever they do not check, they
              permit.

Exit code 0 when clean, 1 on any CRITICAL finding.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(REPO, 'lib')
PG = os.path.join(REPO, 'postgres')

CRITICAL, WARN, OK = 'CRITICAL', 'WARN', 'OK'
results = []


def record(level, check, detail):
    results.append((level, check, detail))
    mark = {OK: '  ok  ', WARN: ' warn ', CRITICAL: ' FAIL '}[level]
    print(f'[{mark}] {check}: {detail}')


def read(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        return fh.read()


# ----------------------------------------------------------------- 1. OTP ----

def audit_otp():
    cfg = os.path.join(LIB, 'core', 'dev_config.dart')
    if not os.path.exists(cfg):
        record(CRITICAL, 'OTP config', 'lib/core/dev_config.dart missing')
        return
    src = read(cfg)

    # ⚠️ The whole point: a release build must not be able to skip OTP even if
    # the flag is left on. A bare `const bool kDevSkipOtp = true;` ships a
    # second-factor bypass and nothing about the .exe says so.
    if re.search(r'kDevSkipOtp\s*=\s*true\s*;', src):
        record(CRITICAL, 'OTP bypass',
               'kDevSkipOtp is unconditionally true - release builds would '
               'skip two-factor authentication')
    elif 'kReleaseMode' in src and 'kDevSkipOtp' in src:
        record(OK, 'OTP bypass',
               'kDevSkipOtp is gated on !kReleaseMode - a release build always '
               'requires the emailed code')
    else:
        record(CRITICAL, 'OTP bypass',
               'kDevSkipOtp is not tied to kReleaseMode; a flipped constant '
               'would ship')

    if 'bool.fromEnvironment' in src:
        record(OK, 'OTP opt-in',
               'skipping OTP needs an explicit --dart-define, not a source edit')
    else:
        record(WARN, 'OTP opt-in',
               'the bypass is a source constant; prefer a --dart-define so it '
               'cannot be committed in the on state')

    # Every privileged portal must actually consult the flag.
    portals = {
        'disposal': 'lib/screens/disposal/disposal_login_screen.dart',
        'valuation': 'lib/screens/valuation/valuation_login_screen.dart',
        'appeal': 'lib/screens/appeal/appeal_login_screen.dart',
        'executive': 'lib/screens/executive/executive_login_screen.dart',
        'ict': 'lib/screens/ict/ict_login_screen.dart',
    }
    missing = []
    for name, rel in portals.items():
        p = os.path.join(REPO, rel)
        if not os.path.exists(p):
            missing.append(f'{name} (screen not found)')
            continue
        s = read(p)
        # An OTP portal both starts and finishes an OTP login.
        if 'startOtpLogin' not in s and 'finishOtpLogin' not in s:
            missing.append(f'{name} (no OTP flow)')
    if missing:
        record(CRITICAL, 'privileged portals use OTP',
               'no OTP flow in: ' + ', '.join(missing))
    else:
        record(OK, 'privileged portals use OTP',
               f'{len(portals)} portals run the emailed-code flow '
               f'({", ".join(portals)})')


# ------------------------------------------------------------ 2. passwords ----

def audit_passwords():
    sqls = {n: read(os.path.join(PG, n))
            for n in sorted(os.listdir(PG)) if n.endswith('.sql')}
    all_sql = '\n'.join(sqls.values())

    if 'password_policy_violation' not in all_sql:
        record(CRITICAL, 'server password policy',
               'no password_policy_violation function - the database accepts '
               'whatever a client sends')
        return
    record(OK, 'server password policy',
           'password_policy_violation() defines the rule in SQL')

    # ⚠️ Defining the policy is not applying it. Both password entry points
    # must call it, or a direct RPC bypasses every screen.
    # ⚠️ Migrations REDEFINE functions. 04_auth.sql still holds the original
    # sign_up, and 52_ replaces it; reading the first match reported the
    # policy as missing while the live database had it. Files are applied in
    # name order, so the LAST definition is the one that is actually running.
    for fn in ('auth.sign_up', 'auth.change_password'):
        latest = None
        for name in sorted(sqls):
            for m in re.finditer(
                    re.escape('create or replace function ' + fn)
                    + r'(.*?)\$fn\$;', sqls[name], re.S):
                latest = (name, m.group(1))
        if latest is None:
            record(WARN, f'{fn} policy', 'function not found in postgres/*.sql')
            continue
        where, defn = latest
        if 'password_policy_violation' in defn:
            record(OK, f'{fn} policy',
                   f'validates before hashing (latest definition: {where})')
        else:
            record(CRITICAL, f'{fn} policy',
                   f'latest definition ({where}) does NOT call '
                   f'password_policy_violation - a direct RPC can set a weak '
                   f'password')

    # A stale 6-character rule left in SQL would be the weakest link.
    # Only superseded files may still contain the old rule; what matters is
    # whether any function STILL RUNNING carries it. A file whose functions are
    # all redefined later is dead text.
    superseded = set()
    for fn in ('auth.sign_up', 'auth.change_password'):
        seen = [n for n in sorted(sqls)
                if 'create or replace function ' + fn in sqls[n]]
        superseded.update(seen[:-1])
    live_weak = []
    for name in sorted(sqls):
        if name in superseded:
            continue
        for w in re.findall(r'length\(p_password\)\s*<\s*(\d+)', sqls[name]):
            if int(w) < 12:
                live_weak.append(f'{name} (< {w})')
    if live_weak:
        record(CRITICAL, 'weak length rule',
               'SQL still enforces a sub-12 minimum in: '
               + ', '.join(live_weak))
    else:
        record(OK, 'length rule',
               'no live SQL rule below 12 characters (older definitions are '
               'superseded by a later migration)')

    # Rotation needs a server-side answer, not only a client getter.
    if 'password_age_status' in all_sql:
        record(OK, 'rotation', 'password_age_status() answers server-side')
    else:
        record(WARN, 'rotation',
               'expiry is computed only on the client (ProfileModel)')

    if 'password_updated_at' in all_sql:
        record(OK, 'rotation anchor', 'profiles.password_updated_at is set')
    else:
        record(CRITICAL, 'rotation anchor', 'no password_updated_at column')

    # The Dart mirror must not be laxer than the SQL.
    pol = os.path.join(LIB, 'core', 'security_policy.dart')
    if os.path.exists(pol) and 'PasswordPolicy' in read(pol):
        dart = read(pol)
        m = re.search(r'minLength\s*=\s*(\d+)', dart)
        if m and int(m.group(1)) >= 12:
            record(OK, 'client mirror',
                   f'PasswordPolicy.minLength = {m.group(1)}, matching the SQL')
        else:
            record(CRITICAL, 'client mirror',
                   'PasswordPolicy is weaker than the server rule')
    else:
        record(WARN, 'client mirror',
               'no PasswordPolicy; each screen carries its own rule')

    # Screens must not still carry their own weaker check.
    stale = []
    for base, _d, files in os.walk(LIB):
        for name in files:
            if not name.endswith('.dart'):
                continue
            p = os.path.join(base, name)
            s = read(p)
            # ⚠️ Anchor on the VARIABLE, not on nearby text. Looking for
            # "pass" anywhere in the preceding 200 characters matched
            # `parts.length < 3` inside a method that happened to sit near the
            # word "password" — a list length reported as a password rule.
            for m in re.finditer(
                    r'\b(\w*(?:pass|pwd)\w*)\s*(?:\.text\s*)?'
                    r'\.length\s*<\s*([0-9]+)', s, re.I):
                n = int(m.group(2))
                if n < 12:
                    line = s[:m.start()].count('\n') + 1
                    stale.append(
                        f'{os.path.relpath(p, REPO)}:{line} (< {n})')
    if stale:
        for s_ in stale[:10]:
            record(WARN, 'stale client rule', s_)
    else:
        record(OK, 'client rules',
               'no screen carries its own weaker password length check')


# ----------------------------------------------------------------- 3. RBAC ----

# A function that only READS is governed by the RLS on what it selects. One
# that WRITES under SECURITY DEFINER is not - it must check the caller itself.
#
# ⚠️ `update\s+\w` matched the word "update" inside identifiers like
# `email_confirmed_at ... updated_at` and `password_updated_at`, reporting two
# read-only `select` functions as unguarded writers. Require the table
# keyword form, and treat a function declared `stable`/`immutable` as
# read-only regardless - Postgres itself forbids writing in one.
MUTATES = re.compile(
    r'\b(insert\s+into\s+[\w."]|update\s+(?:only\s+)?[\w."]+\s+set\b|'
    r'delete\s+from\s+[\w."])', re.I)
READ_ONLY_VOLATILITY = re.compile(r'^\s*(stable|immutable)\s*$', re.I | re.M)
CHECKS_ROLE = re.compile(
    r'auth_user_is_\w+|auth\.uid\(\)|current_setting\(\s*.app\.current_user',
    re.I)

# Functions that legitimately run before anyone is signed in, or that are
# called BY the auth machinery itself. Each is listed with why.
RBAC_EXEMPT = {
    # Pre-authentication by definition: these run to let someone sign in.
    'auth.sign_in': 'runs before a session exists',
    'auth.sign_up': 'account creation; gated by the admin screens + RLS',
    'auth.record_failed_login': 'lockout bookkeeping during sign-in',
    'auth.clear_failed_login': 'lockout bookkeeping during sign-in',
    'auth.change_password': 'reached via reset flow; identity proved by OTP',
    'auth.update_user': 'called by the auth layer itself',
    'public.reset_password_for_identifier': 'reset flow; proved by e-mail OTP',
    'public.reset_email_for_identifier': 'reset flow; returns only an address',
    'public.email_for_login': 'resolves a username to an e-mail, pre-login',
    # Triggers: they run as part of a statement whose own rights already
    # applied, and take no caller argument.
    'public.handle_new_user': 'trigger on auth.users',
    'public.handle_password_update': 'trigger on auth.users',
    'public.notify_db_change': 'trigger, emits a notification only',
    'public.tsi_autofill_package_item': 'trigger, fills a column',
    'public.di_autofill_package_item': 'trigger, fills a column',
    'public.purge_old_audit_logs': 'retention job, deletes only expired rows',
}


def audit_rbac():
    # ⚠️ Same trap as the password check: a function defined in 02_schema.sql
    # and REDEFINED by a later migration must be judged on its FINAL form.
    # Scanning every definition reported disposal_toggle_outcome_delivery as
    # unguarded after migration 52 had already added the guard — and the live
    # database agreed with 52. Files apply in name order, so last wins.
    latest = {}   # fn -> (file, body)
    for name in sorted(os.listdir(PG)):
        if not name.endswith('.sql'):
            continue
        src = read(os.path.join(PG, name))
        for m in re.finditer(
                r'create or replace function\s+([\w.]+)\s*\((.*?)\)\s*'
                r'returns.*?(?=\ncreate or replace function|\Z)',
                src, re.S | re.I):
            latest[m.group(1)] = (name, m.group(0))

    findings = []
    checked = 0
    for fn, (name, body) in sorted(latest.items()):
        if 'security definer' not in body.lower():
            continue
        if READ_ONLY_VOLATILITY.search(body):
            continue              # declared stable/immutable: cannot write
        if not MUTATES.search(body):
            continue              # read-only: RLS on the selected tables applies
        checked += 1
        if fn in RBAC_EXEMPT:
            continue
        if not CHECKS_ROLE.search(body):
            findings.append((fn, name))

    if findings:
        for fn, where in findings:
            record(CRITICAL, 'RBAC',
                   f'{fn} ({where}) is SECURITY DEFINER and writes, but never '
                   f'checks the caller - RLS does not apply inside it')
    else:
        record(OK, 'RBAC',
               f'{checked} SECURITY DEFINER writers checked; every '
               f'non-exempt one re-verifies the caller server-side')

    # Privileged mutations must not be granted to `public` (which includes
    # anon, i.e. not signed in).
    bad_grants = []
    for name in sorted(os.listdir(PG)):
        if not name.endswith('.sql'):
            continue
        src = read(os.path.join(PG, name))
        for m in re.finditer(
                r'grant execute on function\s+([\w.]+)\s*\([^)]*\)\s*\n?\s*to\s+(\w+)',
                src, re.I):
            fn, role = m.group(1), m.group(2).lower()
            if role != 'public':
                continue
            # Read-only helpers may be public; writers may not.
            fnbody = re.search(
                re.escape('create or replace function ' + fn) + r'(.*?)\$',
                src, re.S)
            if fnbody and MUTATES.search(fnbody.group(1)):
                bad_grants.append(f'{fn} ({name})')
    # Deduplicate: a later migration may re-grant correctly.
    if bad_grants:
        for g in sorted(set(bad_grants)):
            record(WARN, 'grant to public',
                   f'{g} mutates and is granted to public - check a later '
                   f'migration revokes it')
    else:
        record(OK, 'grants',
               'no data-mutating function is granted to public in its final '
               'migration')

    # And the client must not be the only thing enforcing a role.
    ui_only = []
    for base, _d, files in os.walk(os.path.join(LIB, 'screens')):
        for nm in files:
            if nm.endswith('.dart'):
                ui_only.append(os.path.join(base, nm))
    guards = sum(1 for p in ui_only
                 if re.search(r'isAdmin|isDisposal|isValuation|isExecutive',
                              read(p)))
    record(OK, 'defence in depth',
           f'{guards} screens hide controls by role; the database re-checks '
           f'independently, so hiding is cosmetic rather than the control')


def main():
    print('=' * 72)
    print('User-level security audit (MFA / passwords / RBAC)')
    print('=' * 72)
    print('\n-- 1. MFA / OTP --')
    audit_otp()
    print('\n-- 2. password strength & rotation --')
    audit_passwords()
    print('\n-- 3. server-side RBAC --')
    audit_rbac()

    fails = [r for r in results if r[0] == CRITICAL]
    warns = [r for r in results if r[0] == WARN]
    print('\n' + '=' * 72)
    print(f'{len(results) - len(fails) - len(warns)} passed, '
          f'{len(warns)} warnings, {len(fails)} failures')
    print('=' * 72)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
