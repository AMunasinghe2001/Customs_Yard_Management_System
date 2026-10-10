// Yard Access's crest and title were all but invisible: its accent is #1A237E
// on a #060D1F panel, a contrast ratio of 1.46. Every other portal runs 2.29x
// (Appeal) to 8.57x, so it was the only one that could not be read.
//
// The panel now draws its crest, title and badge marks in WHITE when the
// accent cannot carry them, and keeps the accent everywhere else.
//
//     portal              accent vs deep   ink      ink vs deep
//     Yard Access          1.46x           WHITE      19.4x
//     Appeal (purple)      2.29x           accent      2.3x
//     ICT                  2.83x           accent      2.8x
//     Disposal (green)     3.53x           accent      3.5x
//     Top Mgmt (teal)      3.80x           accent      3.8x
//     Valuation (gold)     7.91x           accent      7.9x
//     DC/SDDC (gold)       8.57x           accent      8.6x
//
// ⚠️ The threshold is 1.9, and it sits in the GAP rather than next to a
// value: 1.46 on one side, 2.29 on the other, nothing between. A threshold at
// 2.2 would have left purple 0.09 from turning white, and a designer nudging
// that swatch would have restyled a portal by accident.
//
// ⚠️ Only the panel's MARKS change. The gradient corner, the badge fill
// and its border still carry the accent -- the branding being in the portal's
// colour is the point of it, and none of those has to be legible.
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';

double _ch(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) =>
    0.2126 * _ch(c.r) + 0.7152 * _ch(c.g) + 0.0722 * _ch(c.b);
double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const yardBlue = Color(0xFF1A237E);
  final portals = <String, (Color, Color)>{
    'Yard Access': (yardBlue, const Color(0xFF060D1F)),
    'Valuation (gold)': (const Color(0xFFD4A017), const Color(0xFF0A0F2C)),
    'DC/SDDC (gold)': (const Color(0xFFD4A017), const Color(0xFF050411)),
    'Disposal (green)': (AppTheme.successGreen, const Color(0xFF051A0F)),
    'Top Mgmt (teal)': (AppTheme.executiveTeal, const Color(0xFF0A0F2C)),
    'ICT': (AppTheme.ictCyan, const Color(0xFF050411)),
    'Appeal (purple)': (AppTheme.appealPurple, const Color(0xFF0A0F2C)),
  };

  test('the ink rule picks white only where the accent cannot be read', () {
    // ignore: avoid_print
    print('  portal              accent vs deep   ink       ink vs deep');
    for (final e in portals.entries) {
      final (accent, deep) = e.value;
      final c = _contrast(accent, deep);
      final ink = c < 1.9 ? Colors.white : accent;
      final inkC = _contrast(ink, deep);
      // ignore: avoid_print
      print('  ${e.key.padRight(18)} ${c.toStringAsFixed(2)}x'
          '            ${ink == Colors.white ? "WHITE " : "accent"}    '
          '${inkC.toStringAsFixed(1)}x');

      // ⚠️ 2.2, which is where the complaint actually sat. The five
      // other panels run 2.83x (ICT) to 8.57x and were never objected to;
      // Yard Access was 1.46x, half the dimmest of them, and that is the gap
      // the eye picked up. A floor at 3.0 would have swept ICT and Appeal in
      // too -- a restyle of four panels nobody asked about.
      expect(inkC, greaterThan(2.2), reason: '${e.key} branding is too dim');
    }
  });

  test('only Yard Access changes', () {
    // ⚠️ The five that already read correctly keep their own colour —
    // branding being IN the portal's colour is the point of it. A threshold
    // that swept purple (2.36x) into white as well would be a restyle.
    for (final e in portals.entries) {
      final (accent, deep) = e.value;
      final isWhite = _contrast(accent, deep) < 1.9;
      expect(isWhite, e.key == 'Yard Access',
          reason: '${e.key} changed and should not have');
    }
  });

  group('the panel is built the way this measures', () {
    final source = File('lib/widgets/brand_panel.dart').readAsStringSync();

    test('the ink rule is in the widget, at 1.9', () {
      expect(source, contains('Color get _ink'));
      expect(source, contains('contrast < 1.9 ? Colors.white : widget.accent'));
    });

    test('the crest, title and badge marks use it', () {
      // ⚠️ Four marks. Missing one leaves a panel where the title is
      // white and the crest is still sinking into the background, which is
      // worse than either.
      expect(source, contains('tint: ink'));
      expect('color: ink,'.allMatches(source).length, greaterThanOrEqualTo(2));
      expect(source, contains('Icon(widget.badgeIcon, color: ink'));
    });

    test('the accent still carries the panel itself', () {
      // The gradient and the badge's fill and border are the portal's colour,
      // and must stay so.
      expect(source, contains('_corner(accent, t)'));
      expect(source, contains('border: Border.all(color: accent.withOpacity(0.3))'));
      expect(source, contains('color: accent.withOpacity(0.06)'));
    });
  });
}
