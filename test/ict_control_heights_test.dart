// Every control in an ICT toolbar is exactly one height.
//
// ⚠️ Measured, not eyeballed. "Same size" is the kind of claim that reads as
// true in the source — every one of these is wrapped in a SizedBox of
// kIctControlHeight — and is still wrong on screen, because Material gives
// buttons a minimum tap target and an InputDecorator its own intrinsic
// height, and either can beat the box around it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/ict/ict_ui.dart';
import 'package:cus_yard_management/widgets/styled_dropdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/ict/activity_logs_tab.dart';

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
    expect(button, kIctPrimaryButtonHeight, reason: 'primary action');
    // ⚠️ These three assertions were all TRUE while the fields were visibly
    // shorter than the button on screen. A layout rect is not where the ink
    // is: an InputDecorator sizes its own container to the content plus
    // kIctFieldPadY and centres it, so a field laid out at 40 painted at 34.
    // What actually holds the line is tool/measure_toolbar.py, which reads
    // the pixels out of a golden.
    expect(kIctPrimaryButtonHeight, kIctControlHeight,
        reason: 'the button fills its box, so it must be the field height');
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
    // ⚠️ And the cap tracks the control, so raising one without the other
    // cannot quietly pass. The strip is a caption, a control and its padding:
    // anything more than that is the strip becoming a second header.
    expect(kIctToolbarMaxHeight - kIctControlHeight, lessThanOrEqualTo(34),
        reason: 'the cap was raised further than the control it holds');
  });

  // ⚠️ The synthetic toolbar above can agree with itself and still be wrong
  // about the app. This measures a REAL ICT toolbar — the one on Activity
  // Logs — and compares the rectangles a person actually sees.
  testWidgets('on a real screen the boxes line up top and bottom',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ictAllOfficeLogsProvider.overrideWith(
            (ref) => Future.value(const AuditLogPage(rows: [], total: 0))),
        yardFilterOptionsProvider
            .overrideWith((ref) => Future.value(const <YardFilterOption>[])),
        ictLogEntityTypesProvider
            .overrideWith((ref) => Future.value(const <String>[])),
        ictLogYearsProvider.overrideWith((ref) => Future.value(const [2026])),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: ActivityLogsTab(accent: _accent)),
      ),
    ));
    await tester.pumpAndSettle();

    final searchBox = tester.getRect(find.descendant(
        of: find.byType(TextField), matching: find.byType(InputDecorator)));
    final firstSelect = tester.getRect(find.descendant(
        of: find.byType(IctSelect).first,
        matching: find.byType(InputDecorator)));

    // Both cells are a caption over a box, so the boxes share BOTH edges.
    // Comparing only the bottoms would pass while the search box floated up
    // with its own height, which is exactly what it did.
    expect(searchBox.top, moreOrLessEquals(firstSelect.top, epsilon: 0.5),
        reason: 'the search box sits higher than the filters beside it');
    expect(searchBox.bottom, moreOrLessEquals(firstSelect.bottom, epsilon: 0.5),
        reason: 'the search box is shorter than the filters beside it');
    expect(searchBox.height, kIctControlHeight);
  });

  // ⚠️ THE test. Every other one here measures the layout after a SizedBox
  // has forced a height, and they all passed while the dropdown was visibly
  // taller than the search box on screen — because the box was 34 and what
  // OVERFLOWED it was the border being painted.
  //
  // A Material prefix icon is a 48x48 tap target, so the dropdown's intrinsic
  // height was 48 against the search field's 36. Given unbounded height, the
  // two must want the same size; only then does forcing them to one produce
  // one.
  testWidgets('unforced, the two want the same height', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          // Deliberately NOT inside IctToolbar: no SizedBox, nothing forcing
          // a height, so each control reports what it actually wants.
          Expanded(
            child: IctSearchField(
              controller: TextEditingController(),
              accent: _accent,
              hintText: 'Search',
              onChanged: (_) {},
            ),
          ),
          Expanded(
            child: IctSelect(
              label: 'Yard',
              icon: Icons.warehouse_rounded,
              accent: _accent,
              value: 'all',
              options: const [StyledDropdownOption('all', 'All Yards')],
              onChanged: (_) {},
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final boxes = find
        .byType(InputDecorator)
        .evaluate()
        .map((e) => (e.renderObject as RenderBox).size.height)
        .toList();
    expect(boxes.length, 2);
    expect(boxes.first, boxes.last,
        reason: 'one of them wants to be taller than the box it is given, '
            'and paints its border outside it');
  });

  testWidgets('the period segments stand at the control height too',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: IctSegmented(accent: _accent, children: [
          IctSegment(
              label: 'All Time',
              icon: Icons.all_inclusive_rounded,
              selected: true,
              onTap: (_) {}),
          IctSegment(
              label: 'By Year',
              icon: Icons.calendar_today_rounded,
              selected: false,
              onTap: (_) {}),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    // It sits in the same row of the page as the filters below it, so it is
    // held to the same number rather than to whatever its padding adds up to.
    expect(tester.getSize(find.byType(IctSegmented)).height,
        kIctControlHeight);
  });

  // ⚠️ The complaint this answers: "draw a line above and below and nothing
  // should stick out past it." Heights being equal does not say that — a
  // control can match on height and still hang below, if it is aligned
  // differently or its box is not where you think. This asserts CONTAINMENT:
  // the button's ink never crosses the line the fields draw.
  testWidgets('nothing sticks out above or below the field line',
      (tester) async {
    await pumpToolbar(tester);

    final field = tester.getRect(find.descendant(
        of: find.byType(TextField), matching: find.byType(InputDecorator)));
    final select = tester.getRect(find.descendant(
        of: find.byType(IctSelect), matching: find.byType(InputDecorator)));
    final ink = tester.getRect(find.byType(ElevatedButton));

    // The two fields are the line, so they must be exactly the same line.
    expect(select.top, field.top);
    expect(select.bottom, field.bottom);

    // And the button lives inside it, top and bottom.
    expect(ink.top, greaterThanOrEqualTo(field.top),
        reason: 'the button rises above the fields');
    expect(ink.bottom, lessThanOrEqualTo(field.bottom),
        reason: 'the button hangs below the fields');

    // Same box, top and bottom — the button fills its cell as the fields
    // fill theirs.
    expect(ink.top, field.top);
    expect(ink.bottom, field.bottom);
  });

  // ⚠️ A card header is not a toolbar. In a toolbar the primary button stands
  // in a row of fields and matches them; in a header it stands beside a title
  // and a subtitle — about 36pt of text — and at the field height it was the
  // TALLEST thing in the strip, so it decided how tall the header was and
  // pushed the rule under it down. A header's height should be set by its
  // words.
  testWidgets('a card header does not grow to fit its button', (tester) async {
    tester.view.physicalSize = const Size(1400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget card({List<Widget> actions = const []}) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: IctSectionCard(
              icon: Icons.account_balance_rounded,
              title: 'Directorates',
              subtitle: 'Head-office divisions. The SR prefix goes in front.',
              badge: '8',
              actions: actions,
              child: const SizedBox(height: 80),
            ),
          ),
        );

    await tester.pumpWidget(card());
    await tester.pumpAndSettle();
    final bare = tester.getSize(find.byType(IctSectionCard)).height;

    await tester.pumpWidget(card(actions: [
      IctPrimaryButton(
        dense: true,
        label: 'Add Directorate',
        icon: Icons.add_rounded,
        accent: _accent,
        onPressed: () {},
      ),
    ]));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(IctSectionCard)).height, bare,
        reason: 'the Add button is stretching the card header');
    expect(tester.getSize(find.byType(ElevatedButton)).height,
        kIctHeaderButtonHeight);
  });

  test('every card-header action is the dense one', () {
    // The toolbar's button keeps the field height; a header's must not.
    final yards = File('lib/screens/ict/yard_directorate_tab.dart')
        .readAsStringSync();
    expect('IctPrimaryButton('.allMatches(yards).length,
        'dense: true'.allMatches(yards).length,
        reason: 'a card-header button was added without dense: true');
  });
}
