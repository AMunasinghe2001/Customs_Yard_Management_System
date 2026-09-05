// The card must be at least as tall as the table inside it.
//
// ⚠️ Being a few pixels SHORT is the whole bug. A DataTable2 that overflows its
// box by even one pixel keeps its own scroll view alive, and that view swallows
// the mouse wheel -- so with the pointer over a table the page will not move,
// and there is no way past a long card but to find a gap beside it.
//
// The first attempt at this used `rows * 48 + 56`, which ignored the theme's
// `dividerThickness: 1` and so came up one pixel per row short. It looked
// right, changed nothing on screen, and is exactly why this is measured here
// against a real table rather than reasoned about.
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/table_pager.dart';

void main() {
  /// Renders [rowCount] rows in a box of the height the helper asks for, and
  /// reports how tall the table actually wanted to be.
  Future<({double box, double content})> measure(
      WidgetTester tester, int rowCount) async {
    final key = GlobalKey();
    final boxHeight = dataTable2Height(rowCount);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SizedBox(
          width: 1400,
          height: boxHeight,
          child: DataTable2(
            key: key,
            minWidth: 1280,
            columns: const [
              DataColumn2(label: Text('A')),
              DataColumn2(label: Text('B')),
            ],
            rows: [
              for (var i = 0; i < rowCount; i++)
                DataRow(cells: [DataCell(Text('r$i')), const DataCell(Text('x'))]),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The inner vertical scroll view is what steals the wheel. If it has
    // nothing to scroll, maxScrollExtent is 0.
    //
    // ⚠️ Read from each Scrollable's own STATE. `Scrollable.of(element)` looks
    // UP the tree from that element and throws when there is none above it,
    // which is what an earlier version of this test did — it failed on every
    // case and said nothing about the heights.
    var maxExtent = 0.0;
    for (final state in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
      final pos = state.position;
      if (pos.axis == Axis.vertical && pos.hasContentDimensions) {
        maxExtent =
            maxExtent > pos.maxScrollExtent ? maxExtent : pos.maxScrollExtent;
      }
    }
    return (box: boxHeight, content: maxExtent);
  }

  group('the helper leaves nothing to scroll', () {
    for (final rowCount in [1, 2, 3, 5, 8, 12, 20]) {
      testWidgets('$rowCount rows fit without overflow', (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final m = await measure(tester, rowCount);

        // ⚠️ maxScrollExtent of 0 means the table has no surplus, so the wheel
        // passes straight through to the page. Anything above 0 is the bug.
        expect(m.content, 0,
            reason: '$rowCount rows overflow the ${m.box}px box by '
                '${m.content}px — the card would keep the wheel');
      });
    }
  });

  group('the arithmetic itself', () {
    test('it accounts for the heading, the rows AND the dividers', () {
      // 56 heading + 49 per row (48 + the theme's 1px divider) + slack.
      expect(dataTable2Height(0), 62);
      expect(dataTable2Height(1), 111);
      expect(dataTable2Height(10), 552);
    });

    test('it grows by more than the bare row height', () {
      // ⚠️ The first version used 48 and was short by exactly the dividers.
      final perRow = dataTable2Height(11) - dataTable2Height(10);
      expect(perRow, greaterThan(48));
    });
  });
}
