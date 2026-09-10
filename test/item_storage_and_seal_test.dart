import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dialog =
      File('lib/widgets/package_details_dialog.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final dash =
      File('lib/screens/disposal/disposal_dashboard_screen.dart').readAsStringSync();

  group('a valuation stays sealed while bidding is open', () {
    test('the seal is keyed to the sale CLOSE, not its start', () {
      // A reserve price is most dangerous while bidding is open, so the
      // start time is exactly the wrong gate.
      expect(services, contains("sale['sale_end_time']"));
      expect(services, contains('hasRun: moment != null && DateTime.now().isAfter(moment)'));
    });

    test('a round that has not run shows the seal, not the figure', () {
      expect(dialog,
          contains('final sealed = !valuerView && !(ranById[id] ?? false);'));
      expect(dialog, contains('SealedValuation(compact: true)'));
    });

    test('the directorate that SET the price still sees it', () {
      // Sealing there would hide the number from the only people whose job
      // is to decide the next one.
      expect(dialog, contains('valuerView'));
    });
  });

  group('per-item storage', () {
    test('entries are matched to the item, and legacy ones are not lost', () {
      // A pre-items admission carries no package_item_id. Dropping it would
      // make the goods look as though they were never in a warehouse.
      expect(dialog, contains(
          '.where((e) => e.packageItemId == null || e.packageItemId == item.id)'));
    });

    test('it shows where, under what, since when, and what it costs', () {
      expect(dialog, contains("'Storage & Movement'"));
      expect(dialog, contains("label: 'Held under'"));   // post status activity
      expect(dialog, contains("' · Zone '"));            // zone within warehouse
      expect(dialog, contains("label: 'Admitted'"));
      // The label switches: a bill where one is payable, otherwise the
      // cost of the space nobody is billed for.
      expect(dialog, contains("charge > 0 ? 'Storage charge' : 'Space cost (not billed)'"));
      expect(dialog, contains("'Delivered out'"));       // delivered vs held
      expect(dialog, contains("'In warehouse'"));
    });

    test('a zero figure is stated, not left blank', () {
      // Reached only when the space cost is genuinely zero; an empty cell
      // reads as a missing figure rather than an answer.
      expect(dialog, contains(": 'No charge'"));
    });

    test('nothing is rendered for goods never admitted', () {
      expect(dialog, contains('if (entries.isEmpty) return const SizedBox.shrink();'));
    });
  });

  test('the closed-sale chip does not repeat the sold tally', () {
    // The card already shows "0 / 4 sold" on the same row and the table
    // below marks every item, so counts here were the same fact three times.
    expect(dash, contains("Text('All items decided'"));
    expect(dash, contains('const _SaleClosedChip();'));
    expect(dash, isNot(contains('Bidding closed —')));
    expect(dash, isNot(contains('_SaleClosedChip(soldCount:')));
  });

  group('one fact, one place', () {
    test('the Disposition Breakdown is gone, not merely hidden', () {
      // It restated what the storage section and the status badge already
      // say, and its counts could drift from the entries behind them.
      expect(dialog, isNot(contains("'Disposition Breakdown'")));
      expect(dialog, isNot(contains('_DispositionRow')));
      expect(dialog, isNot(contains('String _heldLabel(')));
      expect(dialog, isNot(contains('String _leftLabel(')));
      // And the single-line "Current Warehouse" it sat beside.
      expect(dialog, isNot(contains("label: 'Current Warehouse'")));
      // The comment above the removal quotes the old wording, so match the
      // CODE that rendered it rather than the phrase itself.
      expect(dialog, isNot(contains("value: 'Left the warehouse — '")));
    });

    test('an admission does not repeat the item-level activity', () {
      expect(dialog, contains('itemActivity.toLowerCase()'));
    });
  });

  group('every final outcome gets the badge and the tint', () {
    test('sold, destroyed and re-exported are terminal, not neutral', () {
      // These sat in _neutralStatuses, so a SOLD item got no badge and no
      // tint while a released one did — one outcome visible, the rest not.
      expect(dialog, contains("final isItemSold = _itemStatus == 'sold';"));
      expect(dialog, contains("_itemStatus == 'destroyed'"));
      expect(dialog, contains("_itemStatus == 're-exported'"));
      expect(dialog, contains('isItemFinalOutcome'));
      // isItemTerminal drives both the badge and the card tint.
      expect(dialog, contains('isItemFinalOutcome;'));
    });

    test('each outcome has its own label and colour', () {
      expect(dialog, contains("if (isItemSold) return 'SOLD';"));
      expect(dialog, contains("return 'DESTROYED';"));
      expect(dialog, contains("return 'RE-EXPORTED';"));
      expect(dialog, contains("if (isItemReleased) return 'RELEASED';"));
    });

    test('a released item is caught by status OR by quantity', () {
      // The status column is not always updated; the quantities still say
      // the goods left.
      expect(dialog, contains('final isItemReleased = isItemReleasedDone ||'));
    });
  });

  test('the popup calls the field what the form calls it', () {
    // The officer picks a "Post Status Activity" (stored in hold_reason);
    // labelling it "Reason" only here looked like a different field.
    expect(dialog, contains("'Post Status Activity',"));
    expect(dialog, isNot(contains("                                                      'Reason',")));
  });

  group('goods the State took still show what the space cost', () {
    final note = File('lib/widgets/storage_charge_note.dart').readAsStringSync();

    test('the space cost ignores the billing rule, by design', () {
      // calculatePackageCharge returns 0 for forfeited / confiscated /
      // abandoned / destroyed. That is who PAYS, not what the days cost.
      expect(note, contains('double spaceCostFor('));
      expect(note, contains('does NOT do is'));
    });

    test('one walk, not two', () {
      // Rates change mid-stay, so a second copy of the day-by-day walk
      // would drift from this one the first time a rate rule changed.
      expect(note, contains('_spaceCost(from: from, units: units, rates: rates, until: until)'));
      expect(dialog, contains('spaceCostFor('));
    });

    test('the popup shows the cost instead of a bare "No charge"', () {
      expect(dialog, contains("'Space cost (not billed)'"));
      expect(dialog, contains('final billed = charge > 0;'));
      expect(dialog, contains('Not billed — these goods were taken by the State.'));
    });

    test('an unbilled figure is not dressed as a bill', () {
      // Gold is the money colour on this card; a cost nobody pays must not
      // borrow it.
      expect(dialog, contains('color: billed'));
    });
  });

  test('Old Entries opens the same popup as Goods History', () {
    // useLegacySummary swaps the per-item cargo list for a one-item
    // summary, so the same SR showed two different records depending on
    // which page opened it.
    final old = File('lib/screens/packages/old_entries_screen.dart').readAsStringSync();
    expect(old, contains('PackageDetailsDialog'));
    expect(old, isNot(contains('useLegacySummary: true')));
  });

  test('Unsold keeps its single-item focus, which already shows storage', () {
    // An unsold ROW is one item, so the focused legacy view is right there
    // — and it already carries StorageChargeNote, which uses the same
    // space-cost walk. Changing it would widen the popup to the whole SR.
    final unsold =
        File('lib/screens/packages/unsold_packages_screen.dart').readAsStringSync();
    expect(unsold, contains('highlightItemId: f.itemId'));
    expect(dialog, contains("title: 'Storage'"));
    expect(dialog, contains('StorageChargeNote('));
  });
}