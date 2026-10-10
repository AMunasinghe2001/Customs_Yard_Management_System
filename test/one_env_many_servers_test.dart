// One `.env`, several servers, switched by a single line.
//
// ⚠️ THE PROBLEM THIS REPLACES: the file used to hold one block per server
// with all but one commented out. Switching meant editing every line of two
// blocks, and a half-finished edit produced a MIXED configuration — a cloud
// host with a local password — which fails as an authentication error and
// reads like a wrong password rather than a half-applied change.
//
// Now each server keeps `KEY__<profile>` keys and only `PG_PROFILE` moves.
import 'dart:io';

import 'package:cus_yard_management/core/app_env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = File('.env');

  group('the profile mechanism', () {
    test('the checked-in .env names a profile', () {
      if (!env.existsSync()) return; // CI has no .env; nothing to assert.
      expect(AppEnv.profile, isNotEmpty,
          reason: 'PG_PROFILE is unset, so the suffixed keys are ignored '
              'and the app falls back to compiled-in defaults');
    });

    test('every key the active profile needs is present', () {
      if (!env.existsSync()) return;
      final src = env.readAsStringSync();
      final p = AppEnv.profile;
      // ⚠️ Host and user alone are not enough to call a profile complete: a
      // profile missing its PASSWORD silently inherits another server's,
      // which is the exact mixed-configuration failure this replaced.
      for (final key in ['PG_HOST', 'PG_DATABASE', 'PG_USER', 'PG_PASSWORD']) {
        expect(src, contains('${key}__$p='),
            reason: '$key is missing for profile "$p"');
      }
    });

    test('a profiled key beats the unsuffixed one', () {
      // The resolution order that makes the whole thing work.
      if (!env.existsSync()) return;
      final src = env.readAsStringSync();
      final p = AppEnv.profile;
      final m = RegExp('^PG_HOST__$p=(.*)\$', multiLine: true).firstMatch(src);
      expect(m, isNotNull);
      expect(AppEnv.read('PG_HOST', dartDefine: '', fallback: 'SENTINEL'),
          m!.group(1)!.trim());
    });

    test('an unknown profile falls back rather than inventing a value', () {
      // ⚠️ The fallback is what makes this safe to adopt gradually: a .env
      // with no profiles behaves exactly as it did before.
      expect(AppEnv.read('PG_NOT_A_REAL_KEY', dartDefine: '', fallback: 'fb'),
          'fb');
    });
  });

  group('the screen says which server is in force', () {
    test('describe() carries the profile name', () {
      // ⚠️ Switching is now one line, so "which server am I on" has to be
      // answerable from the error screen — otherwise a stale PG_PROFILE
      // looks like a broken network.
      final src =
          File('lib/core/db/pg_connection.dart').readAsStringSync();
      expect(src, contains('AppEnv.profile'));
      expect(src, contains(r"' [$p]'"));
    });
  });
}
