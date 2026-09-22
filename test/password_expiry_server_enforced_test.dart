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
      // ⚠️ sr_auth.uid() alone was not enough. 13 policies ask sr_auth.role()
      // instead — "Officers can view all packages" is just
      // `sr_auth.role() = 'authenticated'` — and with only uid() gated a
      // locked session still read all 176 packages.
      expect(migration, contains('create or replace function sr_auth.uid()'));
      expect(migration, contains('create or replace function sr_auth.role()'));
      expect(migration, contains("then 'anon'"));
    });

    test('the verdict is computed once, not per policy', () {
      // sr_auth.uid() runs once per policy per row; a profiles lookup in its
      // body would put a query on every row of every screen.
      expect(migration, contains('app.password_expired'));
      final uidBody = migration.substring(
          migration.indexOf('create or replace function sr_auth.uid()'));
      expect(uidBody.substring(0, 400).contains('from public.profiles'), isFalse,
          reason: 'sr_auth.uid() must stay a session-variable read');
    });

    test('the client cannot decide its own verdict', () {
      // It supplies an identity; the database decides what that identity
      // may do.
      expect(conn, contains('sr_auth.begin_session'));
      expect(conn.contains("set_config('app.current_user_id'"), isFalse,
          reason: 'the client must not set the flag-bearing variables itself');
    });

    test('changing the password is still possible while locked', () {
      // The one permitted action. It works because it takes the user id as
      // an argument and never calls sr_auth.uid().
      expect(migration, contains('sr_auth.change_password_unchecked'));
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
      // sr_auth.change_password is not in 01_auth_and_session.sql or anywhere
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
        // ⚠️ A STAGE on every portal now — the modal is gone. Three screens
        // used a dialog, so the same moment in the same flow looked like a
        // different product depending on which door the officer came
        // through, and a modal reads as an interruption to something else
        // when it IS the sign-in.
        final hasStage = src.contains('_passwordStage') ||
            src.contains('PasswordExpiredStage');
        expect(hasStage, isTrue,
            reason: '$path can sign in, so it must be able to change');
        expect(src.contains('isPasswordExpired'), isTrue,
            reason: '$path must notice the expiry');
      });
    }

    test('the stage offers no way to carry on without changing', () {
      // ⚠️ "Later" is what the 90 days already were. As a STAGE there is no
      // barrier to dismiss and nothing behind it — the sign-in form it
      // replaces has already been accepted — so the only exits are a new
      // password or signing out.
      final d =
          File('lib/widgets/password_expired_stage.dart').readAsStringSync();
      // ⚠️ This asserted the file contained no 'Skip' at all. The stage now
      // serves the WARNING phase too — the last days before the limit, where
      // deferring is exactly right — so the word is legitimately present and
      // the absence check would have to be deleted or weakened.
      //
      // Tightened instead of relaxed: what matters was never the word but
      // that the skip is UNREACHABLE once expired. Assert the condition
      // itself, which is a stronger claim than the old spelling test — it
      // would still fail if someone offered the skip unconditionally.
      expect(d, contains('widget.expired ? _signOut : widget.onSkip'),
          reason: 'an expired password cannot be postponed');
      // And a caller who forgets the flag must get the strict mode.
      expect(d, contains('this.expired = true'),
          reason: 'omitting `expired:` would silently allow a skip');
      expect(d, contains('Update Password & Sign In'));
    });

    test('backing out signs the officer out rather than stranding them', () {
      final d =
          File('lib/widgets/password_expired_stage.dart').readAsStringSync();
      expect(d, contains('signOut()'),
          reason: 'an expired session can read nothing; leaving it signed '
              'in only strands them on an empty dashboard');
    });

    test('the stage replaces the credentials form, not covers it', () {
      // A modal reads as an interruption to something else; this IS the
      // sign-in, and the credentials behind it have already been accepted.
      for (final path in const [
        'lib/screens/login/login_screen.dart',
        'lib/screens/admin/admin_login_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, contains('] else ...['),
            reason: '$path must swap the form out, not draw over it');
      }
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
      expect(m019, contains('sr_auth.session_user_id()'));
    });

    test('and ONLY its own, and only while locked', () {
      // One row, not a relaxation. Scoped to the expiry flag so it adds
      // nothing for a healthy session.
      expect(m019, contains("current_setting('app.password_expired', true) = 'on'"));
      expect(m019, contains('id = sr_auth.session_user_id()'));
    });

    test('the 30-minute idle rule does not fire while locked', () {
      // ⚠️ A locked session cannot write its heartbeat, so last_seen_at
      // goes null and isExpired treats null as long gone — signing the
      // officer out on the next redirect, before they could change
      // anything. The thing forcing the rotation made it impossible.
      expect(svc, contains('!profile.isPasswordExpired &&'),
          reason: 'the session check must skip a password-locked session');
    });

    test('session_user_id is kept separate from sr_auth.uid', () {
      // They answer different questions: "who may act" (nobody, while
      // locked) versus "whose session is this" (still truthful).
      expect(m019, contains('create or replace function sr_auth.session_user_id()'));
      expect(m019.contains('create or replace function sr_auth.uid()'), isFalse,
          reason: '019 must not widen the lock it depends on');
    });
  });
}
