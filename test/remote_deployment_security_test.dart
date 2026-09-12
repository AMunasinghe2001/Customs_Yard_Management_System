import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/db/connection_health.dart';
import 'package:cus_yard_management/core/db/pg_connection.dart';

/// Deploying over the public internet: a static IP, port forwarding, and
/// branch PCs that are no longer on the office LAN.
void main() {
  group('PG_HOST survives what people actually paste', () {
    // The normaliser is private; it is exercised through the public `host`
    // getter by setting the value the same way a .env would.
    String norm(String raw) {
      // ignore: invalid_use_of_visible_for_testing_member
      return PgConfig.debugNormaliseHost(raw);
    }

    test('a plain domain or IP is untouched', () {
      expect(norm('db.customs.gov.lk'), 'db.customs.gov.lk');
      expect(norm('203.0.113.10'), '203.0.113.10');
      expect(norm('localhost'), 'localhost');
    });

    test('whitespace and a blank value fall back rather than fail', () {
      // ⚠️ `PG_HOST=` (set but empty) must behave like "not set". Left as an
      // empty string it reaches the resolver and fails as a host lookup,
      // which reads like the server is down.
      expect(norm('  203.0.113.10  '), '203.0.113.10');
      expect(norm(''), 'localhost');
      expect(norm('   '), 'localhost');
    });

    test('a scheme, a port or a path is trimmed off', () {
      // These are what a branch office pastes out of pgAdmin or a browser.
      expect(norm('postgres://203.0.113.10'), '203.0.113.10');
      expect(norm('203.0.113.10:5432'), '203.0.113.10');
      expect(norm('db.customs.gov.lk:5432'), 'db.customs.gov.lk');
      expect(norm('postgres://db.customs.gov.lk:5432/Customs_SR_DB'),
          'db.customs.gov.lk');
      expect(norm('postgres://user:pw@db.customs.gov.lk:5432/x'),
          'db.customs.gov.lk');
    });

    test('a bare IPv6 literal is bracketed, not chopped', () {
      // ⚠️ Stripping at the first colon would leave a fragment that resolves
      // to nothing. Several colons means IPv6, not host:port.
      expect(norm('::1'), '[::1]');
      expect(norm('2001:db8::1'), '[2001:db8::1]');
    });

    test('an already-bracketed literal keeps its brackets', () {
      expect(norm('[::1]'), '[::1]');
      expect(norm('[2001:db8::1]:5432'), '[2001:db8::1]');
    });
  });

  group('the transport policy names the real risk', () {
    test('loopback without TLS is not a finding', () {
      // The traffic never leaves the machine, so there is no wire to tap.
      //
      // ⚠️ Asks the RULE about a value, not the machine's current `.env`.
      // Requiring `PgConfig.isLoopbackHost` made this a test of whichever
      // server the developer was pointed at, so naming a real deployment in
      // the .env reported a config change as a security regression.
      expect(PgConfig.debugIsLoopback('localhost'), isTrue);
      expect(PgConfig.debugIsLoopback('127.0.0.1'), isTrue);
      expect(PgConfig.debugIsLoopback('10.10.71.15'), isFalse,
          reason: 'a LAN address is a network hop, however short');
    });
  });

  group('the CA certificate is loadable and reported', () {
    tearDown(PgConfig.resetSecurityContextCache);

    test('no path means the OS trust store', () {
      // Correct when the certificate comes from a real CA on a domain.
      expect(PgConfig.sslRootCertPath, isEmpty);
      expect(PgConfig.resolvedSslRootCertPath, isNull);
      expect(PgConfig.sslRootCertProblem, isNull);
      expect(PgConfig.securityContext, isNull);
    });

    test('a missing file is a stated problem, not a silent downgrade', () {
      // ⚠️ Without this the app falls back to the OS trust store,
      // verification fails against a self-signed office certificate, and the
      // error names the TLS handshake rather than the file that is wrong.
      final src = File('lib/core/db/pg_connection.dart').readAsStringSync();
      expect(src, contains('which does not exist'));
      expect(src, contains('final certProblem = sslRootCertProblem;'),
          reason: 'the startup policy must surface it');
    });

    test('the context is threaded into BOTH settings objects', () {
      // The app runs on a pool; a context on the single-connection settings
      // alone would leave every pooled connection unverified.
      final src = File('lib/core/db/pg_connection.dart').readAsStringSync();
      expect('securityContext: securityContext'.allMatches(src).length, 2,
          reason: 'pool settings and connection settings both need it');
    });

    test('it is built once, not on every connection open', () {
      // The pool opens a fresh connection whenever it grows or retires one.
      final src = File('lib/core/db/pg_connection.dart').readAsStringSync();
      expect(src, contains('static bool _contextBuilt = false;'));
    });

    test('a relative path resolves beside the executable', () {
      // So `PG_SSL_ROOT_CERT=ca.crt` works on an installed copy, wherever it
      // happens to be launched from.
      final src = File('lib/core/db/pg_connection.dart').readAsStringSync();
      expect(src, contains('Platform.resolvedExecutable'));
    });
  });

  group('a branch PC is told when its link drops', () {
    setUp(ConnectionHealth.reportSuccess);
    tearDown(ConnectionHealth.reportSuccess);

    test('it starts online', () {
      expect(ConnectionHealth.offline.value, isFalse);
      expect(ConnectionHealth.lastReason.value, isNull);
    });

    test('a transport failure raises the banner, a success clears it', () {
      ConnectionHealth.reportOffline('x');
      expect(ConnectionHealth.offline.value, isTrue);
      ConnectionHealth.reportSuccess();
      expect(ConnectionHealth.offline.value, isFalse);
      expect(ConnectionHealth.lastReason.value, isNull);
    });

    test('the reason names whose fault it is', () {
      // ⚠️ The distinction that matters to an officer is whether the problem
      // is their own internet or the office end — they can act on the first.
      expect(ConnectionHealth.describe(Exception('Failed host lookup: x')),
          contains('no internet connection'));
      expect(ConnectionHealth.describe(Exception('Connection timed out')),
          contains('did not respond'));
      expect(ConnectionHealth.describe(Exception('Connection refused')),
          contains('refused'));
      expect(
          ConnectionHealth.describe(Exception('CERTIFICATE_VERIFY_FAILED')),
          contains('contact ICT'));
    });

    test('only TRANSPORT failures raise it', () {
      // A permission denial is the database ANSWERING — the link is fine, and
      // blaming the network would send an officer to check their router over
      // a bug in the app.
      final src = File('lib/services/services.dart').readAsStringSync();
      expect(src, contains('if (transient) ConnectionHealth.reportOffline('));
    });

    test('success is reported once, in the shared retry helper', () {
      // 228 call sites go through it; the banner cannot be kept honest by
      // asking each of them to remember.
      final src = File('lib/services/services.dart').readAsStringSync();
      expect('ConnectionHealth.reportSuccess()'.allMatches(src).length, 1);
    });

    test('the banner is mounted above the lock screen', () {
      // A PC that drops its link while unattended should say so when someone
      // comes back to it.
      final src = File('lib/main.dart').readAsStringSync();
      final b = src.indexOf('OfflineBanner(');
      final l = src.indexOf('IdleLockOverlay(');
      expect(b, greaterThan(-1));
      expect(b, lessThan(l), reason: 'the banner must wrap the lock, not sit '
          'inside it');
    });
  });
}
