import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/destruction_status_pill.dart';

/// The yard's Destroyed Goods table and Central Disposal's show the SAME
/// destruction states. They drifted apart once already -- different padding,
/// different column widths, and a "Mark Destroyed" button that dwarfed the
/// chips beside it -- so these tests pin the shared control's geometry and the
/// fact that both screens actually go through it.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      );

  group('the pill is one size in every state', () {
    testWidgets('destroyed, pending and mark-destroyed all measure the same',
        (tester) async {
      final sizes = <String, Size>{};

      for (final entry in <String, DestructionStatusPill>{
        'destroyed': const DestructionStatusPill(destroyed: true),
        'pending': const DestructionStatusPill(destroyed: false),
        'markable': DestructionStatusPill(destroyed: false, onMark: () {}),
      }.entries) {
        await tester.pumpWidget(host(entry.value));
        await tester.pump();
        sizes[entry.key] =
            tester.getSize(find.byType(DestructionStatusPill).first);
      }

      expect(sizes['destroyed'], sizes['pending'],
          reason: 'Pending rendered narrower than Destroyed');
      expect(sizes['destroyed'], sizes['markable'],
          reason: 'the clickable Mark Destroyed rendered a different size');
      expect(sizes['destroyed'],
          const Size(kDestructionPillWidth, kDestructionPillHeight));
    });

    testWidgets('the pill fits inside the shared status column width',
        (tester) async {
      expect(kDestructionPillWidth, lessThan(kDestructionStatusColumnWidth));
    });
  });

  group('the state each rendering means', () {
    testWidgets('a confirmed destruction is not clickable', (tester) async {
      await tester.pumpWidget(host(const DestructionStatusPill(destroyed: true)));
      expect(find.text('Destroyed'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('unconfirmed with no handler reads Pending, not a button',
        (tester) async {
      await tester
          .pumpWidget(host(const DestructionStatusPill(destroyed: false)));
      expect(find.text('Pending'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing,
          reason: 'Central Disposal is read-only; only the yard confirms');
    });

    testWidgets('unconfirmed with a handler is a working button',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
          host(DestructionStatusPill(destroyed: false, onMark: () => taps++)));
      expect(find.text('Mark Destroyed'), findsOneWidget);
      await tester.tap(find.byType(DestructionStatusPill));
      expect(taps, 1);
    });
  });

  group('both tables go through the shared control', () {
    final yard =
        File('lib/screens/packages/disposition_category_screen.dart')
            .readAsStringSync();
    final central =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();

    test('neither screen keeps a private copy of the status chip', () {
      for (final src in {'yard': yard, 'central': central}.entries) {
        expect(src.value, contains('DestructionStatusPill'),
            reason: '${src.key} must use the shared pill');
        expect(src.value, isNot(contains('class _MarkDestroyedCell')),
            reason: '${src.key} kept a private status widget');
        expect(src.value, isNot(contains('class _DisposalStatusChip')),
            reason: '${src.key} kept a private status widget');
      }
    });

    test('both read the SAME money figure through the shared cell', () {
      // They disagreed before: one summed destructionExpense alone, the other
      // depositSpent, so one SR showed two different numbers.
      for (final src in {'yard': yard, 'central': central}.entries) {
        expect(src.value, contains('DestructionExpenseCell'),
            reason: '${src.key} must use the shared expense cell');
      }
      expect(yard, isNot(contains('class _YardDestructionExpenseCell')));
      expect(central, isNot(contains('class _DisposalExpensesCell')));
    });

    test('the yard drops the columns that have no answer on each table',
        () {
      // Whitespace/line-endings vary, so compare on a normalised copy rather
      // than the file's exact bytes.
      final flat = yard.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          flat,
          contains("widget.finalTag != 'DESTROYED') const DataColumn2( "
              "label: Text('HS Code')"),
          reason: 'HS Code is not gated off the Destroyed table');
      // ⚠️ Officer is now gated off RE-EXPORTED as well: it reads
      // `returnedByName ?? returnedByBadge ?? '—'`, and a re-export sets
      // neither, so every row on that page printed a dash.
      expect(
          flat,
          contains("widget.finalTag != 'DESTROYED' && widget.finalTag != "
              "'RE-EXPORTED') const DataColumn2( label: Text('Officer')"),
          reason: 'Officer is not gated off Destroyed and Re-exported');
      // The Notes / Receipt No column is gated off for DESTROYED too.
      expect(
          flat,
          contains("if (widget.finalTag != 'DESTROYED') DataColumn2( "
              "label: Text(widget.finalTag == 'SOLD'"),
          reason: 'the Notes column is not gated off the Destroyed table');
    });
  });

  group('the cost form is shaped for a destruction', () {
    final form =
        File('lib/screens/disposal/expenses_tab.dart').readAsStringSync();
    final central =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();

    test('a destruction IS advertised, so the field is offered', () {
      // ⚠️ This test used to assert the opposite. The form excluded
      // advertising on the reasoning that "the goods go straight to the
      // destroying contractor, so nothing is advertised" -- and the officer
      // corrected it: a destruction is advertised, out of the same
      // destroying deposit.
      expect(
          form,
          contains("static const _notForDestruction = {'auction_expense'}"),
          reason: 'advertising must be enterable on a destruction');
    });

    test('but an auction is still never offered', () {
      // A destroyed item is never sold, so a figure here would be a
      // data-entry mistake rather than a field anyone needs.
      expect(form, contains("_notForDestruction = {'auction_expense'}"));
    });

    test('the destruction notice names advertising too', () {
      // The copy has to match the fields on screen; it told the officer only
      // "costs entered here" while the disposal version named both.
      expect(
          form,
          contains('Notice: Destruction and advertising costs entered here '
              'are deducted from the lodged Destroying Deposit.'));
    });

    test('the details popup shows Advertising unconditionally', () {
      // ⚠️ It was `if (advertisingExpense > 0)`, from the same wrong
      // premise. A blank box means "nothing spent yet", which is information
      // -- Destruction, Labour and Transport beside it are always shown.
      final popup =
          File('lib/widgets/package_details_dialog.dart').readAsStringSync();
      final i = popup.indexOf("label: 'Advertising'");
      expect(i, greaterThan(-1));
      // Look back a little way: no `> 0` guard may wrap it.
      final before = popup.substring(i - 400, i);
      expect(before, isNot(contains('advertisingExpense > 0')),
          reason: 'Advertising is hidden again when nothing is spent');
    });

    test('but anything already recorded under them still spends the deposit',
        () {
      // Dropping the fields must not hand the depositor a refund they are not
      // owed, so the hidden kinds stay in the arithmetic.
      expect(form, contains('_hiddenSpend'));
      expect(
          form,
          contains(
              "_fields.keys.fold<double>(0, (a, k) => a + _valueOf(k)) + _hiddenSpend"));
    });

    test('the Destroyed Goods table opens it in its destruction shape', () {
      // Matched loosely: `dart format` rewraps this call, and it now also
      // carries `locked:`. The point is the destruction shape, not the
      // line breaks.
      expect(central, contains('RecordExpenseDialog('));
      expect(central, contains('forDestruction: true'));
    });
  });
}
