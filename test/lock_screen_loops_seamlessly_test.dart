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
}
