/// Head-office directorates, and the yards that sit under them.
///
/// A yard alone no longer decides an SR number. The full shape is
///
///     <DIRECTORATE>/<YARD>/SR/<NN>/<YYYY>      e.g. CED/GL1/SR/25/2026
///
/// and several yards belong to MORE THAN ONE directorate — NNR is both CED and
/// PSD; Katunayaka, Rathmalana and Mattala are both B/A and ACD. So the prefix
/// comes from the SIGNED-IN USER's directorate (`profiles.directorate`, chosen
/// at registration), not from the yard.
///
/// The lists below are a SEED and an offline fallback. The live lists come from
/// the `directorates` / `yards` / `yard_directorates` tables, which the ICT
/// Directorate maintains at run time — see [DirectorateService].
library;

/// One head-office directorate.
class Directorate {
  /// Stable key stored in `profiles.directorate` and `yard_directorates`.
  final String code;

  /// Human-readable name shown in the UI.
  final String name;

  /// What goes in FRONT of the SR number. Kept separate from [code] because
  /// "B/A" is the real prefix but a slash makes an awkward key.
  final String srPrefix;

  const Directorate(
      {required this.code, required this.name, required this.srPrefix});
}

/// The seeded directorates, in the order they should appear in a picker.
///
/// ⚠️ This is a fallback only. ICT can add more from the portal at run time, so
/// read [directoratesProvider] rather than this list anywhere the user's own
/// data is involved.
const List<Directorate> kDirectorates = [
  Directorate(
      code: 'CED', name: 'Customs Enforcement Directorate', srPrefix: 'CED'),
  Directorate(code: 'PSD', name: 'Port & Shipping Directorate', srPrefix: 'PSD'),
  Directorate(code: 'RTF', name: 'Revenue Task Force', srPrefix: 'RTF'),
  Directorate(code: 'BA', name: 'Baggage / Airport', srPrefix: 'B/A'),
  Directorate(code: 'ACD', name: 'Air Cargo Directorate', srPrefix: 'ACD'),
  Directorate(code: 'EXD', name: 'Export Directorate', srPrefix: 'EXD'),
  Directorate(code: 'PRD', name: 'Preventive Directorate', srPrefix: 'PRD'),
  Directorate(
      code: 'SSD',
      name: 'Social Protection & Security Directorate',
      srPrefix: 'SSD'),
];

Directorate? directorateByCode(String? code) {
  if (code == null || code.trim().isEmpty) return null;
  for (final d in kDirectorates) {
    if (d.code == code) return d;
  }
  return null;
}

String directorateName(String? code) =>
    directorateByCode(code)?.name ?? (code ?? 'No Directorate');

/// The SR-number prefix for [code], or `''` when the account has no
/// directorate — in which case the SR number keeps its old, unprefixed shape.
String directorateSrPrefix(String? code) =>
    directorateByCode(code)?.srPrefix ?? '';

/// Which directorates each yard belongs to (seed / offline fallback).
///
/// A yard may appear under several — that is the whole reason the SR prefix is
/// taken from the user rather than the yard.
const Map<String, List<String>> kYardDirectorates = {
  // CED
  'GL1': ['CED'],
  'GL2': ['CED'],
  'RCT': ['CED'],
  'CRT': ['CED'],
  'BQ': ['CED'],
  'JCT': ['CED'],
  // Both CED and PSD.
  'NNR': ['CED', 'PSD'],
  // PSD
  'TRINCO': ['PSD'],
  'MIDCO': ['PSD'],
  'TRANSCO': ['PSD'],
  'LAKSIRI': ['PSD'],
  'CSL': ['PSD'],
  'BO': ['PSD'],
  // RTF
  'MOBILE': ['RTF'],
  'MAINOFF': ['RTF'],
  // Both B/A and ACD.
  'KAT': ['BA', 'ACD'],
  'RATH': ['BA', 'ACD'],
  'MATT': ['BA', 'ACD'],
  // B/A only.
  'PALALI': ['BA'],
  // EXD
  'TRIO': ['EXD'],
  'ACE': ['EXD'],
  'ASIAN': ['EXD'],
};

/// The directorate codes [yardCode] sits under (empty when unmapped).
List<String> directoratesForYard(String? yardCode) =>
    kYardDirectorates[yardCode] ?? const [];

/// Builds the full SR number from its parts.
///
/// [directorateCode] may be null or unmapped — an account created before
/// directorates existed still gets a working, unprefixed number rather than an
/// error.
String composeSrNumber({
  required String yardPrefix,
  required int serial,
  required int year,
  String? directorateCode,
}) {
  final dir = directorateSrPrefix(directorateCode);
  final body = '$yardPrefix/SR/${serial.toString().padLeft(2, '0')}/$year';
  return dir.isEmpty ? body : '$dir/$body';
}

/// Strips a leading directorate prefix, if present.
///
/// Lookups must match both shapes: goods registered before this change carry
/// `GL1/SR/62/2026`, goods registered after carry `CED/GL1/SR/62/2026`, and the
/// two refer to the same package.
String stripDirectoratePrefix(String srNumber) {
  final parts = srNumber.split('/');
  // "B/A" itself contains a slash, so the prefix can be one OR two segments.
  for (final d in kDirectorates) {
    final p = '${d.srPrefix}/';
    if (srNumber.toUpperCase().startsWith(p.toUpperCase())) {
      return srNumber.substring(p.length);
    }
  }
  // Unknown leading segment followed by <yard>/SR/... — drop it anyway, so a
  // directorate ICT added after this build still resolves.
  if (parts.length >= 5 && parts[2] == 'SR') {
    return parts.sublist(1).join('/');
  }
  return srNumber;
}

/// True when [srNumber] already carries a directorate prefix.
bool hasDirectoratePrefix(String srNumber) =>
    stripDirectoratePrefix(srNumber) != srNumber;
