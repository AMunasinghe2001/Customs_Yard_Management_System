import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/directorates.dart';
import 'package:cus_yard_management/core/yards.dart';

/// A yard keeps more than one register. `SR` and `OA` share a yard, a year AND
/// a serial run: the register says which book a number was written in, while
/// the serial is the yard's single running count, so the number after
/// `OA/10/2026` is `SR/11/2026` if the next goods go to a warehouse.
///
/// Everything below pins that, and the fact that an OA number is otherwise an
/// ordinary number the rest of the app reads exactly like an SR one.
void main() {
  group('composing a number names its register', () {
    test('SR is what a caller gets without asking', () {
      expect(
        composeSrNumber(yardPrefix: 'GL1', serial: 7, year: 2026),
        'GL1/SR/07/2026',
      );
    });

    test('OA composes into the same shape, with its own segment', () {
      expect(
        composeSrNumber(
            yardPrefix: 'GL1', serial: 7, year: 2026, docType: 'OA'),
        'GL1/OA/07/2026',
      );
    });

    test('the directorate prefix rides in front of either register', () {
      expect(
        composeSrNumber(
            yardPrefix: 'GL1',
            serial: 25,
            year: 2026,
            directorateCode: 'CED',
            docType: 'OA'),
        'CED/GL1/OA/25/2026',
      );
    });

    test('a lower-case or padded register is normalised', () {
      expect(
        composeSrNumber(
            yardPrefix: 'GL1', serial: 3, year: 2026, docType: ' oa '),
        'GL1/OA/03/2026',
      );
    });
  });

  group('reading a register back off a number', () {
    test('both shapes answer with their own register', () {
      expect(docTypeOfSrNumber('GL1/SR/87/2026'), 'SR');
      expect(docTypeOfSrNumber('GL1/OA/01/2026'), 'OA');
      expect(docTypeOfSrNumber('CED/GL1/OA/01/2026'), 'OA');
      expect(docTypeOfSrNumber('CED/GL1/SR/87/2026'), 'SR');
    });

    test('a shape naming no known register answers null, not a guess', () {
      expect(docTypeOfSrNumber('GL1/MISC/187/2025'), isNull);
      expect(docTypeOfSrNumber('nonsense'), isNull);
      expect(docTypeOfSrNumber(null), isNull);
      expect(docTypeOfSrNumber(''), isNull);
    });
  });

  group('an OA number is an ordinary number everywhere else', () {
    test('the directorate prefix strips off an OA number too', () {
      // This guarded on the literal 'SR' segment, so an OA number kept its
      // directorate prefix and then failed to match its own package.
      expect(stripDirectoratePrefix('CED/GL1/OA/01/2026'), 'GL1/OA/01/2026');
      expect(stripDirectoratePrefix('CED/GL1/SR/01/2026'), 'GL1/SR/01/2026');
    });

    test('an unknown directorate is still stripped off an OA number', () {
      expect(stripDirectoratePrefix('XYZ/GL1/OA/01/2026'), 'GL1/OA/01/2026');
    });

    test('the yard is read from an OA number the same way', () {
      expect(yardOfSrNumber('GL1/OA/01/2026'), 'GL1');
      expect(yardOfSrNumber('CED/NNR/OA/01/2026'), 'NNR');
    });

    test('an OA number sorts by year then serial, like any other', () {
      final list = [
        'GL1/OA/02/2025',
        'GL1/SR/09/2026',
        'GL1/OA/10/2026',
        'GL1/SR/01/2026',
      ]..sort(compareSrNewestFirst);
      expect(list, [
        'GL1/OA/10/2026',
        'GL1/SR/09/2026',
        'GL1/SR/01/2026',
        'GL1/OA/02/2025',
      ]);
    });

    test('the same year+serial in both registers still sorts deterministically',
        () {
      // Legitimate: the two registers count independently, so GL1/OA/07/2026
      // and GL1/SR/07/2026 both exist. Order must not depend on input order.
      final a = ['GL1/SR/07/2026', 'GL1/OA/07/2026']..sort(compareSrNewestFirst);
      final b = ['GL1/OA/07/2026', 'GL1/SR/07/2026']..sort(compareSrNewestFirst);
      expect(a, b);
    });
  });

  group('one serial run, shared by both registers', () {
    // ⚠️ THE RULE CHANGED, on the officer's report: OA/10/2026 was registered
    // and the form then offered SR/10/2026, so the yard had two packages
    // numbered 10 in the same year with only the register letters telling
    // them apart on a paper file. The serial is now the yard's single running
    // count and the register says which book the number was written in.
    //
    // getNextSrNumber's scan, lifted out so the rule can be tested without a
    // database: the highest serial for this yard, in EITHER register.
    int nextSerial(List<String> existing, String yardPrefix) {
      var next = 1;
      for (final sr in existing) {
        final parts = stripDirectoratePrefix(sr).split('/');
        if (parts.length < 4) continue;
        if (parts[0].toUpperCase() != yardPrefix.toUpperCase()) continue;
        if (!isSrDocType(parts[1])) continue;
        final n = int.tryParse(parts[2].trim());
        if (n != null && n >= next) next = n + 1;
      }
      return next;
    }

    final existing = [
      'CED/GL1/SR/85/2026',
      'CED/GL1/SR/86/2026',
      'CED/GL1/SR/87/2026',
      'CED/GL1/OA/01/2026',
      'CED/GL1/OA/02/2026',
    ];

    test('an OA number raises the next SR number', () {
      // The reported case, in miniature.
      expect(nextSerial(['CED/GL1/SR/09/2026', 'CED/GL1/OA/10/2026'], 'GL1'),
          11);
    });

    test('both registers continue the same run', () {
      expect(nextSerial(existing, 'GL1'), 88);
    });

    test('the first number of the year starts at 1', () {
      expect(nextSerial(const [], 'GL1'), 1);
    });

    test("another yard's numbers never feed the run", () {
      expect(nextSerial(['CED/NNR/OA/400/2026', ...existing], 'GL1'), 88);
    });

    test('the unprefixed legacy shape still counts', () {
      expect(nextSerial(['GL1/OA/90/2026', ...existing], 'GL1'), 91);
    });

    test('a segment that names no register is ignored', () {
      // Guards the loosened check: it must accept SR and OA, not anything.
      expect(nextSerial(['CED/GL1/XX/900/2026', ...existing], 'GL1'), 88);
    });

    test('getNextSrNumber really scans the same way', () {
      // nextSerial above is a lifted copy, so it would keep passing if the
      // real scan went back to one register.
      final src = File('lib/services/services.dart').readAsStringSync();
      final scan = src.substring(src.indexOf('Future<String> getNextSrNumber'));
      final body = scan.substring(0, scan.indexOf('composeSrNumber'));
      expect(body, contains(r"ilike('sr_number', '%$prefix/%/%/$year')"),
          reason: 'the query must ask for BOTH registers');
      expect(body, contains('kSrDocTypes.contains(parts[1].trim().toUpperCase())'),
          reason: 'the scan must accept either register, but only a register');
      expect(body.contains('!= type'), isFalse,
          reason: 'the scan rejects the other register again');
      expect(scan, contains('docType: type'),
          reason: 'the number is still minted in the register that was asked for');
    });
  });
}
