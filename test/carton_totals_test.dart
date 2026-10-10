// Twenty cartons of sixty pieces were recorded as sixty pieces.
//
// ⚠️ THE RULE, given directly: goods registered in cartons are counted as
// CARTONS × PER-CARTON. The SR form asks for both -- "Quantity" is the carton
// count, "Inner Q" is how many are in ONE carton -- and the total is the
// product.
//
// The form stored `innerQtyCtrl` raw as `package_items.quantity`, so the
// per-carton figure became the whole count. `quantity` is the operational
// number the entire app reads: the warehouse charge (itemCount × rate-days),
// the zone capacity, and the Qty column on every table. All of them were
// short by a factor of the carton count, and nothing looked wrong because
// every one of them agreed with every other.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/widgets/qty_cell.dart';

void main() {
  final form =
      File('lib/screens/inspection/inspection_screen.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('a carton registration multiplies out', () {
    test('the form stores cartons x per-carton, not per-carton alone', () {
      final f = flat(form);
      expect(
          f,
          contains('quantity: r.unitOfMeasureCtrl.text == \'Cartons\' '
              '? ((int.tryParse(r.qtyCtrl.text) ?? 1) * '
              '(int.tryParse(r.innerQtyCtrl.text) ?? 1))'));
    });

    test('reopening the form backs the total out again', () {
      // ⚠️ Without this the form would read "20 Cartons of 1176 Pieces each"
      // and the next save would multiply the total a second time.
      final f = flat(form);
      expect(f, contains('final cartons = item.innerQuantity ?? 1;'));
      expect(f, contains('cartons > 0 ? (item.quantity ~/ cartons)'));
    });
  });

  group('quantity stays the operational count', () {
    PackageItem item({required int qty, String? innerUnit, int? innerQty}) =>
        PackageItem(
          id: 'i',
          packageId: 'p',
          itemName: 'Widgets',
          quantity: qty,
          unitOfMeasure: 'Pieces',
          innerUnit: innerUnit,
          innerQuantity: innerQty,
        );

    test('effectiveQuantity is the total, and the packaging is a label', () {
      final it = item(qty: 1176, innerUnit: 'Cartons', innerQty: 20);
      expect(it.effectiveQuantity, 1176);
      expect(it.packagingLabel, '20 Cartons');
    });

    test('goods with no packaging carry no label', () {
      expect(item(qty: 10).packagingLabel, isNull);
    });

    test('the shared wording says both numbers', () {
      expect(qtyWithPackaging(item(qty: 1176, innerUnit: 'Cartons', innerQty: 20)),
          '1176 Pieces (in 20 Cartons)');
      expect(qtyWithPackaging(item(qty: 10)), '10 Pieces');
    });
  });

  group('the tables read one shared cell', () {
    test('every goods table uses QtyCell rather than a bare number', () {
      for (final path in [
        'lib/screens/packages/detained_packages_screen.dart',
        'lib/screens/packages/abandoned_packages_screen.dart',
        'lib/screens/packages/other_packages_screen.dart',
        'lib/screens/packages/perishable_goods_screen.dart',
        'lib/screens/packages/disposition_category_screen.dart',
        'lib/screens/warehouses/warehouses_screen.dart',
        'lib/screens/forfeited_packages/forfeited_packages_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, contains('QtyCell('), reason: '$path shows a bare count');
        expect(src, contains('qty_cell.dart'), reason: '$path lacks the import');
      }
    });
  });

  group('the Update dialog is the same form, so it follows the same rule', () {
    // ⚠️ A SECOND copy of the carton form lives in the details popup. It kept
    // the old arithmetic after the SR form was fixed, so reopening an item
    // there showed the TOTAL in the per-carton box ("5 Cartons of 5 Pieces
    // each" out of 5 pieces in 5 cartons) and saving stored that reading as
    // fact -- squaring the count on every edit.
    final dialog =
        File('lib/widgets/package_details_dialog.dart').readAsStringSync();
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('both of its save paths multiply out', () {
      // Two save paths: the single highlighted item, and the whole list.
      final n = '* (int.tryParse('.allMatches(flat(dialog)).length;
      expect(n, greaterThanOrEqualTo(2),
          reason: 'a save path still stores the per-carton figure raw');
    });

    test('both of its read-backs divide the total out again', () {
      final f = flat(dialog);
      expect(f, contains('final hiCartons = hi.innerQuantity ?? 1;'));
      expect(f, contains('final cartons = item.innerQuantity ?? 1;'));
    });

    test('it never puts the raw total in the per-carton box', () {
      expect(dialog.contains('innerQtyCtrl.text = hi.quantity.toString()'),
          isFalse,
          reason: 'the total is shown as one carton of contents again');
      expect(dialog.contains('innerQtyCtrl.text = item.quantity.toString()'),
          isFalse,
          reason: 'the total is shown as one carton of contents again');
    });
  });
}
