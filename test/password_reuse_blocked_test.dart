import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rotating a password is pointless if the old one can come straight back.
///
/// sr_auth.change_password already refused the CURRENT password, so the laziest
/// way to satisfy a 90-day prompt was blocked. But nothing stopped an officer
/// alternating between two: change to B, change back to A. If A ever leaked,
/// it returns every 90 days and the rotation protects nothing.
void main() {
  final sql =
      File('migrations/023_password_history_blocks_reuse.sql').readAsStringSync();

  group('a password cannot be reused', () {
    test('previous hashes are kept', () {
      expect(sql, contains('create table if not exists sr_auth.password_history'));
    });

    test('it stores hashes, never a password', () {
      // The column is the bcrypt hash moved aside from sr_auth.users as it is
      // replaced — no more sensitive than where it came from, and a reuse
      // check is impossible without it.
      expect(sql, contains('password_hash text not null'));
      expect(sql.toLowerCase().contains('plaintext text'), isFalse);
    });

    test('the history is not readable by the application role', () {
      // Only the SECURITY DEFINER function needs it.
      expect(sql, contains('revoke all on sr_auth.password_history'));
      expect(sql, contains('authenticated'));
    });

    test('each stored hash is compared with its OWN salt', () {
      // ⚠️ bcrypt salts per row, so the candidate cannot be hashed once and
      // looked up — it must be crypt()ed against each stored hash in turn.
      // A plain equality test against a single hash would never match and
      // the check would silently pass everything.
      expect(sql, contains('crypt(p_password, v_old.password_hash)'),
          reason: 'the comparison ignores the per-row salt, so no reuse is '
              'ever detected');
    });

    test('the outgoing password is recorded before it is replaced', () {
      final insert = sql.indexOf('insert into sr_auth.password_history');
      final update = sql.indexOf('update sr_auth.users');
      expect(insert, greaterThan(-1));
      expect(update, greaterThan(insert),
          reason: 'the old hash is overwritten before it is saved, so the '
              'password just replaced could be reused immediately');
    });

    test('the history is trimmed so it cannot grow without bound', () {
      expect(sql, contains('delete from sr_auth.password_history'));
      expect(sql, contains('password_history_depth()'));
    });

    test('the refusal names what to do, not just what failed', () {
      expect(sql, contains('You have used this password before'));
      expect(sql, contains('This is your current password'));
    });
  });

  group('the reset path still works without a session', () {
    final fix = File(
        'migrations/024_reset_may_set_a_password_without_a_session.sql')
        .readAsStringSync();

    test('it calls the UNGUARDED setter', () {
      // ⚠️ A regression introduced by 018's caller guard. That guard refuses
      // anyone whose app.current_user_id is not the user being changed --
      // right for a signed-in officer, fatal for a RESET, which by
      // definition has no session. Forgot-password died with "You may only
      // change your own password", shown as "Something went wrong".
      expect(fix, contains('change_password_unchecked'));
    });

    test('but the reuse and policy checks still apply', () {
      // Those live INSIDE the inner function, so skipping the wrapper skips
      // only the are-you-yourself test that the one-time code already
      // answered. The migration proves it rather than asserting it.
      expect(fix, contains('the reset path accepted a password it had just set'),
          reason: 'nothing verifies that reuse is still blocked on this path');
    });

    test('it resolves the setter at runtime, not by hardcoding', () {
      // On a database where 018 has not run, sr_auth.change_password IS the
      // unguarded body — hardcoding the _unchecked name would break a fresh
      // install.
      expect(fix, contains("proname = 'change_password_unchecked'"));
      expect(fix, contains('v_setter :='));
    });
  });
}
