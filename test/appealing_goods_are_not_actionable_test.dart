import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/models/models.dart';

/// Goods inside their 30-day appeal window cannot be acted on. The owner still
/// has time to appeal, so the yard may neither record a final disposition nor
/// send them to Central Disposal.
///
/// ⚠️ Observed: a row showing "Appealing · 12d" opened a popup whose Final
/// Disposition button was ENABLED. The gate was "is this row already
/// completed" alone — it never consulted the appeal state the very same table
/// was painting one column to the left.
void main() {
  final today = DateTime.now();
  DateTime daysAgo(int d) => today.subtract(Duration(days: d));

  group('canActOnHeldGoods', () {
    test('an open window blocks action', () {
      expect(canActOnHeldGoods(entryDate: daysAgo(12)), isFalse);
      expect(canActOnHeldGoods(entryDate: daysAgo(29)), isFalse);
    });

    test('a closed window allows it', () {
      expect(canActOnHeldGoods(entryDate: daysAgo(31)), isTrue);
      expect(canActOnHeldGoods(entryDate: daysAgo(400)), isTrue);
    });

    test('a ruling releases the goods early', () {
      // The Directorate has spoken; the calendar no longer matters.
      const decided = ItemAppealOutcome(decision: 'SALE', onHold: false);
      expect(canActOnHeldGoods(entryDate: daysAgo(2), outcome: decided), isTrue);
    });

    test('a HOLD blocks even after the window closes', () {
      // ⚠️ The case a date comparison alone gets wrong: an appeal is lodged
      // and still under review, so the deadline passing does not release it.
      const held =
          ItemAppealOutcome(decision: null, onHold: true);
      expect(canActOnHeldGoods(entryDate: daysAgo(90), outcome: held), isFalse);
    });

    test('a hold beats a decision', () {
      const both =
          ItemAppealOutcome(decision: 'SALE', onHold: true);
      expect(canActOnHeldGoods(entryDate: daysAgo(90), outcome: both), isFalse);
    });

    test('no date and no ruling is not actionable', () {
      // Nothing is known, so nothing is permitted — the safe direction.
      expect(canActOnHeldGoods(), isFalse);
    });
  });

  group('every held-goods page consults it', () {
    const pages = [
      'lib/screens/packages/other_packages_screen.dart',
      'lib/screens/packages/abandoned_packages_screen.dart',
    ];

    for (final path in pages) {
      final name = path.split('/').last.replaceAll('_screen.dart', '');
      final src = File(path).readAsStringSync();

      test('$name gates Final Disposition on the appeal state', () {
        expect(src, contains('canActOnHeldGoods('),
            reason: '$name can still record a disposition while appealing');
      });

      test('$name does not force the button unconditionally', () {
        // ⚠️ Abandoned passed `forceFinalDisposition: true` on the claim that
        // every row was actionable, while painting an AppealStateChip above.
        expect(src.contains('forceFinalDisposition: true'), isFalse,
            reason: 'an appealing row would get an enabled button');
      });
    }
  });

  group('the bulk request refuses them too', () {
    final dialog =
        File('lib/screens/forfeited_packages/disposal_request_dialog.dart')
            .readAsStringSync();

    test('a pending row cannot be selected', () {
      // Greying it out is not enough — it must be inert.
      expect(dialog, contains('onTap: pending ? null : onToggle'));
    });
  });

  group('a finished row is not told to proceed', () {
    final src = File('lib/screens/packages/other_packages_screen.dart')
        .readAsStringSync();

    test('the appeal banner is hidden once the outcome is recorded', () {
      // ⚠️ The banner is an INSTRUCTION — "Proceed with: Release to owner"
      // tells the yard what it must still carry out. On a COMPLETED row there
      // is nothing left to carry out, so it read as a contradiction: goods
      // already recorded with an Other outcome, waiting only to be delivered,
      // captioned with an order to release them.
      //
      // Other Goods is the only page that mixes finished and unfinished rows;
      // Abandoned and Detained carry no `completed` flag at all.
      expect(src, contains('appealDecisionLabel: row.completed'),
          reason: 'a finished row still shows an instruction it cannot act on');
      expect(src, contains('appealDecisionCode: (!row'),
          reason: 'the decision code must be suppressed with the label');
    });
  });
}
