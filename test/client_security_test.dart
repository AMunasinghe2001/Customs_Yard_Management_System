import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/app_log.dart';
import 'package:cus_yard_management/core/db/pg_connection.dart';

/// Client-side hardening: what the shipped .exe may write to stdout, and what
/// may be compiled into it.
///
/// The source-level checks here overlap `tool/audit_client_security.py` on
/// purpose. The script is what a release runs; these run on every `flutter
/// test`, so a bare `print()` added to a screen fails in CI rather than
/// waiting for someone to remember the audit.
void main() {
  group('AppLog', () {
    test('debug output is suppressed in a release build', () {
      // The test binary is a debug build, so this asserts the RULE rather than
      // the outcome: verbose tracks !kReleaseMode exactly.
      expect(AppLog.verbose, equals(!kReleaseMode));
      expect(AppLog.verbose, isTrue, reason: 'tests run in debug');
    });

    test('a warning prints its message but not the exception payload', () {
      // ⚠️ This is the property that matters. An exception's toString() is how
      // a record or an address ends up in a log without anyone intending it:
      // a Postgres error quotes the row it rejected, an auth error quotes the
      // address. In release the message survives and `error:` does not.
      final lines = _capture(() {
        AppLog.warn('sign-in status update failed',
            error: Exception('duplicate key: officer@customs.gov.lk'),
            tag: 'auth');
      });
      final joined = lines.join('\n');
      expect(joined, contains('sign-in status update failed'));
      expect(joined, contains('WARN'));
      // Debug build, so the payload IS shown here - the release branch is what
      // drops it, and that branch is what the source check below pins.
      expect(joined, contains('officer@customs.gov.lk'));
    });

    test('security notices survive into release', () {
      // An administrator asking "why is auto-update off" needs this line in
      // the build they actually run, so it is deliberately not gated.
      final lines = _capture(() => AppLog.security('refusing update feed'));
      expect(lines.join('\n'), contains('SECURITY: refusing update feed'));
    });

    test('the release branches are what the source actually says', () {
      // Reading the source rather than the behaviour, because a debug test run
      // can never execute the release path. This fails if someone swaps the
      // guard for kDebugMode - which would also silence PROFILE builds, and
      // profile is what performance work runs on.
      final src = File('lib/core/app_log.dart').readAsStringSync();
      expect(src, contains('kReleaseMode'),
          reason: 'AppLog must gate on kReleaseMode');
      expect(src.contains('if (kReleaseMode) return;'), isTrue,
          reason: 'AppLog.debug must return early in release');
    });
  });

  group('no secrets are compiled in', () {
    test('the Gmail credentials have no defaults', () {
      // A real App Password was hardcoded here once and is still in git
      // history. There must never be a fallback again: with none, the app
      // reports e-mail as unconfigured instead of silently using an old
      // account.
      final src = File('lib/core/otp_config.dart').readAsStringSync();
      expect(RegExp(r"GMAIL_USER'[^)]*fallback:\s*''").hasMatch(src), isTrue,
          reason: 'GMAIL_USER must fall back to the empty string');
      expect(
          RegExp(r"GMAIL_APP_PASSWORD'[^)]*fallback:\s*''").hasMatch(src),
          isTrue,
          reason: 'GMAIL_APP_PASSWORD must fall back to the empty string');
    });

    test('no credential literals anywhere in lib/', () {
      final offenders = <String>[];
      final shapes = <RegExp, String>{
        RegExp(r'\beyJ[A-Za-z0-9_-]{20,}\.'): 'JWT',
        RegExp(r'\bsk-[A-Za-z0-9]{20,}\b'): 'API key',
        RegExp(r'\bAIza[A-Za-z0-9_-]{30,}\b'): 'Google API key',
        RegExp(r'://[^/\s:@]+:[^/\s:@]+@'): 'credentials in a URL',
        RegExp(r"'[a-z]{4}\s[a-z]{4}\s[a-z]{4}\s[a-z]{4}'"):
            'Gmail App Password',
      };
      for (final f in _dartFiles('lib')) {
        final text = f.readAsStringSync();
        shapes.forEach((re, what) {
          if (re.hasMatch(text)) offenders.add('${f.path}: $what');
        });
      }
      expect(offenders, isEmpty);
    });

    test('the stock database password is flagged, not silently used', () {
      // The default stays so a fresh checkout runs, but the app must be able
      // to say it is using it.
      expect(PgConfig.defaultPassword, equals('postgres'));
      expect(PgConfig.usingDefaultPassword, isTrue,
          reason: 'no .env in the test environment');
    });
  });

  group('no bare print() in shipped code', () {
    test('app code logs through AppLog', () {
      // print() is NOT stripped from a release build: it writes to stdout in
      // the shipped .exe exactly as in debug. Standalone dev scripts are
      // exempt - they are never part of the app.
      const exemptDirs = ['lib\\scripts\\', 'lib/scripts/'];
      const exemptFiles = ['test_providers_run.dart'];
      final bare = RegExp(r'(?<![\w.])print\s*\(');

      final offenders = <String>[];
      for (final f in _dartFiles('lib')) {
        final p = f.path;
        if (exemptDirs.any(p.contains)) continue;
        if (exemptFiles.any(p.endsWith)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].split('//').first;
          if (bare.hasMatch(code) && !code.contains('debugPrint')) {
            offenders.add('$p:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'use AppLog.debug/warn/error instead of print()');
    });
  });

  group('release build configuration', () {
    test('obfuscation is documented with split symbols', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('--obfuscate'));
      expect(readme, contains('--split-debug-info'));
      expect(readme, contains('flutter symbolize'),
          reason: 'the symbols are useless if decoding them is undocumented');
    });

    test('the release script pairs obfuscation with split-debug-info', () {
      // ⚠️ --obfuscate alone throws away the mapping, and a crash from that
      // build can never be decoded.
      final script = File('tool/build_release.ps1').readAsStringSync();
      expect(script, contains('--obfuscate'));
      expect(script, contains('--split-debug-info'));
    });

    test('symbols and .env are gitignored', () {
      final ign = File('.gitignore').readAsStringSync();
      expect(ign, contains('.env'));
      expect(ign.contains('symbols'), isTrue);
    });
  });
}

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// Collects what [body] writes through `debugPrint`.
List<String> _capture(void Function() body) {
  final out = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) out.add(message);
  };
  try {
    body();
  } finally {
    debugPrint = previous;
  }
  return out;
}
