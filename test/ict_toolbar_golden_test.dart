// A picture of the toolbar, so its edges can be measured rather than argued
// about.
//
// ⚠️ Every earlier attempt measured the LAYOUT — `getRect` on a widget — and
// every one of them said the controls matched while the screen said they did
// not. A layout rect is not what a person sees: a field's border is a 1px
// stroke drawn INSIDE its box, and a button's fill runs to the box's edge, so
// two boxes with identical rects put ink in different places.
//
// Run with `flutter test --update-goldens` to write the file; the pixels are
// then measured directly (see tool/measure_toolbar.py).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/ict/ict_ui.dart';
import 'package:cus_yard_management/widgets/styled_dropdown.dart';

const _accent = Color(0xFF8E3A5F);

void main() {
  testWidgets('the toolbar, as painted', (tester) async {
    tester.view.physicalSize = const Size(1200, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: IctToolbar(children: [
              Expanded(
                flex: 3,
                child: IctSearchField(
                  controller: TextEditingController(),
                  accent: _accent,
                  hintText: 'Search name, salary no, email or username',
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
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
        find.byType(IctToolbar), matchesGoldenFile('goldens/ict_toolbar.png'));
  },
      // ⚠️ SKIPPED in a normal run, on purpose. This is a measuring
      // instrument, not a regression check: google_fonts fetches its font over
      // the network, which a test cannot do, so the test always ends in an
      // exception even though the image is written correctly first.
      //
      // Run it deliberately when a control's height changes:
      //     flutter test test/ict_toolbar_golden_test.dart --update-goldens
      //     python tool/measure_toolbar.py
      //
      // The suite stays green; the pixels stay measurable.
      skip: true);
}
