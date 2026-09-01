import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/directorates.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/models/models.dart';

/// ICT can add/remove yards, directorates and their many-to-many links at
/// run time (see [[yards-directorates-are-db-data]]). A yard filter dropdown
/// must reflect that immediately: a yard under SEVERAL directorates (NNR is
/// CED and PSD) becomes one entry PER directorate ("CED/NNR", "PSD/NNR"),
/// because "NNR" alone cannot tell a CED package from a PSD one filed at the
/// same physical yard -- confirmed live against the database: 38 options,
/// with exactly NNR/Rathmalana/Mattala/Katunayaka split and nothing else.
void main() {
  ProviderContainer buildContainer({
    required List<YardModel> yards,
    required List<DirectorateModel> directorates,
    required Map<String, List<String>> yardDirs,
  }) {
    return ProviderContainer(overrides: [
      yardsProvider.overrideWith((ref) => Future.value(yards)),
      directoratesProvider.overrideWith((ref) => Future.value(directorates)),
      yardDirectoratesProvider.overrideWith((ref) => Future.value(yardDirs)),
    ]);
  }

  group('yardFilterOptionsProvider', () {
    test('a single-directorate yard is ONE plain entry', () async {
      final c = buildContainer(
        yards: const [YardModel(code: 'GL1', name: 'Grey Line 1', srPrefix: 'GL1')],
        directorates: const [
          DirectorateModel(code: 'CED', name: 'Customs Enforcement', srPrefix: 'CED'),
        ],
        yardDirs: const {'GL1': ['CED']},
      );
      final options = await c.read(yardFilterOptionsProvider.future);
      expect(options, hasLength(1));
      expect(options.single.value, 'GL1');
      expect(options.single.label, 'Grey Line 1');
      expect(options.single.directorate, isNull);
    });

    test('a multi-directorate yard becomes one entry PER directorate', () async {
      final c = buildContainer(
        yards: const [YardModel(code: 'NNR', name: 'NNR', srPrefix: 'NNR')],
        directorates: const [
          DirectorateModel(code: 'CED', name: 'Customs Enforcement', srPrefix: 'CED'),
          DirectorateModel(code: 'PSD', name: 'Port & Shipping', srPrefix: 'PSD'),
        ],
        yardDirs: const {'NNR': ['CED', 'PSD']},
      );
      final options = await c.read(yardFilterOptionsProvider.future);
      expect(options, hasLength(2));
      expect(options.map((o) => o.label), containsAll(['CED/NNR', 'PSD/NNR']));
      // Both must resolve back to the SAME physical yard for the row match.
      expect(options.every((o) => o.filterYard == 'NNR'), isTrue);
      // Values must be distinct so the dropdown never collides.
      expect(options.map((o) => o.value).toSet(), hasLength(2));
    });

    test('an inactive yard is dropped from the list', () async {
      final c = buildContainer(
        yards: const [
          YardModel(code: 'GL1', name: 'Grey Line 1', srPrefix: 'GL1'),
          YardModel(code: 'OLD', name: 'Retired Yard', srPrefix: 'OLD', isActive: false),
        ],
        directorates: const [
          DirectorateModel(code: 'CED', name: 'Customs Enforcement', srPrefix: 'CED'),
        ],
        yardDirs: const {'GL1': ['CED'], 'OLD': ['CED']},
      );
      final options = await c.read(yardFilterOptionsProvider.future);
      expect(options.map((o) => o.value), isNot(contains('OLD')));
    });
  });

  group('matchesYardFilter', () {
    const prefixToCode = {'CED': 'CED', 'PSD': 'PSD'};

    test('null filter (All Yards) matches everything', () {
      expect(matchesYardFilter(null, 'NNR', 'CED/NNR/SR/01/2026'), isTrue);
    });

    test('a plain yard-code filter matches on yard alone', () {
      expect(matchesYardFilter('GL1', 'GL1', 'CED/GL1/SR/01/2026'), isTrue);
      expect(matchesYardFilter('GL1', 'GL2', 'CED/GL2/SR/01/2026'), isFalse);
    });

    test('"CED/NNR" matches only the CED package at NNR', () {
      expect(
          matchesYardFilter('NNR|CED', 'NNR', 'CED/NNR/SR/01/2026',
              prefixToCode: prefixToCode),
          isTrue);
      expect(
          matchesYardFilter('NNR|CED', 'NNR', 'PSD/NNR/SR/01/2026',
              prefixToCode: prefixToCode),
          isFalse,
          reason: 'Same yard, wrong directorate.');
    });

    test('"PSD/NNR" never matches a package filed at a different yard', () {
      expect(
          matchesYardFilter('NNR|PSD', 'GL1', 'PSD/GL1/SR/01/2026',
              prefixToCode: prefixToCode),
          isFalse,
          reason: 'Right directorate prefix, wrong yard -- must not leak.');
    });

    test('an unprefixed legacy SR number never matches a split entry', () {
      // Pre-directorate registrations kept minting GL1/SR/.. with no prefix.
      expect(
          matchesYardFilter('NNR|CED', 'NNR', 'NNR/SR/01/2026',
              prefixToCode: prefixToCode),
          isFalse);
    });
  });
}
