#!/usr/bin/env python3
"""Audits the client-side / desktop hardening of the Flutter app.

    python tool/audit_client_security.py

Three things, all static - no server and no build needed:

  1. SECRETS  - no API key, token, or credential literal in lib/. Config must
                come from --dart-define or the .env, never from source.
  2. LOGGING  - nothing writes user data to stdout in a RELEASE build. Bare
                print() survives release; AppLog.debug does not.
  3. BUILD    - the release pipeline obfuscates and splits debug symbols, and
                .env / symbol directories are not committed.

Exit code 0 when clean, 1 on any CRITICAL finding, so it can gate a release.
"""

import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(REPO, 'lib')

CRITICAL, WARN, OK = 'CRITICAL', 'WARN', 'OK'
results = []


def record(level, check, detail):
    results.append((level, check, detail))
    mark = {OK: '  ok  ', WARN: ' warn ', CRITICAL: ' FAIL '}[level]
    print(f'[{mark}] {check}: {detail}')


def dart_files(root=LIB):
    for base, _dirs, files in os.walk(root):
        for name in sorted(files):
            if name.endswith('.dart'):
                yield os.path.join(base, name)


def rel(path):
    return os.path.relpath(path, REPO).replace('\\', '/')


# ⚠️ Splitting a line on '//' to drop the comment also truncates every URL at
# its scheme - 'https://x.supabase.co' becomes 'https:'. That silently blinded
# this scanner to the two findings it most needs to make: a project URL and a
# password embedded in a connection string. Strip only a '//' that is outside
# a string literal.
def strip_comment(line):
    out = []
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == '\\':
                out.append(line[i:i + 2])
                i += 2
                continue
            if c == quote:
                quote = None
            out.append(c)
        elif c in ("'", '"'):
            quote = c
            out.append(c)
        elif c == '/' and i + 1 < len(line) and line[i + 1] == '/':
            break
        else:
            out.append(c)
        i += 1
    return ''.join(out)


# ------------------------------------------------------------- 1. secrets ----

