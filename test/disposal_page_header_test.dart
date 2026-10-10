import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/disposal_page_header.dart';

/// The four "Send Disposal Request" pages (Detained, Forfeited, Abandoned,
/// Other) share one header. They used to each build their own [Wrap] holding
/// the title block and an unbreakable Row of stat chips plus the button — and
/// because a Wrap child cannot shrink, that whole Row dropped to its own line
/// as soon as the title block left it no room. The four subtitles are very
/// different lengths, so the four pages broke at four different widths;
/// Detained, with the longest subtitle, dropped while space clearly remained.
void main() {
  // The real subtitles, longest first. Detained's is what exposed the bug.
  const detained = 'Goods held under inquiry — decide their outcome or send '
      'them for sale or destruction';
  const other = 'Manage packages with an "Other" status — release, re-export '
      'or send for disposal';
  const forfeited = 'Manage forfeited packages and their 30-day appeal periods';
  const abandoned = 'Manage abandoned goods and send them for disposal';

  Widget chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 20)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      );

  Widget harness(String title, String subtitle, {required double width}) =>
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: DisposalPageHeader(
                title: title,
                subtitle: subtitle,
                trailing: [
                  chip('Total'),
                  chip('In Appeal'),
                  chip('Actionable'),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.local_shipping_rounded, size: 16),
                    label: const Text('Send Disposal Request'),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// Widths a maximised window down to a small one, minus the nav rail.
  const widths = [1600.0, 1400.0, 1200.0, 1000.0, 900.0, 860.0, 800.0, 700.0];

  group('the header never overflows', () {
    for (final page in {
      'Detained Goods': detained,
      'Forfeited Goods': forfeited,
      'Abandoned Goods': abandoned,
      'Other Goods': other,
    }.entries) {
      for (final w in widths) {
        testWidgets('${page.key} at ${w.toInt()}px', (tester) async {
          tester.view.physicalSize = const Size(1920, 1080);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(harness(page.key, page.value, width: w));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '${page.key} overflowed at ${w.toInt()}px');
        });
      }
    }
  });

  group('the stats stay beside the title while there is room', () {
    /// True when the trailing block sits to the RIGHT of the title rather than
    /// below it — the thing that was going wrong on Detained.
    Future<bool> statsAreInline(WidgetTester tester, String subtitle,
        {required double width}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness('Detained Goods', subtitle, width: width));
      await tester.pump();
      final title = tester.getRect(find.text('Detained Goods'));
      final button = tester.getRect(find.text('Send Disposal Request'));
      return button.left > title.right && button.top < title.bottom;
    }

    testWidgets('the longest subtitle keeps them inline at 1000px',
        (tester) async {
      expect(await statsAreInline(tester, detained, width: 1000), isTrue,
          reason: 'the stats and button dropped below the title');
    });

    testWidgets('and still at 900px', (tester) async {
      expect(await statsAreInline(tester, detained, width: 900), isTrue);
    });

    testWidgets('every page agrees at the same width', (tester) async {
      // The four used to break at four different widths because only the
      // subtitle length differed. They must behave identically now.
      for (final s in [detained, forfeited, abandoned, other]) {
        expect(await statsAreInline(tester, s, width: 1000), isTrue,
            reason: 'a page still breaks earlier than the others');
      }
    });

    testWidgets('they stay inline even at the narrowest width', (tester) async {
      // The trailing block scrolls rather than dropping below the title, so
      // the button never moves off the header line.
      expect(await statsAreInline(tester, detained, width: 700), isTrue);
    });
  });

  group('all four pages actually use the shared header', () {
    const pages = {
      'detained': 'lib/screens/packages/detained_packages_screen.dart',
      'forfeited':
          'lib/screens/forfeited_packages/forfeited_packages_screen.dart',
      'abandoned': 'lib/screens/packages/abandoned_packages_screen.dart',
      'other': 'lib/screens/packages/other_packages_screen.dart',
    };

    for (final page in pages.entries) {
      test('${page.key} builds its header from DisposalPageHeader', () {
        final src = File(page.value).readAsStringSync();
        expect(src, contains('DisposalPageHeader('),
            reason: '${page.key} still rolls its own header');
        expect(src, contains("import '../../widgets/disposal_page_header.dart';"));
      });
    }
  });
}
