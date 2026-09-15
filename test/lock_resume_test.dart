import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/idle_lock.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// Coming back from the lock screen.
///
/// The lock still signs the user out — an unattended PC must hold no live
/// session. What it now also does is remember WHO was there and WHERE, so the
/// same person signing back in resumes instead of restarting.
void main() {
  setUp(LockedSessionMemory.clear);

  group('the same officer resumes where they were', () {
    test('signing back in returns them to their page', () {
      LockedSessionMemory.capture(uid: 'user-1', currentRoute: '/sr-register');
      expect(
          resumeRouteAfterSignIn(uid: 'user-1', home: '/dashboard'),
          '/sr-register');
    });

    test('a half-filled form is still there for them', () {
      LockedSessionMemory.capture(uid: 'user-1', currentRoute: '/sr-register');
      LockedSessionMemory.formState['/sr-register'] = {'consignee': 'ACME'};

      expect(resumeRouteAfterSignIn(uid: 'user-1', home: '/dashboard'),
          '/sr-register');
      expect(LockedSessionMemory.formState['/sr-register'],
          {'consignee': 'ACME'},
          reason: 'the work they had typed was thrown away');
    });
  });

  group('a DIFFERENT officer gets a fresh app', () {
    test('they land on the portal home, not the previous page', () {
      LockedSessionMemory.capture(uid: 'user-1', currentRoute: '/sr-register');
      expect(resumeRouteAfterSignIn(uid: 'user-2', home: '/dashboard'),
          '/dashboard');
    });

    test('and never inherit the other person\'s typing', () {
      // ⚠️ This is the one that matters. A form left half-filled by the
      // officer before them must not reappear under a different name — the
      // record would be saved as the new person's work.
      LockedSessionMemory.capture(uid: 'user-1', currentRoute: '/sr-register');
      LockedSessionMemory.formState['/sr-register'] = {'consignee': 'ACME'};

      resumeRouteAfterSignIn(uid: 'user-2', home: '/dashboard');
      expect(LockedSessionMemory.formState, isEmpty,
          reason: 'one officer can see what another was typing');
    });
  });

  group('nothing is resumed when there is nothing to resume', () {
    test('no capture means the portal home', () {
      expect(resumeRouteAfterSignIn(uid: 'user-1', home: '/dashboard'),
          '/dashboard');
    });

    test('a null uid never matches a null memory', () {
      // Both null would be "equal" on a naive ==; nobody must resume as
      // nobody.
      expect(resumeRouteAfterSignIn(uid: null, home: '/dashboard'),
          '/dashboard');
    });

    test('the memory is SPENT, so an ordinary sign-in is not redirected', () {
      LockedSessionMemory.capture(uid: 'user-1', currentRoute: '/sr-register');
      expect(resumeRouteAfterSignIn(uid: 'user-1', home: '/dashboard'),
          '/sr-register');
      // Signing out normally and back in later must not land on that page.
      expect(resumeRouteAfterSignIn(uid: 'user-1', home: '/dashboard'),
          '/dashboard',
          reason: 'a stale resume fires on a later, unrelated sign-in');
    });

    test('the login page itself is never a resume target', () {
      LockedSessionMemory.capture(uid: 'user-1', currentRoute: '/');
      expect(resumeRouteAfterSignIn(uid: 'user-1', home: '/dashboard'),
          '/dashboard');
    });
  });

  group('the lock still signs out', () {
    test('the overlay captures BEFORE it navigates away', () {
      // ⚠️ Order matters: the navigation replaces the location, so a capture
      // after it would record the login page instead of the officer's page.
      final src = _read('lib/widgets/idle_lock_overlay.dart');
      final capture = src.indexOf('LockedSessionMemory.capture(');
      final navigate = src.indexOf('router.go(_loginRoute)');
      expect(capture, greaterThan(0), reason: 'nothing is captured at all');
      expect(capture, lessThan(navigate),
          reason: 'the capture runs after the navigation, so it records the '
              'login page rather than where the officer was');
    });

    test('signOut is still called', () {
      final src = _read('lib/widgets/idle_lock_overlay.dart');
      expect(src, contains('signOut()'),
          reason: 'the lock stopped signing out — it is no longer a security '
              'control');
    });

    test('every portal login routes through the helper', () {
      // A screen that still hardcodes its home cannot resume.
      final missed = <String>[];
      for (final f in Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('login'))) {
        final src = f.readAsStringSync();
        for (final home in const [
          "context.go('/admin')",
          "context.go('/ict')",
          "context.go('/disposal')",
          "context.go('/valuation')",
          "context.go('/appeal')",
          "context.go('/executive')",
          "context.go('/dashboard')",
        ]) {
          if (src.contains('$home;')) missed.add('${f.path}: $home');
        }
      }
      expect(missed, isEmpty,
          reason: 'these sign-ins bypass the resume: ${missed.join(", ")}');
    });
  });
}
