// "BOTTOM OVERFLOWED BY 20 PIXELS", straight down the Sold Goods table.
//
// ⚠️ Reported with a screenshot. The Sold Price cell stacks two lines — the
// amount and the tax beneath it — in a Column with no `mainAxisSize.min` and
// no line limit. A long amount ("Rs 265000000.00") wrapped to a second line,
// the pair grew past the 48px row, and Flutter painted its black-and-yellow
// overflow bar across every affected row.
//
// ⚠️ The Valuation cell immediately beside it already carried a comment
// about being given exactly this treatment, for exactly this reason. The
// Sold Price cell was simply never brought along.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/screens/packages/disposition_category_screen.dart')
      .readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final f = flat(src);

  group('the Sold Price cell stays inside its row', () {
    // The stacked amount + tax, which is the cell that overflowed.
    String cell() {
      final i = f.indexOf('item.soldPrice.toStringAsFixed(2)');
      expect(i, greaterThan(-1), reason: 'the Sold Price cell is gone');
      // Back up to the Column that holds it.
      final start = f.lastIndexOf('return Column(', i);
      expect(start, greaterThan(-1));
      return f.substring(start, (i + 400).clamp(0, f.length));
    }

    test('the Column asks for only the height it needs', () {
      expect(cell(), contains('mainAxisSize: MainAxisSize.min,'),
          reason: 'the cell takes the full row height and then asks for more');
    });

    test('the amount cannot wrap to a second line', () {
      expect(cell(), contains('maxLines: 1,'));
      expect(cell(), contains('overflow: TextOverflow.ellipsis,'));
    });

    test('the tax line is limited too', () {
      final i = f.indexOf('taxSum.toStringAsFixed(2)');
      expect(i, greaterThan(-1));
      final seg = f.substring(i, (i + 260).clamp(0, f.length));
      expect(seg, contains('maxLines: 1,'));
      expect(seg, contains('overflow: TextOverflow.ellipsis,'));
    });

    test('it matches the Valuation cell beside it', () {
      // ⚠️ Same column, same row, same shape — the two must not drift, or
      // one of them starts overflowing again the next time an amount grows.
      final v = f.indexOf('fmt.format(unitCost)');
      expect(v, greaterThan(-1), reason: 'the Valuation cell changed shape');
      final vStart = f.lastIndexOf('return Column(', v);
      expect(f.substring(vStart, v), contains('mainAxisSize: MainAxisSize.min,'));
    });
  });
}
