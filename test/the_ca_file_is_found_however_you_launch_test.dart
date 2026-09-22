// The CA file must be found whatever launched the app.
//
// ⚠️ THE BUG: `PG_SSL_ROOT_CERT` is a relative name, and the resolver looked
// only beside the .exe. That covers an INSTALLED copy, where the .crt sits
// next to the executable — but not `flutter run`, where the .exe lives in
// build\windows\...\Debug while the working directory is the project root.
//
// The fallback was the bare relative path, so whether TLS worked came down
// to the working directory: the same build connected from one launcher and
// failed from another with only "Bad server certificate" to go on — a
// message that names TLS and says nothing about a missing file.
import 'dart:io';

import 'package:cus_yard_management/core/db/pg_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the CA file is found however you launch', () {
    test('a configured certificate RESOLVES to a file that exists', () {
      // The invariant that matters. If a CA is configured at all, it must
      // land on a real file — otherwise `securityContext` silently falls
      // back to the OS trust store and verification fails against
      // Supabase's private CA.
      if (PgConfig.sslRootCertPath.trim().isEmpty) return; // none configured
      final resolved = PgConfig.resolvedSslRootCertPath;
      expect(resolved, isNotNull);
      expect(File(resolved!).existsSync(), isTrue,
          reason: 'PG_SSL_ROOT_CERT resolved to "$resolved", which is not on '
              'disk — TLS will fail with "Bad server certificate"');
      expect(PgConfig.sslRootCertProblem, isNull);
      expect(PgConfig.securityContext, isNotNull,
          reason: 'the file exists but no SecurityContext was built');
    });

    test('the resolver tries more than just the exe folder', () {
      // ⚠️ Source-level, because the launch shapes cannot all be simulated
      // from one test run: `flutter test` has no app .exe at all
      // (resolvedExecutable is the Dart VM in the SDK cache), so the
      // exe-folder branch can never succeed here.
      final src = File('lib/core/db/pg_connection.dart').readAsStringSync();
      final i = src.indexOf('resolvedSslRootCertPath');
      final body = src.substring(i, src.indexOf('\n  }', i));
      expect(body, contains('Directory.current.path'),
          reason: 'the working directory is where `flutter run` finds it');
      expect(body, contains('runner'),
          reason: 'the debug build output is where the .exe actually is');
      expect(body, contains('existsSync()'),
          reason: 'candidates must be TESTED, not just listed');
    });

    test('an unfound certificate is reported, not silently ignored', () {
      // ⚠️ The dangerous failure is a SILENT fallback to the OS trust
      // store: the connection then fails on a private CA and the error
      // names TLS rather than the missing file.
      final src = File('lib/core/db/pg_connection.dart').readAsStringSync();
      expect(src, contains('does not exist'),
          reason: 'sslRootCertProblem must name the missing path');
    });
  });
}
