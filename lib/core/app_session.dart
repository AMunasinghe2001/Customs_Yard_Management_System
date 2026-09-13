import 'db/pg_realtime.dart';
import 'yards.dart';

/// Lightweight global holder for the signed-in user's yard, so services can
/// tag new records and generate SR numbers without threading the profile
/// through every call. Set whenever a profile is loaded (login / session
/// verification) and cleared on sign-out.
class AppSession {
  static String currentYard = kDefaultYardCode;

  /// The head-office directorate this account registered under
  /// (`profiles.directorate`), which decides the SR-number prefix.
  ///
  /// Null for accounts created before directorates existed — those keep
  /// minting the original, unprefixed `<YARD>/SR/NN/YYYY` numbers rather than
  /// guessing a directorate for them. A yard can sit under two directorates
  /// (NNR is CED and PSD; Katunayaka is B/A and ACD), so the yard cannot
  /// stand in for it.
  static String? currentDirectorate;
  static String? currentRole;

  /// The yard to STAMP on a record this session creates, or null when the
  /// session does not belong to a yard.
  ///
  /// ⚠️ Not the same as [currentYard], and the difference is the bug this
  /// exists to fix. `currentYard` falls back to [kDefaultYardCode] because SR
  /// numbers must always resolve to something — but that fallback was also
  /// being written onto audit rows, so an ICT or Valuation sign-in was logged
  /// as happening in Grey Line 1. A directorate is not inside a yard; it
  /// touches one only through the SR records it reads, and that link is
  /// carried by the PACKAGE's yard.
  static String? get stampYard => isYardBound ? currentYard : null;

  static void setYard(String? yard) {
    currentYard = (yard == null || yard.isEmpty) ? kDefaultYardCode : yard;
  }

  static void setRole(String? role) {
    currentRole = (role == null || role.isEmpty) ? null : role.trim().toLowerCase();
  }

  /// Whether this session is an officer or yard admin bound to a single yard.
  static bool get isYardBound {
    if (currentRole == null) return true; // Safe default
    return currentRole == 'officer' || currentRole == 'admin';
  }

  /// The roles whose screens legitimately read EVERY yard.
  ///
  /// The head-office directorates work across the whole country by design —
  /// Disposal approves requests from every yard, Appeal hears every yard's
  /// appeals, Valuation prices every yard's goods, Executive signs off on all
  /// of it, and ICT administers the lot. A realtime filter must never hide
  /// another yard's change from them.
  ///
  /// Only 'officer' and 'admin' are bound to one yard, and they are the bulk
  /// of the 100 clients — which is exactly where the saved queries come from.
  static const Set<String> _crossYardRoles = {
    'disposal',
    'appeal',
    'valuation',
    'executive',
    'ict',
  };

  /// Decides whether this client may ignore other yards' realtime
  /// notifications, from the role it just signed in as.
  ///
  /// ⚠️ Called on sign-in and on sign-out, and it must be BOTH directions:
  /// leaving it on after a Disposal user signs out would let the next,
  /// yard-bound user keep paying for every yard's traffic, and leaving it off
  /// after an officer signs out would silently blind a Disposal user to other
  /// yards. [PgRealtime.watchAllYards] therefore defaults to the safe value
  /// (true, see there) and is narrowed only when the role is known.
  static void applyYardFilterToRealtime(String? role) {
    setRole(role);
    final r = (role ?? '').trim().toLowerCase();
    PgRealtime.instance.watchAllYards = r.isEmpty || _crossYardRoles.contains(r);
  }

  static void setDirectorate(String? directorate) {
    currentDirectorate =
        (directorate == null || directorate.isEmpty) ? null : directorate;
  }

  static void clear() {
    // ⚠️ NOT kDefaultYardCode. That default is 'GL1', so a cleared session
    // silently claimed to BE GL1 — and every Dart-side `.eq('yard', ...)`
    // filter, plus the yard stamped on anything created before the next
    // profile loaded, would quietly say GL1. An ended session belongs to no
    // yard: the empty string matches none, and the callers that build
    // filters already skip an empty yard and fall through to the database's
    // own per-yard policies, which is the safe direction.
    currentYard = '';
    currentDirectorate = null;
    currentRole = null;
    // Back to "see everything" on sign-out: the next user's role is unknown
    // until they sign in, and missing an update is worse than an extra query.
    applyYardFilterToRealtime(null);
  }
}
