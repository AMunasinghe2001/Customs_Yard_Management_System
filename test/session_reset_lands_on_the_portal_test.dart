import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/session_reset.dart';

/// Changing an expired password still landed the officer on the HOME page,
/// even after the screens were told to return to their own sign-in form.
///
/// ⚠️ The navigation was never the problem. `signOut()` calls
/// clearCachedSessionData(), which bumps `sessionEpoch` and REBUILDS THE
/// PROVIDERSCOPE — a deliberate security measure, because Riverpod keeps
/// ~100 non-autoDispose providers that would otherwise show one officer's
/// rows to the next. Rebuilding the scope builds a NEW GoRouter, and a new
/// router starts at its `initialLocation`, which was the literal '/'. So the
/// portal's own `context.go` was thrown away a frame later.
void main() {
  group('a session reset can be told where to land', () {
    setUp(() => pendingLandingRoute = null);

    test('defaults to the portal picker', () {
      // An ordinary sign-out should still go home.
      expect(takeLandingRoute(), '/');
    });

    test('honours a route the caller asked for', () {
      pendingLandingRoute = '/admin/login';
      expect(takeLandingRoute(), '/admin/login');
    });

    test('is spent once, so the NEXT reset goes home again', () {
      // ⚠️ Otherwise a password change would pin every later sign-out to
      // that portal's sign-in page for the life of the process.
      pendingLandingRoute = '/ict/login';
      expect(takeLandingRoute(), '/ict/login');
      expect(takeLandingRoute(), '/');
    });
  });

  group('every portal names its own sign-in route', () {
    const expected = {
      'lib/screens/login/login_screen.dart': '/login',
      'lib/screens/admin/admin_login_screen.dart': '/admin/login',
      'lib/screens/valuation/valuation_login_screen.dart': '/valuation/login',
      'lib/screens/disposal/disposal_login_screen.dart': '/disposal/login',
      'lib/screens/appeal/appeal_login_screen.dart': '/appeal/login',
      'lib/screens/executive/executive_login_screen.dart': '/executive/login',
      'lib/screens/ict/ict_login_screen.dart': '/ict/login',
    };

    expected.forEach((path, route) {
      test('$path -> $route', () {
        final src = File(path).readAsStringSync();
        // The two yard portals hand the route to the shared stage; the other
        // five set it inline before signing out. Either spelling counts.
        expect(
          src.contains("pendingLandingRoute = '$route'") ||
              src.contains("signInRoute: '$route'"),
          isTrue,
          reason: 'this portal does not say where the session reset should '
              'land, so it will fall back to the home page',
        );
      });
    });

    test('the router honours it instead of hardcoding /', () {
      final router = File('lib/core/router.dart').readAsStringSync();
      expect(router, contains('initialLocation: takeLandingRoute()'));
      expect(router.contains("initialLocation: '/',"), isFalse);
    });

    test('the stage sets it BEFORE signing out', () {
      // signOut() schedules the rebuild; setting it afterwards would be too
      // late for the router that is about to be built.
      final stage =
          File('lib/widgets/password_expired_stage.dart').readAsStringSync();
      final set = stage.indexOf('pendingLandingRoute =');
      final out = stage.indexOf('signOut()', set);
      expect(set, greaterThan(-1));
      expect(out, greaterThan(set),
          reason: 'the landing route is set after the reset was scheduled');
    });
  });
}
