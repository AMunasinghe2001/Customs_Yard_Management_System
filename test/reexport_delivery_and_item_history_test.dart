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
      expect(screen, contains('class _ReexportDeliveryCell'));
      expect(screen, contains('_ReexportDeliveryCell( entry: row.entry'));
      expect(screen, contains('delivered: r.delivered'));
      final models = code(File('lib/models/models.dart').readAsStringSync());
      expect(models, contains("delivered: json['delivered'] as bool?"));
    });
  });

  group('a yard-decided ending shows an outcome panel', () {
    final dialog =
        code(File('lib/widgets/package_details_dialog.dart').readAsStringSync());
    final mig56 =
        File('postgres/56_delivery_carries_its_date.sql').readAsStringSync();

    test('goods with no tender still say how they ended', () {
      // ⚠️ The Final Outcome panel lived INSIDE TenderHistorySection, so
      // goods the yard decided on directly had no ending at all: the popup
      // ran Warehouse Summary straight into System Entry By and never said
      // what became of them. The DG-ruled row beside it in the same table
      // showed a full panel, so one page told two different stories about
      // the same kind of event.
      expect(dialog, contains('class YardOutcome'));
      expect(dialog, contains('class _YardOutcomeTile'));
      expect(dialog, contains('widget.yardOutcome != null'));
      expect(screen, contains('yardOutcome: row.fromTopManagement'));
    });

    test('one ending per popup', () {
      // ⚠️ A Top Management row keeps ITS panel -- that one carries the
      // ruling, the decision date and the DG's note. Drawing both would put
      // two FINAL OUTCOME headings on one dialog.
      expect(screen, contains('yardOutcome: row.fromTopManagement ? null'));
    });

    test('an ending with no hand-over step draws no delivery line', () {
      // ⚠️ Released goods walk out with their owner -- there is nobody to
      // wait for. `delivered` is NULL there, and drawing null as "not yet
      // delivered" would put goods in a queue that does not exist.
      expect(dialog, contains('if (delivered != null) ...['));
    });

    test('what the goods await is named by the ending', () {
      // ⚠️ "Pending" says none of it. A sale waits for a buyer to
      // collect, a re-export for a ship, a destruction for the burn.
      expect(dialog, contains('Not yet shipped'));
      expect(dialog, contains('Not yet collected'));
      expect(dialog, contains('Not yet destroyed'));
    });

    test('a delivery date is gated on its own flag', () {
      // ⚠️ `tender_sale_items` and `destruction_items` carry NO delivery-
      // consistency check -- only `unsold_proposals` does -- and the data
      // drifted through the gap: 20 rows hold a delivered_at while reading
      // not-delivered. The FLAG is the answer; a date beside a false flag is
      // a leftover, not a hand-over. The migration asserts no such row can
      // reach the view.
      final c = code(mig56);
      expect(c, contains('case when ti.is_delivered then ti.delivered_at end'));
      expect(c, contains('case when di.delivered then di.delivered_at end'));
      expect(c, contains('rows carry a delivery date but are not delivered'));
    });

    test('the migration asserts the RULE, not the tally', () {
      // ⚠️ Migration 55 pinned re-export deliveries at exactly 1 -- the
      // count on the day it ran. Officers marked two more within the hour,
      // so re-running it failed on a system working exactly as intended. 56
      // asserts what must always hold instead: no re-export reports
      // delivered without a recorded departure behind it.
      expect(code(mig56),
          contains('reports delivered with nothing recorded behind it'));
    });

    test('the table refreshes on every delivery source', () {
      // ⚠️ `dispositionPageProvider` watched packages, warehouse entries
      // and bids -- but not `tender_sale_items`, which is where a sold
      // lot's delivery lives. Marking one delivered updated the pill and
      // left the row's own data stale until the page was reopened. The
      // re-export path was safe only by accident, writing to a table that
      // happened to be watched.
      final providers =
          code(File('lib/core/providers.dart').readAsStringSync());
      final start = providers.indexOf('final dispositionPageProvider');
      final fn = providers.substring(start, start + 900);
      expect(fn, contains('tenderSaleItemsChangeTriggerProvider'));
      expect(fn, contains('warehouseEntriesChangeTriggerProvider'));
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
