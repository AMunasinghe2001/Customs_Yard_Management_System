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

  static void setYard(String? yard) {
    currentYard = (yard == null || yard.isEmpty) ? kDefaultYardCode : yard;
  }

  static void setDirectorate(String? directorate) {
    currentDirectorate =
        (directorate == null || directorate.isEmpty) ? null : directorate;
  }

  static void clear() {
    currentYard = kDefaultYardCode;
    currentDirectorate = null;
  }
}
