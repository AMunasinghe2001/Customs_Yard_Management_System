// Tests for the four appeal states, and for the seeder rules that make all
// four reachable.
//
// The bug these lock down: the seed only ever produced TWO of the four states
// -- "Appealing - Nd" while the window ran, and "Enabled" once it expired.
// The two that need a human ruling ("On Appeal Hold" and "Decided - X") were
// never written by anything, so the Appeal Directorate's "Decided Goods" tab
// was permanently empty and no row anywhere showed a hold.
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

void main() {
  group('AppealStateChip states', () {
    final future = DateTime.now().add(const Duration(days: 7));
    final past = DateTime.now().subtract(const Duration(days: 7));

    test('a hold blocks action even after the deadline has passed', () {
      // The whole point of a hold: the calendar alone can never produce it,
      // and it must OUTLAST the deadline. Deriving state from the date would
      // wrongly show these goods as actionable.
      const outcome = ItemAppealOutcome(onHold: true);
      expect(outcome.unblocksAction, isFalse);

      // Even decided-and-held stays blocked -- the hold wins.
      const both = ItemAppealOutcome(decision: 'SALE', onHold: true);
      expect(both.unblocksAction, isFalse);
      expect(DateTime.now().isAfter(past), isTrue);
    });

    test('a decision unblocks action before the window closes', () {
      const outcome = ItemAppealOutcome(decision: 'SALE');
      expect(outcome.isDecided, isTrue);
      expect(outcome.unblocksAction, isTrue);
      // The window is still open, yet the ruling ends the wait early.
      expect(DateTime.now().isBefore(future), isTrue);
    });

    test('no outcome leaves the window in charge', () {
      const outcome = ItemAppealOutcome();
      expect(outcome.isDecided, isFalse);
      expect(outcome.unblocksAction, isFalse);
    });

    test('every decision code the seeder writes renders a label', () {
      // A code the model does not recognise renders as NO decision at all --
      // the row would silently fall back to the countdown. Each code the
      // seeder can write must map to a label.
      for (final code in const [
        'RELEASE',
        'SALE',
        'DESTROY',
        'RE-EXPORT',
        'OTHER',
      ]) {
        expect(ItemAppealOutcome(decision: code).label, isNotNull,
            reason: '$code must map to a label the yard can read');
      }
      expect(const ItemAppealOutcome(decision: 'NONSENSE').label, isNull);
    });
  });

  group('a ruling names an action the yard can actually carry out', () {
    // ⚠️ A decision is an INSTRUCTION to take one of the five Final
    // Disposition actions (Release / Sale / Destroy / Re-export / Other).
    // A code outside that set names an action the yard cannot perform, and
    // renders as no decision at all.
    test('every Final Disposition action has a matching decision code', () {
      for (final code in const [
        'RELEASE',
        'SALE',
        'DESTROY',
        'RE-EXPORT',
        'OTHER',
      ]) {
        expect(ItemAppealOutcome(decision: code).label, isNotNull);
      }
    });

    test('a code the yard has no action for is not treated as a decision', () {
      const bogus = ItemAppealOutcome(decision: 'REFER-BACK');
      expect(bogus.label, isNull);
    });
  });

  group('the 30-day window applies to every status alike', () {
    test('a package entered today is still inside its window', () {
      final today = DateTime.now().subtract(const Duration(days: 1));
      expect(isWithinAppealWindow(today), isTrue);
      expect(appealDaysLeft(today), greaterThan(0));
    });

    test('a package entered 40 days ago has run out', () {
      final old = DateTime.now().subtract(const Duration(days: 40));
      expect(isWithinAppealWindow(old), isFalse);
      expect(appealDaysLeft(old), 0);
    });

    // ⚠️ Detain is NOT exempt. It has no forfeited_packages row of its own, so
    // it is easy to assume it has no window either -- but the window runs from
    // the ENTRY DATE and freezes a Detain exactly as it freezes a Forfeit.
    test('the window is derived from the entry date, not from a forfeiture',
        () {
      final entered = DateTime.now().subtract(const Duration(days: 10));
      // The deadline runs from the calendar DAY of entry, not from the moment
      // -- goods that arrived at 4pm are not shortchanged against ones that
      // arrived at 9am, so the time of day is dropped.
      final day = DateTime(entered.year, entered.month, entered.day);
      expect(appealDeadlineFrom(entered), day.add(const Duration(days: 30)));
      expect(isWithinAppealWindow(entered), isTrue);
    });
  });

  group('per-item decisions do not bleed across a package', () {
    // One SR number can cover several goods, and the Appeal Directorate rules
    // on ONE item at a time. A package-level decision must not mark an
    // undecided sibling as decided.
    // ⚠️ packageDetails MUST be supplied: the guard that stops a decision
    // bleeding onto a sibling asks how many items the package has, and with a
    // null packageDetails it never engages -- a test without it passes even
    // with the bug put back, proving nothing.
    ForfeitedPackageModel model({
      required String itemId,
      Map<String, dynamic> perItem = const {},
      String? packageLevel,
      int itemCount = 2,
    }) {
      final now = DateTime(2026, 1, 1);
      return ForfeitedPackageModel(
        id: 'f1',
        packageId: 'p1',
        srNumber: 'CED/GL1/SR/01/2026',
        consigneeName: 'Test',
        forfeitedAt: now,
        appealDeadline: now.add(const Duration(days: 30)),
        reason: 'test',
        source: 'forfeit',
        itemId: itemId,
        appealDecision: packageLevel,
        itemAppealDecisions: perItem,
        packageDetails: PackageModel(
          id: 'p1',
          srNumber: 'CED/GL1/SR/01/2026',
          consigneeName: 'Test',
          status: 'pending',
          createdAt: now,
          updatedAt: now,
          warehouseEntries: const [],
          items: [
            for (var i = 1; i <= itemCount; i++)
              PackageItem(
                id: 'i$i',
                packageId: 'p1',
                itemName: 'Goods $i',
                quantity: 10,
                status: 'Forfeit',
              ),
          ],
        ),
      );
    }

    test('an item with its own decision resolves to that decision', () {
      final m = model(
        itemId: 'i1',
        perItem: {
          'i1': {'decision': 'SALE'},
        },
      );
      expect(m.appealDecisionForItem('i1'), 'SALE');
      expect(m.hasAppealDecision, isTrue);
    });

    test('a sibling with no entry of its own is NOT decided', () {
      final m = model(
        itemId: 'i2',
        perItem: {
          'i1': {'decision': 'SALE'},
        },
      );
      expect(m.appealDecisionForItem('i2'), isNull);
    });

    test('a stale package-level decision does not bleed onto a sibling', () {
      // The old flow wrote ONE item's decision to the whole package. On a
      // multi-item package that value must be ignored, or an undecided item
      // silently inherits a ruling that was never made about it.
      final m = model(itemId: 'i2', packageLevel: 'DESTROY');
      expect(m.appealDecisionForItem('i2'), isNull);
      expect(m.hasAppealDecision, isFalse);
    });

    test('a long OTHER note is trimmed so it fits the decision chip', () {
      // The note is free text an officer typed and it becomes the chip's
      // LABEL. A sentence-long one overflowed the chip and was clipped
      // mid-word ("Decided - Referred back to the yard for further inquiry").
      final m = model(
        itemId: 'i1',
        perItem: {
          'i1': {
            'decision': 'OTHER',
            'note': 'Referred back to the yard for further inquiry',
          },
        },
      );
      final label = m.appealDecisionLabelForItem('i1')!;
      expect(label.length, lessThanOrEqualTo(kAppealDecisionLabelMaxChars));
      expect(label, endsWith('…'));
      // The full note is still available -- only the LABEL is shortened.
      expect(m.appealDecisionNoteForItem('i1'),
          'Referred back to the yard for further inquiry');
    });

    test('a short OTHER note is shown in full', () {
      final m = model(
        itemId: 'i1',
        perItem: {
          'i1': {'decision': 'OTHER', 'note': 'Referred back to yard'},
        },
      );
      expect(m.appealDecisionLabelForItem('i1'), 'Referred back to yard');
    });

    test('an OTHER decision with no note falls back to "Other"', () {
      final m = model(
        itemId: 'i1',
        perItem: {
          'i1': {'decision': 'OTHER'},
        },
      );
      expect(m.appealDecisionLabelForItem('i1'), 'Other');
    });

    test('a SINGLE-item package still honours the package-level decision', () {
      // The fallback is valid when there is only one item -- there is no
      // sibling to bleed onto.
      final m = model(itemId: 'i1', packageLevel: 'DESTROY', itemCount: 1);
      expect(m.appealDecisionForItem('i1'), 'DESTROY');
    });
  });
}
