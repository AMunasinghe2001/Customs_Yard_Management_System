import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/directorates.dart';
import 'package:cus_yard_management/core/yards.dart';

/// The SR number is the app's human-facing key: it goes on the barcode label
/// stuck to the goods, into every report, and into `forfeited_packages`. It now
/// has TWO valid shapes living side by side —
///
///   * `GL1/SR/62/2026`      registered before directorates existed
///   * `CED/GL1/SR/62/2026`  registered after
///
/// — so the round-trip between composing one and reading it back apart is
/// exactly where a mistake would quietly mis-file goods.
void main() {
  group('composeSrNumber', () {
    test('prefixes the directorate when the account has one', () {
      expect(
        composeSrNumber(
            yardPrefix: 'GL1', serial: 25, year: 2026, directorateCode: 'CED'),
        'CED/GL1/SR/25/2026',
      );
    });

    test('keeps the original shape when the account has no directorate', () {
      // Pre-directorate accounts must keep working rather than minting a
      // half-formed "/GL1/SR/…".
      expect(
        composeSrNumber(yardPrefix: 'GL1', serial: 25, year: 2026),
        'GL1/SR/25/2026',
      );
      expect(
        composeSrNumber(
            yardPrefix: 'GL1', serial: 25, year: 2026, directorateCode: ''),
        'GL1/SR/25/2026',
      );
    });

    test('an unknown directorate falls back rather than inventing a prefix',
        () {
      expect(
        composeSrNumber(
            yardPrefix: 'GL1', serial: 3, year: 2026, directorateCode: 'NOPE'),
        'GL1/SR/03/2026',
      );
    });

    test('pads the serial to two digits', () {
      expect(
        composeSrNumber(
            yardPrefix: 'NNR', serial: 7, year: 2026, directorateCode: 'PSD'),
        'PSD/NNR/SR/07/2026',
      );
      // …but does not truncate a serial that has outgrown two digits.
      expect(
        composeSrNumber(
            yardPrefix: 'NNR', serial: 143, year: 2026, directorateCode: 'PSD'),
        'PSD/NNR/SR/143/2026',
      );
    });

    test('B/A keeps its slash, giving a five-segment number', () {
      // "B/A" is the only prefix containing a slash, so it is the case most
      // likely to break naive split('/') parsing downstream.
      expect(
        composeSrNumber(
            yardPrefix: 'KAT', serial: 9, year: 2026, directorateCode: 'BA'),
        'B/A/KAT/SR/09/2026',
      );
    });
  });

  group('stripDirectoratePrefix', () {
    test('removes a known prefix', () {
      expect(stripDirectoratePrefix('CED/GL1/SR/25/2026'), 'GL1/SR/25/2026');
      expect(stripDirectoratePrefix('PSD/NNR/SR/07/2026'), 'NNR/SR/07/2026');
    });

    test('removes the two-segment B/A prefix', () {
      expect(stripDirectoratePrefix('B/A/KAT/SR/09/2026'), 'KAT/SR/09/2026');
    });

    test('leaves an already-bare number alone', () {
      expect(stripDirectoratePrefix('GL1/SR/62/2026'), 'GL1/SR/62/2026');
    });

    test('removes a directorate ICT added after this build shipped', () {
      // The const list is only a seed; ICT can add directorates at run time, so
      // an unrecognised leading segment in front of <yard>/SR/<n>/<yyyy> is
      // still a prefix and must not be mistaken for the yard.
      expect(stripDirectoratePrefix('XYZ/GL1/SR/25/2026'), 'GL1/SR/25/2026');
    });

    test('leaves an unrelated string alone', () {
      expect(stripDirectoratePrefix('GL1/MISC/2026'), 'GL1/MISC/2026');
      expect(stripDirectoratePrefix(''), '');
    });

    test('round-trips whatever composeSrNumber produced', () {
      for (final dir in [null, 'CED', 'PSD', 'BA', 'EXD']) {
        final sr = composeSrNumber(
            yardPrefix: 'GL1', serial: 42, year: 2026, directorateCode: dir);
        expect(stripDirectoratePrefix(sr), 'GL1/SR/42/2026',
            reason: 'directorate $dir did not round-trip (got $sr)');
      }
    });
  });

  group('hasDirectoratePrefix', () {
    test('distinguishes the two shapes', () {
      expect(hasDirectoratePrefix('CED/GL1/SR/25/2026'), isTrue);
      expect(hasDirectoratePrefix('B/A/KAT/SR/09/2026'), isTrue);
      expect(hasDirectoratePrefix('GL1/SR/25/2026'), isFalse);
    });
  });

  group('yardOfSrNumber', () {
    test('reads the yard out of both shapes', () {
      // This is what routes a package to the right yard's data, so getting it
      // wrong on the prefixed shape would leak goods across yards.
      expect(yardOfSrNumber('GL1/SR/62/2026'), 'GL1');
      expect(yardOfSrNumber('CED/GL1/SR/62/2026'), 'GL1');
      expect(yardOfSrNumber('PSD/NNR/SR/07/2026'), 'NNR');
      expect(yardOfSrNumber('B/A/KAT/SR/09/2026'), 'KAT');
    });

    test('returns null for an unknown yard rather than defaulting', () {
      expect(yardOfSrNumber('CED/NOSUCH/SR/01/2026'), isNull);
      expect(yardOfSrNumber(''), isNull);
      expect(yardOfSrNumber(null), isNull);
    });
  });

  group('compareSrNewestFirst with prefixes', () {
    test('still sorts newest first when the shapes are mixed', () {
      // It reads the serial and year from the END, so a leading directorate
      // must not disturb it — including across the two shapes.
      final list = [
        'CED/GL1/SR/01/2025',
        'GL1/SR/86/2026',
        'CED/GL1/SR/09/2026',
        'GL1/SR/12/2024',
      ]..sort(compareSrNewestFirst);

      expect(list, [
        'GL1/SR/86/2026',
        'CED/GL1/SR/09/2026',
        'CED/GL1/SR/01/2025',
        'GL1/SR/12/2024',
      ]);
    });
  });

  group('directoratesForYard', () {
    test('a yard can belong to more than one directorate', () {
      // The whole reason the SR prefix comes from the USER and not the yard.
      expect(directoratesForYard('NNR'), containsAll(['CED', 'PSD']));
      expect(directoratesForYard('KAT'), containsAll(['BA', 'ACD']));
      expect(directoratesForYard('RATH'), containsAll(['BA', 'ACD']));
      expect(directoratesForYard('MATT'), containsAll(['BA', 'ACD']));
    });

    test('single-directorate yards map to exactly one', () {
      expect(directoratesForYard('GL1'), ['CED']);
      expect(directoratesForYard('TRIO'), ['EXD']);
      expect(directoratesForYard('PALALI'), ['BA']);
    });

    test('an unmapped yard yields an empty list, not an error', () {
      expect(directoratesForYard('NOSUCH'), isEmpty);
      expect(directoratesForYard(null), isEmpty);
    });

    test('every mapped yard exists in kYards', () {
      // A mapping naming a yard the app does not know would produce a picker
      // entry that cannot be selected.
      final codes = {for (final y in kYards) y.code};
      for (final yardCode in kYardDirectorates.keys) {
        expect(codes, contains(yardCode),
            reason: '$yardCode is mapped to a directorate but missing '
                'from kYards');
      }
    });

    test('every mapped directorate exists in kDirectorates', () {
      final codes = {for (final d in kDirectorates) d.code};
      for (final entry in kYardDirectorates.entries) {
        for (final dir in entry.value) {
          expect(codes, contains(dir),
              reason: '${entry.key} maps to unknown directorate $dir');
        }
      }
    });
  });

  group('the seeded lists themselves', () {
    test('yard codes are unique', () {
      final codes = [for (final y in kYards) y.code];
      expect(codes.toSet().length, codes.length,
          reason: 'duplicate yard code in kYards');
    });

    test('directorate codes and SR prefixes are unique', () {
      final codes = [for (final d in kDirectorates) d.code];
      expect(codes.toSet().length, codes.length);
      // Two directorates sharing a prefix would make an SR number ambiguous
      // about which one minted it.
      final prefixes = [for (final d in kDirectorates) d.srPrefix];
      expect(prefixes.toSet().length, prefixes.length);
    });

    test('GL1 remains the first yard', () {
      // kDefaultYardCode falls back to kYards.first, so the order matters.
      expect(kYards.first.code, kDefaultYardCode);
    });
  });
}
