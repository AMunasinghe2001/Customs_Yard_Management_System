import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sending a disposal request asks Central Disposal to sell or destroy goods
/// the State is holding. That is a yard ADMINISTRATION act — the SDDC / DDC
/// who runs the yard, never an officer.
///
/// ⚠️ It was gated on `actionable > 0` alone, in five separate copies, so any
/// yard officer could press it. The same officer is already refused the Final
/// Disposition button on the very same rows.
void main() {
  const screens = [
    'lib/screens/packages/detained_packages_screen.dart',
    'lib/screens/packages/abandoned_packages_screen.dart',
    'lib/screens/packages/other_packages_screen.dart',
    'lib/screens/packages/perishable_goods_screen.dart',
    'lib/screens/forfeited_packages/forfeited_packages_screen.dart',
  ];

  group('every held-goods page uses the one gated button', () {
    for (final path in screens) {
      final name = path.split('/').last.replaceAll('_screen.dart', '');

      test('$name does not build its own disposal button', () {
        final src = File(path).readAsStringSync();
        // ⚠️ The label may only appear inside the shared widget. A page that
        // spells it out again has its own ungated copy — which is exactly how
        // five of them drifted from the Final Disposition rule.
        expect(src.contains("Text('Send Disposal Request')"), isFalse,
            reason: '$name builds its own button; it will not be role-gated');
        expect(src, contains('SendDisposalRequestButton('));
      });
    }
  });

  group('the shared button refuses an officer', () {
    final src =
        File('lib/widgets/send_disposal_request_button.dart').readAsStringSync();

    test('it requires an admin, positively', () {
      expect(src, contains('isAdmin'));
      // ⚠️ Not `!isOfficer`: a null profile (still loading, or signed out
      // under us) must not be read as permission.
      expect(src, contains('profile?.isAdmin ?? false'));
      expect(src.contains('!isOfficer'), isFalse,
          reason: 'a null profile would then count as permission');
    });

    test('it says WHY it is disabled', () {
      // A dead button with no explanation reads as a fault in the app.
      expect(src, contains('Only SDDC / DDC can send a disposal request'));
    });
  });

  group('the database does not rely on the button', () {
    final sql =
        File('migrations/025_only_yard_admin_sends_disposal_requests.sql')
            .readAsStringSync();

    test('the policy is RESTRICTIVE, so it can only subtract', () {
      // ⚠️ A permissive policy is OR-ed with the others: adding one would
      // GRANT a new way in rather than taking one away.
      expect(sql, contains('as restrictive'));
      expect(sql, contains('auth_user_is_yard_officer()'));
    });

    test('reading is left alone', () {
      // An officer must still see what their yard has sent.
      expect(sql, contains('disposal_requests_officer_may_read'));
    });

    test('the verification runs as yard_app, not as the superuser', () {
      // ⚠️ THE bug in the first version of this migration. A migration runs
      // as `postgres`, and RLS never applies to a superuser — so the officer
      // insert succeeded and the check still reported success. It also named
      // a column the table does not have, so the run before that "passed" on
      // a typo. Testing as the non-superuser the app connects with is what
      // makes it a test of the policy at all.
      expect(sql, contains('set local role yard_app'));
      expect(sql, contains('when insufficient_privilege then'));
      expect(sql, contains('the WRONG reason'),
          reason: 'an unrelated error must not be mistaken for "blocked"');
    });
  });
}
