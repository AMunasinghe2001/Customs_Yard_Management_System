// The seal, then the portals.
//
// The window is shown BEFORE main() connects to PostgreSQL, caches the query
// layer's foreign keys and starts the change listener -- so on a cold start
// the first thing on screen has always been a portal page not yet backed by a
// database. The splash covers exactly that gap.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/home/splash_gate.dart';

void main() {
  setUp(SplashGate.resetForTest);

  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
      );

  group('it runs once per launch, not once per visit', () {
    test('the first ask gets the splash', () {
      expect(SplashGate.consume(), isTrue);
    });

    test('every ask after that does not', () {
      // ⚠️ '/' is also where SIGNING OUT lands, and the route rebuilds every
      // time. A seal that reappeared then would read as the whole app
      // restarting, which is alarming rather than welcoming.
      expect(SplashGate.consume(), isTrue);
      expect(SplashGate.consume(), isFalse);
      expect(SplashGate.consume(), isFalse);
    });

    test('the router asks exactly once, and uses the answer', () {
      final router = File('lib/core/router.dart').readAsStringSync();
      expect('SplashGate.consume()'.allMatches(router).length, 1);
      expect(router, contains('SplashGate(child: HomeScreen())'));
      // And the bare page when the splash is spent.
      expect(router, contains(': const HomeScreen()'));
    });
  });

  group('the page arrives as the seal lifts, not before it', () {
    testWidgets('it is NOT in the tree while the seal holds', (t) async {
      // ⚠️ Building it underneath from the first frame spends its entrance
      // where nobody can see it: the logo scales in and the cards land while
      // the curtain is opaque, so the dissolve then cross-fades the splash's
      // logo into a SECOND, already-settled one. That read as a reload.
      await t.pumpWidget(host(const SplashGate(
          child: Center(child: Text('portal', key: Key('portal'))))));
      await t.pump();
      expect(find.byKey(const Key('portal')), findsNothing);

      await t.pump(SplashGate.hold);
      await t.pumpAndSettle();
    });

    testWidgets('it appears the moment the lift starts', (t) async {
      await t.pumpWidget(host(const SplashGate(
          child: Center(child: Text('portal', key: Key('portal'))))));
      await t.pump();
      await t.pump(SplashGate.hold + const Duration(milliseconds: 1));
      // Its entrance now runs IN VIEW, under a curtain going transparent.
      expect(find.byKey(const Key('portal')), findsOneWidget);
      await t.pumpAndSettle();
    });

    testWidgets('the seal is over it while it holds', (t) async {
      await t.pumpWidget(host(const SplashGate(child: SizedBox())));
      await t.pump();
      expect(find.text('Sri Lanka Customs'), findsOneWidget);
      expect(find.text('SR Management System'), findsOneWidget);
      await t.pump(SplashGate.hold);
      await t.pumpAndSettle();
    });
  });

  group('it gets out of the way', () {
    testWidgets('the splash is gone from the tree once it has lifted',
        (t) async {
      await t.pumpWidget(host(const SplashGate(child: SizedBox())));
      await t.pump();
      expect(find.text('Sri Lanka Customs'), findsOneWidget);

      // Hold, then dissolve.
      await t.pump(SplashGate.hold);
      await t.pump(SplashGate.fade);
      await t.pumpAndSettle();

      // ⚠️ Removed entirely, not merely transparent: a stacked overlay left
      // behind keeps eating pointer events and repainting a blur nobody sees.
      expect(find.text('Sri Lanka Customs'), findsNothing);
    });

    testWidgets('the page below becomes clickable as soon as it starts showing',
        (t) async {
      var taps = 0;
      await t.pumpWidget(host(SplashGate(
        child: Center(
          child: GestureDetector(
            // ⚠️ behavior: opaque. A bare SizedBox has no background and is
            // not hit-testable, so the tap misses whether a splash is over it
            // or not -- which would make this test pass for the wrong reason.
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 200, height: 80, key: Key('card')),
          ),
        ),
      )));
      await t.pump();

      // The card is not even mounted while the seal holds.
      expect(find.byKey(const Key('card')), findsNothing);

      // Once it lifts the page takes taps, even mid-fade.
      await t.pump(SplashGate.hold + const Duration(milliseconds: 1));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.byKey(const Key('card')));
      expect(taps, 1);

      await t.pumpAndSettle();
    });
  });

  group('the timings stay honest', () {
    test('the hold is short', () {
      // ⚠️ A splash that outstays the work it covers is just a delay, and this
      // one runs on every launch.
      expect(SplashGate.hold.inMilliseconds, lessThanOrEqualTo(1000));
      // ⚠️ The fade is deliberately LONGER than the hold now: the portal's own
      // entrance runs underneath it, and a curtain that vanished first left
      // half the cards still visibly moving.
      expect(SplashGate.fade.inMilliseconds,
          greaterThan(SplashGate.hold.inMilliseconds ~/ 2));
      // Together they still have to stay out of the way quickly.
      expect(
          (SplashGate.hold + SplashGate.fade).inMilliseconds,
          lessThanOrEqualTo(2000));
    });
  });

  group('the blur', () {
    final src =
        File('lib/screens/home/splash_gate.dart').readAsStringSync();

    test('is never applied at exactly zero sigma', () {
      // ⚠️ A zero-sigma blur renders as a black rectangle on some backends
      // rather than as no blur at all.
      expect(src, contains('t <= 0.001'));
      expect(src, contains('sigmaX: 0.01, sigmaY: 0.01'));
    });

    test('the layer recedes as one thing', () {
      // Blur and scale share the same tween, so it does not fade in parts.
      expect(src, contains('Transform.scale(scale: 1 + t * 0.06'));
    });
  });

  group('the background does not jump when the seal lifts', () {
    final splash =
        File('lib/screens/home/splash_gate.dart').readAsStringSync();
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();

    test('both use the SAME widget, not two copies of it', () {
      // ⚠️ The glows are mid-travel when the seal lifts. Two independent
      // copies would be at different points on their paths, so the background
      // would jump at the one moment the reader is looking straight at it.
      expect(home, contains('class DriftingGlows extends StatefulWidget'));
      expect(splash, contains("import 'home_screen.dart' show DriftingGlows;"));
      for (final src in [splash, home]) {
        expect(src, contains('Positioned.fill(child: DriftingGlows())'));
      }
      // And the splash keeps no glow of its own to drift out of step.
      expect(splash, isNot(contains('class _Glow ')));
    });

    test('the drift never intercepts a click meant for a portal card', () {
      final layer = home.substring(home.indexOf('class DriftingGlows'));
      expect(layer, contains('IgnorePointer('));
    });

    test('it loops without a jump, and slowly', () {
      // Reversing rather than restarting, so it never snaps back; eased, so
      // each pass slows at the turn.
      expect(home, contains('..repeat(reverse: true)'));
      expect(home, contains('Curves.easeInOutSine.transform'));
      // Slow enough not to distract from choosing a portal.
      expect(home, contains('duration: const Duration(seconds: 24)'));
    });

    test('the controller is disposed', () {
      final layer = home.substring(home.indexOf('class _DriftingGlowsState'));
      expect(layer, contains('_c.dispose();'));
    });
  });

  group('the seal carries no gold line', () {
    test('the progress bar is gone', () {
      // ⚠️ It read as an underline on the name rather than as a loading
      // indicator, and it was the only gold on an otherwise blue-and-white
      // mark. The dissolve already says the app is working.
      final splash =
          File('lib/screens/home/splash_gate.dart').readAsStringSync();
      expect(splash, isNot(contains('LinearProgressIndicator')));
    });
  });
}
