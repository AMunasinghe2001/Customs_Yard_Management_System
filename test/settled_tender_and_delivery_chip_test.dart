import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();
  final other =
      File('lib/screens/packages/other_packages_screen.dart').readAsStringSync();
  final admin = File('lib/screens/admin/admin_screen.dart').readAsStringSync();

  test('an undeliverable row states why, instead of showing a dash', () {
    // The column asks "have these left the yard?" — for goods still under
    // appeal the answer is not unknown, it is that nothing is decided.
    expect(other, contains('class _NotYetDeliverableChip'));
    expect(other, contains("Text('Not yet decided'"));
    expect(other, contains('_NotYetDeliverableChip()'));
  });

  test('the staff filter names a posting, not an account state', () {
    // The group holds two different people: a disabled account, and a
    // transferred officer whose account is perfectly live.
    expect(admin, contains("_statusChip('Serving', true)"));
    expect(admin, contains("_statusChip('Past Staff', false)"));
    expect(admin, isNot(contains("_statusChip('Inactive', false)")));
  });

  group('a settled tender sale recedes', () {
    test('the card takes a grey wash, strong enough to see', () {
      expect(dash, contains('final settledWash ='));
      expect(dash, contains('? settledWash'));
      // At 0.07 it was invisible beside an unsettled card, so a finished
      // sale looked identical to one still waiting on a decision.
      expect(dash, contains('muted.withOpacity(0.16)'));
    });

    test('it greys only once EVERY item is Sold or Unsold', () {
      // allDecided, not allSold: a sale whose items all went Unsold is
      // equally finished, and one still holding an undecided item is not.
      expect(dash, contains('widget.sale.allDecided : allSold'));
    });

    test('the wash frames the table instead of filling it', () {
      // The card is the grey surround; the table is the panel cut out of
      // it. With no ground of its own the table let the card's colour
      // through, so a perishable sale's whole grid came out amber — and
      // painting both grey made one flat block with no edge to the data.
      expect(dash, contains('color: context.colors.cardDark,'));
      expect(dash, contains('context.colors.textMuted.withOpacity(0.45)'));
    });

    test('the header goes lighter than the rows, not darker', () {
      // The surround is already grey, so a dark header merges into it and
      // the table loses its top edge.
      expect(dash, contains('headingRowColor: settled'));
      expect(dash, contains('Colors.white.withOpacity(0.05)'));
    });
  });
}
