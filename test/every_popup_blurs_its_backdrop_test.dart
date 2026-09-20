import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/widgets/app_dialog.dart';

/// ⚠️ THE BUG, reported with two screenshots side by side: the one-tap
/// calendar sat over a softly blurred page, and the SR Register Entry popup
/// -- and every other popup in the app -- sat over a flat dim.
///
/// [showAppDialog] was written to fix exactly that, and its doc comment has
/// said "dimmed AND blurred" since the day it landed. It only ever faded and
/// scaled. A promise in a comment is not a backdrop, so these tests ask the
/// widget tree instead.
void main() {
  group('every popup blurs the page behind it', () {
    testWidgets('showAppDialog puts a BackdropFilter behind the dialog',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('hello')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets,
          reason: 'the page behind a popup must be blurred, not just dimmed');
    });

    testWidgets('the blur ramps in rather than snapping to full strength',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('hello')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump(); // route pushed, t == 0

      double sigmaOf(WidgetTester t) {
        final f = t
            .widgetList<BackdropFilter>(find.byType(BackdropFilter))
            .first
            .filter;
        // ⚠️ ImageFilter has no sigma getter; its toString carries the
        // value, as `ImageFilter.blur(2.5, 2.5, unspecified)`. Anchor on the
        // opening paren -- an unanchored number match takes the dot in
        // "ImageFilter.blur" and fails to parse.
        final m = RegExp(r'blur\(([0-9.]+)').firstMatch(f.toString());
        return double.parse(m!.group(1)!);
      }

      final atStart = sigmaOf(tester);
      await tester.pump(const Duration(milliseconds: 80));
      final midway = sigmaOf(tester);
      await tester.pumpAndSettle();
      final settled = sigmaOf(tester);

      expect(atStart, lessThan(midway),
          reason: 'a full-strength blur on frame one snaps the page out of '
              'focus before the popup is even visible');
      expect(midway, lessThanOrEqualTo(settled));
      expect(settled, greaterThan(1.0));
    });

    test('the blur lives in the shared helper, not in one popup', () {
      // ⚠️ 134 call sites go through showAppDialog. Blurring inside any
      // single dialog widget would fix that one popup and leave the rest,
      // which is how the two screenshots came to differ in the first place.
      final src = File('lib/widgets/app_dialog.dart').readAsStringSync();
      expect(src, contains('BackdropFilter'));
      expect(src, contains('ImageFilter.blur'));
    });

    test('no popup is opened with a raw showDialog', () {
      // A raw showDialog cannot blur -- it has no transitionBuilder hook --
      // so one would silently be the odd popup out again.
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        for (final line in f.readAsLinesSync()) {
          final t = line.trim();
          if (t.startsWith('//') || t.startsWith('///')) continue;
          // `showDialog` as a call, not as an import-show entry.
          if (RegExp(r'\bshowDialog[<(]').hasMatch(t)) {
            offenders.add('${f.path}: $t');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'use showAppDialog so the backdrop matches everywhere');
    });
  });
}
