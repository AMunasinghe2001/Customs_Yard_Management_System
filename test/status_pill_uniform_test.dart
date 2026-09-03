// Every status pill in a table column is the same size.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/widgets/destruction_status_pill.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  group('one box, whatever the label', () {
    // ⚠️ A pill that sizes to its own text makes a column of them ragged.
    // "Convert" came out half the width of "Remove from the Premises", so the
    // eye could not scan down the column — and the three tables that show
    // these side by side did not line up with each other.
    test('the shared width is one constant', () {
      expect(kStatusPillWidth, kDestructionPillWidth);
      expect(kStatusPillWidth, greaterThan(0));
    });

    test('every status control renders through the shared builder', () {
      final pill = _read('lib/widgets/destruction_status_pill.dart');
      final shared = _read('lib/screens/executive/unsold_shared.dart');

      // Destroyed, Delivered and Final Outcome all go through _statusPill.
      expect(pill, contains('class DestructionStatusPill'));
      expect(pill, contains('class DeliveryStatusPill'));
      expect(shared, contains('statusPill('),
          reason: 'the outcome chip must use the shared box');

      // ⚠️ …and none of them may build its own sized container instead.
      expect(shared.contains('padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)'),
          isFalse,
          reason: 'a hand-rolled box would drift from the shared one');
    });

    test('the box is fixed, not text-sized', () {
      final pill = _read('lib/widgets/destruction_status_pill.dart');
      expect(pill, contains('width: kDestructionPillWidth'));
      expect(pill, contains('height: kDestructionPillHeight'));
    });

    // A fixed pill inside a narrower column would clip and paint overflow
    // stripes, so every column that holds one must be at least as wide.
    test('the columns that hold one are wide enough', () {
      expect(kDestructionStatusColumnWidth,
          greaterThanOrEqualTo(kStatusPillWidth));

      final perishable =
          _read('lib/screens/packages/perishable_goods_screen.dart');
      final match =
          RegExp(r"Text\('Final Outcome'\)[\s\S]{0,200}?fixedWidth: (\d+)")
              .firstMatch(perishable);
      expect(match, isNotNull);
      expect(int.parse(match!.group(1)!),
          greaterThanOrEqualTo(kStatusPillWidth.round()));
    });
  });
}
