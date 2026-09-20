import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comment lines dropped, then flattened.
///
/// ⚠️ Comments go from the RAW text LINE BY LINE, before the whitespace
/// collapse — flatten first and the newline a `//` runs to is gone, so every
/// assertion below would match prose as readily as code.
String code(String raw) => raw
    .split('\n')
    .where((l) =>
        !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Columns and cells inside one balanced `[ ... ]`, from a marker.
int _countIn(String src, String marker, String needle) {
  final i = src.indexOf(marker);
  expect(i, greaterThan(0), reason: 'marker not found: $marker');
  var depth = 0;
  var started = false;
  var j = i;
  for (; j < src.length; j++) {
    if (src[j] == '[') {
      depth++;
      started = true;
    } else if (src[j] == ']') {
      depth--;
      if (started && depth == 0) break;
    }
  }
  return needle.allMatches(src.substring(i, j)).length;
}

void main() {
  final val = File('lib/screens/valuation/valuation_dashboard_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final c = code(val);

  group('the three tables carry the same columns in the same order', () {
    test('cells match columns, or data_table_2 throws at runtime', () {
      // ⚠️ THE failure a test can catch and a build cannot. A mismatch
      // compiles perfectly and throws the first time the table paints.
      for (final t in [
        ("columns: const [ DataColumn2(label: Text('SR Number')",
            'DataColumn2('),
      ]) {
        // Both tables start their column list identically, so count each
        // occurrence in turn rather than by marker.
        expect(t.$2, isNotEmpty);
      }
      final pendingCols = _countIn(
          val,
          "columns: const [\n                    DataColumn2(label: Text('SR Number')",
          'DataColumn2(');
      final pendingCells = _countIn(
          val,
          "return DataRow(cells: [\n                      DataCell(TooltipText(f?.srNumber",
          'DataCell(');
      expect(pendingCols, pendingCells,
          reason: 'Pending/Perishable: $pendingCols columns, $pendingCells cells');

      final unsoldCols = _countIn(
          val,
          "columns: const [\n                        DataColumn2(label: Text('SR Number')",
          'DataColumn2(');
      final unsoldCells = _countIn(
          val,
          "cells: [\n                            DataCell(TooltipText(f.srNumber",
          'DataCell(');
      expect(unsoldCols, unsoldCells,
          reason: 'Unsold Tenders: $unsoldCols columns, $unsoldCells cells');
    });

    test('every table shows Location, not a bare yard', () {
      // ⚠️ Yard, warehouse AND zone. A yard name on a page that lists every
      // yard says which one and nothing about where in it — and these goods
      // may need looking at before they are priced.
      expect("Text('Location')".allMatches(c).length, 2);
      expect(c.contains("label: Text('Yard'), size: ColumnSize.S"), isFalse,
          reason: 'the bare Yard column is back');
      expect("unsoldLocation(".allMatches(c).length, greaterThanOrEqualTo(2));
    });

    test('Source appears beside Disposition on both', () {
      // ⚠️ How the goods came to be here decides what may be done with them,
      // and the valuer was pricing without it.
      expect("Text('Source')".allMatches(c).length, 2);
      expect("SourceChip(".allMatches(c).length, greaterThanOrEqualTo(2));
    });

    test('non-text columns are centred, header and cell alike', () {
      // ⚠️ Disposition was a centred header over a left-aligned chip, which
      // reads as a column that does not line up with its own title.
      expect(c, contains("Center(child: Text('Disposition'))"));
      expect(c, contains('Center(child: _DispoChip('));
      // ⚠️ "No. of Goods", not "Qty". The column was renamed across all 19
      // tables to match the Warehouses page, which had always spelled it out
      // -- so the app now says one thing rather than two.
      expect(c, contains("Center(child: Text('No. of Goods'))"));
    });
  });

  group('one yard chip, three portals', () {
    test('it names the directorate as well as the yard', () {
      // ⚠️ A yard code alone is ambiguous: ICT groups yards under
      // directorates, one yard can sit under two, and every SR number these
      // pages list is written CED/GL1/SR/… — so a bare "Grey Line 1" made
      // the reader map the name back to the code in the column beneath it.
      final chip =
          code(File('lib/widgets/yard_chip.dart').readAsStringSync());
      expect(chip, contains('class YardChip'));
      expect(chip, contains("'\${prefix == null ? '' : '\$prefix/'}\$code"));
      // The SR number is the authority; the link table is the fallback, and
      // only when it is unambiguous.
      expect(chip, contains('if (forYard.length != 1) return null;'));
    });

    test('all three portals use it', () {
      expect(c, contains('YardChip('));
      final disposal = code(
          File('lib/screens/disposal/disposal_dashboard_screen.dart')
              .readAsStringSync());
      expect(disposal, contains('YardChip('));
      // ⚠️ And nobody keeps a private copy — that is how three chips drift.
      expect(disposal.contains('Text(yardName(request.yard),'), isFalse);
      expect(c.contains('Text(yardName(request.yard),'), isFalse);
    });
  });
}
