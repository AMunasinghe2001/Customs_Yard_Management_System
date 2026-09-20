// "Was this appealed, and when?" — a question the popup could not answer.
//
// ⚠️ Reported directly: the details popup should show the appeal and its time
// period, the way the tables already do. Eight screens open this popup —
// Abandoned, Detained, Other, Goods History, Old Entries, Released, Forfeited
// and Warehouses — and NONE of them passed `tenderHistoryFor`, which was the
// only thing that made the Appeal section appear. So the table showed an
// Appeal column, the officer clicked into the row, and the popup said nothing
// about the appeal at all.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dialog =
      File('lib/widgets/package_details_dialog.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final f = flat(dialog);

  group('the popup answers for itself', () {
    test('the section no longer depends on the caller passing a row', () {
      // ⚠️ Gating on tenderHistoryFor is what hid it on eight screens.
      expect(f, contains('if (appealFor != null) _AppealHistorySection('));
      expect(f.contains('if (widget.tenderHistoryFor != null) _AppealHistorySection('),
          isFalse,
          reason: 'the appeal section is gated on the caller again');
    });

    test('a caller that DOES pass one still wins', () {
      // The Appeal Directorate's own popup passes the exact row it is about,
      // and must not be second-guessed by a lookup.
      expect(f, contains('final appealFor = widget.tenderHistoryFor ??'));
    });

    test('it looks the row up from the package when nothing was passed', () {
      expect(f, contains('ref .watch(forfeitedByItemProvider(p.id)) '
          '.valueOrNull?[highlightedItem.id]'));
    });

    test('it shows THIS item, never a sibling', () {
      // ⚠️ THE BUG a first attempt introduced: CED/GL1/SR/24/2025 holds four
      // items, each with its own forfeited row, and only Paint Thinner Cans
      // was ruled on. Falling back to "whichever row came first" put that
      // ruling on the Laptop Chargers popup — the table said Enabled and the
      // popup said Decided · Other about the same goods.
      expect(f.contains('byItem.values.first'), isFalse,
          reason: "a sibling item's appeal can be shown again");
    });

    test('a popup about no particular item shows no appeal', () {
      // The lookup keys strictly by item, so there is nothing to show.
      expect(f, contains('highlightedItem == null ? null :'));
    });
  });

  group('the section says what the officer asked for', () {
    test('it names the state in the same words the tables use', () {
      expect(dialog, contains("'On Appeal Hold'"));
      expect(dialog, contains("'In appeal window'"));
      expect(dialog, contains("'Window closed, no appeal'"));
    });

    test('it gives the time period, not just the state', () {
      // ⚠️ The window's START, whatever the goods are called. The label
      // itself is now chosen from the source (see the group below), so this
      // pins the FIELD, not one wording of it.
      expect(f, contains('label: _appealStartLabel(f.source),'));
      expect(dialog, contains("label: 'Appeal deadline'"));
    });

    test('it gives the ruling and when it was made', () {
      expect(dialog, contains("label: 'Ruling'"));
      expect(dialog, contains("label: 'Decided on'"));
    });

    test('a hold explains itself', () {
      expect(dialog, contains("label: 'Hold placed on'"));
      expect(dialog, contains("label: 'Reason for the hold'"));
    });
  });

  group('the window start is named for what the goods actually are', () {
    // ⚠️ `forfeited_packages` is every route into the appeal window, not just
    // forfeits. 250 of the 318 rows in this database are abandoned, "Other",
    // detained or perishable -- and every one of them read "Forfeited on",
    // which states that the State has taken goods still under inquiry.
    // SourceChip already corrects exactly this for Detained.

    test('the label is chosen from the source, not hardcoded', () {
      expect(f, contains('label: _appealStartLabel(f.source),'));
      expect(f.contains("label: 'Forfeited on',"), isFalse,
          reason: 'every kind of goods reads as forfeited again');
    });

    test('each source gets its own verb', () {
      expect(f, contains("'abandoned' => 'Abandoned on'"));
      expect(f, contains("'detain' || 'detained' => 'Detained on'"));
      expect(f, contains("'perishable' => 'Recorded on'"));
      expect(f, contains("'other' => 'Recorded on'"));
    });

    test('a real forfeit still says Forfeited on', () {
      expect(f, contains("_ => 'Forfeited on',"));
    });

    test('it matches the wording SourceChip already uses', () {
      // One row must read the same in the table and in the popup.
      final chip = File('lib/widgets/source_chip.dart').readAsStringSync();
      for (final s in ['abandoned', 'perishable', 'other']) {
        expect(chip.contains("'$s'"), isTrue,
            reason: 'SourceChip no longer knows $s');
      }
      expect(chip, contains("'detain' || 'detained'"));
    });
  });
}
