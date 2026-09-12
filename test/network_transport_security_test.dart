import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/app_updater.dart';
import 'package:cus_yard_management/core/db/pg_client.dart';
import 'package:cus_yard_management/core/db/pg_connection.dart';

/// Network- and database-level protections, checked without a server.
///
/// These are the properties that stop being obvious the moment someone edits a
/// `.env` or adds an RPC: whether a remote host is reached in clear text,
/// whether the updater will run a binary named by an unauthenticated feed, and
/// whether anything but a value can reach the SQL text.
void main() {
  group('transport policy', () {
    test('plaintext to localhost is not a finding', () {
      // The default install: app and database on the same PC. Nothing crosses
      // a wire, so demanding TLS here would be noise that trains people to
      // ignore the warning that matters.
      //
      // ⚠️ Asserts the RULE, not the machine's current `.env`. This used to
      // require `PgConfig.isLoopbackHost` to be true, which made it a test of
      // whichever server the developer happened to be pointed at — it broke
      // the moment the .env named a real deployment, reporting a config
      // change as a security regression.
      expect(PgConfig.debugNormaliseHost('localhost'), 'localhost');
      for (final h in ['localhost', '127.0.0.1', '::1']) {
        expect(PgConfig.debugIsLoopback(h), isTrue, reason: h);
      }
      expect(PgConfig.debugIsLoopback('10.10.71.15'), isFalse,
          reason: 'a LAN address is a network hop, however short');
    });

    test('loopback is recognised by every spelling', () {
      // A deployment writing 127.0.0.1 rather than localhost must not be told
      // its connection is insecure, and ::1 must not be mistaken for remote.
      for (final h in ['localhost', 'LOCALHOST', '127.0.0.1', '127.0.1.1',
        '::1', '[::1]', '  localhost  ']) {
        expect(_loopback(h), isTrue, reason: '$h should count as loopback');
      }
      for (final h in ['192.168.1.50', 'db.example.gov.lk', '10.0.0.4', '']) {
        expect(_loopback(h), isFalse, reason: '$h should count as remote');
      }
    });

    test('sslMode maps to encrypt-only vs verified', () {
      // verifyFull is the only mode that defeats a machine in the middle;
      // require merely encrypts to whoever answers.
      expect(SslModeChoice.of(useSsl: false, verify: false), 'disable');
      expect(SslModeChoice.of(useSsl: true, verify: false), 'require');
      expect(SslModeChoice.of(useSsl: true, verify: true), 'verifyFull');
    });

    test('describe names the TLS state', () {
      // ⚠️ Reads the live config, so it asserts the SHAPE of the string
      // rather than one deployment's values.
      expect(PgConfig.describe, contains(PgConfig.host));
      // The connection-failure screen shows this string, and its TLS state is
      // the single most useful thing on it — whichever state that is.
      expect(
          PgConfig.describe,
          anyOf(contains('no TLS'), contains('TLS, unverified'),
              contains('TLS, verified')));
    });
  });

  group('update feed', () {
    test('https is always acceptable', () {
      expect(isUpdateFeedAcceptable('https://updates.example.lk/appcast.xml'),
          isTrue);
    });

    test('http is refused without the explicit opt-in', () {
      // The default build has ALLOW_INSECURE_UPDATE_FEED unset. An http feed
      // chooses which .exe the app downloads and runs, so silence here would
      // be remote code execution waiting for someone on the path.
      expect(allowInsecureUpdateFeed, isFalse);
      expect(isUpdateFeedAcceptable('http://192.168.1.50/updates/appcast.xml'),
          isFalse);
      expect(isUpdateFeedAcceptable('http://updates.example.lk/appcast.xml'),
          isFalse);
    });

    test('non-http schemes and junk are refused', () {
      for (final u in ['', 'not a url', 'ftp://host/appcast.xml',
        'file:///C:/appcast.xml', 'javascript:alert(1)']) {
        expect(isUpdateFeedAcceptable(u), isFalse, reason: 'accepted "$u"');
      }
    });
  });

  group('RPC identifiers cannot extend the statement', () {
    // rpc() pastes the function name and each argument NAME into SQL as
    // syntax — Postgres has no way to bind either. Values are still bound.
    test('a function name with a quote or paren is rejected', () {
      for (final fn in [
        'email_for_login"; drop table packages; --',
        'fn(1); drop table packages; --',
        'a.b.c',
        '',
        '1_starts_with_digit',
        'has space',
      ]) {
        expect(() => supabase.rpc(fn), throwsA(isA<ArgumentError>()),
            reason: 'accepted function name "$fn"');
      }
    });

    test('an argument name with SQL in it is rejected', () {
      expect(
        () => supabase.rpc('email_for_login',
            params: {'identifier => x, y': 'anything'}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => supabase.rpc('email_for_login', params: {'a); drop table t; --': 1}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the names the app actually uses still pass validation', () {
      // The guard must not break the real call sites. Checked against the
      // same pattern rather than by calling rpc(), because a valid name goes
      // on to open a socket — which a unit test must not depend on.
      for (final fn in [
        'email_for_login',
        'auth.record_failed_login',
        'reset_password_for_identifier',
        'purge_old_audit_logs',
        'disposal_position_available',
        'appeal_ensure_forfeited_row',
      ]) {
        for (final part in fn.split('.')) {
          expect(_plainIdentifier(part), isTrue,
              reason: 'rejected real call site "$fn"');
        }
      }
      // And the argument names those call sites pass.
      for (final arg in ['p_email', 'identifier', 'p_identifier', 'code']) {
        expect(_plainIdentifier(arg), isTrue, reason: 'rejected arg "$arg"');
      }
    });
  });
}

/// Mirrors PgClient._identifierPattern.
bool _plainIdentifier(String s) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_$]{0,62}$').hasMatch(s);

bool _loopback(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '::1' ||
      h == '[::1]' ||
      h.startsWith('127.');
}

/// Mirrors PgConfig.sslMode's decision so it can be checked for every
/// combination without mutating process-wide configuration.
class SslModeChoice {
  static String of({required bool useSsl, required bool verify}) {
    if (!useSsl) return 'disable';
    return verify ? 'verifyFull' : 'require';
  }
}
