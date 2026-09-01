import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

/// Each directorate portal admits ONLY its own role, by a plain string
/// compare on `profiles.role`. A security pass once rewrote every directorate
/// account to `officer`, and the portals then rejected all of them with
/// "This account is not a ... account" -- correctly, but the data was wrong.
/// These pin the mapping the restore relied on.
void main() {
  ProfileModel withRole(String role) => ProfileModel(
        id: 'u1',
        fullName: 'Test',
        role: role,
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

  group('a portal admits only its own role', () {
    test('disposal', () {
      expect(withRole('disposal').isDisposal, isTrue);
      expect(withRole('officer').isDisposal, isFalse,
          reason: 'An officer must not reach the Disposal portal.');
    });

    test('appeal / valuation / executive / ict', () {
      expect(withRole('appeal').isAppeal, isTrue);
      expect(withRole('valuation').isValuation, isTrue);
      expect(withRole('executive').isExecutive, isTrue);
      expect(withRole('ict').isIct, isTrue);
      // ...and none of them answers to the yard roles.
      for (final r in ['officer', 'admin']) {
        final p = withRole(r);
        expect(p.isAppeal || p.isValuation || p.isExecutive || p.isIct, isFalse,
            reason: '$r must not reach any directorate portal.');
      }
    });
  });

  // A code is consumed the instant it verifies, so a SECOND tap of
  // "Verify & Sign In" finds nothing left and threw "No verification code was
  // sent" -- which matched no branch and fell through to the generic
  // "Sign in failed. Please try again.", hiding why the first attempt failed
  // and inviting a retry that can never succeed.
  test('every OTP portal explains an already-used code', () {
    const portals = [
      'lib/screens/disposal/disposal_login_screen.dart',
      'lib/screens/appeal/appeal_login_screen.dart',
      'lib/screens/valuation/valuation_login_screen.dart',
      'lib/screens/executive/executive_login_screen.dart',
      'lib/screens/ict/ict_login_screen.dart',
    ];
    for (final path in portals) {
      final src = File(path).readAsStringSync();
      expect(src, contains("low.contains('no verification code')"),
          reason: '$path falls through to the generic failure.');
      expect(src, contains('already been used'), reason: path);
      expect(src, contains("low.contains('too many attempts')"), reason: path);
    }
  });
}
