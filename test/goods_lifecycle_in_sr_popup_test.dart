// An SR holds several goods, and they meet different ends.
//
// The popup could already show a tender history -- but only when a caller
// handed it ONE forfeited package. Opened from Goods History, where the SR
// carries every item it registered, it showed nothing: an officer reading
// CED/GL1/OA/07/2025 could not tell that the Truck Tyres had sold while the
// Steel Sheets were still sitting in Open Area 01.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dialog = File('lib/widgets/package_details_dialog.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final flat = dialog.replaceAll(RegExp(r'\s+'), ' ');

  group('each item carries its own story', () {
    test('the lifecycle section is rendered per item', () {
      expect(dialog, contains('class _ItemLifecycleSection'));
      expect(flat, contains('_ItemLifecycleSection( packageId: p.id, item: item,'));
    });

    test('it defers to an explicit tenderHistoryFor when a caller passes one',
        () {
      // ⚠️ The disposal pages pin the popup to one forfeited row on purpose --
      // the row the officer clicked. Rendering per-item histories there too
      // would show the same package twice.
      expect(flat, contains('if (widget.tenderHistoryFor == null) _ItemLifecycleSection('));
    });

    test('it reuses the one TenderHistorySection, not a second copy', () {
      // Valuations, bids, the committee round and the final outcome all
      // already live there. A parallel implementation would drift.
      final section = dialog.substring(dialog.indexOf('class _ItemLifecycleSection'));
      expect(section, contains('TenderHistorySection('));
    });

    test('an item with no forfeiture and no appeal renders nothing', () {
      // A section reading "no tender history" on goods that were never meant
      // to go to tender is noise.
      final section = dialog.substring(dialog.indexOf('class _ItemLifecycleSection'));
      expect(section, contains('if (forfeited == null && !hasAppeal) return const SizedBox.shrink();'));
    });
  });

  group('the appeal is part of the story', () {
    test('a hold or a ruling is shown, and shown FIRST', () {
      final section = dialog.substring(dialog.indexOf('class _ItemLifecycleSection'));
      expect(section, contains('itemAppealOutcomesProvider(packageId)'));
      expect(section, contains('appeal.isDecided || appeal.onHold'));
      // While an appeal is held nothing below it can proceed, so it is the
      // answer to "why has nothing happened".
      expect(section.indexOf('AppealStateChip'),
          lessThan(section.indexOf('TenderHistorySection')));
    });

    test('the chip it uses is the one the tables use', () {
      expect(dialog, contains("import 'appeal_state_chip.dart';"));
    });
  });

  group('the lookup must still find goods that have already gone', () {
    test('the provider is deliberately unfiltered', () {
      // ⚠️ getForfeitedPackages drops a package the moment it is tendered,
      // requested, sold or destroyed -- which is exactly the set of items
      // whose story is worth telling.
      expect(providers, contains('final forfeitedByItemProvider'));
      expect(services, contains('getForfeitedByItemForPackage'));
    });

    test('it keys by item, because forfeiture is per item', () {
      final m = services.substring(services.indexOf('getForfeitedByItemForPackage'));
      expect(m, contains("final itemId = f.itemId;"));
      expect(m, contains('if (itemId == null) continue;'));
      // Newest first, so the most recent forfeiture wins.
      expect(m, contains('out.putIfAbsent(itemId, () => f);'));
    });
  });

  group('a decision is not a hand-over', () {
    test('the Final Outcome tile says whether the goods actually left', () {
      // ⚠️ It is a BANNER now -- the same one the Sold popup carries.
      // It was an 11.5pt line squeezed under the decision note, on
      // pages whose whole job is to say whether the goods have gone.
      final tile = dialog.substring(dialog.indexOf('class _FinalOutcomeTile'));
      expect(tile, contains('proposal!.delivered'));
      expect(tile, contains('DeliveryStatusBanner('));
      // The banner itself still says both halves.
      final banner =
          dialog.substring(dialog.indexOf('class DeliveryStatusBanner'));
      expect(banner, contains("'Awaiting "));
      expect(banner, contains('doneLabel'));
    });
  });

  group('the storage section answers where the goods are', () {
    // ⚠️ These four checks used to guard the "Disposition Breakdown". That
    // block has been REMOVED because it restated what the status badge and
    // this section already say — but the questions it was built to answer
    // are still questions, so they are re-pinned here against
    // _ItemStorageSection, which now answers them.

    test('it shows for any item with warehouse history', () {
      // Not just detained / released / disposed items: an ordinary item
      // sitting in a warehouse is the commonest case of all, and it used to
      // get nothing while the item below it got an answer.
            expect(dialog, contains('e.packageItemId == item.id'));
      expect(dialog, contains('e.packageItemId == null'));
      expect(flat, contains('if (entries.isEmpty && !isPerishable) return const SizedBox.shrink();'));
    });

    test('it names the place, not just a count', () {
      expect(dialog, contains('entry.warehouseName'));
      // And the zone within it — how the goods are actually found.
      expect(dialog, contains("' · Zone '"));
    });

    test('the warehouse name carries which kind of space it is', () {
      // "Open Area 01" / "Warehouse 01" — the stored name already says it,
      // so there is no hard-coded OA/SR branch.
      expect(dialog, isNot(contains("'In Open Area'")));
      expect(dialog, isNot(contains("'In Warehouse'")));
    });

    test('several locations get a row each, so nothing overflows', () {
      // The old block squeezed every location into one line and had to fall
      // back to "(N locations)" past two. Each admission now has its own
      // row, with its own quantity, dates and charge.
      expect(dialog, contains('for (final e in entries) ...['));
      expect(dialog, isNot(contains('locations)')));
    });
  });
}