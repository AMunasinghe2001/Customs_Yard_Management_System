import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two yard portals gave no warning before the 90-day password limit.
///
/// ⚠️ They gated on `isPasswordExpired` ALONE, while the four directorate
/// portals had always entered the same stage on `|| isPasswordExpiringSoon`
/// and offered "Skip for now" for the last week. So a yard officer's first
/// notice of the rotation was the morning it locked them out of every record
/// — migration 018 makes an expired session read nothing at all.
void main() {
  const yardPortals = {
    'the SC / DSC / ASC portal': 'lib/screens/login/login_screen.dart',
    'the SDDC / DDC portal': 'lib/screens/admin/admin_login_screen.dart',
  };

  yardPortals.forEach((what, path) {
    group(what, () {
      final src = File(path).readAsStringSync();

      test('warns before the limit, not only after it', () {
        expect(src, contains('isPasswordExpiringSoon'),
            reason: 'this portal still only reacts once the password has '
                'already expired');
      });

      test('tells the officer how long is left', () {
        expect(src, contains('daysUntilPasswordExpiry'),
            reason: '"expires soon" without a day count is not a warning');
      });

      test('offers a skip, and only while the password still works', () {
        // The stage decides whether to DRAW the skip from `expired`; the
        // screen must supply both that flag and the callback.
        expect(src, contains('onSkip:'));
        expect(src, contains('expired:'),
            reason: 'without this the stage defaults to expired=true and '
                'the skip is never drawn');
      });
    });
  });

  group('the shared stage', () {
    final src = File('lib/widgets/password_expired_stage.dart').readAsStringSync();

    test('never offers a skip once the password has expired', () {
      // ⚠️ Not politeness. Migration 018 has already shut an expired session
      // out of every record, so skipping would land the officer in an empty
      // app that looks broken.
      expect(src, contains('widget.expired ? _signOut : widget.onSkip'),
          reason: 'the skip is drawn regardless of whether it can work');
    });

    test('defaults to the strict mode', () {
      // A caller that forgets the flag must get the SAFE behaviour, not a
      // skippable expiry.
      expect(src, contains('this.expired = true'),
          reason: 'forgetting `expired:` would silently allow a skip');
    });
  });
}
