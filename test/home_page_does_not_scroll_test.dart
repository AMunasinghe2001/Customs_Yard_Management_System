// The portal chooser must not scroll.
//
// ⚠️ Reported with a screenshot: the seal was clipped at the top and the
// footer at the bottom, because the page was taller than the window. It is a
// doorway — an officer is here for two seconds to press one of six Sign In
// buttons — and having to scroll to reach one of them is wrong at any size.
//
// The cause was that everything on it was FIXED. The header scaled UP when
// there was room to spare but had no way to give ground when there was not,
// and the card's text boxes are fixed heights, so below ~768px the column
// simply ran past the bottom: 1px over at 768, 41px at 720.
import 'dart:io';

import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the portal chooser fits the window', () {
    // ⚠️ 1280x720 is the size the app actually opens at
    // (windows/runner/main.cpp), so it is the one that must never scroll.
    // The rest are the laptop and monitor shapes this was reported on.
    const sizes = <Size>[
      Size(1920, 1080),
      Size(1584, 1000),
      Size(1366, 900),
      Size(1366, 768),
      Size(1280, 800),
      Size(1152, 864),
      Size(1024, 768),
      Size(1280, 720), // the shipped default
      Size(1024, 640),
    ];

    for (final size in sizes) {
      testWidgets('no vertical scroll at ${size.width.toInt()}'
          'x${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const HomeScreen(),
          ),
        ));
        // Let the staggered card animations finish; a mid-flight frame is
        // not the layout anyone sees.
        await tester.pump(const Duration(seconds: 2));

        final scrollable =
            tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(scrollable.position.maxScrollExtent, 0,
            reason: 'the page is taller than the window at $size, so the '
                'seal is clipped at the top and the footer at the bottom');
      });
    }

    testWidgets('and nothing overflows its box', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const HomeScreen(),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      // A RenderFlex overflow reports through the error pipe, not by
      // failing layout, so an explicit check is the only way to catch it.
      expect(tester.takeException(), isNull);
    });
  });

  group('the header can give ground, not only take it', () {
    test('there is a tight factor as well as a tall one', () {
      // ⚠️ With only `tall`, every window below its floor got the SAME
      // header — which is exactly why a short screen overflowed. The card's
      // fixed boxes have to shrink with it, or the header alone cannot
      // recover enough room.
      final src = File('lib/screens/home/home_screen.dart').readAsStringSync();
      expect(src, contains('final tight ='));
      expect(src, contains('* tight'));
      expect(src, contains('tight: tight,'));
      expect(src, contains('widget.tight'),
          reason: 'the card must shrink too, not just the header');
    });
  });
}
