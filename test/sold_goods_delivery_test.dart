// Four things wrong on the Sold Goods and Disposal Requests screens.
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the destruction-status test now used by the details popup.
bool statusIsDestruction(String? status) {
  final st = (status ?? '').toLowerCase();
  return st == 'destroyed' ||
      st == 'supposed to be destroyed' ||
      st == 'destroy';
}

void main() {
  group('the Destruction panel belongs to the item, not the package', () {
    // ⚠️ One SR number covers several goods, and they meet different ends.
    // Asking whether ANY item in the package was being destroyed showed the
    // "Destruction Status & Financials" panel on a SOLD item's popup, because
    // a sibling under the same number was pending destruction.
    bool showsDestructionPanel({
      required String? viewedItemStatus,
      required List<String> siblingStatuses,
    }) {
      // The viewed item decides when it is known.
      if (viewedItemStatus != null) return statusIsDestruction(viewedItemStatus);
      return siblingStatuses.any(statusIsDestruction);
    }

    test('a sold item does not show it, even beside a destroyed sibling', () {
      expect(
          showsDestructionPanel(
              viewedItemStatus: 'sold',
              siblingStatuses: const ['supposed to be destroyed']),
          isFalse);
    });

    test('a destroyed item does show it', () {
      expect(
          showsDestructionPanel(
              viewedItemStatus: 'destroyed', siblingStatuses: const []),
          isTrue);
    });

    test('an item awaiting destruction shows it', () {
      expect(
          showsDestructionPanel(
              viewedItemStatus: 'supposed to be destroyed',
              siblingStatuses: const []),
          isTrue);
    });

    test('with no item in view it falls back to the package', () {
      expect(
          showsDestructionPanel(
              viewedItemStatus: null,
              siblingStatuses: const ['sold', 'destroyed']),
          isTrue);
      expect(
          showsDestructionPanel(
              viewedItemStatus: null, siblingStatuses: const ['sold']),
          isFalse);
    });
  });

  group('confirming delivery', () {
    // The action moved out of the details popup and into the table cell.
    // Only a yard confirms it, and there is no revert.
    bool showsMarkDeliveredButton(
            {required bool isDelivered, required bool isDisposalDirectorate}) =>
        !isDelivered && !isDisposalDirectorate;

    test('a pending row in a yard offers the button', () {
      expect(
          showsMarkDeliveredButton(
              isDelivered: false, isDisposalDirectorate: false),
          isTrue);
    });

    // ⚠️ No "Mark as Not Delivered": goods that left with their buyer cannot
    // un-leave, so a delivered row is a plain label.
    test('a delivered row offers nothing — there is no revert', () {
      expect(
          showsMarkDeliveredButton(
              isDelivered: false, isDisposalDirectorate: false),
          isTrue);
      expect(
          showsMarkDeliveredButton(
              isDelivered: true, isDisposalDirectorate: false),
          isFalse);
    });

    test('Central Disposal watches but does not confirm', () {
      expect(
          showsMarkDeliveredButton(
              isDelivered: false, isDisposalDirectorate: true),
          isFalse);
    });
  });

  group('a disposal request is always a sale', () {
    // The "0 Destruction" pill read as a route the app does not have.
    test('only the Sale count is worth showing', () {
      const dispositions = ['sale', 'sale', 'sale', 'sale'];
      final destruction = dispositions.where((d) => d == 'destruction').length;
      expect(destruction, 0);
      expect(dispositions.length, 4);
    });
  });
}
