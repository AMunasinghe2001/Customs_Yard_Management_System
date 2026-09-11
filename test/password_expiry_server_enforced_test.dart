import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// The 90-day rule is enforced by the DATABASE, not by the login screen.
///
/// These read the migration and the connection layer, because the behaviour
/// they describe cannot be exercised without a live PostgreSQL — it was
/// verified there by hand (see the migration header), and these hold the
/// shape of it against a future edit.
void main() {
  final migration =
      File('migrations/018_expired_password_locks_the_session.sql')
          .readAsStringSync();
  final conn = File('lib/core/db/pg_connection.dart').readAsStringSync();
  final auth = File('lib/core/db/pg_auth.dart').readAsStringSync();

  group('an expired password locks the session at the database', () {
    test('BOTH roots of the authorization model are gated', () {
      // ⚠️ auth.uid() alone was not enough. 13 policies ask auth.role()
      // instead — "Officers can view all packages" is just
      // `auth.role() = 'authenticated'` — and with only uid() gated a
      // locked session still read all 176 packages.
      expect(migration, contains('create or replace function auth.uid()'));
      expect(migration, contains('create or replace function auth.role()'));
      expect(migration, contains("then 'anon'"));
    });

    test('the verdict is computed once, not per policy', () {
      // auth.uid() runs once per policy per row; a profiles lookup in its
      // body would put a query on every row of every screen.
      expect(migration, contains('app.password_expired'));
      final uidBody = migration.substring(
          migration.indexOf('create or replace function auth.uid()'));
      expect(uidBody.substring(0, 400).contains('from public.profiles'), isFalse,
          reason: 'auth.uid() must stay a session-variable read');
    });

    test('the client cannot decide its own verdict', () {
      // It supplies an identity; the database decides what that identity
      // may do.
      expect(conn, contains('auth.begin_session'));
      expect(conn.contains("set_config('app.current_user_id'"), isFalse,
          reason: 'the client must not set the flag-bearing variables itself');
    });

    test('changing the password is still possible while locked', () {
      // The one permitted action. It works because it takes the user id as
      // an argument and never calls auth.uid().
      expect(migration, contains('auth.change_password_unchecked'));
      expect(migration, contains('current_setting(\'app.current_user_id\', true)'));
    });

    test('but only your OWN password', () {
      // Taking an id as a parameter means a locked session could otherwise
      // aim it at somebody else.
      expect(migration, contains('You may only change your own password.'));
      expect(migration, contains('42501'));
    });

    test('the pool is dropped after a change, or the lock sticks', () {
      // setCurrentUser cannot notice: the user id has not changed, so the
      // idle connections keep the expired flag they were opened with.
      expect(auth, contains('refreshSessionState()'));
      expect(conn, contains('Future<void> refreshSessionState()'));
    });

    test('it survives a fresh database that lacks change_password', () {
      // auth.change_password is not in 01_supabase_compat.sql or anywhere
      // in postgres/ — it was added to the running database by hand, so
      // 02_schema.sql must not fail on its absence.
      expect(migration, contains('skipping its guard'));
    });
  });

  group('every portal can escape the lock it can reach', () {
    // ⚠️ The database now refuses an expired session everything except the
    // password change. A portal that can SIGN IN but cannot CHANGE is a
    // dead end — the officer reaches an empty app with no remedy — so the
    // two must go together on all seven.
    const portals = [
      'lib/screens/login/login_screen.dart',
      'lib/screens/admin/admin_login_screen.dart',
      'lib/screens/ict/ict_login_screen.dart',
      'lib/screens/disposal/disposal_login_screen.dart',
      'lib/screens/appeal/appeal_login_screen.dart',
      'lib/screens/valuation/valuation_login_screen.dart',
      'lib/screens/executive/executive_login_screen.dart',
    ];

    for (final path in portals) {
      test('${path.split('/').last} offers a way to change an expired password',
          () {
        final src = File(path).readAsStringSync();
        final hasStage = src.contains('_passwordStage') ||
            src.contains('MandatoryPasswordChangeDialog');
        expect(hasStage, isTrue,
            reason: '$path can sign in, so it must be able to change');
        expect(src.contains('isPasswordExpired'), isTrue,
            reason: '$path must notice the expiry');
      });
    }

    test('the shared dialog cannot be dismissed away', () {
      // "Later" is what the 90 days already were.
      final d = File('lib/widgets/mandatory_password_change_dialog.dart')
          .readAsStringSync();
      expect(d, contains('canPop: false'));
      expect(d, contains('barrierDismissible: false'));
    });

    test('backing out signs the officer out rather than stranding them', () {
      final d = File('lib/widgets/mandatory_password_change_dialog.dart')
          .readAsStringSync();
      expect(d, contains('signOut()'),
          reason: 'an expired session can read nothing; leaving it signed '
              'in only strands them on an empty dashboard');
    });
  });

  group('the lock must be escapable, not just tight', () {
    final m019 =
        File('migrations/019_locked_session_can_read_its_own_profile.sql')
            .readAsStringSync();
    final svc = File('lib/services/services.dart').readAsStringSync();

    test('a locked session can still read its OWN profile', () {
      // ⚠️ The app learns a password has expired by READING THE PROFILE.
      // Migration 018 blocked exactly that, so finishOtpLogin's
      // `.single()` got zero rows and threw — the officer saw "Sign in
      // failed", never reached the change dialog, and had spent an OTP.
      expect(m019, contains('profiles_expired_self_read'));
      expect(m019, contains('auth.session_user_id()'));
    });

    test('and ONLY its own, and only while locked', () {
      // One row, not a relaxation. Scoped to the expiry flag so it adds
      // nothing for a healthy session.
      expect(m019, contains("current_setting('app.password_expired', true) = 'on'"));
      expect(m019, contains('id = auth.session_user_id()'));
    });

    test('the 30-minute idle rule does not fire while locked', () {
      // ⚠️ A locked session cannot write its heartbeat, so last_seen_at
      // goes null and isExpired treats null as long gone — signing the
      // officer out on the next redirect, before they could change
      // anything. The thing forcing the rotation made it impossible.
      expect(svc, contains('!profile.isPasswordExpired &&'),
          reason: 'the session check must skip a password-locked session');
    });

    test('session_user_id is kept separate from auth.uid', () {
      // They answer different questions: "who may act" (nobody, while
      // locked) versus "whose session is this" (still truthful).
      expect(m019, contains('create or replace function auth.session_user_id()'));
      expect(m019.contains('create or replace function auth.uid()'), isFalse,
          reason: '019 must not widen the lock it depends on');
    });
  });
}
