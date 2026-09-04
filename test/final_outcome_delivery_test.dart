// A final outcome is a DECISION, not a hand-over.
//
// The DG rules "Government Use" on 3 July and the goods sit in Warehouse 01
// until somebody comes for them. Nothing recorded that anybody had: the yard
// could not say "these have gone", Central Disposal could not see whether they
// had, and zone capacity plus the storage charge went on counting goods that
// were no longer there.
//
// Sold goods already worked this way -- `tender_sale_items.is_delivered` and a
// Mark Delivered button that closes the warehouse entry. These tests pin the
// same shape onto the four Final Outcome pages.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final shared = File('lib/screens/executive/unsold_shared.dart').readAsStringSync();
  final yard = File('lib/screens/packages/unsold_packages_screen.dart').readAsStringSync();
  final disposal = File('lib/screens/disposal/disposal_dashboard_screen.dart').readAsStringSync();
  final migration =
      File('postgres/16_final_outcome_goods_can_be_handed_over.sql').readAsStringSync();
  final models = File('lib/models/models.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();

  group('the column exists only where there is something to hand over', () {
    test('the decided tables carry a Delivery column', () {
      expect(shared, contains("label: Center(child: Text('Delivery'))"));
    });

    test('the UNDECIDED table does not', () {
      // Its rows are still waiting on the DG, so the column would be nothing
      // but dashes. Count: the Delivery column appears once, in the decided
      // list only.
      expect("Text('Delivery')".allMatches(shared).length, 1);
      // Both lists still end with Details, so neither lost a column.
      expect("label: Center(child: Text('Details'))".allMatches(shared).length, 2);
    });

    test('the cell is optional, so the two tables stay in step', () {
      // ⚠️ A cell passed to the undecided table -- or omitted from the decided
      // one -- puts the cells out of line with the columns, and data_table_2
      // throws. The parameter is nullable and the cell is emitted only when
      // one is supplied.
      expect(shared, contains('Widget? delivery,'));
      expect(shared,
          contains('if (delivery != null) DataCell(Center(child: delivery)),'));
    });
  });

  group('both portals pass a cell exactly when the column is there', () {
    test('the yard gates its cell on the same filter as its columns', () {
      final flat = yard.replaceAll(RegExp(r'\s+'), ' ');
      // Columns: proposalFilter == null ? kUnsoldColumns : kUnsoldDecidedColumns
      expect(flat, contains('columns: widget.proposalFilter == null ? kUnsoldColumns : kUnsoldDecidedColumns'));
      // Cell: the SAME condition, so the two can never disagree.
      expect(flat, contains('delivery: widget.proposalFilter == null ? null : UnsoldDeliveryCell( proposal: proposals[f.id])'));
    });

    test('Central Disposal does too', () {
      final flat = disposal.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains('columns: proposalFilter == null ? kUnsoldColumns : kUnsoldDecidedColumns'));
      expect(flat, contains('delivery: proposalFilter == null ? null : UnsoldDeliveryCell( proposal: proposals[f.id])'));
    });
  });

  group('only the yard hands goods over', () {
    test('the button is refused to Central Disposal and to the DG', () {
      // They watch: Central Disposal carries out the decision through the yard,
      // and the DG made it. Neither is standing at the gate.
      expect(shared,
          contains('!profile.isDisposal && !profile.isExecutive'));
      expect(shared, contains('onMark: canEdit ? () => _markDelivered(p) : null'));
    });

    test('a watcher is told who they are waiting for', () {
      expect(shared, contains('Awaiting the yard to confirm hand-over'));
    });

    test('an undecided row shows nothing to deliver', () {
      expect(shared, contains("if (p == null) {"));
    });
  });

  group('the write reaches every reader', () {
    test('both proposal maps are invalidated, not just this page', () {
      // ⚠️ Central Disposal's outcome tabs read the SAME row through the
      // by-item map. Refreshing one leaves the two portals disagreeing about
      // whether the goods have been handed over.
      expect(shared, contains('ref.invalidate(unsoldProposalsProvider);'));
      expect(shared, contains('ref.invalidate(unsoldProposalsByItemProvider);'));
    });

    test('the warehouse is told too', () {
      // The hand-over closed the entry, so every page that asks "where is this
      // now" has to re-read.
      expect(shared,
          contains('ref.read(warehouseRefreshTriggerProvider.notifier).trigger();'));
    });

    test('the service goes through the one RPC', () {
      expect(services, contains('disposal_toggle_outcome_delivery'));
      expect(services, contains('Future<void> toggleOutcomeDelivery('));
    });
  });

  group('the record itself', () {
    test('the model carries both halves', () {
      expect(models, contains('final bool delivered;'));
      expect(models, contains('final DateTime? deliveredAt;'));
      expect(models, contains("delivered: json['delivered'] as bool? ?? false"));
      expect(models, contains("deliveredAt: parseDbDate(json['delivered_at'])"));
    });

    test('a delivery means a moment, and a moment means a delivery', () {
      // A row with one and not the other cannot be read.
      expect(migration, contains('unsold_proposals_delivery_consistent'));
      expect(migration.replaceAll(RegExp(r'\s+'), ' '), contains(
          'check ((delivered and delivered_at is not null) or (not delivered and delivered_at is null))'));
    });

    test('marking delivered CLOSES the warehouse entry in the same statement',
        () {
      // ⚠️ Not a display flag. Goods that have gone must stop counting against
      // zone capacity and stop accruing storage -- and a second statement that
      // could fail on its own would leave them counted forever.
      expect(migration, contains('update public.warehouse_entries w'));
      expect(migration, contains('set is_returned  = true'));
      expect(migration, contains("'[FINAL:'"));
      // Only on the way OUT. Un-marking must not resurrect a closed entry.
      expect(migration, contains('if p_delivered then'));
    });

    test('every existing decision starts undelivered', () {
      // Backfilling "true" would assert a hand-over nobody recorded, and the
      // yard would lose the list of what it still holds.
      expect(migration, contains('add column if not exists delivered boolean not null default false'));
    });
  });
}
