// The crest's ship and aeroplane are painted a flat #1a1764 -- the app's own
// dark navy -- because a real transparent knockout does not survive
// flutter_svg. That only reads as a hole while the background behind them IS
// that colour, and the panel is a three-stop gradient, so it only just held.
//
// Animating the gradient breaks it outright: the two shapes stop matching what
// is behind them and the crest grows two navy stickers. This is what the panel
// has to keep true while it moves.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/brand_panel.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: SizedBox(width: 600, height: 800, child: child)),
    );

BrandPanel _panel() => const BrandPanel(
      accent: Color(0xFF2E7D32),
      deepColor: Color(0xFF051A0F),
      badgeLabel: 'Central Disposal Directorate',
      badgeIcon: Icons.gavel_rounded,
    );

/// The gradient the panel is painting this frame.
LinearGradient _gradient(WidgetTester t) {
  final box = t.widget<Container>(find
      .descendant(of: find.byType(BrandPanel), matching: find.byType(Container))
      .first);
  return (box.decoration as BoxDecoration).gradient as LinearGradient;
}

void main() {
  group('the knockout follows the background', () {
    // ⚠️ Tested against the REAL asset file, read from disk. A widget test
    // cannot see the SVG string -- rootBundle does not serve project assets in
    // the test harness -- and asserting on a colour passed around the widget
    // tree would prove nothing: a knockout handed along correctly but never
    // written into the SVG looks identical in the tree and wrong on screen.
    final asset =
        File('Sri_Lanka_Customs_logo_tinted.svg').readAsStringSync();

    test('the asset really does have a painted-on knockout', () {
      // If this fails the crest was re-exported. Check whether it now has real
      // transparency -- in which case delete crestWithKnockout entirely.
      expect(asset, contains('fill:$kCrestKnockoutHex'));
      expect('fill:$kCrestKnockoutHex'.allMatches(asset).length, 2,
          reason: 'the ship and the plane -- two paths, no more, no fewer');
    });

    test('the swap repaints both of them, and nothing else', () {
      const behind = Color(0xFF123456);
      final out = crestWithKnockout(asset, behind);

      expect(out.contains('fill:$kCrestKnockoutHex'), isFalse,
          reason: 'a knockout was left at the asset colour');
      expect('fill:#123456'.allMatches(out).length, 2);

      // The tinted paths are untouched: they are what SvgTheme colours.
      expect('fill:currentColor'.allMatches(out).length,
          'fill:currentColor'.allMatches(asset).length);
      expect(out.length, asset.length,
          reason: 'both hexes are 7 chars — nothing else should have moved');
    });

    test('alpha is dropped, because a see-through hole is not a hole', () {
      // SVG fill takes #rrggbb. A half-transparent knockout would let the
      // filled disc beneath show through and stop reading as a hole at all.
      final out = crestWithKnockout(asset, const Color(0x80123456));
      expect(out, contains('fill:#123456'));
      expect(out.contains('80123456'), isFalse);
    });

    test('a different colour behind gives a different knockout', () {
      // The point of the whole exercise: as the gradient moves, this moves.
      final a = crestWithKnockout(asset, const Color(0xFF1A1764));
      final b = crestWithKnockout(asset, const Color(0xFF1E2A6B));
      expect(a, isNot(b));
    });

    testWidgets('the panel feeds it the colour behind the crest', (t) async {
      // The crest sits at the middle of the panel, so the colour behind it is
      // the gradient's MIDDLE stop -- and that is what must reach the SVG.
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      final mid1 = _gradient(t).colors[1];

      await t.pump(const Duration(seconds: 3));
      final mid2 = _gradient(t).colors[1];

      expect(mid2, isNot(mid1),
          reason: 'the background never moved, so nothing had to keep up');

      // And the two knockouts those colours produce differ, which is what
      // stops the crest growing two navy stickers mid-animation.
      expect(crestWithKnockout(asset, mid1),
          isNot(crestWithKnockout(asset, mid2)));
    });
  });

  group('the animation is calm enough to sit behind a password field',
      () {
    testWidgets('one full cycle takes several seconds, not a moment',
        (t) async {
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      final a = _gradient(t).colors[2];

      // Half a second in, the accent should barely have moved. A background
      // that changes visibly in half a second competes with the form.
      await t.pump(const Duration(milliseconds: 500));
      final b = _gradient(t).colors[2];

      final da = (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
      expect(da, lessThan(0.12),
          reason: 'the accent is moving fast enough to distract');

      await t.pump(const Duration(seconds: 4));
      final c = _gradient(t).colors[2];
      final dc = (a.r - c.r).abs() + (a.g - c.g).abs() + (a.b - c.b).abs();
      expect(dc, greaterThan(da),
          reason: 'over seconds it should actually travel');
    });

    testWidgets('it reverses rather than snapping back to the start',
        (t) async {
      // A repeat() without reverse jumps from the end to the beginning, and
      // the jump is the thing the eye catches on a loop this slow.
      await t.pumpWidget(_host(_panel()));
      final samples = <Color>[];
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 750));
        samples.add(_gradient(t).colors[2]);
      }
      // No single step may be a large jump: a snap-back would show as one.
      var biggest = 0.0;
      for (var i = 1; i < samples.length; i++) {
        final d = (samples[i].r - samples[i - 1].r).abs() +
            (samples[i].g - samples[i - 1].g).abs() +
            (samples[i].b - samples[i - 1].b).abs();
        if (d > biggest) biggest = d;
      }
      expect(biggest, lessThan(0.25), reason: 'the loop snaps back visibly');
    });

    testWidgets('the stops move too, so it reads as light not as a fade',
        (t) async {
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      final s1 = _gradient(t).stops![1];
      await t.pump(const Duration(seconds: 3));
      final s2 = _gradient(t).stops![1];
      expect(s1, isNot(s2));

      // ⚠️ And never cross: stops out of order throw at paint time.
      final g = _gradient(t);
      for (var i = 1; i < g.stops!.length; i++) {
        expect(g.stops![i], greaterThan(g.stops![i - 1]));
      }
    });
  });

  group('the panel still says what it used to', () {
    testWidgets('name, subtitle and portal badge', (t) async {
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Sri Lanka Customs'), findsOneWidget);
      expect(find.text('SR Management System'), findsOneWidget);
      expect(find.text('Central Disposal Directorate'), findsOneWidget);
      expect(find.byIcon(Icons.gavel_rounded), findsOneWidget);
    });

    testWidgets('the crest keeps its space while the asset loads', (t) async {
      // Otherwise the title and badge jump upward on first paint, which is
      // more noticeable than the crest arriving a frame late.
      await t.pumpWidget(_host(_panel()));
      await t.pump(); // one frame: the FutureBuilder has no data yet
      final sized = t.widgetList<SizedBox>(find.descendant(
          of: find.byType(BrandPanel), matching: find.byType(SizedBox)));
      expect(sized.any((s) => s.width == 200 && s.height == 200), isTrue,
          reason: 'nothing reserves the crest\'s 200x200');
    });

    testWidgets('it disposes its controller', (t) async {
      // A repeating controller left running keeps the screen rebuilding for
      // as long as the app lives.
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(_host(const SizedBox()));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
    });
  });
}
