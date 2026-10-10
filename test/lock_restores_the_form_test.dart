// A five-minute lock that cost the officer their typing.
//
// ⚠️ Reported directly: the lock already returned the SAME person to the SAME
// page, but a half-filled form came back EMPTY. LockedSessionMemory.formState
// existed for exactly this and nothing ever wrote to it, so the page was
// restored and the work on it was not.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/idle_lock.dart';

void main() {
  setUp(LockedSessionMemory.clear);

  group('open forms are snapshotted at the moment of locking', () {
    test('a registered form is read when the lock captures', () {
      LockedSessionMemory.registerForm('/x', () => {'a': '1'});
      LockedSessionMemory.captureOpenForms();
      expect(LockedSessionMemory.formState['/x'], {'a': '1'});
    });

    test('the snapshot is taken THEN, not as the officer types', () {
      // ⚠️ The registry holds a callback, not a copy. Saving onevery keystroke
      // would copy a whole form per character; the lock fires from a timer
      // and asks each form to describe itself once.
      var value = 'first';
      LockedSessionMemory.registerForm('/x', () => {'a': value});
      value = 'second';
      LockedSessionMemory.captureOpenForms();
      expect(LockedSessionMemory.formState['/x'], {'a': 'second'});
    });

    test('a form that throws does not stop the lock', () {
      // The screen still has to go up, with or without one field.
      LockedSessionMemory.registerForm('/bad', () => throw StateError('x'));
      LockedSessionMemory.registerForm('/good', () => {'a': '1'});
      LockedSessionMemory.captureOpenForms();
      expect(LockedSessionMemory.formState['/good'], {'a': '1'});
    });

    test('a form that has been left behind is not snapshotted', () {
      LockedSessionMemory.registerForm('/x', () => {'a': '1'});
      LockedSessionMemory.unregisterForm('/x');
      LockedSessionMemory.captureOpenForms();
      expect(LockedSessionMemory.formState['/x'], isNull);
    });
  });

  group('restoring consumes the snapshot', () {
    test('taking it once leaves nothing behind', () {
      LockedSessionMemory.registerForm('/x', () => {'a': '1'});
      LockedSessionMemory.captureOpenForms();
      expect(LockedSessionMemory.takeForm('/x'), {'a': '1'});
      expect(LockedSessionMemory.takeForm('/x'), isNull,
          reason: 'a later visit would re-fill a form already finished with');
    });
  });

  group('a DIFFERENT officer gets a fresh app', () {
    test('clear() drops the saved work', () {
      LockedSessionMemory.registerForm('/x', () => {'a': '1'});
      LockedSessionMemory.captureOpenForms();
      LockedSessionMemory.clear();
      expect(LockedSessionMemory.takeForm('/x'), isNull);
    });

    test('but live forms stay registered, so the NEXT lock still works', () {
      // ⚠️ _openForms holds mounted widgets that unregister on dispose.
      // Clearing them would leave the next lock with nothing to snapshot.
      LockedSessionMemory.registerForm('/x', () => {'a': '1'});
      LockedSessionMemory.clear();
      LockedSessionMemory.captureOpenForms();
      expect(LockedSessionMemory.formState['/x'], {'a': '1'});
    });

    test('resuming to a different person returns home and forgets', () {
      LockedSessionMemory.capture(uid: 'u1', currentRoute: '/inspection');
      expect(resumeRouteAfterSignIn(uid: 'u2', home: '/dash'), '/dash');
      expect(LockedSessionMemory.route, isNull);
    });

    test('the same person comes back to the page they were on', () {
      LockedSessionMemory.capture(uid: 'u1', currentRoute: '/inspection');
      expect(resumeRouteAfterSignIn(uid: 'u1', home: '/dash'), '/inspection');
    });
  });

  group('the lock actually calls it, and the SR form actually uses it', () {
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('the overlay captures forms before it navigates away', () {
      // ⚠️ BEFORE the router.go below it: one line later the form is gone
      // and there is nothing left to read.
      final overlay =
          File('lib/widgets/idle_lock_overlay.dart').readAsStringSync();
      final f = flat(overlay);
      expect(f, contains('LockedSessionMemory.captureOpenForms();'));
      expect(f.indexOf('captureOpenForms()'),
          lessThan(f.indexOf('router.go(_loginRoute)')));
    });

    test('the SR register form restores itself', () {
      final screen = File('lib/screens/inspection/inspection_screen.dart')
          .readAsStringSync();
      final f = flat(screen);
      expect(f, contains('LockRestorableForm<InspectionScreen>'));
      expect(f, contains("String get formStateId => '/inspection';"));
      // Both halves, and the goods rows with them — the per-item controllers
      // are most of what an officer types on this page.
      expect(f, contains('Map<String, dynamic> readFormState()'));
      expect(f, contains('void writeFormState('));
      expect(f, contains("'items': ["));
      expect(f, contains("final rows = (saved['items'] as List?)"));
    });
  });
}
