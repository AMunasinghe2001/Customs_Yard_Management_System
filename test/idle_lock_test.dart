import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/idle_lock.dart';
import 'package:cus_yard_management/screens/lock/idle_lock_screen.dart';

/// Pumps [child] inside the same activity detector the real app wraps its
/// router in, over a container the test can click on.
Widget _harness(ProviderContainer container, {Widget? child}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: IdleActivityDetector(
        child: child ??
            const Scaffold(body: Center(child: Text('working area'))),
      ),
    ),
  );
}

void main() {
  group('IdleLockController', () {
    testWidgets('locks once the idle timeout has elapsed', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      container.read(idleLockControllerProvider).arm();

      expect(container.read(idleLockedProvider), isFalse);

      // Just short of the timeout: still unlocked.
      await tester.pump(kIdleLockTimeout - const Duration(seconds: 1));
      expect(container.read(idleLockedProvider), isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(container.read(idleLockedProvider), isTrue);
    });

    testWidgets('a click restarts the countdown', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      container.read(idleLockControllerProvider).arm();

      // Wait most of the way, then interact.
      await tester.pump(kIdleLockTimeout - const Duration(seconds: 2));
      await tester.tap(find.text('working area'));
      await tester.pump();

      // The original deadline passes -- but the tap reset it, so still open.
      await tester.pump(const Duration(seconds: 3));
      expect(container.read(idleLockedProvider), isFalse);

      // A full further timeout with no input does lock it.
      await tester.pump(kIdleLockTimeout);
      expect(container.read(idleLockedProvider), isTrue);
    });

    testWidgets('activity does not silently unlock a locked app',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      final c = container.read(idleLockControllerProvider);
      c.lockNow();
      expect(container.read(idleLockedProvider), isTrue);

      // Poking (as a stray mouse move would) must not reopen the app: signing
      // in again is the only way back.
      c.poke();
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(idleLockedProvider), isTrue);
    });

    testWidgets('stop() prevents locking while nobody is signed in',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      final c = container.read(idleLockControllerProvider);
      c.arm();
      c.stop();

      await tester.pump(kIdleLockTimeout + const Duration(seconds: 5));
      expect(container.read(idleLockedProvider), isFalse);
    });

    testWidgets('never locks before a session has armed it', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));

      // Exactly what happens on the portal chooser at start-up: the user moves
      // the mouse and clicks around a page nobody has signed into. The timer
      // must not be running at all -- this locked the login screen behind a
      // "sign in again" notice before `arm()` gated it.
      await tester.tap(find.text('working area'));
      await tester.pump();
      await tester.pump(kIdleLockTimeout + const Duration(seconds: 5));

      expect(container.read(idleLockedProvider), isFalse);
    });

    testWidgets('a sign-out mid-countdown cancels the pending lock',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      final c = container.read(idleLockControllerProvider);
      c.arm();

      // Sign out with the countdown nearly elapsed.
      await tester.pump(kIdleLockTimeout - const Duration(seconds: 1));
      c.stop();

      await tester.pump(const Duration(seconds: 5));
      expect(container.read(idleLockedProvider), isFalse,
          reason: 'the lock must not land on a signed-out app');
    });

    testWidgets('arm() is idempotent and does not push the deadline out',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      final c = container.read(idleLockControllerProvider);
      c.arm();

      // The overlay re-arms from build(), which runs constantly. If each call
      // restarted the timer the app would never lock while anything on screen
      // was repainting.
      for (var i = 0; i < 4; i++) {
        await tester.pump(kIdleLockTimeout ~/ 5);
        c.arm();
      }
      await tester.pump(kIdleLockTimeout ~/ 4);

      expect(container.read(idleLockedProvider), isTrue);
    });

    testWidgets('unlock() resumes the countdown', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      final c = container.read(idleLockControllerProvider);
      c.lockNow();
      c.unlock();
      expect(container.read(idleLockedProvider), isFalse);

      await tester.pump(kIdleLockTimeout + const Duration(seconds: 1));
      expect(container.read(idleLockedProvider), isTrue,
          reason: 'the timer must be running again after an unlock');
    });
  });

  group('IdleLockScreen', () {
    testWidgets('shows the seal, the reason, and the way back', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: IdleLockScreen(onUnlock: () {}),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Sri Lanka Customs'), findsOneWidget);
      expect(find.textContaining('Locked after'), findsOneWidget);
      expect(find.text('Click anywhere to sign in again'), findsOneWidget);
    });

    testWidgets('a click anywhere asks to unlock', (tester) async {
      var unlocked = 0;
      await tester.pumpWidget(MaterialApp(
        home: IdleLockScreen(onUnlock: () => unlocked++),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tapAt(const Offset(40, 40)); // a far corner, not the logo
      expect(unlocked, 1);
    });

    testWidgets('keeps animating without settling (it is a screensaver)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: IdleLockScreen(onUnlock: () {}),
      ));
      // pumpAndSettle would time out on a deliberately endless animation, so
      // this asserts the repeat really is endless rather than a one-shot.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.hasRunningAnimations, isTrue);
    });
  });
}
