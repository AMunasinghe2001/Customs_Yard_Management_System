import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an expired OTP user may remain on their portal to change password', () {
    final router = File('lib/core/router.dart').readAsStringSync();

    // The session is required by the mandatory password-change stage.  If the
    // router signs it out while the login page is still public, rebuilding
    // the ProviderScope returns the user to the home page.
    final expiryGuard = router.substring(
      router.indexOf('if (profile != null && profile.isPasswordExpired)'),
      router.indexOf("if (isLoggedIn &&\n          (state.matchedLocation == '/'"),
    );
    expect(expiryGuard, contains('if (isPublicPage)'));
    expect(expiryGuard, contains('return null;'));
    expect(expiryGuard, isNot(contains('signOut()')));
  });
}
