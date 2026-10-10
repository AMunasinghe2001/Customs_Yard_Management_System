// Goods that are not where their category says they belong.
//
// ⚠️ Reported directly: when a warehouse or zone is full the officer is
// offered another one and the goods go there — and afterwards nothing says so.
// A month later nobody can tell a deliberate placement from an overflow, and
// nobody knows which goods to move back when space frees up.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

void main() {
  WarehouseEntryModel entry({
    bool moved = false,
    String? intendedName,
    String? intendedZone,
    String? reason,
  }) =>
      WarehouseEntryModel(
        id: 'e',
        packageId: 'p',
        warehouseId: 'w',
        warehouseName: 'Warehouse 03',
        warehouseCode: 'W 03',
        holdReason: 'Detain',
        itemCount: 1,
        admittedAt: DateTime(2026, 1, 1),
        movedForSpace: moved,
        intendedWarehouseName: intendedName,
        intendedZone: intendedZone,
        movedReason: reason,
      );

  group('the note says where the goods belonged', () {
    test('ordinary goods carry no note at all', () {
      // So a caller can branch on null rather than on a flag AND a string.
      expect(entry().displacementNoteWith(null), isNull);
    });

    test('it names the intended warehouse and zone', () {
      expect(
          entry(moved: true, intendedName: 'Warehouse 02', intendedZone: 'B')
              .displacementNoteWith(null),
          'Meant for Warehouse 02 · Zone B, moved here because it was full');
    });

    test('it adds what was full, when that was recorded', () {
      expect(
          entry(
                  moved: true,
                  intendedName: 'Warehouse 02',
                  intendedZone: 'B',
                  reason: 'Zone B was full (0 free of 500, 12 needed)')
              .displacementNoteWith(null),
          'Meant for Warehouse 02 · Zone B — '
          'Zone B was full (0 free of 500, 12 needed)');
    });

    test('a name passed in by the page is used when the row has none', () {
      // ⚠️ The row cannot carry it: a second foreign key to `warehouses`
      // would make every existing `warehouses(*)` embed ambiguous.
      expect(entry(moved: true, intendedZone: 'A').displacementNoteWith('Open Area 01'),
          'Meant for Open Area 01 · Zone A, moved here because it was full');
    });

    test('it still says something when the intended place is unknown', () {
      expect(entry(moved: true).displacementNoteWith(null),
          'Moved here because the intended location was full');
    });
  });

  group('the fact is recorded, never inferred', () {
    final mig = File('migrations/042_goods_moved_for_space_are_marked.sql')
        .readAsStringSync();
    final services = File('lib/services/services.dart').readAsStringSync();
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('the entry carries the flag, the target and the reason', () {
      expect(mig, contains('moved_for_space boolean not null default false'));
      expect(mig, contains('intended_warehouse_id uuid'));
      expect(mig, contains('intended_zone text'));
      expect(mig, contains('moved_reason text'));
    });

    test('the intended warehouse is NOT a foreign key', () {
      // ⚠️ A second FK from warehouse_entries to warehouses makes the app's
      // `warehouses(*)` embed ambiguous — the query builder refuses it
      // outright, which would break all 44 call sites that use it.
      expect(mig.contains('intended_warehouse_id uuid\n    references'), isFalse,
          reason: 'the ambiguating foreign key is back');
      expect(flat(mig), contains('NO foreign key, deliberately'));
    });

    test('admission writes it only when the goods were actually displaced', () {
      final f = flat(services);
      final fn = f.substring(f.indexOf('Future<void> addEntry('));
      expect(fn.substring(0, 900), contains('bool movedForSpace = false'));
      expect(fn.substring(0, 3000), contains('if (movedForSpace) ...{'));
    });

    test('the save captures the intended place BEFORE overwriting it', () {
      // One line later the selection is gone, and it cannot be recovered by
      // re-reading the category target — targets are editable.
      final screen = File('lib/screens/inspection/inspection_screen.dart')
          .readAsStringSync();
      final g = flat(screen);
      expect(g, contains('_displaced[i] = ('));
      expect(g.indexOf('_displaced[i] = ('),
          lessThan(g.indexOf('_itemWarehouseSelections[entry.key] = entry.value')));
      expect(g, contains('movedForSpace: moved != null'));
    });
  });

  group('both surfaces say it, in one wording', () {
    final badge = File('lib/widgets/displaced_badge.dart').readAsStringSync();

    test('the table gets a chip and the popup a full line', () {
      expect(badge, contains('class DisplacedBadge'));
      expect(badge, contains('class DisplacedNotice'));
      // ⚠️ The CLASSES and the fact that each carries a label, not the exact
      // words: the wording is a design decision that has already been
      // revised once, and pinning the sentence makes every later improvement
      // look like a regression.
      expect(badge, contains('Relocated'),
          reason: 'neither surface names the displacement any more');
    });

    test('it is not red', () {
      // Nothing is wrong with these goods and nobody has to act today.
      // ⚠️ The CODE, not the file: the doc comment names dangerRed to say
      // why it is not used, and matching the whole file would fail on the
      // very sentence that records the decision.
      final code = badge
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');
      expect(code.contains('dangerRed'), isFalse);
      expect(code, contains('accentBlue'));
    });

    test('both screens use the shared widgets', () {
      expect(File('lib/screens/warehouses/warehouses_screen.dart')
          .readAsStringSync(), contains('DisplacedBadge('));
      expect(File('lib/widgets/package_details_dialog.dart').readAsStringSync(),
          contains('DisplacedNotice('));
    });
  });
}
