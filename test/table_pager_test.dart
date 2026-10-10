// One pager, every table.
//
// The app had two: an arrows-only "‹ Page 3 ›" bar under twenty tables, and
// the numbered one built for the ICT console. The arrows-only bar could not
// answer "how far through am I" or "how much is there", and reaching page 12
// meant eleven clicks. Now there is one implementation and the console wraps
// it, so the two cannot drift apart on the very thing that makes a pager
// readable.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cus_yard_management/widgets/table_pager.dart';
import 'package:cus_yard_management/core/theme.dart';

void main() {
  group('the window of page numbers', () {
    test('a short run shows every page, with no ellipsis', () {
      expect(TablePager.windowFor(0, 1), [0]);
      expect(TablePager.windowFor(3, 7), [0, 1, 2, 3, 4, 5, 6]);
      expect(TablePager.windowFor(0, 7).contains(null), isFalse);
    });

    test('first and last are ALWAYS offered', () {
      // They are the two people actually aim for.
      for (final page in [0, 5, 9, 14]) {
        final w = TablePager.windowFor(page, 15);
        expect(w.first, 0, reason: 'page $page must offer the first page');
        expect(w.last, 14, reason: 'page $page must offer the last page');
      }
    });

    test('the current page keeps its neighbours', () {
      final w = TablePager.windowFor(7, 15);
      expect(w, containsAll(<int?>[6, 7, 8]));
    });

    test('the gaps collapse to an ellipsis', () {
      // Rendered as "1 … 7 8 9 … 15": the bar stays one width at 15 pages and
      // at 3,000.
      final w = TablePager.windowFor(7, 15);
      expect(w.where((e) => e == null).length, 2);
      expect(w.length, lessThan(9));
    });

    test('near either end only one gap appears', () {
      expect(TablePager.windowFor(0, 15).where((e) => e == null).length, 1);
      expect(TablePager.windowFor(14, 15).where((e) => e == null).length, 1);
    });

    test('no page is offered twice, and none is out of range', () {
      for (final page in [0, 1, 2, 8, 12, 13, 14]) {
        final w = TablePager.windowFor(page, 15).whereType<int>().toList();
        expect(w.toSet().length, w.length, reason: 'duplicate at page $page');
        expect(w.every((p) => p >= 0 && p < 15), isTrue);
        // Ascending, or the numbers would read out of order.
        final sorted = [...w]..sort();
        expect(w, sorted);
      }
    });

    test('an empty table asks for no pages at all', () {
      expect(TablePager.windowFor(0, 0), isEmpty);
    });
  });

  group('one implementation, not two', () {
    final ict = File('lib/screens/ict/ict_ui.dart').readAsStringSync();

    test('the console delegates rather than keeping its own copy', () {
      final section = ict.substring(ict.indexOf('class IctPager'));
      expect(section, contains('child: TablePager('));
      // The drawing itself must be gone from the console.
      expect(ict, isNot(contains('class _PagerNumber')));
      expect(ict, isNot(contains('class _PagerStep')));
    });

    test('the console still supplies its own padding', () {
      // It sits INSIDE the table card on the card's footer rule, not floating
      // under a table like every other use.
      final section = ict.substring(ict.indexOf('class IctPager'));
      expect(section, contains('EdgeInsets.fromLTRB(16, 0, 16, 8)'));
    });
  });

  group('the bar itself', () {
    // ⚠️ Needs the real theme: the pager reads context.colors, which is an
    // AppColors ThemeExtension, and a bare MaterialApp has none.
    Widget host(Widget child) => MaterialApp(
        theme: AppTheme.lightTheme, home: Scaffold(body: child));

    testWidgets('it says the range and the total, not just the page number',
        (tester) async {
      await tester.pumpWidget(host(TablePager(
          total: 358, page: 4, pageSize: 25, onPageChanged: (_) {})));
      expect(find.text('Showing 101–125 of 358'), findsOneWidget);
    });

    testWidgets('an empty table says so rather than showing "0–0 of 0"',
        (tester) async {
      await tester.pumpWidget(host(
          TablePager(total: 0, page: 0, onPageChanged: (_) {})));
      expect(find.text('No records'), findsOneWidget);
    });

    testWidgets('the last page stops at the real total', (tester) async {
      // 358 rows, 25 a page: the last page holds 8, not 25.
      await tester.pumpWidget(host(TablePager(
          total: 358, page: 14, pageSize: 25, onPageChanged: (_) {})));
      expect(find.text('Showing 351–358 of 358'), findsOneWidget);
    });

    testWidgets('tapping a number asks for that page', (tester) async {
      int? asked;
      await tester.pumpWidget(host(TablePager(
          total: 358, page: 4, pageSize: 25, onPageChanged: (p) => asked = p)));
      await tester.tap(find.text('15'));
      expect(asked, 14, reason: 'the label is 1-based, the callback 0-based');
    });

    testWidgets('the current page cannot be tapped to reload itself',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(TablePager(
          total: 100, page: 2, pageSize: 25, onPageChanged: (_) => calls++)));
      await tester.tap(find.text('3'));
      expect(calls, 0);
    });
  });
}
