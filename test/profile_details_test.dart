import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

/// Reads a source file with line endings normalised to LF, so the multi-line
/// assertions below behave the same on a CRLF checkout.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

ProfileModel _profile({
  required String role,
  DateTime? createdAt,
}) =>
    ProfileModel(
      id: 'p1',
      fullName: 'Test Officer',
      role: role,
      isActive: true,
      createdAt: createdAt ?? DateTime.now(),
    );

void main() {
  final profileScreen = _read('lib/screens/profile/edit_profile_screen.dart');

  group('a profile photo is capped at 2MB', () {
    test('the limit is declared as 2MB', () {
      expect(profileScreen, contains('_maxProfileImageBytes = 2 * 1024 * 1024'));
    });

    test('the pick is rejected above it, and measured off the file', () {
      // The picker's own reported size is not what gets stored -- the file is.
      expect(profileScreen, contains('await File(path).length()'));
      expect(profileScreen, contains('if (length > _maxProfileImageBytes)'));
      expect(profileScreen, contains('Please choose one under 2MB'));
    });

    test('rejecting returns null rather than the oversized path', () {
      final fn = profileScreen.substring(
          profileScreen.indexOf('Future<String?> _pickProfileImage'));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      final guard = body.indexOf('if (length > _maxProfileImageBytes)');
      expect(guard, greaterThan(-1));
      expect(body.indexOf('return null;', guard), greaterThan(guard),
          reason: 'an over-size photo must not be accepted anyway');
    });
  });

  group('ICT owns Job Role and Yard', () {
    test('neither is editable on the profile form', () {
      // Both sit in one Row; each must be readOnly AND disabled.
      final row = profileScreen.substring(
          profileScreen.indexOf("labelText: 'Job Role'") - 800,
          profileScreen.indexOf("labelText: 'Yard'") + 400);
      expect('readOnly: true'.allMatches(row).length, greaterThanOrEqualTo(2));
      expect('enabled: false'.allMatches(row).length, greaterThanOrEqualTo(2));
      expect(row, contains("helperText: 'Set by ICT'"));
    });

    test('the yard dropdown is gone', () {
      expect(profileScreen, isNot(contains("label: 'Yard',\n")),
          reason: 'a StyledDropdownFormField would let the officer reassign');
      expect(profileScreen, isNot(contains('StyledDropdownFormField')));
    });

    test('saving does not send them', () {
      // updateProfile skips a null, so omitting them leaves ICT's values.
      final save = profileScreen.substring(
          profileScreen.indexOf('fullName: _nameCtrl!.text.trim()'));
      final call = save.substring(0, save.indexOf(');'));
      expect(call, isNot(contains('jobRole:')));
      expect(call, isNot(contains('yard:')));
    });
  });

  group('the details card', () {
    test('no longer shows Role beside Job Role', () {
      // Role named the same thing as Job Role in coarser words.
      expect(profileScreen, isNot(contains("_Field('Role'")));
      expect(profileScreen, isNot(contains("label: 'Role',")));
    });

    test('shows the expiry countdown', () {
      expect(profileScreen, contains("_Field(\n                'Disables In'"));
    });

    test('groups the fields instead of stacking nine identical bars', () {
      for (final group in ['Identity', 'Contact', 'Posting', 'Account']) {
        expect(profileScreen, contains("title: '$group'"));
      }
      // Two to a row when wide, one when narrow.
      expect(profileScreen, contains('_twoColumnMinWidth'));
      expect(profileScreen, contains('final twoUp = constraints.maxWidth >='));
    });
  });

  group('the expiry countdown agrees with whether the account can expire', () {
    // daysUntilExpiry's exemptions must match isExpired's, or a profile counts
    // down towards an expiry that will never be enforced.
    for (final role in ['disposal', 'appeal', 'valuation', 'executive', 'ict']) {
      test('$role never expires, so it has no countdown', () {
        final p = _profile(
            role: role, createdAt: DateTime.now().subtract(const Duration(days: 400)));
        expect(p.isExpired, isFalse, reason: '$role is institutional');
        expect(p.daysUntilExpiry, isNull,
            reason: '$role showed a countdown for an expiry that never comes');
      });
    }

    for (final role in ['officer', 'admin']) {
      test('$role does expire, so it has one', () {
        final p = _profile(role: role);
        expect(p.daysUntilExpiry, isNotNull);
        expect(p.daysUntilExpiry, greaterThan(0));
      });

      test('$role past its window reads as expired and negative', () {
        final p = _profile(
            role: role,
            createdAt: DateTime.now().subtract(const Duration(days: 400)));
        expect(p.isExpired, isTrue);
        expect(p.daysUntilExpiry, lessThan(0));
      });
    }
  });
}
