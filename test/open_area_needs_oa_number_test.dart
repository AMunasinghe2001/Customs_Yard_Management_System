// An SR number says which register the goods were entered in; the warehouse
// says where they physically went. Nothing made the two agree.
//
// ⚠️ Reported directly: goods can be sent to an OPEN AREA while the SR number
// still reads `SR/...`. The form asks for the register up front and the
// warehouse two tabs later, so an officer who picks the warehouse last has no
// prompt to go back. The number is printed on the paper file and the label, so
// the mismatch is expensive to find later and cannot be corrected without
// reissuing both.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/directorates.dart';

void main() {
  group('a warehouse names its register', () {
    test('an open area is OA, a warehouse is SR', () {
      expect(docTypeOfWarehouse(code: 'OA 01'), 'OA');
      expect(docTypeOfWarehouse(code: 'W01'), 'SR');
      expect(docTypeOfWarehouse(code: 'W 03'), 'SR');
    });

    test('the CODE decides, not the name', () {
      // ⚠️ Codes are the controlled, unique field; names are free text an
      // officer can retype. A row whose name was edited must still answer
      // from its code.
      expect(docTypeOfWarehouse(code: 'OA 02', name: 'Warehouse 09'), 'OA');
      expect(docTypeOfWarehouse(code: 'W04', name: 'Open Area 09'), 'SR');
    });

    test('spacing and case do not change the answer', () {
      expect(docTypeOfWarehouse(code: 'oa01'), 'OA');
      expect(docTypeOfWarehouse(code: ' OA  05 '), 'OA');
    });

    test('with no code it falls back to the name', () {
      expect(docTypeOfWarehouse(name: 'Open Area 01'), 'OA');
      expect(docTypeOfWarehouse(name: 'Warehouse 01'), 'SR');
    });

    test('an unknown shape is treated as a covered warehouse', () {
      // SR is the default register, so an unrecognised code must not start
      // demanding OA numbers for ordinary goods.
      expect(docTypeOfWarehouse(code: 'Z9'), 'SR');
      expect(docTypeOfWarehouse(), 'SR');
    });
  });

  group('the save step refuses a mismatch', () {
    final screen = File('lib/screens/inspection/inspection_screen.dart')
        .readAsStringSync();
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
    final f = flat(screen);

    test('it is checked before anything is written', () {
      // ⚠️ BEFORE the capacity prompt and before upsertPackage. Checking
      // after the save would leave a wrongly-numbered package in the table.
      final send = f.substring(f.indexOf('Future<void> _sendToWarehouse()'));
      final body = send.substring(0, send.indexOf('upsertPackage('));
      expect(body, contains('_findRegisterMismatch()'));
    });

    test('it compares the number against every chosen warehouse', () {
      final fn = f.substring(f.indexOf('Future<String?> _findRegisterMismatch()'));
      expect(fn.substring(0, 1600), contains('docTypeOfSrNumber(data.srNumber)'));
      expect(fn.substring(0, 1600), contains('docTypeOfWarehouse(code: w.code, name: w.name)'));
    });

    test('it names the number the officer should switch to', () {
      // "Change the Register" alone would leave them guessing which number.
      final fn = f.substring(f.indexOf('Future<String?> _findRegisterMismatch()'));
      expect(fn.substring(0, 1800), contains('withSrDocType(data.srNumber, needed)'));
      expect(fn.substring(0, 1800), contains('it becomes \$should'));
    });

    test('it refuses rather than renumbering silently', () {
      // The number may already be written on the file, so which of the two is
      // wrong is the officer's call, not the app's.
      final send = f.substring(f.indexOf('Future<void> _sendToWarehouse()'));
      final body = send.substring(0, send.indexOf('upsertPackage('));
      expect(body, contains('context.showError(mismatch); return;'));
    });

    test('a number with no register is left alone', () {
      // Legacy shapes that name no register must not be blocked.
      final fn = f.substring(f.indexOf('Future<String?> _findRegisterMismatch()'));
      expect(fn.substring(0, 900), contains('if (current == null) return null;'));
    });
  });
}
