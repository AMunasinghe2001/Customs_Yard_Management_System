// One name for the count column, across every table in the app.
//
// ⚠️ The Warehouses page had always called it "No. of Goods" while the other
// eighteen tables said "Qty" — the same number under two names, so a reader
// moving between pages had to work out they were looking at the same thing.
// The spelt-out name won because it is the one that says what the figure is.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final screens = Directory('lib/screens')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  group('every count column is named the same way', () {
    test('no table says "Qty" any more', () {
      final offenders = <String>[];
      for (final f in screens) {
        final src = f.readAsStringSync();
        if (src.contains("Text('Qty')")) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'these tables still say Qty: ${offenders.join(', ')}');
    });

    test('the tables that count goods say "No. of Goods"', () {
      // The six yard tables, the four shared unsold column sets, the six
      // disposal tables, two valuation tables and the committee tab.
      var found = 0;
      for (final f in screens) {
        found += "Text('No. of Goods')".allMatches(f.readAsStringSync()).length;
      }
      expect(found, greaterThanOrEqualTo(19),
          reason: 'a count column lost its name');
    });

    test('the header is centred, like the number under it', () {
      // ⚠️ A left-aligned title over a centred figure reads as a column that
      // does not line up with its own heading.
      final offenders = <String>[];
      for (final f in screens) {
        final src = f.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
        for (final m
            in RegExp(r".{40}Text\('No\. of Goods'\)").allMatches(src)) {
          if (!m.group(0)!.contains('Center(')) offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'uncentred headers in: ${offenders.toSet().join(', ')}');
    });

    test('the column is wide enough for the words', () {
      // ⚠️ 70px fitted "Qty" and clips "No. of Goods". Every renamed column
      // was widened to the 100 the Warehouses page already used.
      final offenders = <String>[];
      for (final f in screens) {
        final src = f.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
        for (final m in RegExp(
                r"Text\('No\. of Goods'\)\)\), size: ColumnSize\.\w+, fixedWidth: (\d+)")
            .allMatches(src)) {
          if (int.parse(m.group(1)!) < 100) offenders.add('${f.path} (${m.group(1)})');
        }
      }
      expect(offenders, isEmpty,
          reason: 'too narrow for the label: ${offenders.join(', ')}');
    });
  });
}
