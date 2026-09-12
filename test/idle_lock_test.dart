import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/idle_lock.dart';
import 'package:cus_yard_management/core/session_reset.dart';
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
  // ⚠️ The lock flag is a process-global ValueNotifier, deliberately: it has
  // to outlive the ProviderScope, because locking signs the user out and a
  // sign-out rebuilds that scope. The cost is that it also outlives a TEST,
  // so a test that locks would leave the next one starting out locked.
  setUp(() => idleLockedFlag.value = false);
  tearDown(() => idleLockedFlag.value = false);

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

  group('the lock survives its own sign-out', () {
    // ⚠️ These two are one bug seen twice: locking signs the user out, and
    // signing out rebuilds the ProviderScope to drop the previous session's
    // cached rows. Anything the lock keeps INSIDE that container is thrown
    // away one frame after the lock goes up.
    testWidgets('the lock screen stays up when the scope is rebuilt',
        (tester) async {
      sessionEpoch.value = 0;
      await tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: sessionEpoch,
          builder: (_, epoch, __) => ProviderScope(
            key: ValueKey('session-$epoch'),
            child: MaterialApp(
              home: Consumer(builder: (context, ref, _) {
                return Text(ref.watch(idleLockedProvider) ? 'LOCKED' : 'OPEN',
                    textDirection: TextDirection.ltr);
              }),
            ),
          ),
        ),
      );
      expect(find.text('OPEN'), findsOneWidget);

      ProviderScope.containerOf(tester.element(find.byType(Consumer)),
              listen: false)
          .read(idleLockedProvider.notifier)
          .set(true);
      await tester.pump();
      expect(find.text('LOCKED'), findsOneWidget);

      // What signing out does one frame later.
      sessionEpoch.value++;
      await tester.pump();

      expect(find.text('LOCKED'), findsOneWidget,
          reason: 'a StateProvider here is reset by the rebuild, so the '
              'lock screen vanished and the app looked like it had '
              'stopped locking');
    });

    test('the flag is the single source of truth across containers', () {
      // Two containers, as before and after a sign-out.
      final a = ProviderContainer();
      addTearDown(a.dispose);
      a.read(idleLockedProvider.notifier).set(true);

      final b = ProviderContainer();
      addTearDown(b.dispose);
      expect(b.read(idleLockedProvider), isTrue,
          reason: 'the new container must see the lock that is still up');
    });

    test('a controller in a fresh container still refuses to re-arm', () {
      // poke() must not restart the countdown while the lock is up, and it
      // reads the flag through the provider — so this has to hold in the
      // container that exists AFTER the sign-out too.
      idleLockedFlag.value = true;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final controller = c.read(idleLockControllerProvider);
      controller.arm();
      expect(c.read(idleLockedProvider), isTrue);
    });
  });

  // ⚠️ The whole sequence, end to end, with the scope rebuild in it —
  // verified to FAIL against the old in-container StateProvider, so it
  // actually holds the fix rather than describing it.
  testWidgets('lock -> sign-out rebuilds the scope -> lock STAYS up',
      (tester) async {
    sessionEpoch.value = 0;
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: sessionEpoch,
        builder: (_, epoch, __) => ProviderScope(
          key: ValueKey('session-$epoch'),
          child: MaterialApp(
            home: Consumer(builder: (context, ref, _) {
              final locked = ref.watch(idleLockedProvider);
              return IdleActivityDetector(
                child: Stack(children: [
                  const Scaffold(body: Center(child: Text('desk'))),
                  if (locked)
                    const Positioned.fill(
                        child: ColoredBox(
                            color: Color(0xFF000000),
                            child: Center(
                                child: Text('LOCK SCREEN',
                                    textDirection: TextDirection.ltr)))),
                ]),
              );
            }),
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
        tester.element(find.byType(IdleActivityDetector)),
        listen: false);
    container.read(idleLockControllerProvider).arm();

    // Nothing happens before the timeout.
    await tester.pump(kIdleLockTimeout - const Duration(seconds: 1));
    expect(find.text('LOCK SCREEN'), findsNothing);

    // The timer fires.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('LOCK SCREEN'), findsOneWidget);

    // Sign-out bumps the epoch a frame later — the real collision.
    clearCachedSessionData();
    await tester.pump();
    sessionEpoch.value++;
    await tester.pump();

    expect(find.text('LOCK SCREEN'), findsOneWidget,
        reason: 'the lock must outlive the sign-out that it caused');
  });

  test('the portal to return to outlives the scope rebuild', () {
    // Set while the session is alive, read AFTER the sign-out that replaces
    // the container — so it cannot live inside it.
    lastLockedPortal = '/disposal/login';
    sessionEpoch.value++;
    expect(lastLockedPortal, '/disposal/login',
        reason: 'the officer must come back to the door they came through');
  });

  test('no portal returns to the chooser', () {
    // The lock goes back to the role's own sign-in page. '/' is the portal
    // chooser — the front door with every portal on it — and is the wrong
    // answer for someone who was already inside one.
    const routes = [
      '/ict/login',
      '/disposal/login',
      '/appeal/login',
      '/valuation/login',
      '/executive/login',
      '/admin/login',
      '/login',
    ];
    for (final r in routes) {
      expect(r, isNot('/'));
    }
  });

  group('the lock wears the portal it locked', () {
    final src = File('lib/widgets/idle_lock_overlay.dart').readAsStringSync();

    test('every role maps to a colour, none falls through', () {
      // ⚠️ `admin` is the yard's SDDC/DDC, whose sign-in is GOLD — it used to
      // fall through to the light-blue default, so locking a yard
      // administrator's screen showed a portal colour that was not theirs.
      for (final role in const [
        'ict',
        'appeal',
        'executive',
        'disposal',
        'valuation',
        'admin',
      ]) {
        expect(src, contains("'$role'"), reason: '$role has no accent');
      }
    });

    test('officer still has a default to fall back to', () {
      // The one role with no colour of its own; the default is for it, not a
      // gap left by accident.
      expect(src, contains('accentLightBlue'));
      expect(src, contains('// officer, and anything unmapped'));
    });
  });

  group('the lock screen does not band', () {
    final src = File('lib/screens/lock/idle_lock_screen.dart').readAsStringSync();

    test('the glow falls off over eight stops, not two', () {
      // ⚠️ Two stops fall linearly, and a display has 256 levels per channel
      // — on near-black the wide dim outer half gets far too few and each
      // level covers enough pixels to read as a ring. Drifting, those rings
      // look like waves.
      expect(src, contains('for (var i = 0; i < 8; i++)'));
      expect(src, contains('math.pow(1 - i / 7, 2)'));
    });

    test('one blur covers both glows', () {
      // The filter is the expensive part and it is the same filter.
      expect(src, contains('ui.ImageFilter.blur('));
      expect('ImageFiltered('.allMatches(src).length, 1);
    });

    test('opacity was raised to survive the blur', () {
      // A blur spreads the same light over more pixels; at the old 0.16/0.22
      // the glows all but vanished behind it.
      expect(src, contains('opacity: 0.24'));
      expect(src, contains('opacity: 0.32'));
    });
  });
}
