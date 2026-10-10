// The lock screen's motion, and the one arithmetic mistake that made it jump.
//
// ⚠️ Reported directly: the two background glows and the outer ring "go a
// distance, break, and start again somewhere else" — like a tour that never
// finishes.
//
// Every one of these is driven by an AnimationController that runs 0 -> 1 and
// repeats. An angle of `value * 2pi * k` returns to its starting position on
// the wrap ONLY when k is a whole number. At k = 0.7 the glow had travelled
// 0.7 of a revolution when the controller reset, so it teleported back —
// once every 24 seconds, forever.
//
// The inner ring (k = 1) always looked right, which is exactly why the fault
// was hard to place: two of the three pieces were correct.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File('lib/screens/lock/idle_lock_screen.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  // ⚠️ CODE only. Every fix below is explained in a comment that quotes the
  // old broken expression, so matching the raw file finds `t * 0.7` and
  // `146 + 6 * breath` in the very sentences recording that they are gone.
  final f = flat(src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n'));

  group('every repeating angle closes on a whole revolution', () {
    test('the outer ring turns a whole number of times per cycle', () {
      expect(f, contains('orbit * 2 * math.pi * 2, 0.18)'));
      expect(f.contains('orbit * 2 * math.pi * 0.6'), isFalse,
          reason: 'the outer ring snaps back on every wrap again');
    });

    test('the inner ring is unchanged, because it was already right', () {
      expect(f, contains('orbit * 2 * math.pi, 0.34)'));
    });

    test('the second glow completes whole turns too', () {
      expect(f, contains('math.cos(t * 2 + 1.2)'));
      expect(f, contains('math.sin(t * 2 + 1.2)'));
      expect(f.contains('t * 0.7'), isFalse,
          reason: 'the glow teleports on every wrap again');
    });

    test('the two rings still differ, so they never line up', () {
      // Opposite signs and different speeds — the point of two rings is that
      // they are not one ring.
      expect(f, contains('-orbit * 2 * math.pi * 2'));
    });
  });

  group('the gradient closes on itself', () {
    test('the sweep is described all the way to 1.0', () {
      // ⚠️ A SweepGradient whose stops end early HOLDS its last colour around
      // the rest of the circle, and the jump from that held colour back to
      // stops[0] is a hard seam at the gradient's own zero angle. Rotated
      // with the arc, that seam crossed the drawn part once per revolution.
      expect(f, contains('stops: [0.0, frac * 0.18, frac * 0.82, frac, 1.0]'));
    });

    test('the unlit remainder is transparent at BOTH ends', () {
      // First and last stop must agree, or the seam is back.
      // The stop list ends transparent AND begins transparent: five colours
      // for five stops, with withOpacity(0) at each end.
      expect(
          f,
          contains('color.withOpacity(0), color.withOpacity(alpha), '
              'color.withOpacity(alpha), color.withOpacity(0), '
              'color.withOpacity(0),'),
          reason: 'the gradient no longer closes on itself');
    });
  });

  group('only the seal breathes', () {
    test('the ring radii are fixed', () {
      // ⚠️ Two motions at once read as wobble rather than rotation.
      expect(f, contains('_arc(canvas, centre, 146,'));
      expect(f, contains('_arc(canvas, centre, 178,'));
      expect(f.contains('146 + 6 * breath'), isFalse,
          reason: 'the rings pulse with the seal again');
      expect(f.contains('178 - 5 * breath'), isFalse,
          reason: 'the rings pulse with the seal again');
    });

    test('the seal itself still scales, and the halo still pulses', () {
      expect(f, contains('scale: 0.97 + 0.05 * breath'));
      expect(f, contains('88 + 12 * breath'));
    });
  });

  group('the lock screen is mounted once and stays mounted', () {
    final main = File('lib/main.dart').readAsStringSync();
    final overlay =
        File('lib/widgets/idle_lock_overlay.dart').readAsStringSync();
    final screen =
        File('lib/screens/lock/idle_lock_screen.dart').readAsStringSync();

    test('it lives ABOVE MaterialApp, outside the ProviderScope', () {
      // ⚠️ Locking signs the session out, which bumps the session
      // epoch and replaces the whole ProviderScope. routerProvider then
      // yields a NEW GoRouter, so MaterialApp.router is rebuilt and
      // every widget under its builder is destroyed -- which is where
      // the lock screen used to be. It came up, then about two seconds
      // later jumped back to its first frame.
      final lockLayer = main.indexOf('_LockLayer(');
      final scope = main.indexOf('ProviderScope(');
      expect(lockLayer, greaterThan(-1),
          reason: 'main.dart no longer mounts the lock above the app');
      expect(lockLayer, lessThan(scope),
          reason: 'the lock must wrap the ProviderScope, not sit in it');
    });

    test('the overlay no longer draws it', () {
      // It keeps the job it can only do from inside the scope --
      // watching for idleness and signing out -- and nothing else.
      expect(overlay, isNot(contains('child: IdleLockScreen(')),
          reason: 'drawing it here is what made it rebuild');
      expect(overlay, contains('return widget.child;'));
    });

    test('the entrance is a plain one-shot again', () {
      // ⚠️ The earlier attempt started the fade at value 1.0 on a
      // rebuild. That hid the fade but NOT the reset: drift, breathe
      // and orbit still began from zero, so the screen still jumped.
      // Not being rebuilt at all is the only fix that covers them.
      expect(screen, isNot(contains('idleLockEntranceShown')));
      expect(screen, contains('duration: const Duration(milliseconds: 900),'));
    });

    test('the screen takes plain values, never providers', () {
      // That is what lets it sit outside MaterialApp at all.
      expect(screen, isNot(contains('ref.watch')));
      expect(screen, isNot(contains('ref.read')));
      expect(main, contains('valueListenable: lockAccent'));
    });

    test('the unlock callback is read at PRESS time', () {
      // ⚠️ The overlay re-publishes it after every session reset, so
      // one captured at mount would belong to a torn-down container.
      expect(main, contains('onUnlock: () => lockUnlockRequest?.call()'));
      expect(overlay, contains('lockUnlockRequest = _unlock;'));
    });

    test('Directionality and Material are supplied by hand', () {
      // ⚠️ Outside MaterialApp none of the inherited widgets the
      // screen expects are in scope; without these it throws on the
      // first Text it lays out.
      final layer = main.substring(main.indexOf('class _LockLayer'));
      expect(layer, contains('Directionality('));
      expect(layer, contains('Material('));
    });
  });
}
