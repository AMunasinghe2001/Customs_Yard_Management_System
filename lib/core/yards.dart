/// Customs yards (departments) the application serves. Each user belongs to
/// exactly one yard; data is isolated per yard.
class Yard {
  /// Stable code stored in the database (`profiles.yard`, `*.yard`).
  final String code;

  /// Human-readable name shown in the UI.
  final String name;

  /// Prefix used when generating SR numbers, e.g. "GL1/SR/01/2026".
  final String srPrefix;

  const Yard({required this.code, required this.name, required this.srPrefix});
}

/// The seven supported yards. The first one is the historical default.
const List<Yard> kYards = [
  Yard(code: 'GL1', name: 'Grey Line 1', srPrefix: 'GL1'),
  Yard(code: 'GL2', name: 'Grey Line 2', srPrefix: 'GL2'),
  Yard(code: 'RCT', name: 'RCT', srPrefix: 'RCT'),
  Yard(code: 'BQ', name: 'BQ', srPrefix: 'BQ'),
  Yard(code: 'JCT', name: 'JCT', srPrefix: 'JCT'),
  Yard(code: 'NNR', name: 'NNR', srPrefix: 'NNR'),
  Yard(code: 'CVT', name: 'CVT', srPrefix: 'CVT'),
];

/// The default yard used for existing data and as a fallback.
const String kDefaultYardCode = 'GL1';

Yard yardByCode(String? code) {
  for (final y in kYards) {
    if (y.code == code) return y;
  }
  return kYards.first; // default → Grey Line 1
}

String yardName(String? code) => yardByCode(code).name;
String yardSrPrefix(String? code) => yardByCode(code).srPrefix;
