// Two dialog shapes on one page, and the plainer one asked to destroy things.
//
// ⚠️ Reported directly: Yard Administration opened Edit Zone as a yard-styled
// dialog (navy gradient header, icon box, uppercase label) and then asked
// "Delete zone Y6?" in a bare AlertDialog — a plain title row with no header
// at all. Side by side they read as two different products, and the one
// asking the officer to commit to something irreversible was the plainer.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final admin = File('lib/screens/admin/admin_screen.dart').readAsStringSync();
  final confirm = File('lib/widgets/confirm_dialog.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final a = flat(admin);

  group('Yard Administration has one dialog shape', () {
    test('no bare AlertDialog is left on the page', () {
      expect(admin.contains('AlertDialog('), isFalse,
          reason: 'a dialog on this page is unstyled again');
    });

    test('every confirmation uses the shared one, in the yard chrome', () {
      // Zone (twice — two routes reach it), warehouse, category.
      expect('ConfirmDialog.show('.allMatches(a).length, 4);
      expect('yard: true,'.allMatches(a).length, greaterThanOrEqualTo(6),
          reason: 'a dialog lost the yard chrome');
    });

    test('the zone form matches the zone form it duplicates', () {
      // ⚠️ Two routes open Add/Edit Zone and only one was styled, so the same
      // job looked like a different feature depending on the button.
      expect(a, contains("title: existing == null ? 'Add Zone' : 'Edit Zone'"));
      expect('StyledFormDialog('.allMatches(a).length, greaterThanOrEqualTo(2));
    });
  });

  group('the shared dialog can wear the yard chrome', () {
    test('it takes a yard flag and passes it through', () {
      expect(confirm, contains('final bool yard;'));
      expect(flat(confirm), contains('yard: yard,'));
    });

    test('it still defaults to the directorate look', () {
      // ⚠️ Only the yard's own pages opt in; the other portals have their
      // own chrome and must not change because this flag was added.
      expect(confirm, contains('this.yard = false'));
      expect(flat(confirm), contains('bool yard = false,'));
    });
  });

  group('the confirmations say what is actually lost', () {
    test('deleting a category explains what happens to the goods', () {
      // "Delete X?" alone does not say that goods already recorded keep the
      // category, nor that its storage target is forgotten.
      // ⚠️ Fragments, not the whole sentence: the literal is split across
      // adjacent Dart strings, so the joined text never appears contiguously
      // in the SOURCE however it is wrapped.
      expect(a, contains('Goods already recorded under'));
      expect(a, contains('storage location is forgotten'));
    });

    test('deleting a warehouse says its zones go too', () {
      expect(a, contains('Its zones go with it'));
    });

    test('deleting a zone keeps the wording it already had', () {
      expect('Goods already recorded in this zone stay where they are'
          .allMatches(a).length, 2,
          reason: 'the two zone-delete routes disagree again');
    });
  });

  group('the warehouse delete asks before it acts', () {
    test('the delete runs outside the dialog', () {
      // ⚠️ It used to run from inside the dialog's own button, so a failure
      // had to close the dialog and the error landed on whatever was under
      // it. Confirm, then act — like every other delete here.
      expect(a, contains('if (!ok) return; try { await '
          'ref.read(warehouseServiceProvider).deleteWarehouse(warehouse.id);'));
    });
  });
}
