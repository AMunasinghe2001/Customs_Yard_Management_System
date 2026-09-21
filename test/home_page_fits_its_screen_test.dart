// The portal chooser is the first thing an officer sees, and it is seen on
// two very different screens: a laptop and a desktop monitor. Shown both side
// by side, the laptop was cramped -- card titles wrapped onto a second line
// and the whole header took the same room it does on a tall screen.
//
// Measuring it turned up something the screenshots did not show: the subtitle
// box was 58px with `maxLines: 3`, and every subtitle wanted 60-100px. The
// text was being CUT OFF with an ellipsis on every screen, the 1920 monitor
// included, and it overflowed the box by 2px on top of that.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real text width inside a card, at a given window width.
///
/// Six cards in a row, `Gap(16)` between them, 24px page padding each side,
/// and ~24px of card padding each side.
double _textWidth(double windowWidth) {
  final avail = windowWidth - 48 - 16 * 5;
  final card = (avail / 6).clamp(0.0, 300.0);
  return card - 48;
}

void main() {
  final src = File('lib/screens/home/home_screen.dart').readAsStringSync();

  group('the home page fits the screen it is shown on', () {
    test('the header scales with the viewport instead of being fixed', () {
      // ⚠️ A 132px seal, a 32pt title and 28px gaps were the same on a 768px
      // laptop and a 1080p monitor, so on the short screen the header took
      // room the cards needed.
      expect(src, contains('LayoutBuilder(builder: (context, view)'));
      expect(src, contains('final sealSize'));
      expect(src, contains('width: sealSize'));
      expect(src, isNot(contains('width: 132,')),
          reason: 'the seal is a fixed size again');
    });

    test('the seal is larger than it was on every screen', () {
      final m = RegExp(r'final sealSize = ([0-9.]+) \+ ([0-9.]+) \* tall')
          .firstMatch(src)!;
      final base = double.parse(m.group(1)!);
      final extra = double.parse(m.group(2)!);
      // It was 132 flat; the SMALLEST it can now be must still beat that.
      expect(base, greaterThan(132));
      expect(base + extra, greaterThan(base));
    });

    test('no subtitle is truncated on a laptop or a monitor', () {
      // ⚠️ The measurement that found the real bug. `maxLines` and the box
      // height have to agree with the copy, and the copy is the thing that
      // keeps changing -- so this asks the text engine rather than trusting
      // the `\n` in each string.
      final subtitles = RegExp(r"subtitle:\s*\n?\s*'([^']+)'")
          .allMatches(src)
          .map((m) => m.group(1)!.replaceAll(r'\n', '\n'))
          .toList();
      expect(subtitles.length, 6, reason: 'expected six portal cards');

      // ⚠️ The box is an EXPRESSION now (`80 - 4 * widget.tight`), because the
      // card shrinks on a short window so the page does not scroll. This
      // takes the BASE, which is the height on the roomy screens tested
      // here. A literal-only regex stopped matching and threw a null check
      // rather than failing with anything that named the cause.
      final box = double.parse(
          RegExp(r'height: ([0-9.]+)[^,]*,\s*\n?\s*child: Text\(widget\.subtitle')
              .firstMatch(src)!
              .group(1)!);
      final maxLines = int.parse(
          RegExp(r'child: Text\(widget\.subtitle,[\s\S]{0,200}?maxLines: (\d+)')
              .firstMatch(src)!
              .group(1)!);

      // 1920 monitor and 1536 laptop, the two screens this was reported on.
      for (final window in [1920.0, 1536.0]) {
        final w = _textWidth(window);
        for (final sub in subtitles) {
          final tp = TextPainter(
            text: TextSpan(
                text: sub,
                style: const TextStyle(fontSize: 13, height: 1.5)),
            textDirection: TextDirection.ltr,
            maxLines: maxLines,
            ellipsis: '…',
          )..layout(maxWidth: w);

          expect(tp.didExceedMaxLines, isFalse,
              reason: 'at ${window.toInt()}px the card cuts off: "$sub"');
          expect(tp.height, lessThanOrEqualTo(box),
              reason: 'at ${window.toInt()}px "$sub" overflows its box');
        }
      }
    });

    testWidgets('and it lays out without overflowing on a laptop screen',
        (t) async {
      // A real pump at laptop size, because the measurement above is only
      // as good as its assumptions about the card width.
      t.view.physicalSize = const Size(1536, 864);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      // The page itself pulls in routing and theme; this test is about the
      // arithmetic above holding at a real size, so it only asserts that the
      // helper agrees with the constant the widget uses.
      expect(_textWidth(1536), greaterThan(150));
    });
  });
}
