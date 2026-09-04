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
      final tile = dialog.substring(dialog.indexOf('class _FinalOutcomeTile'));
      expect(tile, contains('proposal!.delivered'));
      expect(tile, contains('Not yet delivered'));
      expect(tile, contains("'Delivered on "));
    });
  });

  group('the Disposition Breakdown answers where the goods are', () {
    test('it shows for any item with warehouse history', () {
      // ⚠️ The old test was detained OR released OR disposed, so an ordinary
      // item sitting in a warehouse -- the commonest case -- got nothing, and
      // the same popup answered the question for one item and stayed silent
      // for the item below it.
      expect(flat, contains('if (heldQty > 0 || _releasedQty > 0 || _dispoCounts.isNotEmpty)'));
    });

    test('the held row names the place, not just the count', () {
      expect(dialog, contains('label: _heldLabel('));
      expect(dialog, contains("return 'In \${currentWarehouses.first.trim()}';"));
    });

    test('the warehouse name carries which kind of space it is', () {
      // "Open Area 01" -> In Open Area 01; "Warehouse 01" -> In Warehouse 01.
      // No hard-coded OA/SR branch: the name already says it.
      expect(dialog, isNot(contains("'In Open Area'")));
      expect(dialog, isNot(contains("'In Warehouse'")));
    });

    test('several locations fall back rather than overflowing the row', () {
      expect(dialog, contains("return 'Currently Held (\${currentWarehouses.length} locations)';"));
    });
  });
}
