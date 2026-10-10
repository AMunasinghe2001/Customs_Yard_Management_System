import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Changing an expired password dropped the officer on the HOME page.
///
/// ⚠️ The profile held in `currentProfileProvider` was read BEFORE the
/// change, so its `password_updated_at` was still the old one and
/// `isPasswordExpired` stayed true. Carrying it into the app meant the
/// router's expiry guard (core/router.dart) refused the destination and
/// redirected to '/'. The officer set a new password and landed on the
/// portal picker, as if nothing had happened.
///
/// The fix everywhere is the same: END the session after the change and
/// return to that portal's own sign-in form, so the officer signs in with
/// the new password the ordinary way. That also proves the new password
/// works while the form that could correct it is still on screen.
void main() {
  const portals = {
    'SC / DSC / ASC': 'lib/screens/login/login_screen.dart',
    'SDDC / DDC': 'lib/screens/admin/admin_login_screen.dart',
    'Valuation': 'lib/screens/valuation/valuation_login_screen.dart',
    'Central Disposal': 'lib/screens/disposal/disposal_login_screen.dart',
    'Appeal': 'lib/screens/appeal/appeal_login_screen.dart',
    'Top Management': 'lib/screens/executive/executive_login_screen.dart',
    'ICT': 'lib/screens/ict/ict_login_screen.dart',
  };

  // ⚠️ The two yard portals do not call changePassword themselves -- they
  // render the shared PasswordExpiredStage, which owns the submit. Their
  // half of the fix therefore lives in the widget, so that is the file to
  // read for them. The other five have the flow inline.
  const stage = 'lib/widgets/password_expired_stage.dart';
  const usesSharedStage = {
    'SC / DSC / ASC',
    'SDDC / DDC',
  };

  portals.forEach((name, path) {
    group(name, () {
      final src = File(usesSharedStage.contains(name) ? stage : path)
          .readAsStringSync();

      test('does not walk into the app on the stale profile', () {
        // The two yard portals drove the shared stage, whose onDone used to
        // push the dashboard directly; the other five called _finishLogin
        // straight after changePassword. Either way the session that
        // carried the EXPIRED profile went on to authorise a page.
        final at = src.indexOf('changePassword(');
        expect(at, greaterThan(-1), reason: 'no password change here');
        // Look at what happens between the change and the end of that block.
        final after = src.substring(at, (at + 1400).clamp(0, src.length));
        expect(after.contains('_finishLogin('), isFalse,
            reason: 'the stale profile is walked straight into the app; the '
                "router's expiry guard then bounces it to the home page");
      });

      test('ends the session the change was collected in', () {
        final at = src.indexOf('changePassword(');
        final after = src.substring(at, (at + 1400).clamp(0, src.length));
        expect(after, contains('signOut()'),
            reason: 'the pre-change session survives the change');
      });

      test('clears the profile so nothing else can use it', () {
        final at = src.indexOf('changePassword(');
        final after = src.substring(at, (at + 1400).clamp(0, src.length));
        expect(after, contains('currentProfileProvider.notifier).state = null'),
            reason: 'a stale expired profile is left in the provider');
      });
    });
  });
}
