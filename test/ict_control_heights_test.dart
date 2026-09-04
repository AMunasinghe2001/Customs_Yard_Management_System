// Every control in an ICT toolbar is exactly one height.
//
// ⚠️ Measured, not eyeballed. "Same size" is the kind of claim that reads as
// true in the source — every one of these is wrapped in a SizedBox of
// kIctControlHeight — and is still wrong on screen, because Material gives
// buttons a minimum tap target and an InputDecorator its own intrinsic
// height, and either can beat the box around it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/ict/ict_ui.dart';
import 'package:cus_yard_management/widgets/styled_dropdown.dart';

const _accent = Color(0xFF8E3A5F);

void main() {
  Future<void> pumpToolbar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: IctToolbar(children: [
            Expanded(
              flex: 3,
              child: IctSearchField(
                controller: TextEditingController(),
                accent: _accent,
                hintText: 'Search',
                onChanged: (_) {},
                onClear: () {},
              ),
            ),
            Expanded(
              flex: 2,
              child: IctSelect(
                label: 'Yard',
                icon: Icons.warehouse_rounded,
                accent: _accent,
                value: 'all',
                options: const [StyledDropdownOption('all', 'All Yards')],
                onChanged: (_) {},
              ),
            ),
            IctPrimaryButton(
              label: 'Add Officer / DC',
              icon: Icons.person_add_alt_1_rounded,
              accent: _accent,
              onPressed: () {},
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the search box, the dropdown and the button are one height',
      (tester) async {
    await pumpToolbar(tester);

    // ⚠️ The DECORATOR, not the TextField. The TextField is whatever box we
    // wrapped it in; the InputDecorator is the bordered rectangle a person
    // actually sees, and the two are not the same number.
    final search = tester
        .getSize(find.descendant(
            of: find.byType(TextField), matching: find.byType(InputDecorator)))
        .height;
    // The dropdown's own box, not the caption above it.
    final dropdown = tester
        .getSize(find.descendant(
            of: find.byType(IctSelect), matching: find.byType(InputDecorator)))
        .height;
    final button = tester.getSize(find.byType(ElevatedButton)).height;

    expect(search, kIctControlHeight, reason: 'search box');
    expect(dropdown, kIctControlHeight, reason: 'filter dropdown');
    expect(button, kIctControlHeight, reason: 'primary action');
  });

  testWidgets('they also sit on the same baseline', (tester) async {
    await pumpToolbar(tester);

    double bottomOf(Finder f) => tester.getRect(f).bottom;
    final search = bottomOf(find.byType(TextField));
    final dropdown = bottomOf(find.descendant(
        of: find.byType(IctSelect), matching: find.byType(InputDecorator)));
    final button = bottomOf(find.byType(ElevatedButton));

    // ⚠️ Equal heights are not enough: the dropdown carries a caption above
    // it, so the toolbar aligns on the BOTTOM edge. If that changed, three
    // controls of identical height would still step down the row.
    expect(dropdown, moreOrLessEquals(search, epsilon: 0.5));
    expect(button, moreOrLessEquals(search, epsilon: 0.5));
  });

  testWidgets('the toolbar itself is no taller than it has to be',
      (tester) async {
    await pumpToolbar(tester);

    // The strip is a caption, a control, and the padding around them —
    // nothing else. It sits above the table on every page, so every pixel
    // here is a row the officer cannot see without scrolling.
    final bar = tester.getSize(find.byType(IctToolbar)).height;
    expect(bar, lessThanOrEqualTo(kIctToolbarMaxHeight),
        reason: 'the filter strip has grown a second row of padding');
  });
}
