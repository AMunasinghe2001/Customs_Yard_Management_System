import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An officer released "Imported Apples" from the Perishable Goods page,
/// got a success toast, and the row stayed on the page reading "In Yard" —
/// package_items.status WAS set to 'released' (confirmed directly against
/// the database), but nothing downstream of that write reflected it:
///
///   * perishable_rows had no status filter at all, so a finalised item
///     never left the page it was finalised FROM;
///   * the outcome chip had no branch for a terminal status, so it fell
///     through to the same "In Yard" shown for an item nobody has touched;
///   * Released Goods is driven by warehouse_entries.is_returned, and a
///     perishable that skipped warehousing (by design — the page's own
///     subtitle: "no warehouse, no appeal window") never gets one written.
void main() {
  _handoverIsAnActNotAnArrival();
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  final migration039 =
      flat(read('migrations/039_perishable_rows_hides_finalised_items.sql'));
  final migration040 =
      flat(read('migrations/040_perishable_rows_also_hides_sold.sql'));
  final migration070 =
      flat(read('postgres/70_disposition_rows_released_status.sql'));
  final screen =
      flat(read('lib/screens/packages/perishable_goods_screen.dart'));

  group('perishable_rows drops a finalised item', () {
    test('039 excludes the first four terminal statuses', () {
      expect(migration039, contains("lower(pi.status) not in"));
      for (final s in const ['released', 'destroyed', 're-exported', 'other']) {
        expect(migration039, contains("'$s'"),
            reason: 'the view no longer excludes "$s"');
      }
    });

    test('040 supersedes 039 and adds SOLD to the exclusion', () {
      // ⚠️ 039 deliberately kept SOLD, reasoning the page already gave a sale
      // its own outcome chip "by design". The Department overrode that after
      // seeing 039 in place: only In Tender / Awaiting Top Management / In
      // Yard belong on this page now. 040 is a SEPARATE migration on top of
      // 039, not an edit to 039's history -- the same pattern 038 used to
      // reverse part of 037.
      final clause = migration040.substring(
          migration040.indexOf('lower(pi.status) not in'),
          migration040.indexOf('lower(pi.status) not in') + 160);
      expect(clause, contains("'sold'"),
          reason: 'a sold item is still shown on Perishable Goods');
      for (final s in const ['released', 'destroyed', 're-exported', 'other']) {
        expect(clause, contains("'$s'"),
            reason: "040 dropped one of 039's original exclusions");
      }
    });

    test('the migrations prove the fix against the actually reported items',
        () {
      expect(migration039, contains('2a43b9ca-58ce-42d3-9570-271bf0fd7741'),
          reason: '039 does not verify against the reported item');
      expect(
          migration039, contains('a released perishable item leaves the page'));
      expect(migration040, contains('a sold perishable item leaves the page'));
    });
  });

  group('disposition_rows shows a released item with no warehouse entry', () {
    test('a fifth source exists for a direct release', () {
      // ⚠️ Sources 1-4 are the pre-existing view; none of them can produce
      // final_tag = RELEASED for an item that was never warehouse-admitted.
      // Source 5 is the actual fix -- an item is worthless if it merely
      // leaves Perishable Goods without landing anywhere else.
      expect(migration070, contains('row_key'));
      expect(migration070, contains("'IR:'"),
          reason: 'the new released-by-status source is missing its own '
              'row_key prefix');
      expect(migration070,
          contains("lower(coalesce(pi.status, '')) = 'released'"));
    });

    test('it guards against double-counting an item Source 4 already covers',
        () {
      // An item that WAS warehoused and released the ordinary way must keep
      // coming from Source 4 alone, or it would appear on Released Goods
      // twice.
      expect(migration070,
          contains('w4.package_item_id = pi.id and w4.is_returned = true'));
    });

    test('the migration proves the fix against the actually reported item', () {
      expect(migration070, contains('2a43b9ca-58ce-42d3-9570-271bf0fd7741'));
      expect(
          migration070, contains('the reported item now appears as RELEASED'));
    });

    test('the migration proves no item is double-counted by the NEW source',
        () {
      expect(migration070,
          contains('double-counted because of the NEW released-status source'));
    });
  });

  group('the outcome chip stops showing a released item as "In Yard"', () {
    test('the chip takes the item\'s own status', () {
      final ctor = screen.substring(
          screen.indexOf('const _PerishableOutcomeChip({'),
          screen.indexOf('const _PerishableOutcomeChip({') + 300);
      expect(ctor, contains('required this.status'),
          reason: 'the chip has no way to know the item is finalised');
    });

    test('every terminal status has its own branch, before the fallback', () {
      final build = screen.substring(
          screen.indexOf("switch (status.toLowerCase())"),
          screen.indexOf("label: 'In Yard'"));
      for (final s in const [
        "'released'",
        "'destroyed'",
        "'re-exported'",
        "'other'"
      ]) {
        expect(build, contains("case $s:"),
            reason: '$s has no branch and falls through to "In Yard"');
      }
    });

    test('the call site passes the real item status, not a placeholder', () {
      final call = screen.substring(
          screen.indexOf('child: _PerishableOutcomeChip('),
          screen.indexOf('child: _PerishableOutcomeChip(') + 300);
      expect(call, contains('status: r.item.status'),
          reason: 'the chip is built without the field that fixes this');
    });
  });
}

