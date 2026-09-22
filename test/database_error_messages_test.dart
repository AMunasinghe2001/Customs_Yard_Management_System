import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/db/pg_query.dart';

/// A `raise exception` in a database function is how the schema talks to a
/// PERSON. It reached the sign-in screen wearing the driver's clothes:
///
///   Severity.error 22023: New password must be different from the current one.
///
/// The officer is shown a severity enum and a SQLSTATE before the sentence
/// that was actually written for them.
void main() {
  group('a database refusal reads as a sentence', () {
    test('the driver prefix and SQLSTATE are stripped', () {
      // ⚠️ Verbatim from the reported screen.
      expect(
        describeDatabaseError(Exception(
            'Severity.error 22023: New password must be different from the '
            'current one.')),
        'New password must be different from the current one.',
      );
    });

    test('an Exception: wrapper from a rethrow goes too', () {
      expect(
        describeDatabaseError(
            'Exception: Severity.error 22023: You have used this password '
            'before.'),
        'You have used this password before.',
      );
    });

    test('a message with no SQLSTATE still unwraps', () {
      expect(describeDatabaseError('Severity.error: user not found'),
          'user not found');
    });

    test('a multi-line message keeps its later lines', () {
      // dotAll matters: a raise with a HINT spans lines, and cutting at the
      // first newline would drop the half that says what to do.
      expect(
        describeDatabaseError(
            'Severity.error 22023: Too short.\nUse 12 characters.'),
        'Too short.\nUse 12 characters.',
      );
    });

    test('an unrecognised error is passed through, not flattened', () {
      // ⚠️ Deliberate. Inventing a friendly message for a failure we do not
      // recognise hides the one detail that would explain it.
      expect(describeDatabaseError('Connection closed'), 'Connection closed');
    });
  });

  group('the unwrapping happens where EVERY call passes', () {
    test('_run strips it, not just rpc()', () {
      // ⚠️ It was applied in PgClient.rpc, which covers RPC calls only. A
      // password change goes through `PgDatabase.execute('select
      // sr_auth.change_password(...)')` — a different path — so the sign-in
      // screen still showed `Severity.error 22023:` for the one message the
      // fix was written for. _run is what query() and execute() share.
      final conn =
          File('lib/core/db/pg_connection.dart').readAsStringSync();
      expect(conn, contains('describeDatabaseError(e)'),
          reason: 'the driver prefix survives on direct query/execute calls');

      final client = File('lib/core/db/pg_client.dart').readAsStringSync();
      expect(client.contains('describeDatabaseError'), isFalse,
          reason: 'two places unwrapping the same error will drift');
    });
  });
}
