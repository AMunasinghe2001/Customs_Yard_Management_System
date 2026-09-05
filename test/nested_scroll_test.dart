// One scrollable per page.
//
// The tender-sale cards capped their inner table's height, so a card with more
// rows than the cap scrolled INSIDE itself. Two scrollables then overlapped:
// with the pointer over a table the wheel moved the table, and once that hit
// its bottom the page still would not move -- so there was no way to scroll
// past a long sale without hunting for a gap between the cards.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the cards size to their rows, with no cap', () {
    const sources = [
      'lib/screens/disposal/disposal_dashboard_screen.dart',
      'lib/screens/valuation/valuation_dashboard_screen.dart',
    ];

    for (final path in sources) {
      final name = path.split('/').last.replaceAll('.dart', '');
      final src = File(path).readAsStringSync();

      test('$name caps no inner table height', () {
        // ⚠️ A clamp here is the bug: it is what makes the card scroll
        // separately from the page.
        expect(src, isNot(contains('.clamp(100, 320)')),
            reason: '$path still caps an inner table');
        expect(src, isNot(contains('.clamp(115, 380)')),
            reason: '$path still caps an inner table');
      });

      test('$name still sizes to its row count', () {
        // Sized to content, so the card is exactly as tall as it needs to be
        // and its scroll view has nothing to consume.
        expect(src, contains('* 48.0 +'));
      });
    }
  });

  group('a scroll view with nothing to scroll passes the wheel on', () {
    testWidgets('the outer list moves even with the pointer over the inner one',
        (t) async {
      final outer = ScrollController();

      // An inner scroll view sized to its content -- the shape the cards now
      // have -- inside a scrollable page.
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: outer,
            children: [
              for (var i = 0; i < 12; i++)
                SizedBox(
                  key: ValueKey('card$i'),
                  height: 200,
                  // Exactly as tall as its child: nothing to scroll.
                  child: SingleChildScrollView(
                    child: Container(height: 200, color: Colors.blue.shade50),
                  ),
                ),
            ],
          ),
        ),
      ));
      await t.pump();

      expect(outer.offset, 0);

      // Put the pointer over an inner scroll view and spin the wheel.
      final target = t.getCenter(find.byKey(const ValueKey('card1')));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await t.sendEventToBinding(pointer.hover(target));
      await t.sendEventToBinding(pointer.scroll(const Offset(0, 260)));
      await t.pump();

      // ⚠️ The page moved. If the inner view had surplus height it would have
      // eaten this, which is exactly what the capped cards did.
      expect(outer.offset, greaterThan(0),
          reason: 'the wheel must reach the page when the inner view is full');

      outer.dispose();
    });

    testWidgets('an inner view WITH surplus keeps the wheel — the old bug',
        (t) async {
      final outer = ScrollController();

      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: outer,
            children: [
              for (var i = 0; i < 12; i++)
                SizedBox(
                  key: ValueKey('card$i'),
                  height: 200,
                  child: SingleChildScrollView(
                    // Taller than its box: this one CAN scroll.
                    child: Container(height: 900, color: Colors.blue.shade50),
                  ),
                ),
            ],
          ),
        ),
      ));
      await t.pump();

      final target = t.getCenter(find.byKey(const ValueKey('card1')));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await t.sendEventToBinding(pointer.hover(target));
      await t.sendEventToBinding(pointer.scroll(const Offset(0, 260)));
      await t.pump();

      // The page stayed put — which is the complaint, reproduced.
      expect(outer.offset, 0,
          reason: 'this is the behaviour the height cap was causing');

      outer.dispose();
    });
  });
}
