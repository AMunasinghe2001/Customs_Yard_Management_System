// The crest's ship and aeroplane are painted a flat #1a1764 -- the app's own
// dark navy -- because a real transparent knockout does not survive
// flutter_svg. That only reads as a hole while the background behind them IS
// that colour, and the panel is a three-stop gradient, so it only just held.
//
// Animating the gradient breaks it outright: the two shapes stop matching what
// is behind them and the crest grows two navy stickers. This is what the panel
// has to keep true while it moves.
import 'dart:io';
import 'dart:math' as math;

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
    final asset = File('Sri_Lanka_Customs_logo_tinted.svg').readAsStringSync();

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

  group('the animation is calm enough to sit behind a password field', () {
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
      expect(sized.any((s) => s.width == 240 && s.height == 240), isTrue,
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

  group('the halo lights the crest without breaking it', () {
    test('it is painted UNDER the crest, never over it', () {
      // ⚠️ The ship and plane are fake holes, filled with the colour behind
      // them. Anything drawn ON TOP would tint the disc and those two shapes
      // by different amounts and they would stop reading as cut out — the
      // one thing this widget exists to protect.
      //
      // ⚠️ A SOURCE check. rootBundle does not serve project assets under
      // `flutter test` (see the note at the top of this file), so the crest
      // never renders here and the widget tree cannot show the ordering. A
      // widget test of this would pass against either order, which is worse
      // than no test.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      final halo = src.indexOf('RadialGradient(');
      final crest = src.indexOf('child!,');
      expect(halo, greaterThan(-1), reason: 'no halo found');
      expect(crest, greaterThan(halo),
          reason: 'the crest must come after the halo in the Stack');
    });

    testWidgets('it brightens rather than growing', (t) async {
      // A halo that changes SIZE reads as something approaching and pulls
      // the eye; one that only changes opacity reads as light.
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));

      Size haloSize() {
        final f = find.descendant(
            of: find.byType(BrandPanel), matching: find.byType(Container));
        for (final c in t.widgetList<Container>(f)) {
          final d = c.decoration;
          if (d is BoxDecoration && d.shape == BoxShape.circle) {
            return Size(
                c.constraints?.maxWidth ?? 0, c.constraints?.maxHeight ?? 0);
          }
        }
        return Size.zero;
      }

      final a = haloSize();
      await t.pump(const Duration(seconds: 5));
      final b = haloSize();
      expect(a, b, reason: 'the halo changed size instead of brightness');
      expect(a.width, greaterThan(0), reason: 'no circular halo was found');
    });

    testWidgets('the two animations run on different clocks', (t) async {
      // ⚠️ On one clock the panel would breathe in and out as a single
      // object, which is exactly the thing that draws attention away from
      // the form.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      expect(src, contains('Duration(seconds: 9)'));
      expect(src, contains('Duration(seconds: 14)'));
    });

    testWidgets('both controllers are disposed', (t) async {
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(_host(const SizedBox()));
      await t.pump(const Duration(seconds: 2));
      expect(t.takeException(), isNull);
    });
  });

  group('the portal name reads as its own thing', () {
    testWidgets('a rule separates the service from the door', (t) async {
      // The service's name and the portal being used are two different
      // statements; they were stacked with nothing between them.
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      final rules = t.widgetList<Container>(find.descendant(
          of: find.byType(BrandPanel), matching: find.byType(Container)));
      expect(rules.any((c) => c.constraints?.maxHeight == 1), isTrue,
          reason: 'no hairline between the subtitle and the badge');
    });

    testWidgets('the name and the portal are both still shown', (t) async {
      // The crest itself cannot be asserted here — rootBundle serves no
      // project assets under `flutter test`, so it stays on its placeholder.
      // Its reserved 240x240 is covered by the test above.
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Sri Lanka Customs'), findsOneWidget);
      expect(find.text('SR Management System'), findsOneWidget);
      expect(find.text('Central Disposal Directorate'), findsOneWidget);
    });
  });

  group('the background actually moves', () {
    testWidgets('a painted orb field sits behind the content', (t) async {
      // ⚠️ The gradient alone was the complaint: a six-stop ramp between two
      // near-blacks changes too little to see. The orbs give the eye
      // something with a SHAPE to follow.
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));
      expect(
          find.descendant(
              of: find.byType(BrandPanel), matching: find.byType(CustomPaint)),
          findsWidgets);
    });

    testWidgets('the orbs travel over seconds', (t) async {
      await t.pumpWidget(_host(_panel()));
      await t.pump(const Duration(milliseconds: 100));

      CustomPainter? painter() {
        for (final cp in t.widgetList<CustomPaint>(find.descendant(
            of: find.byType(BrandPanel), matching: find.byType(CustomPaint)))) {
          if (cp.painter?.runtimeType.toString().contains('Orb') ?? false) {
            return cp.painter;
          }
        }
        return null;
      }

      final a = painter();
      expect(a, isNotNull, reason: 'no orb painter found');
      await t.pump(const Duration(seconds: 6));
      final b = painter();
      expect(a!.shouldRepaint(b!), isTrue,
          reason: 'the orbs did not move at all');
    });

    test('the loop closes rather than reversing', () {
      // ⚠️ A reversing controller would send the orbs back along the path
      // they just took, which the eye reads as a rewind. Sine and cosine of
      // the value make the loop close on itself: at t=1 every orb is exactly
      // where it was at t=0.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      final i = src.indexOf('_orbs = AnimationController(');
      expect(i, greaterThan(-1));
      final block = src.substring(i, i + 200);
      expect(block.contains('reverse: true'), isFalse,
          reason: 'the orb loop must not reverse');
      expect(src, contains('math.cos(angle)'));
      expect(src, contains('math.sin(angle)'));
    });

    test('the three orbs do not share a period', () {
      // On matching periods the three return to the same arrangement every
      // cycle and the panel visibly repeats.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      expect(src, contains('speed: 1.00'));
      expect(src, contains('speed: 0.61'));
      expect(src, contains('speed: 1.37'));
    });

    test('it repaints only when something changed', () {
      // shouldRepaint returning true unconditionally would repaint the whole
      // panel on every frame of every other animation as well.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      expect(src, contains('old.t != t || old.accent != accent'));
    });

    test('the orbs are behind a RepaintBoundary', () {
      // The crest above them rebuilds on the gradient's clock; without this
      // the orb field would be re-rasterised along with it.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      final i = src.indexOf('_OrbFieldPainter(');
      expect(src.substring(0, i), contains('RepaintBoundary('));
    });
  });

  group('gold does not wash the panel yellow', () {
    // ⚠️ Gold (#D4A017) has ~2.4x the relative luminance of the next
    // brightest accent and 5x the dimmest. At one shared strength its orbs
    // read as lamps while purple's read as a tint — and the banding, which is
    // a function of how much light is being ramped, showed on gold alone.
    double lum(Color c) {
      double ch(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    // ⚠️ Read the slope and floor OUT OF THE SOURCE rather than restating
    // them. A copy of the formula here passes whatever the widget does: when
    // the panel was darkened for "too much yellow", this group still went
    // green against the old numbers because the test was only checking
    // itself.
    final panelSrc = File('lib/widgets/brand_panel.dart').readAsStringSync();
    final trimExpr = RegExp(
            r'return \(1\.0 - \(l - 0\.08\) \* ([0-9.]+)\)\.clamp\(([0-9.]+), 1\.0\);')
        .firstMatch(panelSrc)!;
    final trimSlope = double.parse(trimExpr.group(1)!);
    final trimFloor = double.parse(trimExpr.group(2)!);

    double orbTrim(Color c) =>
        (1.0 - (lum(c) - 0.08) * trimSlope).clamp(trimFloor, 1.0);

    const gold = Color(0xFFD4A017);
    const purple = Color(0xFF7B1FA2);

    test('the orbs are dimmed in proportion to the accent', () {
      // ⚠️ The PROPERTY, not the number: gold is trimmed hard, the dim
      // accents are left alone. The exact figures have moved twice now
      // (gold 0.55 -> 0.36 when the panel was darkened again) and pinning
      // them only made this test an echo of the source.
      expect(orbTrim(purple), closeTo(1.00, 0.02),
          reason: 'the dim accents must keep their light');
      expect(orbTrim(gold), lessThan(0.45),
          reason: 'gold is the accent that washes the panel');
      expect(orbTrim(gold), greaterThan(0.20),
          reason: 'trimmed, not extinguished');
    });

    test('the trim is applied to the orb alpha, not just computed', () {
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      expect(src, contains('o.a * trim *'),
          reason: 'the trim was worked out and then ignored');
    });

    test('the gradient corner is held back further too', () {
      // The corner and the orbs are two sources of the same colour on one
      // panel; on gold the two together read as a wash.
      // ⚠️ Asserted as a PROPERTY of the floor, not as the literal text of
      // the expression. The previous version of this test pinned
      // "(0.34 + ((_accentLuminance - 0.17) * 1.1)" and so had to be edited
      // every time the panel was retuned, which tells you nothing about
      // whether gold is still held back.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      final floorExpr = RegExp(r'\(([0-9.]+) \+ \(\(_accentLuminance - 0\.17\)'
              r' \* ([0-9.]+)\)\.clamp\(0\.0, ([0-9.]+)\)\)\s*'
              r'\.clamp\(0\.0, ([0-9.]+)\)')
          .firstMatch(src)!;
      final base = double.parse(floorExpr.group(1)!);
      final mult = double.parse(floorExpr.group(2)!);
      final term = double.parse(floorExpr.group(3)!);
      final cap = double.parse(floorExpr.group(4)!);

      double floorFor(Color c) =>
          (base + ((lum(c) - 0.17) * mult).clamp(0.0, term)).clamp(0.0, cap);

      // Gold is held back much further than the dim accents...
      expect(floorFor(gold), greaterThan(0.70));
      expect(floorFor(purple), closeTo(base, 0.001));
      // ...and the ceiling must not be the thing doing the limiting, or the
      // formula stops responding to the accent at all.
      expect(cap, greaterThan(floorFor(gold)));
    });
  });

  group('the banding is blurred away, not just made finer', () {
    test('the whole field goes through one blur', () {
      // ⚠️ The eight-stop ramp removed the hard rings, but a gradient still
      // quantises to 256 levels per channel and on gold the remaining steps
      // read as faint contour lines. A blur smears each step into its
      // neighbours, which is what actually removes them.
      final src = File('lib/widgets/brand_panel.dart').readAsStringSync();
      expect(src, contains('ui.ImageFilter.blur('));
      // One saveLayer for all three orbs: the filter is the expensive part,
      // and it is the same filter.
      expect('canvas.saveLayer('.allMatches(src).length, 1);
      expect('canvas.restore()'.allMatches(src).length, 1);
    });
  });

  group('the crest sits on the deep colour, not on the accent', () {
    final src = File('lib/widgets/brand_panel.dart').readAsStringSync();

    test('a pool of the deep colour is painted over the middle', () {
      // ⚠️ Keeping the orbs in the corners is not enough on its own: they
      // are blurred by 18px and fade over hundreds more, so their light
      // still reaches the centre. The mark needs dark behind it — and the
      // ship and plane are painted with ONE expected colour that cannot
      // track a drifting tint.
      expect(src, contains('final vignetteRadius'));
      expect(src, contains('deep.withOpacity(0.82'));
    });

    test('it is painted LAST, after the orbs', () {
      final orbs = src.indexOf('canvas.restore();');
      final vignette = src.indexOf('final vignetteRadius');
      expect(orbs, greaterThan(-1));
      expect(vignette, greaterThan(orbs),
          reason: 'the orbs would be drawn back over the dark centre');
    });

    test('the orbs are small enough to stay out of the middle', () {
      // At r = 0.5..0.62 a disc centred at (0.18, 0.16) still reaches well
      // past the centre, so three of them covered the whole panel and the
      // accent became the panel's colour rather than light in its corners.
      final m = RegExp(r'r: (0\.\d+)').allMatches(src).toList();
      expect(m, isNotEmpty);
      for (final match in m.take(3)) {
        expect(double.parse(match.group(1)!), lessThan(0.40),
            reason: 'an orb is wide enough to cover the crest');
      }
    });

    test('the gradient keeps its accent in the last third', () {
      // These two stops used to carry most of the accent at 0.22 and 0.46,
      // so the colour reached the middle of the panel.
      expect(src, contains('_corner(accent), 0.08)'));
      expect(src, contains('_corner(accent), 0.24)'));
    });
  });
}