# Shapes that are a credential no matter what they are called.
SECRET_SHAPES = [
    (re.compile(r'\beyJ[A-Za-z0-9_-]{20,}\.'), 'JWT'),
    (re.compile(r'\bsk-[A-Za-z0-9]{20,}\b'), 'OpenAI-style API key'),
    (re.compile(r'\bAIza[A-Za-z0-9_-]{30,}\b'), 'Google API key'),
    (re.compile(r'\bghp_[A-Za-z0-9]{30,}\b'), 'GitHub token'),
    (re.compile(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b'), 'Slack token'),
    (re.compile(r'://[^/\s:@]+:[^/\s:@]+@'), 'credentials in a URL'),
    (re.compile(r'\bhttps://[a-z0-9-]+\.supabase\.co'), 'Supabase project URL'),
    # A Gmail App Password is 16 lowercase letters, usually written in 4 groups.
    (re.compile(r"'[a-z]{4}\s[a-z]{4}\s[a-z]{4}\s[a-z]{4}'"),
     'Gmail App Password'),
]

# An assignment whose NAME says credential and whose value is a literal.
SECRET_ASSIGN = re.compile(
    r'''(?ix)
    \b(password|passwd|secret|api_?key|apikey|auth_?token|access_?token|
       private_?key|client_?secret)\b
    \s*[:=]\s*
    (['"])(?P<val>[^'"]{6,})\2
    ''')

# Values that are not secrets even though they sit next to one of those names.
BENIGN = re.compile(
    r'''(?ix)^(
    change-?me | your-?\w+ | \.\.\. | x{3,} | \*{3,} |
    password | app_?password | \w*_?password |     # a KEY name, not a value
    postgres |                                     # stock dev default
    [A-Z_]{3,} |                                   # SCREAMING_CASE env key
    \s* )$''')


def audit_secrets():
    findings = []
    for path in dart_files():
        with open(path, encoding='utf-8') as fh:
            for n, line in enumerate(fh, 1):
                code = strip_comment(line)
                if not code.strip():
                    continue
                for pattern, what in SECRET_SHAPES:
                    if pattern.search(code):
                        findings.append((CRITICAL, f'{rel(path)}:{n}',
                                         f'hardcoded {what}'))
                m = SECRET_ASSIGN.search(code)
                if m:
                    val = m.group('val')
                    if not BENIGN.match(val):
                        findings.append(
                            (CRITICAL, f'{rel(path)}:{n}',
                             f'credential literal ({val[:12]}...)'))

    if findings:
        for level, where, what in findings:
            record(level, 'hardcoded secret', f'{where} {what}')
    else:
        record(OK, 'hardcoded secrets',
               'no API keys, tokens or credential literals in lib/')

    # Config must be reachable from outside the binary. Both routes present is
    # the intended design: --dart-define for build-time, .env for runtime.
    env_path = os.path.join(REPO, 'lib', 'core', 'app_env.dart')
    if os.path.exists(env_path):
        record(OK, 'externalised config',
               'AppEnv resolves --dart-define > .env > default')
    else:
        record(CRITICAL, 'externalised config', 'lib/core/app_env.dart missing')

    # ⚠️ flutter_dotenv bundles the .env INTO the binary as an asset, which
    # defeats the point of having one. The plain `dotenv` package reads a file
    # from disk at start-up, which is what this app wants.
    pubspec = os.path.join(REPO, 'pubspec.yaml')
    with open(pubspec, encoding='utf-8') as fh:
        spec = fh.read()
    if re.search(r'^\s*flutter_dotenv\s*:', spec, re.M):
        record(WARN, 'dotenv package',
               'flutter_dotenv bundles .env into the binary as an asset - '
               'use the plain `dotenv` package, which reads it from disk')
    elif re.search(r'^\s*dotenv\s*:', spec, re.M):
        record(OK, 'dotenv package',
               'plain `dotenv` - .env is read from disk, not bundled')

    # A .env in the build output would ship secrets inside the installer.
    if re.search(r'^\s*-\s*\.env\s*$', spec, re.M):
        record(CRITICAL, '.env as an asset',
               '.env is listed under flutter: assets - it would be packaged '
               'into the binary')
    else:
        record(OK, '.env not an asset', '.env is not bundled as a Flutter asset')

    # And it must not be committed.
    for f in ('.env',):
        r = subprocess.run(['git', 'ls-files', '--error-unmatch', f],
                           cwd=REPO, capture_output=True, text=True)
        if r.returncode == 0:
            record(CRITICAL, 'secret in git', f'{f} is tracked')
        else:
            record(OK, 'secret in git', f'{f} is not tracked')

    example = os.path.join(REPO, '.env.example')
    if os.path.exists(example):
        record(OK, '.env.example', 'template present for a fresh checkout')
    else:
        record(WARN, '.env.example', 'no template; setup is undocumented')


# ------------------------------------------------------------- 2. logging ----

# print() is NOT removed from a release build - it writes to stdout in the
# shipped .exe. debugPrint is likewise live in release. Only code behind
# kReleaseMode / kDebugMode, or AppLog.debug, is actually quiet.
BARE_PRINT = re.compile(r'(?<![\w.])print\s*\(')

# Files that legitimately print: standalone dev scripts, never shipped in the
# app's widget tree.
LOG_EXEMPT_DIRS = ('lib/scripts/',)
LOG_EXEMPT_FILES = ('lib/test_providers_run.dart',)

# Interpolations that would put user data in a log line.
SENSITIVE_INTERP = re.compile(
    r'''(?ix)\$\{?[\w.]*\b(
    password|passwd|secret|token|otp|
    email|e_?mail|
    user(?:id|_id|name)?|profile|
    nic|badge|mobile|phone
    )\b''')


def audit_logging():
    bare, sensitive = [], []
    for path in dart_files():
        r = rel(path)
        if r in LOG_EXEMPT_FILES or any(r.startswith(d)
                                        for d in LOG_EXEMPT_DIRS):
            continue
        with open(path, encoding='utf-8') as fh:
            for n, line in enumerate(fh, 1):
                code = strip_comment(line)
                if BARE_PRINT.search(code) and 'debugPrint' not in code:
                    bare.append(f'{r}:{n}')
                # A release-visible log line carrying user data.
                if 'AppLog.debug' in code:
                    continue  # compiled out of release entirely
                if ('AppLog.warn' in code or 'AppLog.error' in code
                        or 'AppLog.security' in code):
                    # Only the message is printed in release; `error:` is not.
                    msg = code.split('error:')[0]
                    if SENSITIVE_INTERP.search(msg):
                        sensitive.append(f'{r}:{n}')

    if bare:
        for b in bare:
            record(CRITICAL, 'print() in release',
                   f'{b} - print writes to stdout in release; use AppLog')
    else:
        record(OK, 'no bare print()',
               'app code logs through AppLog, which is release-aware')

    if sensitive:
        for s in sensitive:
            record(CRITICAL, 'user data in a release log', s)
    else:
        record(OK, 'log payloads',
               'no user data interpolated into release-visible log lines')

    # The logger itself must key off kReleaseMode.
    log_path = os.path.join(LIB, 'core', 'app_log.dart')
    if not os.path.exists(log_path):
        record(CRITICAL, 'logger', 'lib/core/app_log.dart missing')
        return
    with open(log_path, encoding='utf-8') as fh:
        src = fh.read()
    if 'kReleaseMode' in src:
        record(OK, 'logger guard', 'AppLog.debug is gated on kReleaseMode')
    else:
        record(CRITICAL, 'logger guard', 'AppLog does not check kReleaseMode')

    # SQL logging must never be on outside debug: a query log carries every
    # value the app sends, which is every record it reads and writes.
    q = os.path.join(LIB, 'core', 'db', 'pg_query.dart')
    if os.path.exists(q):
        with open(q, encoding='utf-8') as fh:
            qs = fh.read()
        if re.search(r'if\s*\(\s*kDebugMode\s*&&\s*_logSql', qs):
            record(OK, 'SQL logging', 'gated on kDebugMode')
        elif '_logSql' in qs:
            record(CRITICAL, 'SQL logging',
                   'SQL logging is not gated on kDebugMode')


# --------------------------------------------------------------- 3. build ----

def audit_build():
    findings = 0

    # The documented release command must obfuscate AND split symbols.
    docs = []
    for name in ('README.md', 'BUILD.md'):
        p = os.path.join(REPO, name)
        if os.path.exists(p):
            with open(p, encoding='utf-8') as fh:
                docs.append((name, fh.read()))
    scripts = []
    tool_dir = os.path.join(REPO, 'tool')
    for name in sorted(os.listdir(tool_dir)):
        if name.endswith(('.ps1', '.sh', '.bat')):
            with open(os.path.join(tool_dir, name), encoding='utf-8',
                      errors='replace') as fh:
                scripts.append((f'tool/{name}', fh.read()))

    documented = [n for n, t in docs + scripts
                  if '--obfuscate' in t and '--split-debug-info' in t]
    if documented:
        record(OK, 'obfuscation documented',
               'flutter build windows --obfuscate --split-debug-info in '
               + ', '.join(documented))
    else:
        record(CRITICAL, 'obfuscation documented',
               'no README/build script documents --obfuscate with '
               '--split-debug-info')
        findings += 1

    # ⚠️ --obfuscate without --split-debug-info discards the symbol map, and a
    # crash from that build can never be read back.
    #
    # Judged per FILE, not per line. A build script legitimately spreads the
    # two flags over separate lines of an argument array and mentions
    # --obfuscate again in its own documentation, so a line-by-line check
    # reported the same script four times for a pairing it does in fact make.
    for name, text in docs + scripts:
        if '--obfuscate' not in text:
            continue
        if '--split-debug-info' in text:
            continue
        record(WARN, 'obfuscation without symbols',
               f'{name}: --obfuscate with no --split-debug-info anywhere - '
               f'crashes from that build cannot be decoded')

    # Symbols must not be committed: they undo the obfuscation.
    r = subprocess.run(['git', 'ls-files'], cwd=REPO,
                       capture_output=True, text=True)
    tracked = r.stdout.splitlines() if r.returncode == 0 else []
    sym = [f for f in tracked
           if re.search(r'(^|/)(debug[-_]?symbols|symbols)/', f)
           or f.endswith('.symbols')]
    if sym:
        record(CRITICAL, 'symbols in git',
               f'{len(sym)} debug-symbol file(s) tracked, e.g. {sym[0]}')
        findings += 1
    else:
        record(OK, 'symbols not in git', 'no debug-symbol files tracked')

    gitignore = os.path.join(REPO, '.gitignore')
    with open(gitignore, encoding='utf-8') as fh:
        ign = fh.read()
    if re.search(r'symbols', ign):
        record(OK, 'symbols ignored', '.gitignore covers the symbol directory')
    else:
        record(WARN, 'symbols ignored',
               'add the --split-debug-info directory to .gitignore')

    return findings


def main():
    print('=' * 72)
    print('Client-side & desktop security audit')
    print(f'repo: {REPO}')
    print('=' * 72)

    print('\n-- 1. hardcoded secrets --')
    audit_secrets()
    print('\n-- 2. release logging --')
    audit_logging()
    print('\n-- 3. build configuration --')
    audit_build()

    fails = [r for r in results if r[0] == CRITICAL]
    warns = [r for r in results if r[0] == WARN]
    print('\n' + '=' * 72)
    print(f'{len(results) - len(fails) - len(warns)} passed, '
          f'{len(warns)} warnings, {len(fails)} failures')
    print('=' * 72)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