// ── Goods must not arrive on their outcome page already finished ───────────
//
// Reported directly: a perishable released or destroyed from Perishable Goods
// landed on Released / Destroyed Goods already reading "Delivered" /
// "Destroyed", with no button left to press and no record that anyone had
// confirmed it.
void _handoverIsAnActNotAnArrival() {
  final released = File('lib/screens/packages/returned_packages_screen.dart')
      .readAsStringSync();
  final category = File('lib/screens/packages/disposition_category_screen.dart')
      .readAsStringSync();
  final cell = File('lib/widgets/handover_cell.dart').readAsStringSync();
  final view = File('postgres/70_disposition_rows_released_status.sql')
      .readAsStringSync();
  final mig =
      File('migrations/041_item_level_handover_for_entryless_goods.sql')
          .readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('a hand-over is an act, not an arrival', () {
    test('no warehouse entry does not mean already delivered', () {
      // ⚠️ `entry == null ? true : false` was the whole bug on Released: a
      // perishable skips warehousing BY DESIGN, so the absence of an entry
      // was read as proof of hand-over for exactly the goods that had never
      // been handed over.
      expect(released.contains('row.entry == null ? true : false'), isFalse,
          reason: 'an absent warehouse entry counts as delivered again');
      expect(flat(released), contains('delivered: row.delivered ?? false'));
    });

    test('Destroyed asks the destruction RECORD, not the routing status', () {
      // package_items.status = 'destroyed' is what moves the row onto the
      // page (migration 039), so it is true for every row there by
      // construction -- it can never answer "has it been destroyed yet?".

      expect(flat(view).contains("pid.status, '')) = 'destroyed'"), isFalse,
          reason: 'is_destroyed reads the routing status again');
      expect(flat(view), contains('from public.destruction_items di'));
    });

    test('the Dart getter defers to the view', () {
      expect(category, contains('isDestroyedFlag'));
      final f = flat(category);
      expect(f, contains('final fromView = isDestroyedFlag;'));
      expect(f, contains('isDestroyedFlag: r.isDestroyed'));
    });

    test('an entry-less row still gets a button to press', () {
      // Requiring an entry left these rows with a pill and nothing behind
      // it, which is why they could only ever be read as already done.
      expect(flat(cell),
          contains('(widget.entry != null || widget.itemId != null)'));
      expect(cell, contains('_markItem()'));
      expect(cell, contains('markItemHandover'));
    });

    test('the act is recorded on the ITEM, not on a fabricated entry', () {
      // warehouse_entries.warehouse_id and hold_reason are NOT NULL, so
      // writing one here would invent a warehouse and a hold reason the
      // goods never had.
      expect(mig, contains('create table if not exists public.package_item_handovers'));
      expect(mig, contains('yard_mark_item_handover'));
      expect(mig.contains('insert into public.warehouse_entries'), isFalse,
          reason: 'a warehouse entry is being fabricated for these goods');
    });

    test('the hand-over refuses goods that are not finished', () {
      // Without this the function would record the hand-over of goods still
      // sitting in the yard undecided.
      expect(flat(mig), contains('if v_status <> p_kind then'));
    });

    test('the migration re-asserts the column that was lost once', () {
      // is_perishable vanished when postgres/70 recreated the view with a
      // plain `create view`, and the only symptom was a filter chip
      // quietly disappearing.
      expect(mig, contains("'is_perishable', 'is_destroyed'"));
      expect(mig, contains('is missing'));
    });
  });
}
