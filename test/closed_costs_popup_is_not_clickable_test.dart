// A closed destruction record opens as a VIEW, and a view must not be
// clickable anywhere.
//
// ⚠️ The first attempt used `readOnly: true`. That governs writes, not
// affordance: the field still took focus, drew the accent focus ring, showed
// a caret and let its text be selected — so the popup looked editable and
// only refused once the officer tried it. Reported from a screenshot with the
// Advertising field lit up exactly that way.
//
// This pumps the real dialog and asks the widget tree, rather than matching
// source text: the point is what the officer can click, and only a rendered
// tree can answer that.
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/disposal/expenses_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SrFinancials _sr() => SrFinancials(
      srNumber: 'CED/GL1/SR/47/2026',
      yard: 'GL1',
      destroyingDeposit: 28726,
      goods: [
        GoodsFinancials(
          itemId: 'item-1',
          srNumber: 'CED/GL1/SR/47/2026',
          goodsName: 'Steel Cooking Pots',
          yard: 'GL1',
          quantity: 108,
          destructionExpense: 32393,
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, {required bool locked}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: RecordExpenseDialog(
          sr: _sr(),
          forDestruction: true,
          locked: locked,
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('a closed destruction record is a view, not a form', () {
    testWidgets('it renders no text field at all', (tester) async {
      await _pump(tester, locked: true);
      expect(find.byType(TextField), findsNothing,
          reason: 'an input on a closed record invites an edit that will '
              'be refused');
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('and nothing in it can take focus', (tester) async {
      await _pump(tester, locked: true);
      // ⚠️ FOCUS is the thing that gave it away: the read-only field drew
      // an accent ring and a caret when clicked. A view has nothing to
      // focus, so no EditableText may exist at all.
      expect(find.byType(EditableText), findsNothing,
          reason: 'a focusable input on a closed record');

      // ⚠️ Scoped to the COST ROWS, not the whole dialog. Two tappable
      // InkWells are legitimate and must stay: the header's X and the Close
      // action -- without them the popup could not be dismissed. What must
      // not be tappable is the content.
      //
      // Counting every InkWell in the tree would have failed on those two
      // and told us nothing; `GestureDetector` is worse still, since the
      // scroll views install their own.
      for (final label in [
        'Destruction Expenses',
        'Advertising Expenses',
        'Labour Costs',
        'Transport Costs',
      ]) {
        final row = find.ancestor(
          of: find.textContaining(label),
          matching: find.byType(Container),
        );
        expect(row, findsWidgets, reason: '$label is missing from the view');
        final taps = tester
            .widgetList<InkWell>(
                find.descendant(of: row.first, matching: find.byType(InkWell)))
            .where((w) => w.onTap != null)
            .length;
        expect(taps, 0, reason: 'the $label row responds to taps');
      }

      // And the dialog is still dismissible.
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('the figures are still readable', (tester) async {
      await _pump(tester, locked: true);
      // Reading them is the only reason a closed form opens.
      expect(find.textContaining('32,393.00'), findsWidgets);
      // A real zero is shown rather than left blank: on a closed record
      // "nothing was charged" is a finding.
      expect(find.textContaining('0.00'), findsWidgets);
    });

    testWidgets('it says why it cannot be edited', (tester) async {
      await _pump(tester, locked: true);
      expect(find.textContaining('already been destroyed'), findsOneWidget);
    });

    testWidgets('it offers Close and no Save', (tester) async {
      await _pump(tester, locked: true);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Save Costs'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('while an OPEN record still has its fields', (tester) async {
      // The control case — proving the tests above are about `locked` and
      // not about the dialog simply failing to build.
      await _pump(tester, locked: false);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Save Costs'), findsOneWidget);
    });
  });
}
