// Perishable Goods had a page but no report.
//
// ⚠️ Reported directly: the Report Generator offers Forfeited, Abandoned,
// Other, Appeal and Re-exported under Goods Disposition — and nothing for
// perishables, which are 28 of this yard's forfeited rows and the one class
// of goods that spoils while somebody waits for a figure.
//
// `_generateSourceForfeitedReport` already does this job for Abandoned and
// Other, and 'perishable' is a real `forfeited_packages.source` value, so
// the report needed a card rather than a new pipeline.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final f = flat(src);

  group('Perishable Goods can be reported', () {
    test('the card exists', () {
      expect(f, contains("title: 'Perishable Goods',"));
    });

    test('it offers all three outputs, like its neighbours', () {
      final i = f.indexOf("title: 'Perishable Goods',");
      final seg = f.substring(i, (i + 700).clamp(0, f.length));
      for (final fmt in ['view', 'pdf', 'excel']) {
        expect(seg, contains("'perishable', 'Perishable Goods', '$fmt'"),
            reason: 'the $fmt output is missing');
      }
    });

    test('it reuses the shared source report, not a new pipeline', () {
      final i = f.indexOf("title: 'Perishable Goods',");
      expect(f.substring(i, (i + 700).clamp(0, f.length)),
          contains('_generateSourceForfeitedReport('));
    });

    test('it sits with the other disposition reports', () {
      // Between "Other Goods" and "Appeal Goods" in the same grid.
      expect(f.indexOf("title: 'Other Goods',"),
          lessThan(f.indexOf("title: 'Perishable Goods',")));
      expect(f.indexOf("title: 'Perishable Goods',"),
          lessThan(f.indexOf("title: 'Appeal Goods',")));
    });
  });

  group('the date column is named for the goods', () {
    test('the header is chosen from the source', () {
      // ⚠️ `forfeited_packages` is every route into the appeal window, so a
      // single "Forfeited On" would be wrong for most rows — the same
      // correction the details popup carries.
      expect(f, contains("'abandoned' => 'Abandoned On'"));
      expect(f, contains("'detain' || 'detained' => 'Detained On'"));
      expect(f, contains("_ => 'Recorded On',"));
    });
  });
}
