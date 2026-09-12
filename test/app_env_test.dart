import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/app_env.dart';
import 'package:cus_yard_management/core/db/pg_connection.dart';

/// The whole point of the .env is that an office can repoint the app without a
/// rebuild. If precedence is wrong, either the file is silently ignored (and
/// people edit it for nothing) or it overrides a deliberate --dart-define.
/// The file with CRLF normalised to LF — see the note in the first test.
String _lf(String s) => s.replaceAll(String.fromCharCode(13), '');

void main() {
  test('the project .env is found and parsed', () {
    // This suite runs from the project root, where .env lives.
    expect(File('.env').existsSync(), isTrue,
        reason: 'copy .env.example to .env');

    AppEnv.load();
    expect(AppEnv.loadedFrom, isNotNull,
        reason: 'AppEnv did not locate any .env');
    expect(AppEnv.loadedFrom, contains('.env'));
  });
  

  test('PgConfig reads its values from the .env', () {
    // These come from the file, not from a compiled-in default: the test
    // passes no --dart-define at all.
    //
    // ⚠️ Asserts that the FILE is being read, not which server it names.
    // Pinning the literal values made this a test of the developer's own
    // deployment: pointing the .env at the real server changed PG_USER from
    // postgres to yard_app and this reported a configuration change as a
    // failure.

    final env = _lf(File('.env').readAsStringSync());
    // Leading whitespace is tolerated: AppEnv trims, and a hand-edited
    // .env picks up stray indentation.
    String fromFile(String key) =>
        RegExp('^' + r'\s*' + '$key=(.*)' + r'$', multiLine: true)
        .firstMatch(env)!
        .group(1)!
        .trim();

    expect(PgConfig.database, fromFile('PG_DATABASE'));
    expect(PgConfig.username, fromFile('PG_USER'));
    expect(PgConfig.port.toString(), fromFile('PG_PORT'));
  });

  test('an absent key falls back to the compiled-in default', () {
    // NOT_A_REAL_KEY is in no .env anywhere.
    expect(
      AppEnv.read('NOT_A_REAL_KEY', dartDefine: '', fallback: 'the-default'),
      'the-default',
    );
  });

  test('a --dart-define beats the .env', () {
    // Simulates the build-time override winning, which is what keeps existing
    // deployments working unchanged.
    expect(
      AppEnv.read('PG_DATABASE',
          dartDefine: 'FromDartDefine', fallback: 'the-default'),
      'FromDartDefine',
    );
  });

  test('readInt and readBool honour the same precedence', () {
    expect(
      AppEnv.readInt('PG_PORT',
          dartDefine: 9999, fallback: 1, dartDefineSentinel: -1),
      9999,
      reason: 'a real --dart-define must win',
    );
    expect(
      AppEnv.readInt('PG_PORT',
          dartDefine: -1, fallback: 1, dartDefineSentinel: -1),
      5432,
      reason: 'the sentinel means "no define", so the .env should win',
    );
    // ⚠️ A false define cannot be told apart from an absent one, so the .env
    // decides. Compared against the FILE rather than a literal: this read
    // `isFalse` while PG_SSL=false was in the developer's own .env, and
    // turning TLS on for the real server broke it.
    // The key may be absent entirely (commented out), in which case the
    // FALLBACK is the answer — which is the third case this is testing and
    // the one a literal `isFalse` could never express.
    final match = RegExp(r'^\s*PG_SSL=(.*)$', multiLine: true)
        .firstMatch(_lf(File('.env').readAsStringSync()));
    final expected = match == null
        ? true // no key: readBool returns the fallback passed below
        : match.group(1)!.trim().toLowerCase() == 'true';
    expect(AppEnv.readBool('PG_SSL', dartDefine: false, fallback: true),
        expected);
    // A true define always wins.
    expect(AppEnv.readBool('PG_SSL', dartDefine: true, fallback: false), isTrue);
  });

  test('describe names the target and its TLS state', () {
    // This string is what the connection-failure screen shows, so it has to be
    // accurate about whether the link is encrypted.
    //
    // ⚠️ Asserts the SHAPE, not one deployment's values — this pinned
    // `postgres@localhost` and broke the moment the .env named the real
    // server.
    expect(PgConfig.describe,
        contains('${PgConfig.username}@${PgConfig.host}:${PgConfig.port}'));
    expect(PgConfig.describe, contains(PgConfig.database));
    expect(
        PgConfig.describe,
        anyOf(contains('no TLS'), contains('TLS, unverified'),
            contains('TLS, verified')));
  });
}
