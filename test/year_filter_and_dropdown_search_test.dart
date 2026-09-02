import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/widgets/styled_dropdown.dart';
import 'package:cus_yard_management/widgets/year_filter.dart';

void main() {
  group('the year filter always offers the year being worked in', () {
    // Derived purely from the data, the list went stale every 1 January: with
    // nothing registered yet, the current year was missing from the very
    // filter meant to find it.
    test('the current and next year appear even with no SRs at all', () {
      final now = DateTime(2026, 3, 1);
      expect(srYears(const [], now: now), ['2027', '2026']);
    });

    test('they are added to whatever the data already has', () {
      final now = DateTime(2026, 3, 1);
      final years = srYears([
        'CED/GL1/SR/01/2024',
        'CED/GL1/SR/02/2023',
      ], now: now);
      expect(years, ['2027', '2026', '2024', '2023']);
    });

    test('an existing year is not duplicated', () {
      final now = DateTime(2026, 3, 1);
      final years = srYears([
        'CED/GL1/SR/01/2026',
        'CED/GL1/SR/02/2026',
        'CED/GL1/SR/03/2027',
      ], now: now);
      expect(years, ['2027', '2026']);
    });

    test('it rolls forward on its own, with no yearly edit', () {
      expect(srYears(const [], now: DateTime(2030, 1, 1)), ['2031', '2030']);
      expect(srYears(const [], now: DateTime(2031, 1, 1)), ['2032', '2031']);
    });

    test('newest first, so this year is at the top of the list', () {
      final years = srYears([
        'CED/GL1/SR/01/2020',
        'CED/GL1/SR/01/2025',
      ], now: DateTime(2026, 6, 1));
      expect(years.first, '2027');
      expect(years, ['2027', '2026', '2025', '2020']);
    });

    test('matching an SR against a year is unchanged', () {
      expect(srYearMatches('CED/GL1/SR/01/2026', '2026'), isTrue);
      expect(srYearMatches('CED/GL1/SR/01/2026', '2025'), isFalse);
      expect(srYearMatches('CED/GL1/SR/01/2026', null), isTrue,
          reason: 'null means All Years');
    });
  });

  group('a long dropdown can be typed into', () {
    List<StyledDropdownOption<String>> opts(int n) => [
          for (var i = 1; i <= n; i++)
            StyledDropdownOption('y$i', 'Yard number $i'),
        ];

    Widget harness(List<StyledDropdownOption<String>> options) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: StyledDropdownButton<String>(
                value: null,
                allLabel: 'All Yards',
                icon: Icons.warehouse_rounded,
                options: options,
                onChanged: (_) {},
              ),
            ),
          ),
        );

    testWidgets('a list that fits on one page gets no search box',
        (tester) async {
      // Everything is already visible; a box would just be in the way.
      await tester.pumpWidget(harness(opts(5)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Type to search…'), findsNothing);
    });

    testWidgets('a list long enough to page gets one', (tester) async {
      await tester.pumpWidget(harness(opts(40)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Type to search…'), findsOneWidget);
    });

    testWidgets('typing narrows the list in place', (tester) async {
      await tester.pumpWidget(harness(opts(40)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();

      // "Yard number 37" is on page 5 of 5 — unreachable without paging.
      expect(find.text('Yard number 37'), findsNothing);

      await tester.enterText(find.byType(TextField), 'number 37');
      await tester.pumpAndSettle();

      expect(find.text('Yard number 37'), findsOneWidget);
      expect(find.text('Yard number 1'), findsNothing);
    });

    testWidgets('the match is case-insensitive', (tester) async {
      await tester.pumpWidget(harness(opts(40)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'YARD NUMBER 12');
      await tester.pumpAndSettle();
      expect(find.text('Yard number 12'), findsOneWidget);
    });

    testWidgets('a query with no match says so rather than showing blank',
        (tester) async {
      await tester.pumpWidget(harness(opts(40)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No match for that search'), findsOneWidget);
    });

    testWidgets('"All" stays reachable while a query is narrowing the list',
        (tester) async {
      // It is a reset, not an option — clearing the filter must always be one
      // tap away.
      await tester.pumpWidget(harness(opts(40)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'number 37');
      await tester.pumpAndSettle();
      expect(find.text('All Yards'), findsWidgets);
    });

    testWidgets('searching from a later page still finds the match',
        (tester) async {
      // Typing resets to the first page, so the result is visible however far
      // in the officer had already paged.
      await tester.pumpWidget(harness(opts(40)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byIcon(Icons.chevron_right_rounded));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'number 12');
      await tester.pumpAndSettle();

      expect(find.text('Yard number 12'), findsOneWidget,
          reason: 'the only match must still be shown');
      expect(find.text('No match for that search'), findsNothing);
    });

    testWidgets('clearing the query restores the full list', (tester) async {
      await tester.pumpWidget(harness(opts(40)));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'number 37');
      await tester.pumpAndSettle();
      expect(find.text('Yard number 1'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Yard number 1'), findsOneWidget);
    });

    testWidgets('picking a filtered option returns that option', (tester) async {
      String? picked;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: StyledDropdownButton<String>(
              value: null,
              allLabel: 'All Yards',
              icon: Icons.warehouse_rounded,
              options: opts(40),
              onChanged: (v) => picked = v,
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(StyledDropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'number 37');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yard number 37'));
      await tester.pumpAndSettle();
      expect(picked, 'y37');
    });
  });

  group('the three posts ICT can assign', () {
    test('officer sits beside DC and SDDC', () {
      // Officers get accounts too — the post list is not admins-only.
      expect(kPostTitles.keys.toList(), ['officer', 'dc', 'sddc']);
      expect(kPostTitles['officer'], 'Officer');
    });

    test('the labels are parallel: each names the post plainly', () {
      expect(kPostTitles['dc'], startsWith('DC'));
      expect(kPostTitles['sddc'], startsWith('SDDC'));
      expect(kPostTitles['officer'], isNot(contains('Yard')));
    });

    test('an officer post still carries the officer permission', () {
      expect(kPostRoles['officer'], 'officer');
      expect(kPostRoles['dc'], 'admin');
      expect(kPostRoles['sddc'], 'admin');
    });

    test('a profile with no post recorded reads as Officer', () {
      final p = ProfileModel(
          id: 'p',
          fullName: 'A',
          role: 'officer',
          isActive: true,
          createdAt: DateTime.now());
      expect(p.postTitle, 'Officer');
    });
  });
}
