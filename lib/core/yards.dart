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

/// The supported customs yards. The first one (Grey Line 1) is the historical
/// default used for existing data. Add new yards here — the whole app (login
/// yard pickers, filters, SR-number prefixes, RLS `profiles.yard`) reads this
/// single list, so nothing else needs editing.
const List<Yard> kYards = [
  Yard(code: 'GL1', name: 'Grey Line 1', srPrefix: 'GL1'),
  Yard(code: 'GL2', name: 'Grey Line 2', srPrefix: 'GL2'),
  Yard(code: 'RCT', name: 'RCT', srPrefix: 'RCT'),
  Yard(code: 'CVT', name: 'CVT', srPrefix: 'CVT'),
  Yard(code: 'BQ', name: 'BQ', srPrefix: 'BQ'),
  Yard(code: 'NNR', name: 'NNR', srPrefix: 'NNR'),
  Yard(code: 'JCT', name: 'JCT', srPrefix: 'JCT'),
  Yard(code: 'PREV', name: 'Preventive', srPrefix: 'PREV'),
  Yard(code: 'BAGG', name: 'Baggage Office', srPrefix: 'BAGG'),
  Yard(code: 'RTF', name: 'RTF', srPrefix: 'RTF'),
  Yard(code: 'BIA', name: 'BIA', srPrefix: 'BIA'),
  Yard(code: 'HMB', name: 'HMB', srPrefix: 'HMB'),
  Yard(code: 'TRINCO', name: 'Trinco', srPrefix: 'TRINCO'),
  Yard(code: 'KURU', name: 'Kurunegala', srPrefix: 'KURU'),
  Yard(code: 'CSL', name: 'CSL', srPrefix: 'CSL'),
  Yard(code: 'DAMB', name: 'Dambulla', srPrefix: 'DAMB'),
  Yard(code: 'MIDIGO', name: 'Midigo', srPrefix: 'MIDIGO'),
  Yard(code: 'KALK', name: 'Kalkisiri', srPrefix: 'KALK'),
  Yard(code: 'TRANSCO', name: 'Transco', srPrefix: 'TRANSCO'),
  Yard(code: 'SEREN', name: 'Serendib', srPrefix: 'SEREN'),
  Yard(code: 'TRIGO', name: 'Trigo', srPrefix: 'TRIGO'),
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

/// The yard an SR number belongs to, read from its prefix ("GL1/SR/01/2025").
///
/// Neither `packages` nor `warehouse_entries` expose a yard on their models,
/// but every SR number is minted with its yard's prefix (see [yardSrPrefix]),
/// so the number itself is the reliable source.
///
/// Returns null when the prefix matches no known yard, so a caller can tell
/// "unknown" apart from a genuine match rather than silently defaulting.
String? yardOfSrNumber(String? srNumber) {
  final prefix = (srNumber ?? '').split('/').first.trim().toUpperCase();
  if (prefix.isEmpty) return null;
  for (final y in kYards) {
    if (y.srPrefix.toUpperCase() == prefix) return y.code;
  }
  return null;
}
