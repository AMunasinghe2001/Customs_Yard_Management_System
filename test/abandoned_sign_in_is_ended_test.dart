import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Walking away from the password-expiry step must END the session.
///
/// ⚠️ The step runs INSIDE a live session — `signInWithPassword` has already
/// succeeded by the time the officer is asked for a new password, which is
/// what makes the change possible at all (migration 018). So the back arrow
/// left a real session behind, the router saw "logged in" on a public page,
/// and delivered the dashboard **with no password ever entered**.
///
/// Observed: a Central Disposal account that backed out of its expiry screen
/// landed in a YARD dashboard with no profile shown.
void main() {
  const portals = [
    'lib/screens/login/login_screen.dart',
    'lib/screens/admin/admin_login_screen.dart',
    'lib/screens/ict/ict_login_screen.dart',
    'lib/screens/disposal/disposal_login_screen.dart',
    'lib/screens/appeal/appeal_login_screen.dart',
    'lib/screens/valuation/valuation_login_screen.dart',
    'lib/screens/executive/executive_login_screen.dart',
  ];

  group('no portal leaves a half-finished sign-in alive', () {
    for (final path in portals) {
      test('${path.split('/').last} ends the session on the way out', () {
        final src = File(path).readAsStringSync();
        expect(src, contains('abandonSignIn(ref)'),
            reason: '$path lets an abandoned sign-in survive the back arrow');
      });
    }

    test('the back arrow never navigates before signing out', () {
      // ⚠️ Order matters: navigating first lets the redirect run against a
      // session that is still live.
      //
      // Checked as "no context.go BEFORE the sign-out", not "a go() soon
      // after" — from a stage the arrow returns to the credentials form
      // without navigating at all, which is correct and has no go() to find.
      for (final path in portals) {
        final src = File(path).readAsStringSync();
        final i = src.indexOf('onPressed: () async {');
        expect(i, greaterThan(-1), reason: '$path has no async back handler');
        final j = src.indexOf('abandonSignIn(ref)', i);
        expect(j, greaterThan(i), reason: '$path never signs out');
        expect(src.substring(i, j).contains('context.go('), isFalse,
            reason: '$path navigates before the sign-out completes');
      }
    });

    test('the helper is safe on an untouched form', () {
      // An ordinary back press from a login nobody has used must cost
      // nothing — otherwise every portal exit becomes a network round trip.
      final helper =
          File('lib/core/abandon_sign_in.dart').readAsStringSync();
      expect(helper, contains('supabase.auth.currentUser == null'));
      expect(helper, contains('return;'));
    });

    test('a failed sign-out still clears the local profile', () {
      // A sign-out that throws must NOT leave the session usable.
      final helper =
          File('lib/core/abandon_sign_in.dart').readAsStringSync();
      final catchAt = helper.indexOf('} catch (_) {');
      expect(catchAt, greaterThan(-1));
      expect(helper.indexOf('currentProfileProvider.notifier).state = null'),
          greaterThan(catchAt),
          reason: 'the profile must be cleared even when sign-out fails');
    });
  });

  group('the router refuses an expired password everywhere', () {
    final router = File('lib/core/router.dart').readAsStringSync();

    test('an expired session cannot reach any page of the app', () {
      // ⚠️ The back arrow is only ONE exit. Any other route into the app
      // would have satisfied "is logged in" just as well, so the gate
      // belongs where every navigation passes.
      expect(router, contains('profile.isPasswordExpired'));
      expect(router, contains("return '/';"));
    });

    test('and the stale session is dropped on a public page', () {
      // On a login page there is nothing to protect, but the session must
      // not survive to authorise the NEXT navigation.
      final i = router.indexOf('profile.isPasswordExpired');
      final block = router.substring(i, i + 900);
      expect(block, contains('signOut()'));
      expect(block, contains('currentProfileProvider.notifier).state = null'));
    });

    test('verifyUserSession still tolerates it, or the change is impossible',
        () {
      // The change is collected inside the session. If verification rejected
      // an expired password the officer could never reach the form that
      // fixes it.
      final svc = File('lib/services/services.dart').readAsStringSync();
      expect(svc, contains('!profile.isPasswordExpired &&'),
          reason: 'the 30-minute idle rule must skip a password-locked '
              'session, which cannot write its own heartbeat');
    });
  });
}
