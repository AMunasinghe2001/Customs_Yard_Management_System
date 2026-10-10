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

  group('the posts ICT can assign', () {
    test('administration and staff are two groups, seniority first', () {
      // ⚠️ A yard is RUN by SDDC and DC and STAFFED by the Superintendent
      // grades. The two groups carry different permissions, so the list is
      // not one flat set of equals.
      expect(kYardAdminPostKeys, ['sddc', 'dc']);
      expect(kYardStaffPostKeys, ['sc', 'dsc', 'asc']);
      expect(kAssignablePostKeys, ['sddc', 'dc', 'sc', 'dsc', 'asc']);
    });

    test('a yard has no plain DC — the post is DDC', () {
      // ⚠️ The KEY is still 'dc' because live accounts store it in
      // profiles.job_role, but the POST is DDC. A plain DC belongs to the
      // directorates, not to a yard.
      expect(kPostTitles['dc'], startsWith('DDC'));
      expect(kPostShortTitles['dc'], 'DDC');
      expect(kPostTitles.containsKey('ddc'), isFalse,
          reason: 'renaming the key would orphan the live account on it');
    });

    test('the labels name the post in full', () {
      expect(kPostTitles['sddc'], 'SDDC (Senior Deputy Director of Customs)');
      expect(kPostTitles['dc'], 'DDC (Deputy Director of Customs)');
      expect(kPostTitles['sc'], 'SC (Superintendent of Customs)');
      expect(kPostTitles['dsc'], 'DSC (Deputy Superintendent of Customs)');
      expect(kPostTitles['asc'], 'ASC (Assistant Superintendent of Customs)');
    });

    test('administration is admin, staff is officer', () {
      for (final k in kYardAdminPostKeys) {
        expect(kPostRoles[k], 'admin', reason: '$k runs the yard');
      }
      for (final k in kYardStaffPostKeys) {
        expect(kPostRoles[k], 'officer', reason: '$k is yard staff');
      }
    });

    test('the legacy officer key still renders but is not offered', () {
      // ⚠️ Live accounts carry 'officer' in profiles.job_role. Dropping it
      // from kPostTitles would leave those rows with no title at all;
      // leaving it in kAssignablePostKeys would keep handing out a post
      // that no longer exists.
      expect(kPostTitles.containsKey('officer'), isTrue);
      expect(kPostRoles['officer'], 'officer');
      expect(kAssignablePostKeys.contains('officer'), isFalse);
    });

    test('every assignable post has a short form and a permission', () {
      for (final k in kAssignablePostKeys) {
        expect(kPostShortTitles[k], isNotNull, reason: '$k has no short form');
        expect(kPostRoles[k], isNotNull, reason: '$k has no permission role');
        expect(kPostTitles[k], isNotNull, reason: '$k has no title');
      }
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

  group('the directorate posts', () {
    test('only ICT has a third post', () {
      // Every other directorate is a DC and an SDDC; ICT also holds the
      // System Administrator, because somebody has to provision the
      // accounts the other posts sign in with.
      expect(kDisposalPositions.length, 2);
      expect(kAppealPositions.length, 2);
      expect(kValuationPositions.length, 2);
      expect(kIctPositions.containsKey('ICT_ADMIN'), isTrue);
      expect(kIctPositions['ICT_ADMIN'], 'System Administrator');
    });

    test('Top Management holds the four most senior posts', () {
      expect(kExecutivePositions['DG'],
          'DGC (Director General of Customs)');
      expect(kExecutivePositions['ADG'],
          'ADGC (Additional Director General of Customs)');
      expect(kExecutivePositions['SDC'], 'SDC (Senior Director of Customs)');
      expect(kExecutivePositions['DC'], 'DC (Director of Customs)');
    });

    test('the live usernames keep their keys', () {
      // ⚠️ exec.dg and exec.adg exist on the database under these keys. The
      // TITLES changed to DGC/ADGC; renaming the keys would orphan them.
      expect(kExecutivePositions.containsKey('DG'), isTrue);
      expect(kExecutivePositions.containsKey('ADG'), isTrue);
      expect(kValuationPositions.containsKey('VDC'), isTrue);
    });

    test('the other directorates say Director of Customs', () {
      for (final m in [
        kDisposalPositions,
        kAppealPositions,
        kValuationPositions
      ]) {
        expect(m.values.any((v) => v.contains('Director of Customs')), isTrue);
      }
    });
  });

  group('the rename does not orphan a live account', () {
  test('every live account still renders a post title', () {
    // job_role / username values taken from the live database.
    const liveYardPosts = ['dc', 'officer', '', null];
    for (final jr in liveYardPosts) {
      final p = ProfileModel(
        id: 'x',
        fullName: 'A',
        jobRole: jr,
        role: jr == 'dc' ? 'admin' : 'officer',
        isActive: true,
        createdAt: DateTime.now(),
      );
      expect(p.postTitle, isNotEmpty, reason: 'job_role "$jr" lost its title');
      expect(p.postShortTitle, isNotEmpty);
    }

    // Directorate usernames on the live database.
    expect(executivePositionLabel('DG'), contains('DGC'));
    expect(executivePositionLabel('ADG'), contains('ADGC'));
    expect(executivePositionLabel('DC'), contains('Director of Customs'));
    expect(valuationPositionLabel('VDC'), contains('Director of Customs'));
    expect(ictPositionLabel('ICT_ADMIN'), 'System Administrator');
  });  });
}
