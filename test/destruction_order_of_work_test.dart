// Destruction is a two-party job, and it has an ORDER. Given directly:
//
//   1. Central Disposal records what the destruction costs.
//   2. Only then may the YARD confirm the goods were destroyed.
//   3. Once destroyed, the costs are closed — the form opens read-only.
//   4. Central Disposal never confirms a destruction at all; it only reads.
//
// Rules 1 and 3 lock against each other: the cost form closes when a row is
// destroyed, so if the yard could mark first the figure could never be
// entered. That is why the gate exists rather than a warning.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pill = File('lib/widgets/destruction_status_pill.dart').readAsStringSync();
  final central =
      File('lib/screens/disposal/disposal_dashboard_screen.dart').readAsStringSync();
  final yard = File('lib/screens/packages/disposition_category_screen.dart')
      .readAsStringSync();
  final form = File('lib/screens/disposal/expenses_tab.dart').readAsStringSync();

  group('the yard cannot confirm a destruction before it is costed', () {
    test('the pill checks the SR spend before offering Mark Destroyed', () {
      expect(pill, contains('final String? srNumber'));
      expect(pill, contains('destructionSpendProvider'));
      expect(pill, contains("label: 'Awaiting Costs'"));
    });

    test('the waiting state carries no onTap', () {
      // ⚠️ It must be inert, not merely coloured differently — a pill that
      // still fires would let the yard straight past the rule.
      final i = pill.indexOf("label: 'Awaiting Costs'");
      expect(i, greaterThan(-1));
      // The enclosing _pill call runs from the preceding '_pill(' to the
      // next closing paren group; no onTap may appear in it.
      final start = pill.lastIndexOf('_pill(', i);
      final segment = pill.substring(start, i + 200);
      expect(segment.contains('onTap:'), isFalse,
          reason: 'the Awaiting Costs pill is clickable');
    });

    test('and it says what is being waited for', () {
      // A disabled control with no explanation is the thing being avoided.
      expect(pill, contains('has not recorded the destruction costs'));
    });

    test('the yard table passes its SR so the gate can apply', () {
      final i = yard.indexOf('DestructionStatusPill(');
      expect(i, greaterThan(-1));
      final segment = yard.substring(i, i + 500);
      expect(segment, contains('srNumber:'));
      expect(segment, contains('onMark:'),
          reason: 'the yard is the side that confirms');
    });

    test('the gate reuses the page-scoped spend query, not a per-row one', () {
      // ⚠️ Twenty rows must not mean twenty round trips — the same mistake
      // the Destroyed Goods tab was already fixed for once.
      expect(pill, contains('DestructionExpenseScope.of(context)'));
    });
  });

  group('Central Disposal reads the destruction but never confirms it', () {
    test('its pill is given no onMark', () {
      final i = central.indexOf('DestructionStatusPill(');
      expect(i, greaterThan(-1));
      final segment = central.substring(i, i + 400);
      expect(segment.contains('onMark:'), isFalse,
          reason: 'Central Disposal must not be able to mark destroyed');
      expect(segment, contains('srNumber:'));
    });
  });

  group('once destroyed, the costs are closed', () {
    test('the dialog takes a locked flag', () {
      expect(form, contains('final bool locked'));
    });

    test('Central Disposal opens it locked for a destroyed row', () {
      expect(central, contains('locked: row.isDestroyed'));
    });

    test('a locked form renders NO input at all', () {
      // ⚠️ This started as `readOnly: true`, which was not enough: a
      // read-only TextField still takes focus, shows a caret, draws the
      // accent focus ring and lets its text be selected -- so a closed
      // record looked editable and refused only after the officer tried.
      // Asked for plainly: a view popup must not be clickable anywhere.
      //
      // `readOnly` governs WRITES; this is about AFFORDANCE, and the only
      // way to have none is to render no input.
      expect(form, contains('if (widget.locked)'));
      expect(form, contains('_ReadOnlyCost('));
      expect(form, contains('class _ReadOnlyCost'));
      expect(form.contains('readOnly: widget.locked'), isFalse,
          reason: 'a read-only field still focuses and shows a caret');
    });

    test('the display row has nothing tappable on it', () {
      final i = form.indexOf('class _ReadOnlyCost');
      expect(i, greaterThan(-1));
      final body = form.substring(i);
      for (final interactive in [
        'onTap',
        'onPressed',
        'InkWell',
        'GestureDetector',
        'TextField',
        'TextFormField',
      ]) {
        expect(body.contains(interactive), isFalse,
            reason: 'the closed-record row exposes $interactive');
      }
    });

    test('a real zero is shown, not left blank', () {
      // On a closed record "nothing was charged" is a finding, not a gap.
      final i = form.indexOf('class _ReadOnlyCost');
      expect(form.substring(i), contains('money.format(amount)'));
    });

    test('there is no Save button at all when locked', () {
      expect(form, contains('actions: widget.locked'));
      expect(form, contains("child: const Text('Close')"));
    });

    test('and the write itself refuses, not just the button', () {
      // A shortcut or an autosave must not slip past the rule.
      final i = form.indexOf('Future<void> _save() async {');
      expect(i, greaterThan(-1));
      expect(form.substring(i, i + 400), contains('if (widget.locked) return;'));
    });

    test('the notice explains why it cannot be edited', () {
      expect(form, contains('already been destroyed'));
      expect(form, contains('cannot be edited'));
    });
  });
}
