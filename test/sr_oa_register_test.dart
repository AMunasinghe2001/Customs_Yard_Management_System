import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/directorates.dart';
import 'package:cus_yard_management/core/yards.dart';

/// A yard keeps more than one register. `SR` and `OA` share a yard and a year
/// but run INDEPENDENT serials: the number after `SR/87` is `SR/88`, never
/// `OA/88`, and an OA number can never continue an SR one. Everything below
/// pins that separation, and the fact that an OA number is otherwise an
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

  group('the serial run is scoped to one register', () {
    // getNextSrNumber's scan, lifted out so the rule can be tested without a
    // database: the highest serial IN THIS REGISTER, for this yard.
    int nextSerial(List<String> existing, String yardPrefix, String docType) {
      var next = 1;
      for (final sr in existing) {
        final parts = stripDirectoratePrefix(sr).split('/');
        if (parts.length < 4) continue;
        if (parts[0].toUpperCase() != yardPrefix.toUpperCase()) continue;
        if (parts[1].trim().toUpperCase() != docType.toUpperCase()) continue;
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

    test('SR continues the SR run', () {
      expect(nextSerial(existing, 'GL1', 'SR'), 88);
    });

    test('OA continues the OA run, NOT the SR one', () {
      // The bug this guards: an OA number handed out as 88 because the scan
      // counted every number in the yard regardless of register.
      expect(nextSerial(existing, 'GL1', 'OA'), 3);
    });

    test('the first number in an empty register starts at 1', () {
      expect(nextSerial(['CED/GL1/SR/87/2026'], 'GL1', 'OA'), 1);
    });

    test('another yard\'s numbers never feed either run', () {
      expect(nextSerial(['CED/NNR/OA/40/2026', ...existing], 'GL1', 'OA'), 3);
    });

    test('the unprefixed legacy shape still counts', () {
      expect(nextSerial(['GL1/OA/09/2026', ...existing], 'GL1', 'OA'), 10);
    });

    test('getNextSrNumber really scopes its scan the same way', () {
      // nextSerial above is a lifted copy, so it would keep passing if the
      // real scan lost its register guard. Pin the production code too.
      final src = File('lib/services/services.dart').readAsStringSync();
      final scan = src.substring(src.indexOf('Future<String> getNextSrNumber'));
      final body = scan.substring(0, scan.indexOf('composeSrNumber'));
      expect(body, contains(r"ilike('sr_number', '%$prefix/$type/%/$year')"),
          reason: 'the query must ask for ONE register');
      expect(body, contains("parts[1].trim().toUpperCase() != type"),
          reason: "the scan must reject the other register number set");
      expect(scan, contains('docType: type'),
          reason: 'the number must be minted in the register it was counted in');
    });
  });
}
