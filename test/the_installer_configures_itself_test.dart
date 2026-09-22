// Zero-configuration install: the officer runs the setup and signs in.
//
// ⚠️ The credential must NOT be in the source tree. It is compiled in at
// build time (--dart-define) and written into the .env the installer
// creates, both of which ship — but a literal here would go into git, and
// this project already carries one such mistake (the Gmail App Password in
// commit 875e445) that still needs revoking.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final iss = File('installer/setup.iss').readAsStringSync();
  final pg = File('lib/core/db/pg_connection.dart').readAsStringSync();

  group('no password is committed', () {
    test('pg_connection.dart reads the database password from the build', () {
      expect(pg, contains("String.fromEnvironment('PG_CLOUD_PASSWORD')"));
    });

    test('and defines no default for it', () {
      // ⚠️ THE TEST THAT MATTERS. A `defaultValue:` on that line is a
      // password in git. The other office settings may have defaults —
      // a hostname is not a secret — but this one may not.
      final m = RegExp(r"String\.fromEnvironment\(\s*'PG_CLOUD_PASSWORD'[^)]*\)")
          .firstMatch(pg);
      expect(m, isNotNull);
      expect(m!.group(0), isNot(contains('defaultValue')),
          reason: 'a default here would commit the database password');
    });

    test('setup.iss takes it as a compile-time define', () {
      expect(iss, contains('#ifndef DbPassword'));
      expect(iss, contains('#define DbPassword ""'));
    });
  });

  group('the installer writes a usable .env', () {
    test('only on a first install', () {
      // ⚠️ An existing .env is how a branch points at its own server.
      // Overwriting it on upgrade would silently move them back.
      expect(iss, contains('if FileExists(Path) then'));
      expect(iss, contains('CurStepChanged'));
      expect(iss, contains('ssPostInstall'));
    });

    test('and writes nothing when no password was compiled in', () {
      // Better to leave the officer with the template flow than with a
      // .env holding an empty password, which fails as "authentication
      // failed" and sends them to the server.
      expect(iss, contains("Pw := '{#DbPassword}';"));
      expect(iss, contains("if Pw = '' then"));
    });

    test('the password is quoted', () {
      // ⚠️ dotenv treats an unquoted # as a comment, so a password
      // containing one is silently truncated.
      expect(iss, contains(r"""'PG_PASSWORD="' + Pw + '"'"""));
    });

    test('TLS is VERIFIED, not merely on', () {
      // ⚠️ The connection crosses the public internet. PG_SSL alone
      // encrypts but accepts ANY certificate, so anything on the path
      // could present its own and read every query in clear.
      expect(iss, contains("'PG_SSL=true'"));
      expect(iss, contains("'PG_SSL_VERIFY=true'"));
    });

    test('and it names the CA the pooler is signed by', () {
      // ⚠️ Supabase's own root is not in the Windows trust store.
      // Without this a verified connection fails as "Bad server
      // certificate" -- whose tempting fix throws the protection away.
      expect(iss, contains('PG_SSL_ROOT_CERT=supabase-root-2021.crt'));
      expect(iss, contains(r'certs\supabase-root-2021.crt'),
          reason: 'the .crt must also SHIP, or the path points at nothing');
    });

    test('it points at the session pooler, not the direct host', () {
      // ⚠️ db.<ref>.supabase.co is IPv6-ONLY and unreachable from most
      // Sri Lankan networks; it fails as "Network is unreachable", which
      // reads like a dead server.
      expect(iss, contains('pooler.supabase.com'));
      expect(iss, isNot(contains('db.knqpwufqpcoevjaxuihp.supabase.co')));
    });
  });

  group('the build folder is not swept into the installer', () {
    test('.env is excluded from the wildcard copy', () {
      // ⚠️ `flutter run` leaves the DEVELOPER'S .env in the Release
      // folder. Without this exclusion every officer received it —
      // verified by installing a build and reading the .env it produced:
      // the developer's database password AND the live Gmail App Password,
      // with the app pointed at localhost.
      final line = iss
          .split('\n')
          .firstWhere((l) => l.contains('{#BuildDir}'), orElse: () => '');
      expect(line, isNotEmpty);
      expect(line, contains('Excludes:'));
      expect(line, contains('.env'));
    });
  });

  group('the office defaults sit below a .env', () {
    test('every setting still reads the .env first', () {
      // The whole point of the precedence chain: one build works against
      // the office server, a backup and Supabase.
      for (final key in const [
        "AppEnv.read('PG_HOST'",
        "AppEnv.readInt('PG_PORT'",
        "AppEnv.read('PG_DATABASE'",
        "AppEnv.read('PG_USER'",
        "AppEnv.read('PG_PASSWORD'",
        "AppEnv.readBool('PG_SSL'",
      ]) {
        expect(pg, contains(key));
      }
    });

    test('they apply only when a password was compiled in', () {
      // ⚠️ Without this a developer checkout would silently try the office
      // server instead of localhost.
      expect(pg, contains('hasBuiltInCredentials'));
      expect(pg, contains("hasBuiltInCredentials ? _cloudHostDefine : 'localhost'"));
    });

    test('the start-up banner says when nothing but the build configured it',
        () {
      // "built-in" and "read a .env I cannot find" otherwise produce the
      // same connection string, and the difference is the diagnosis.
      expect(pg, contains('[built-in]'));
    });
  });

  group('a stale .env is replaced, a deliberate one is not', () {
    test('an upgrade replaces a .env still pointing at loopback', () {
      // ⚠️ An old installer swept the DEVELOPER'S .env into the
      // package, so installed copies carried PG_HOST=localhost and a
      // revoked Gmail password. No officer PC runs its own PostgreSQL,
      // so loopback in an installed copy is never a choice anybody
      // made -- and the app cannot connect at all.
      expect(iss, contains('EnvLooksStale'));
      expect(iss, contains("HostVal = 'localhost'"));
      expect(iss, contains("HostVal = '127.0.0.1'"));
    });

    test('but a .env naming a real server is left alone', () {
      // ⚠️ THE POINT OF THE CHECK. A .env is how a machine is aimed
      // at a local copy, a backup or a test database. Overwriting
      // every one on upgrade would re-point those with nothing said.
      expect(iss, contains('if not EnvLooksStale(Path) then'));
      expect(iss, contains('Exit;'));
    });

    test('the replaced file is kept, not discarded', () {
      // It may hold a password nobody else has a copy of. Renaming
      // costs nothing and makes the change reversible.
      expect(iss, contains('.replaced-by-setup'));
      expect(iss, contains('RenameFile(Path, Backup)'));
    });
  });

  group('uninstalling leaves nothing behind', () {
    // ⚠️ Not tidiness. A stale .env left in place is what made an
    // installed copy keep reaching for localhost long after the build
    // carried the right settings -- so "uninstall and reinstall", the
    // first thing anybody tries, fixed nothing.
    final start = iss.indexOf('[UninstallDelete]');
    final block = iss.substring(start, iss.indexOf('[Code]', start));

    test('the .env and its backup go', () {
      expect(block, contains(r'{app}\.env"'));
      expect(block, contains(r'{app}\.env.replaced-by-setup"'));
    });

    test('every log goes, by wildcard', () {
      // So a log added later does not need this revisited.
      expect(block, contains(r'{app}\*.log"'));
    });

    test('the data tree goes', () {
      // It holds shipped assets only -- the officer's records are in
      // PostgreSQL and the app's own logs are under %APPDATA%.
      expect(block, contains('filesandordirs'));
      expect(block, contains(r'{app}\data"'));
    });

    test('the folder itself goes ONLY if it is empty', () {
      // ⚠️ `dirifempty`, never a blanket wildcard: an export somebody
      // saved beside the program must survive. An uninstaller has no
      // business deleting files it did not create.
      expect(block, contains('Type: dirifempty; Name: "{app}"'));
      expect(block, isNot(contains(r'Type: filesandordirs; Name: "{app}"')),
          reason: 'that would take the user\'s own files with it');
    });
  });

  group('an upgrade over a running app', () {
    final cpp = File('windows/runner/main.cpp').readAsStringSync();

    test('the app publishes a mutex the installer can see', () {
      // ⚠️ Windows locks a running process's DLLs. Without this the
      // install died partway through with
      //
      //     auto_updater_windows_plugin.dll
      //     DeleteFile failed; code 5. Access is denied.
      //
      // and offered "Skip this file (not recommended)", which leaves a
      // half-updated install: a new .exe beside an old plugin.
      expect(cpp, contains('CreateMutexW'));
      expect(iss, contains('AppMutex='));
    });

    test('and the two names agree exactly', () {
      // ⚠️ A typo here is silent: Setup simply never finds the mutex
      // and the old failure comes back.
      final m = RegExp(r'CreateMutexW\([^,]+,[^,]+,\s*L"([^"]+)"')
          .firstMatch(cpp);
      final n = RegExp(r'^AppMutex=(.+)$', multiLine: true)
          .firstMatch(iss);
      expect(m, isNotNull, reason: 'no CreateMutexW in main.cpp');
      expect(n, isNotNull, reason: 'no AppMutex in setup.iss');
      // C++ escapes the backslash; Inno takes the name raw.
      final fromCpp = m!.group(1)!.replaceAll('\\\\', '\\');
      expect(fromCpp, n!.group(1)!.trim());
    });

    test('it is a Global mutex, not session-local', () {
      // An app left running under ANOTHER logged-in account locks the
      // files just the same.
      expect(cpp, contains('Global' + '\\\\'));
    });

    test('Setup closes the app itself and restarts it', () {
      expect(iss, contains('CloseApplications=force'));
      expect(iss, contains('RestartApplications=yes'));
    });
  });

  group('the operator has what they need', () {
    test('the Application Control note exists', () {
      final f = File('installer/README_WINDOWS_POLICIES.md');
      expect(f.existsSync(), isTrue);
      final md = f.readAsStringSync();
      expect(md, contains('4551'));
      expect(md, contains('AppLocker'));
      // ⚠️ One-way door; it must be written down next to the advice.
      expect(md, contains('cannot be turned back on'));
    });

    test('the Supabase bucket script is Supabase-only', () {
      // ⚠️ NOT part of install_all.ps1: local and office servers are
      // plain PostgreSQL with no `storage` schema, so every statement in
      // it would fail there.
      final f = File('postgres/supabase_updates_bucket.sql');
      expect(f.existsSync(), isTrue);
      final sql = f.readAsStringSync();
      expect(sql, contains('SUPABASE SQL EDITOR'));
      expect(sql, contains('NOT PART OF install_all.ps1'));
    });
  });
}
