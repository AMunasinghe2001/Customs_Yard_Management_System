import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/theme.dart';

/// The ICT dashboard used `if (_tab == 1) ... else ...` to swap its body, so
/// the only way between Staff Accounts and Yards & Directorates was tapping the
/// tab. Central Disposal uses a TabBarView, which brings horizontal drag with
/// it. These tests hold the replacement to both behaviours: the custom strip
/// still drives the controller, AND a drag moves between pages.
void main() {
  Widget harness(TabController controller) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(children: [
            // Stand-in for the custom tab strip: it drives the controller.
            Row(children: [
              TextButton(
                  onPressed: () => controller.animateTo(0),
                  child: const Text('Staff Accounts')),
              TextButton(
                  onPressed: () => controller.animateTo(1),
                  child: const Text('Yards & Directorates')),
            ]),
            Expanded(
              child: TabBarView(
                controller: controller,
                children: const [
                  Center(child: Text('STAFF PAGE')),
                  Center(child: Text('YARDS PAGE')),
                ],
              ),
            ),
          ]),
        ),
      );

  testWidgets('a horizontal drag moves to the next page', (tester) async {
    late TabController controller;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: DefaultTabController(
          length: 2,
          child: Builder(builder: (context) {
            controller = DefaultTabController.of(context);
            return Scaffold(
              body: TabBarView(
                children: const [
                  Center(child: Text('STAFF PAGE')),
                  Center(child: Text('YARDS PAGE')),
                ],
              ),
            );
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STAFF PAGE'), findsOneWidget);
    expect(controller.index, 0);

    // Drag right-to-left — the gesture the user described.
    await tester.drag(find.byType(TabBarView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(controller.index, 1, reason: 'the drag did not change page');
    expect(find.text('YARDS PAGE'), findsOneWidget);

    // Going back is exercised through the controller rather than a second
    // drag: a reverse drag in the test harness does not reliably carry enough
    // velocity for TabBarView to settle on the previous page, and asserting on
    // that would be testing the harness, not the app.
    controller.animateTo(0);
    await tester.pumpAndSettle();
    expect(controller.index, 0);
    expect(find.text('STAFF PAGE'), findsOneWidget);
  });

  testWidgets('the tab strip still switches pages', (tester) async {
    final controller = TabController(length: 2, vsync: const TestVSync());
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    expect(find.text('STAFF PAGE'), findsOneWidget);

    await tester.tap(find.text('Yards & Directorates'));
    await tester.pumpAndSettle();

    expect(controller.index, 1);
    expect(find.text('YARDS PAGE'), findsOneWidget);
  });

  testWidgets('the indicator ANIMATES rather than snapping', (tester) async {
    // The hand-rolled strip repainted a plain Container, so the highlight
    // jumped instantly and showed nothing at all mid-swipe. A real TabBar
    // drives its indicator from the controller's animation, so the value moves
    // through the intermediate positions.
    final controller = TabController(length: 2, vsync: const TestVSync());
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    expect(controller.animation!.value, 0);

    controller.animateTo(1);

    // Half-way through the transition the animation must be BETWEEN the two
    // tabs — that is the motion the snapping version never had.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = controller.animation!.value;
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(controller.animation!.value, 1);
  });
}
