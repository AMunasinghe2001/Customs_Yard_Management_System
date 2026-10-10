// The SR register entry, and the three ways its save step went wrong.
//
// ⚠️ Reported directly, all from one flow:
//
//   1. `Exception: column "*" does not exist` on Complete & Send. Covered in
//      pg_query_sql_test.dart -- the RETURNING builder quoted a star.
//
//   2. Going back to the Form to change a warehouse and pressing Next was
//      refused with "A package with SR ... already exists". The package DID
//      exist -- the Complete step had just written it -- but the form was
//      still in create mode, so its duplicate-SR guard fired against its own
//      save and the officer could not correct a warehouse at all.
//
//   3. The failure notice was a square, full-width bar with a DISMISS button
//      that stayed on screen until pressed, unlike every other message in
//      the app.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen =
      File('lib/screens/inspection/inspection_screen.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final f = flat(screen);

  group('the package is written by the warehouse step', () {
    test('only the warehouse step saves it', () {
      // ⚠️ ONE upsert, in _sendToWarehouse. Saving on Next would commit the
      // package before its goods had a warehouse, which is what made going
      // back to change one impossible in the first place.
      expect('upsertPackage('.allMatches(f).length, 1,
          reason: 'a second save path has appeared');
      // ⚠️ To the end of the function, not a fixed 2500 characters: the
      // register and capacity checks that now precede the save pushed it
      // past that window without changing what the test is about.
      final send = f.substring(f.indexOf('Future<void> _sendToWarehouse()'));
      expect(send.substring(0, send.indexOf('_findRegisterMismatch')), isNotEmpty);
      expect(send.substring(0, send.indexOf('catch (e)')),
          contains('upsertPackage('));
    });

    test('saving puts the form into edit mode', () {
      // Without this the duplicate-SR guard on Next finds the package this
      // very step wrote and refuses the edit.
      expect(f, contains('_isUpdate = true; _loadedSrNumber = pkg.srNumber;'));
    });

    test('the guard still blocks a genuinely duplicate SR', () {
      // It must only stand down for THIS SR -- retyping someone else's SR
      // still has to be refused, or two packages share one number.
      expect(f, contains('final isEditingThisSr = _isUpdate && _loadedSrNumber == sr;'));
      expect(f, contains('if (!isEditingThisSr) {'));
    });
  });

  group('messages look like the rest of the app', () {
    test('no message waits for a DISMISS press', () {
      expect(screen.contains("label: 'DISMISS'"), isFalse,
          reason: 'a message pins itself to the page again');
      expect(screen.contains('hideCurrentSnackBar'), isFalse);
    });

    test('the save failure uses the shared error toast', () {
      expect(f, contains('if (mounted) context.showError(userMessage);'));
    });

    test('the success and lookup notices use the shared toasts too', () {
      expect(f, contains("context.showSuccess('All items sent to respective warehouses')"));
      expect(f, contains("context.showError('Please select a warehouse for Goods"));
      expect(f, contains("context.showError('Package data not found')"));
      expect(f, contains("context.showError('Lookup error:"));
    });
  });
}
