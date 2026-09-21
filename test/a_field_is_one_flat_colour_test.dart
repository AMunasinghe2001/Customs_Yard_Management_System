// A text box is ONE colour, in every state.
//
// ⚠️ Reported three times, and only the third report named both halves:
// "සුදු අලු මික්ස් වෙලා ශේඩ් වෙන විදිහට... කර්සර් එක ලගට ගෙනිච්චත් එහෙමයි,
// නිකනුත් එහෙමයි" — the boxes look shaded, hovered or not, and two fields in
// one form did not match each other.
//
// Two separate causes, and fixing either alone left the complaint standing:
//
//   1. THE HOVER BLEND. A `filled: true` input blends `ThemeData.hoverColor`
//      over its fill whenever the pointer is near — Flutter computes
//      `alphaBlend(hoverColor, fillColor)` — so a field was one grey at rest
//      and a darker grey under the cursor. In a screenshot the hovered field
//      and its neighbour read as two different colours.
//
//   2. THE TINT. The fill was a blue-leaning off-white (#F4F7FC, R−B = −8)
//      on a page that leans blue harder, so the two shaded into each other
//      instead of reading as a fill on a background.
//
// ⚠️ Read from the SOURCE, not from `AppTheme.lightTheme`. Building the theme
// pulls in Google Fonts, which in a test either fetches over the network or
// throws for a missing asset — neither has anything to do with colour.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Color(0xFFRRGGBB)` for a named constant in theme.dart.
Color _themeColor(String src, String name) {
  // ⚠️ Allow a line break: `dart format` wraps `static const Color _x =`
  // onto the next line, so an anchored one-line pattern silently misses and
  // the test dies on a null check instead of saying what it could not find.
  final m = RegExp('$name =\\s*Color\\(0x([0-9A-Fa-f]{8})\\)').firstMatch(src);
  expect(m, isNotNull, reason: '$name not found in theme.dart');
  return Color(int.parse(m!.group(1)!, radix: 16));
}

int _delta(Color a, Color b) {
  int ch(double x) => (x * 255).round();
  return (ch(a.r) - ch(b.r)).abs() +
      (ch(a.g) - ch(b.g)).abs() +
      (ch(a.b) - ch(b.b)).abs();
}

void main() {
  final src = File('lib/core/theme.dart').readAsStringSync();

  group('a field does not change colour when the pointer is near', () {
    test('the input theme kills the hover blend', () {
      // ⚠️ Transparent, not "something subtle". Any non-zero alpha is
      // blended over the fill and the box changes colour under the mouse,
      // which is the whole complaint. One setting covers both themes,
      // because both are built by `_buildTheme`.
      expect(src, contains('hoverColor: Colors.transparent'),
          reason: 'fields will shade under the cursor again');
    });

    test('and it is set on the INPUT theme, where filled inputs read it', () {
      // A top-level `ThemeData.hoverColor` would also change buttons and
      // list tiles; this belongs to the fields alone.
      final i = src.indexOf('inputDecorationTheme: InputDecorationTheme(');
      expect(i, greaterThan(-1));
      final block = src.substring(i, i + 2500);
      expect(block, contains('hoverColor: Colors.transparent'));
    });

    test('a transparent hover leaves the fill exactly as it was', () {
      // The property Flutter actually paints: alphaBlend(hover, fill).
      final fill = _themeColor(src, '_fieldFillLight');
      expect(Color.alphaBlend(Colors.transparent, fill), fill);
    });
  });

  group('the fill is a single, near-neutral colour', () {
    test('it does not lean blue', () {
      // ⚠️ THE TINT is what kept this failing after the hover fix. A fill
      // leaning the same way as the page shades into it; a near-neutral
      // grey reads as a deliberate fill.
      final fill = _themeColor(src, '_fieldFillLight');
      final r = (fill.r * 255).round();
      final b = (fill.b * 255).round();
      expect((r - b).abs(), lessThanOrEqualTo(3),
          reason: 'the fill is tinted, so it reads as a wash not a colour');
    });

    test('but it is still visible on the page AND on a card', () {
      // The bug the separate `fieldFill` token exists for: a field the same
      // colour as the card behind it disappears.
      final fill = _themeColor(src, '_fieldFillLight');
      final page = _themeColor(src, '_bgLight');
      final card = _themeColor(src, '_cardLight');
      expect(_delta(fill, page), greaterThanOrEqualTo(6),
          reason: 'the field vanishes into the page');
      expect(_delta(fill, card), greaterThanOrEqualTo(6),
          reason: 'the field vanishes into the card');
    });

    test('and it is not simply the card colour', () {
      expect(_themeColor(src, '_fieldFillLight'),
          isNot(_themeColor(src, '_cardLight')));
    });
  });
}
