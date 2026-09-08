// The two GOLD sign-in panels showed a visible EDGE across the panel — a line
// where the colour turned, rather than light falling across it. The other four
// did not.
//
// A band is a place where brightness changes much faster than either side of
// it, so it can be measured: sample the ramp, divide the biggest step by the
// average. 1.0 would be perfectly even.
//
//     panel               before  after
//     Valuation (gold)     3.89   2.69
//     DC/SDDC (gold)       3.85   2.53
//     Disposal (green)     3.72   3.78
//     Top Mgmt (teal)      3.60   3.67
//     ICT                  3.29   3.02
//     Appeal (purple)      3.29   3.22
//
// ⚠️ Only the two that looked wrong moved. The other four sit within 0.1 of
// where they were, which is the point: they already read correctly, and a fix
// that changes them is a redesign in disguise.
//
// The panels are all one widget, so the numbers differ only because the
// accents do. Gold is the outlier — #D4A017 has relative luminance 0.392
// against 0.078 for purple, so on gold the two ends of the ramp are far enough
// apart for the eye to pick the ramp itself out.
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';

double _ch(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) =>
    0.2126 * _ch(c.r) + 0.7152 * _ch(c.g) + 0.0722 * _ch(c.b);

// The panel's own two curves, restated here so the numbers can be checked
// without pumping six windows. A test that pinned the widget's private methods
// would break on a rename while saying nothing about how the panel looks.
double _depth(Color a) => (1.0 + (_lum(a) - 0.08) * 2.5).clamp(1.0, 1.8);
double _floor(Color a) =>
    (0.22 + ((_lum(a) - 0.17) * 0.9).clamp(0.0, 0.28)).clamp(0.0, 0.55);

Color _corner(Color accent, Color deep, [double t = 1.0]) => Color.lerp(
    accent,
    deep,
    (_floor(accent) + 0.35 * _depth(accent) * (1 - t)).clamp(0.0, 0.75))!;

List<Color> _ramp(Color accent, Color deep, Color navy, double t) {
  final behind = Color.lerp(navy, accent, 0.10 * t * _depth(accent))!;
  final corner = _corner(accent, deep);
  return [
    deep,
    Color.lerp(deep, behind, 0.45)!,
    behind,
    Color.lerp(behind, corner, 0.38)!,
    Color.lerp(behind, corner, 0.72)!,
    _corner(accent, deep, t),
  ];
}

List<double> _stops(double t) =>
    [for (var i = 0; i < 6; i++) (i / 5) * (1 - 0.06 * t) + 0.06 * t];

Color _at(List<Color> colours, List<double> stops, double x) {
  for (var i = 0; i < stops.length - 1; i++) {
    if (x <= stops[i + 1]) {
      final span = stops[i + 1] - stops[i];
      final f = span <= 0 ? 0.0 : (x - stops[i]) / span;
      return Color.lerp(colours[i], colours[i + 1], f.clamp(0.0, 1.0))!;
    }
  }
  return colours.last;
}

double _abruptness(List<Color> colours, List<double> stops) {
  const samples = 200;
  final steps = <double>[];
  var previous = _lum(_at(colours, stops, 0));
  for (var i = 1; i <= samples; i++) {
    final l = _lum(_at(colours, stops, i / samples));
    steps.add((l - previous).abs());
    previous = l;
  }
  final mean = steps.reduce((a, b) => a + b) / steps.length;
  return mean <= 0 ? 1.0 : steps.reduce(math.max) / mean;
}

void main() {
  const gold = Color(0xFFD4A017);
  const navy = Color(0xFF0e0c3a);

  final portals = <String, (Color, Color)>{
    'Valuation (gold)': (gold, const Color(0xFF0A0F2C)),
    'DC/SDDC (gold)': (gold, const Color(0xFF050411)),
    'Disposal (green)': (AppTheme.successGreen, const Color(0xFF051A0F)),
    'Top Mgmt (teal)': (AppTheme.executiveTeal, const Color(0xFF0A0F2C)),
    'ICT': (AppTheme.ictCyan, const Color(0xFF050411)),
    'Appeal (purple)': (AppTheme.appealPurple, const Color(0xFF0A0F2C)),
  };

  double worst(Color accent, Color deep) {
    var w = 0.0;
    // A band can appear at either end of the cycle, so check both and the
    // middle.
    for (final t in [0.0, 0.5, 1.0]) {
      w = math.max(w, _abruptness(_ramp(accent, deep, navy, t), _stops(t)));
    }
    return w;
  }

  group('no panel shows an edge', () {
    test('every portal ramps evenly enough', () {
      for (final e in portals.entries) {
        final (accent, deep) = e.value;
        expect(worst(accent, deep), lessThan(3.9),
            reason: '${e.key} has a hard turn in its gradient');
      }
    });

    test('the gold panels are no longer the worst of the six', () {
      // ⚠️ This is the actual complaint, in numbers: gold used to be the
      // roughest ramp of the six (3.89 against 3.29-3.72). It must not be.
      final goldWorst = math.max(
          worst(gold, const Color(0xFF0A0F2C)), worst(gold, const Color(0xFF050411)));
      for (final e in portals.entries.where((e) => !e.key.contains('gold'))) {
        final (accent, deep) = e.value;
        expect(goldWorst, lessThan(worst(accent, deep)),
            reason: 'gold is rougher than ${e.key} again');
      }
    });

    test('no corner reaches its pure accent', () {
      // ⚠️ A corner of undiluted colour is what makes a gradient read as a
      // shape rather than as light. Every portal is held back now, not only
      // the bright ones.
      for (final e in portals.entries) {
        final (accent, deep) = e.value;
        expect(_lum(_corner(accent, deep)), lessThan(_lum(accent) * 0.92),
            reason: '${e.key} reaches full accent at the corner');
      }
    });
  });

  group('the panel is built the way the measurements assume', () {
    final source = File('lib/widgets/brand_panel.dart').readAsStringSync();

    test('six stops, evenly spaced', () {
      // ⚠️ Adding stops is not enough on its own — measured on gold, holding
      // the first third flat and then turning scored 6.15 against the old
      // 3.53. It squeezed the same change into less room. Even spacing is
      // what removes the edge, so the generated stops are the point.
      expect(source, contains('for (var i = 0; i < 6; i++) (i / 5)'));
      // Six colours to go with them.
      final colours = source.substring(source.indexOf('colors: ['));
      expect(RegExp(r'Color\.lerp|widget\.deepColor|_corner')
              .allMatches(colours.substring(0, 700))
              .length,
          greaterThanOrEqualTo(5));
    });

    test('the corner is one definition, used by every stop', () {
      // Two copies of "how far back is the accent pulled" is two chances for
      // the last stop and the ones feeding it to disagree — which would put
      // the edge back.
      expect(source, contains('Color _corner(Color accent, [double t = 1.0])'));
      expect('_corner('.allMatches(source).length, greaterThanOrEqualTo(4));
    });
  });
}
