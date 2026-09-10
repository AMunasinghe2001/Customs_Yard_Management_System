import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/app_env.dart';
import 'package:cus_yard_management/core/db/pg_connection.dart';

/// The whole point of the .env is that an office can repoint the app without a
/// rebuild. If precedence is wrong, either the file is silently ignored (and
/// people edit it for nothing) or it overrides a deliberate --dart-define.
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
    expect(PgConfig.database, 'Customs_SR_DB');
    expect(PgConfig.username, 'postgres');
    expect(PgConfig.port, 5432);
    expect(PgConfig.connectTimeoutSeconds, 10);
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
    // PG_SSL=false in the file, and a false define cannot be told apart from
    // an absent one — so this stays false.
    expect(AppEnv.readBool('PG_SSL', dartDefine: false, fallback: true), isFalse);
    // A true define always wins.
    expect(AppEnv.readBool('PG_SSL', dartDefine: true, fallback: false), isTrue);
  });

  test('describe names the target and its TLS state', () {
    // This string is what the connection-failure screen shows, so it has to be
    // accurate about whether the link is encrypted.
    expect(PgConfig.describe, contains('postgres@localhost:5432/Customs_SR_DB'));
    expect(PgConfig.describe, contains('no TLS'));
  });
}
