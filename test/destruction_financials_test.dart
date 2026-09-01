import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two problems around destruction expenses, both surfaced from real
/// screenshots.
void main() {
  group('srFinancialsProvider no longer invents money', () {
    final src = File('lib/core/providers.dart').readAsStringSync();

    test('the fake-seed block for proceeds/charges/expenses is gone', () {
      expect(src, isNot(contains('Seed dummy figures when data is empty')));
      expect(src, isNot(contains("hashCode.abs() % 40")),
          reason: 'That constant identified the proceeds fake-seed.');
      expect(src, isNot(contains("hashCode.abs() % 20")),
          reason: 'That constant identified the destruction fake-seed.');
    });

    test('the fake-seeded deposit is gone', () {
      expect(src, isNot(contains('Seed a dummy deposit')));
      expect(src, isNot(contains("hashCode.abs() % 50")),
          reason: 'That constant identified the deposit fake-seed.');
    });
  });

  test('both Destroyed Goods popups now carry the real srFinancials', () {
    // Both used to open PackageDetailsDialog with no srFinancials at all, so
    // the popup always showed "Financial data will be available..." even
    // once Central Disposal had recorded real destruction expenses.
    for (final path in [
      'lib/screens/disposal/disposal_dashboard_screen.dart',
      'lib/screens/packages/disposition_category_screen.dart',
    ]) {
      final flat = File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains('srFinancials: ref .watch(srFinancialsProvider)'),
          reason: '$path never looks up the SR\'s financials for the popup.');
    }
  });

  test('the dead Mark-Delivered destruction section is gone', () {
    // Never instantiated anywhere, but its shape (Valuation / Delivery
    // Status / Destruction Price / Receipt No, plus a "Mark Delivered"
    // button) was exactly what should NOT appear for a destroyed package --
    // destruction has no delivery step, only destroyed-or-not.
    final src = File('lib/widgets/package_details_dialog.dart').readAsStringSync();
    expect(src, isNot(contains('_DestructionDeliverySection')));
  });
}
