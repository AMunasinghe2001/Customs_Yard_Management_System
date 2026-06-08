import 'yards.dart';

/// Lightweight global holder for the signed-in user's yard, so services can
/// tag new records and generate SR numbers without threading the profile
/// through every call. Set whenever a profile is loaded (login / session
/// verification) and cleared on sign-out.
class AppSession {
  static String currentYard = kDefaultYardCode;

  static void setYard(String? yard) {
    currentYard = (yard == null || yard.isEmpty) ? kDefaultYardCode : yard;
  }

  static void clear() {
    currentYard = kDefaultYardCode;
  }
}
