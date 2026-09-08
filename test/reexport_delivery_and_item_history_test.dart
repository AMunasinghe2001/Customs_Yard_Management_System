import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comment lines dropped and whitespace collapsed.
///
/// ⚠️ Comments must go from the RAW text, line by line — flattening first
/// removes the newlines a `//` runs to, and the rest of the file then reads
/// as commented-out. And every assertion below is about what the CODE does,
/// so a sentence in a comment must never be able to satisfy one.
String code(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('--'))
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final services =
      code(File('lib/services/services.dart').readAsStringSync());
  final screen = code(
      File('lib/screens/packages/disposition_category_screen.dart')
          .readAsStringSync());
  final migration =
      File('postgres/55_reexport_delivery_is_recorded.sql').readAsStringSync();

  group('a re-export delivery is recorded, not assumed', () {
    test('the view reads a column instead of asserting true', () {
      // ⚠️ Migration 54 wrote `when r.final_tag = 'RE-EXPORTED' then true`,
      // to drive the dashboard's "n/a" count to zero. It did — by answering
      // the question instead of asking it. All 17 yard-recorded re-exports
      // reported themselves delivered on the day their tag was written, and
      // no officer had said so. A figure that cannot be false is not a
      // figure.
      expect(code(migration), contains('re_export_delivered'));
      expect(code(migration).contains("'RE-EXPORTED' then true"), isFalse,
          reason: 'the constant is back');
    });

    test('a delivery has a date, and a date means a delivery', () {
      // ⚠️ The same check `unsold_proposals` carries. Without it a row can
      // claim to have been collected on no day at all, and the two halves of
      // one fact drift apart.
      expect(code(migration),
          contains('warehouse_entries_reexport_delivery_consistent'));
      expect(code(migration), contains('re_export_delivered_at is not null'));
    });

    test('nothing is backfilled as delivered', () {
      // ⚠️ Every existing row starts "awaiting collection", because nobody
      // recorded a departure — the system knows of none. Defaulting them to
      // delivered would repeat 54's mistake with a different spelling, and
      // the migration asserts the resulting counts against live data.
      expect(migration, contains('BACKFILL: none'));
      expect(code(migration), contains('n_true <> 1'));
      expect(code(migration), contains('n_total <> 19'));
    });

    test('the write refuses an entry that is not a re-export', () {
      // ⚠️ Without the guard the function would flip the flag on a sold or
      // destroyed entry, where it means nothing and where the real delivery
      // lives on another table entirely.
      expect(code(migration), contains('yard_toggle_reexport_delivery'));
      expect(code(migration), contains('is not a re-export'));
      // The same authorisation rule the other two delivery writes use.
      expect(code(migration), contains('auth_user_is_disposal()'));
    });

    test('marking delivered does NOT re-close the warehouse entry', () {
      // ⚠️ Unlike the DG-ruling write, which closes the entry in the same
      // statement. A yard re-export's entry is ALREADY closed: writing
      // [FINAL:RE-EXPORTED] sets is_returned in the same action, and all 17
      // in this yard were closed on the day their tag was written. Re-closing
      // would overwrite `returned_at` with today and lose the day the
      // disposition was actually recorded.
      final fn = code(migration);
      final start = fn.indexOf('yard_toggle_reexport_delivery');
      final end = fn.indexOf(r'$fn$;', start);
      final body = fn.substring(start, end > start ? end : fn.length);
      expect(body.contains('is_returned'), isFalse,
          reason: 'the delivery write closes the entry again');
      expect(services, contains('toggleReexportDelivery'));
    });

    test('the pill can be pressed, and the row carries the answer', () {
      // ⚠️ The cell rendered a CONSTANT — `delivered: true`, `onMark: null` —
      // so all 17 read Delivered from the moment the disposition was recorded
      // and no officer could say otherwise. Ruling a re-export and the goods
      // actually leaving are two events.
      final cell =
          code(File('lib/widgets/handover_cell.dart').readAsStringSync());
      expect(cell, contains('class HandoverCell'));
      expect(screen, contains('kind: HandoverEntryKind.reexport'));
      expect(screen, contains('delivered: r.delivered'));
      final models = code(File('lib/models/models.dart').readAsStringSync());
      expect(models, contains("delivered: json['delivered'] as bool?"));
    });
  });

  group('an ending with a hand-over says whether the goods went', () {
    final dialog =
        code(File('lib/widgets/package_details_dialog.dart').readAsStringSync());
    final mig56 =
        File('postgres/56_delivery_carries_its_date.sql').readAsStringSync();
    final mig57 =
        File('postgres/57_released_delivery.sql').readAsStringSync();

    test('re-export and release get a section; sold and destroyed do not', () {
      // ⚠️ Both are two events wearing one date: the yard RULES it --
      // writing the tag or the receipt -- and the goods LEAVE later, when a
      // ship sails or an owner arrives. Only the ruling was ever stored, so
      // both pages reported every row finished on the day it was decided.
      //
      // Sold and Destroyed already state their ending twice -- the tender
      // history's Final Outcome panel and a Sold Price column; a Destruction
      // Status & Financials section -- and a third panel there repeated what
      // was directly above it.
      expect(dialog, contains('enum HandoverKind'));
      expect(dialog, contains('class _HandoverSection'));
      expect(screen, contains("'RE-EXPORTED' => HandoverOutcome("));
      expect(screen, contains("'RELEASED' => HandoverOutcome("));
      expect(screen, contains('_ => null,'),
          reason: 'sold and destroyed must fall through to no section');
    });

    test('the section is in the dialog\u0027s own language', () {
      // ⚠️ A _DetailSection of _DetailItems, not a tinted banner. It sits
      // directly above Warehouse Summary and the two are read as a pair --
      // where the goods are, and whether they have gone -- so a banner in a
      // different visual language made the popup look assembled from two
      // designs.
      final start = dialog.indexOf('class _HandoverSection');
      final body = dialog.substring(start, start + 2400);
      expect(body, contains('_DetailSection('));
      expect(body, contains('_DetailItem('));
    });

    test('a Top Management row keeps ITS panel, and only that one', () {
      // ⚠️ Its ruling, decision date, note and hand-over are all in the
      // tender history's Final Outcome panel. Drawing both would put two
      // outcome sections on one dialog.
      expect(screen, contains('handover: row.fromTopManagement ? null'));
    });

    test('one cell serves both hand-overs', () {
      // ⚠️ They are the same interaction down to the column width -- a
      // pill, one irreversible action, no revert -- and differ only in which
      // column the answer lives in and what the goods are waiting FOR. Two
      // near-identical widgets would drift, and the drift would show as two
      // pages behaving differently for no reason a reader could see.
      // ⚠️ It lives in its own FILE, because Released Goods is a
      // different screen entirely (ReturnedPackagesScreen). Left private
      // inside the disposition screen, the only way to give Released the
      // same pill would have been to copy it -- two widgets for one
      // interaction, which is exactly the drift the enum prevents.
      final cell =
          code(File('lib/widgets/handover_cell.dart').readAsStringSync());
      expect(cell, contains('enum HandoverEntryKind'));
      expect(cell, contains('class HandoverCell'));
      expect(screen, contains('kind: HandoverEntryKind.reexport'));
      final released = code(File(
              'lib/screens/packages/returned_packages_screen.dart')
          .readAsStringSync());
      expect(released, contains('kind: HandoverEntryKind.released'));
      expect(screen.contains('class _ReexportDeliveryCell'), isFalse,
          reason: 'the duplicated cell is back');
      expect(services, contains('toggleReexportDelivery'));
      expect(services, contains('toggleReleasedDelivery'));
    });

    test('each write refuses the other kind of entry', () {
      // ⚠️ Without the guards a function would flip its flag on an entry
      // whose real delivery lives on another column or another table. A
      // release is the entry with NO disposition tag -- exactly the rule the
      // view's fourth source uses.
      expect(code(mig56), contains('is not a re-export'));
      expect(code(mig57), contains('is not a release'));
      expect(code(mig57), contains('has not been released'));
    });

    test('released rows all answer, and none answers true yet', () {
      // ⚠️ RELEASED used to answer NULL for every row -- no hand-over step
      // existed. All 33 answer now, and none says delivered, because nobody
      // has recorded a collection. Backfilling them to true would repeat
      // migration 54's mistake with a different spelling.
      expect(mig57, contains('BACKFILL: none'));
      expect(code(mig57), contains('released rows still have no delivery answer'));
      expect(code(mig57), contains('n_rel <> 33'));
    });

    test('a delivery date is gated on its own flag', () {
      // ⚠️ `tender_sale_items` and `destruction_items` carry NO delivery-
      // consistency check -- only `unsold_proposals` and the two
      // `warehouse_entries` pairs do -- and the data drifted through the
      // gap: 20 rows hold a delivered_at while reading not-delivered. The
      // FLAG is the answer; a date beside a false flag is a leftover.
      final c = code(mig57);
      expect(c, contains('case when ti.is_delivered then ti.delivered_at end'));
      expect(c, contains('case when di.delivered then di.delivered_at end'));
      expect(c,
          contains('case when we.released_delivered then we.released_delivered_at end'));
      expect(c, contains('rows carry a delivery date but are not delivered'));
    });

    test('the migration asserts the RULE, not the tally', () {
      // ⚠️ Migration 55 pinned re-export deliveries at exactly 1 -- the
      // count on the day it ran. Officers marked two more within the hour
      // through the button 55 had just created, so re-running it failed on a
      // system working exactly as intended.
      expect(code(mig57),
          contains('reports delivered with nothing recorded behind it'));
    });

    test('the table refreshes on every delivery source', () {
      // ⚠️ `dispositionPageProvider` watched packages, warehouse entries
      // and bids -- but not `tender_sale_items`, which is where a sold lot's
      // delivery lives. Marking one delivered updated the pill and left the
      // row's own data stale until the page was reopened.
      final providers =
          code(File('lib/core/providers.dart').readAsStringSync());
      final start = providers.indexOf('final dispositionPageProvider');
      final fn = providers.substring(start, start + 900);
      expect(fn, contains('tenderSaleItemsChangeTriggerProvider'));
      expect(fn, contains('warehouseEntriesChangeTriggerProvider'));
    });
  });

  group('a zone is occupied until the goods actually leave', () {
    final mig58 =
        File('postgres/58_zone_holds_until_delivery.sql').readAsStringSync();

    test('zone capacity reads the occupancy view, not is_returned', () {
      // ⚠️ A release or a re-export CLOSES its warehouse entry the day
      // the disposition is written, so 31 released and 15 re-exported lots
      // vanished from their zones while still physically standing in them --
      // an officer looking for space was told there was room a pallet was
      // sitting in. Measured: 187 entries counted, 233 actually present.
      final start = services.indexOf('getYardWarehouseCapacity');
      final fn = services.substring(start, start + 1200);
      expect(fn, contains("from('zone_occupancy_entries')"));
      expect(fn.contains("eq('is_returned', false)"), isFalse,
          reason: 'capacity is back on the ruling date');
    });

    test('the STORAGE CHARGE deliberately does not follow', () {
      // ⚠️ Billing ends when the yard RULES -- the bill is issued and
      // closed at that point, and the goods then wait on their owner, not
      // on the yard. Capacity is a physical question and billing a
      // contractual one; they end on different days, and wiring them
      // together would bill an owner for their own delay.
      expect(mig58, contains('STORAGE CHARGE deliberately does NOT change'));
      final accrued =
          File('postgres/52_accrued_storage_view.sql').readAsStringSync();
      expect(accrued, contains('is_returned'),
          reason: 'the charge still ends at the ruling');
    });

    test('the view can only ever ADD to what was counted', () {
      // ⚠️ A smaller figure would mean the filter had dropped something
      // genuinely held -- the one failure this change could cause that an
      // officer would not notice until a zone overflowed.
      expect(code(mig58), contains('zone occupancy SHRANK'));
      // And a hand-over that HAS happened must free the space.
      expect(code(mig58),
          contains('goods that have been handed over still occupy a zone'));
    });
  });

  group('the popup shows the state, not just the date', () {
    final dialog =
        code(File('lib/widgets/package_details_dialog.dart').readAsStringSync());

    test('the hand-over section carries the same pill the table does', () {
      // ⚠️ A reader who marked a row Delivered and then opened it had to
      // re-read a date to check the change had taken -- the state they had
      // just changed was the one thing the section did not show at a
      // glance. Same two colours as the table's pill, because it answers
      // the same question about the same row.
      expect(dialog, contains('class _HandoverPill'));
      expect(dialog, contains('_HandoverPill(delivered: gone, kind: k)'));
      expect(dialog, contains("pillDone: 'SHIPPED'"));
      expect(dialog, contains("pillDone: 'COLLECTED'"));
    });
  });

  group('Released Goods has a hand-over of its own', () {
    final released = code(
        File('lib/screens/packages/returned_packages_screen.dart')
            .readAsStringSync());

    test('the page has a Delivery column and a pill in it', () {
      // ⚠️ Released Goods is a SEPARATE screen (ReturnedPackagesScreen),
      // not the shared disposition one, so the column added there did not
      // reach it. A release is two events wearing one date exactly as a
      // re-export is: the receipt says an officer ruled it, and nothing
      // said whether the owner had come.
      expect(released, contains("Center(child: Text('Delivery'))"));
      expect(released, contains('kind: HandoverEntryKind.released'));
    });

    test('its popup carries the same section Re-exported does', () {
      expect(released, contains('handover: HandoverOutcome('));
      expect(released, contains('kind: HandoverKind.released'));
    });
  });

  group('a tender history belongs to ONE item', () {
    test("an item with no sale does not borrow the package's", () {
      // ⚠️ getTenderSaleItemForPackageItem fell back to the package when the
      // item had no sale row, and the package-level lookup returns the newest
      // sale for ANY of its items. CED/GL1/OA/07/2026 is exactly that: Truck
      // Tyres was re-exported with no tender at all, and the popup showed it
      // the two rounds, three re-valuations and bids belonging to Ceramic
      // Floor Tiles — the abandoned item still sitting in the yard. 58 rows
      // in this yard were being shown another item's valuation, silently.
      final start = services.indexOf('getTenderSaleItemForPackageItem');
      expect(start, greaterThan(0));
      final end = services.indexOf('Future<void> deleteTax', start);
      final fn = services.substring(start, end > start ? end : services.length);
      // The null-packageItemId path still answers about the package — that
      // caller asked about the package.
      expect(fn, contains('if (packageItemId == null) { return getTenderSaleItemForPackage'));
      // But once an item is named, the answer is about that item or nothing.
      // The marker is CODE, not a comment: code() strips comment lines,
      // so a heading like '1. Direct per-item' is not in this string.
      final afterGuard =
          fn.substring(fn.indexOf("from('forfeited_packages')"));
      expect(afterGuard.contains('return getTenderSaleItemForPackage'), isFalse,
          reason: 'the cross-item fallback is back');
      expect(afterGuard, contains('return null;'));
    });
  });
}
