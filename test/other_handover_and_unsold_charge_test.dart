import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final note = File('lib/widgets/storage_charge_note.dart').readAsStringSync();
  final dialog =
      File('lib/widgets/package_details_dialog.dart').readAsStringSync();
  final other =
      File('lib/screens/packages/other_packages_screen.dart').readAsStringSync();
  final cell = File('lib/widgets/handover_cell.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final migration =
      File('migrations/013_other_goods_handover.sql').readAsStringSync();

  group('unsold goods carry no storage figure', () {
    test('the note is replaced by a sentence, not removed', () {
      // An empty panel reads as "storage was never recorded" and sends the
      // reader looking for the number somewhere else.
      expect(note, contains('class _NotChargedNote'));
      expect(note, contains('No warehouse charge'));
      expect(note, contains('unsold goods are not billed'));
    });

    test('the rule travels with the figure, not with a page', () {
      // The same packages reappear under Government Use, Auction Goods,
      // Converted Goods and Removed from Premises.
      expect(note, contains('bool _isUnsoldDisposal('));
      expect(note, contains('unsoldProposalsProvider'));
      expect(note, contains('forfeitedByItemProvider'));
    });

    test('the per-item storage block obeys it too', () {
      expect(dialog, contains('unsoldDisposal'));
      expect(dialog, contains("value: 'Not charged'"));
      expect(dialog, contains('storage is not billed on unsold'));
    });
  });

  group('"Other" goods can be handed over', () {
    test('a completed disposition is a ruling, not a departure', () {
      expect(other, contains("Text('Delivery')"));
      expect(other, contains('HandoverEntryKind.other'));
      // The expression wraps across lines in the source, so match the
      // field rather than the whole chain.
      expect(other, contains('otherDelivered'));
    });

    test('goods still under appeal have nothing to hand over', () {
      expect(other, contains('row.completed'));
    });

    test('it does NOT reuse the re-export flag', () {
      // yard_toggle_reexport_delivery rejects a non-re-export entry and
      // writes re_export_delivered — filing these goods as re-exported.
      expect(services, contains('toggleOtherDelivery('));
      expect(services, contains("'yard_toggle_other_delivery'"));
      expect(cell, contains('svc.toggleOtherDelivery('));
    });

    test('the migration guards the tag and leaves the entry closed', () {
      expect(migration, contains('other_delivered'));
      expect(migration, contains("v_tag not in ('FINAL:OTHER', 'OTHER')"));
      // Recording the disposition already closed the entry; re-closing
      // would overwrite returned_at with today.
      expect(migration, isNot(contains('set is_returned')));
    });
  });

  test('the perishable table fits instead of scrolling sideways', () {
    final perishable = File('lib/screens/packages/perishable_goods_screen.dart')
        .readAsStringSync();
    // minWidth is still required — data_table_2 asserts when its fixed
    // columns outgrow the parent — but 1180 was far above what the table
    // needs, so it scrolled on a window it would have fitted.
    expect(perishable, contains('minWidth: 820'));
    expect(perishable, isNot(contains('minWidth: 1180')));
  });
}
