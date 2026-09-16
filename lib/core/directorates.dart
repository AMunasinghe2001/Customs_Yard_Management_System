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

/// The register a number belongs to — the segment after the yard.
///
/// A yard keeps more than one register, and each runs its OWN serial when a
/// number is MINTED: the next free `SR` is counted among `SR` numbers only,
/// and the next free `OA` among `OA` numbers only. So `getNextSrNumber` scopes
/// its scan by type.
///
/// Switching the register on a number already on screen is a different thing —
/// a correction, not a request for another number — and keeps the serial. See
/// [withSrDocType].
///
/// Goods registered under either type are the same goods everywhere else in
/// the app — the type changes how a number is minted, nothing about how the
/// package is then treated.
const List<String> kSrDocTypes = ['SR', 'OA'];

/// The default register, used wherever a caller does not name one. Keeping SR
/// the default is what leaves every existing call site behaving unchanged.
const String kDefaultSrDocType = 'SR';

/// True when [segment] names a register this build knows.
bool isSrDocType(String segment) =>
    kSrDocTypes.any((t) => t.toUpperCase() == segment.trim().toUpperCase());

/// The register [srNumber] belongs to (`SR`, `OA`, …), or null when its shape
/// names none. Reads the segment after the yard, on the directorate-stripped
/// form, so both `GL1/OA/07/2026` and `CED/GL1/OA/07/2026` answer `OA`.
String? docTypeOfSrNumber(String? srNumber) {
  if (srNumber == null || srNumber.trim().isEmpty) return null;
  final parts = stripDirectoratePrefix(srNumber.trim()).split('/');
  if (parts.length < 4) return null;
  final seg = parts[1].trim().toUpperCase();
  return isSrDocType(seg) ? seg : null;
}

/// The register a warehouse belongs to: `OA` for an open area, `SR` for a
/// covered warehouse.
///
/// ⚠️ Read from the CODE, not the name. Codes are the controlled field --
/// `warehouses.code` is unique and is what the yard prints on a label --
/// while names are free text an officer can retype ("Open Area 01", "open
/// area 1", "OA-1"). The seeded codes are `OA 01`, `W01`, `W02`, `W 03`, so
/// the register is the leading letters with spaces removed.
///
/// Falls back to the name only when a code is missing entirely.
String docTypeOfWarehouse({String? code, String? name}) {
  final c = (code ?? '').replaceAll(' ', '').toUpperCase();
  if (c.isNotEmpty) return c.startsWith('OA') ? 'OA' : kDefaultSrDocType;
  final n = (name ?? '').replaceAll(' ', '').toUpperCase();
  return n.startsWith('OPENAREA') || n.startsWith('OA')
      ? 'OA'
      : kDefaultSrDocType;
}

/// Builds the full SR number from its parts.
///
/// [directorateCode] may be null or unmapped — an account created before
/// directorates existed still gets a working, unprefixed number rather than an
/// error.
///
/// [docType] selects the register (see [kSrDocTypes]); each carries its own
/// serial run, so the caller must pass the same type it counted with.
String composeSrNumber({
  required String yardPrefix,
  required int serial,
  required int year,
  String? directorateCode,
  String docType = kDefaultSrDocType,
}) {
  final dir = directorateSrPrefix(directorateCode);
  final type = docType.trim().isEmpty
      ? kDefaultSrDocType
      : docType.trim().toUpperCase();
  final body = '$yardPrefix/$type/${serial.toString().padLeft(2, '0')}/$year';
  return dir.isEmpty ? body : '$dir/$body';
}

/// Swaps the REGISTER segment of [srNumber], leaving the serial alone.
///
/// Switching the register on the registration form is a correction -- "this
/// should have been an OA, not an SR" -- about a number the officer is already
/// looking at. Re-minting from the other register's own count moved the serial
/// out from under them, so a number they had just read changed to something
/// else. The serial, yard, directorate and year all stay; only the register
/// segment changes.
///
/// Returns null when [srNumber] is not a shape this can rewrite, so the caller
/// can fall back to minting a fresh number.
String? withSrDocType(String srNumber, String docType) {
  final trimmed = srNumber.trim();
  if (trimmed.isEmpty) return null;
  final type = docType.trim().toUpperCase();
  if (!isSrDocType(type)) return null;

  final bare = stripDirectoratePrefix(trimmed);
  final parts = bare.split('/');
  // <YARD>/<REGISTER>/<serial>/<year>
  if (parts.length < 4) return null;
  if (!isSrDocType(parts[1])) return null;

  parts[1] = type;
  final rebuilt = parts.join('/');
  // Put back whatever prefix was in front, so a directorate-prefixed number
  // stays prefixed.
  final prefixLen = trimmed.length - bare.length;
  return prefixLen > 0 ? trimmed.substring(0, prefixLen) + rebuilt : rebuilt;
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
  // Unknown leading segment followed by <yard>/<register>/... — drop it
  // anyway, so a directorate ICT added after this build still resolves. The
  // register is SR or OA (see kSrDocTypes), never SR alone.
  if (parts.length >= 5 && isSrDocType(parts[2])) {
    return parts.sublist(1).join('/');
  }
  return srNumber;
}

/// True when [srNumber] already carries a directorate prefix.
bool hasDirectoratePrefix(String srNumber) =>
    stripDirectoratePrefix(srNumber) != srNumber;

/// The directorate CODE whose prefix [srNumber] carries, or null if it has
/// none (a pre-directorate registration, still minting the old unprefixed
/// shape).
///
/// [prefixToCode] maps `srPrefix -> code` for every KNOWN directorate — pass
/// the live map built from [directoratesProvider] wherever one is available,
/// so a directorate ICT adds at run time is recognised immediately. Falls
/// back to [kDirectorates] when omitted (a const-context caller, or a screen
/// with no provider access).
String? directorateOfSrNumber(String srNumber,
    {Map<String, String>? prefixToCode}) {
  final entries = prefixToCode?.entries ??
      kDirectorates.map((d) => MapEntry(d.srPrefix, d.code));
  for (final e in entries) {
    final p = '${e.key}/';
    if (srNumber.toUpperCase().startsWith(p.toUpperCase())) return e.value;
  }
  return null;
}

