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

  group('the photo picker only accepts real image formats', () {
    test('the allow-list is jpg/jpeg/png', () {
      expect(profileScreen,
          contains("_allowedImageExtensions = ['jpg', 'jpeg', 'png']"));
    });

    test('the picker is asked for exactly those, not FileType.image', () {
      // FileType.image lets the platform offer anything it calls an image --
      // SVG included, which is a document that can carry script.
      expect(profileScreen, contains('type: FileType.custom'));
      expect(profileScreen,
          contains('allowedExtensions: _allowedImageExtensions'));
      expect(profileScreen, isNot(contains('type: FileType.image')));
    });

    test('the extension is re-checked after the pick', () {
      // A picker filter is a convenience the platform may not honour.
      expect(profileScreen,
          contains('if (!_allowedImageExtensions.contains(ext))'));
      expect(profileScreen, contains('Only JPG and PNG images are accepted'));
    });
  });

  group('DC and SDDC are separate posts', () {
    test('three posts are offered, not two roles', () {
      expect(kPostTitles.keys.toList(), ['officer', 'dc', 'sddc']);
      expect(kPostTitles['dc'], contains('DC'));
      expect(kPostTitles['sddc'], contains('SDDC'));
    });

    test('both admin posts still carry the admin permission', () {
      // The DB role column has only 'admin' and 'officer'; the POST is what
      // distinguishes DC from SDDC.
      expect(kPostRoles['dc'], 'admin');
      expect(kPostRoles['sddc'], 'admin');
      expect(kPostRoles['officer'], 'officer');
    });

    test('every post maps to a role and vice versa', () {
      expect(kPostRoles.keys.toSet(), kPostTitles.keys.toSet());
    });

    test('postTitle prefers the recorded post over the bare role', () {
      final dc = ProfileModel(
          id: 'p', fullName: 'A', role: 'admin', isActive: true,
          createdAt: DateTime.now(), jobRole: 'sddc');
      expect(dc.postTitle, kPostTitles['sddc']);
    });

    test('an account with no post recorded still reads sensibly', () {
      expect(_profile(role: 'admin').postTitle, 'DC / SDDC');
      expect(_profile(role: 'officer').postTitle, 'Officer');
    });

    test('a free-text job role is shown as typed', () {
      final p = ProfileModel(
          id: 'p', fullName: 'A', role: 'officer', isActive: true,
          createdAt: DateTime.now(), jobRole: 'Wharf Supervisor');
      expect(p.postTitle, 'Wharf Supervisor');
    });
  });

  group('the ICT form writes the post it collected', () {
    final ict = _read('lib/screens/ict/ict_dashboard_screen.dart');

    test('every post picker is built from the shared map', () {
      // Add, Edit and the Role Filter -- so a post added to kPostTitles shows
      // up in all three without another edit.
      expect('for (final e in kPostTitles.entries)'.allMatches(ict).length, 3,
          reason: 'the two dialogs and the filter must offer the same posts');
    });

    test('the Edit dialog uses the same styled dropdown as Add', () {
      expect(ict, isNot(contains('DropdownButtonFormField<String>(')),
          reason: 'a bare dropdown made the two forms look unrelated');
      expect('_IctDialogDropdown('.allMatches(ict).length,
          greaterThanOrEqualTo(2));
    });

    test('the permission role is derived from the post', () {
      // Three call sites must carry it: the OTP request and the create in the
      // Add flow, and the update in Edit. Counting, not just presence -- the
      // post silently not reaching one of them is the failure mode.
      expect("kPostRoles[selectedPost] ?? 'officer'".allMatches(ict).length, 3);
      expect('jobRole: selectedPost'.allMatches(ict).length, 2,
          reason: 'create and update must both stamp the post');
    });

    test('the service persists it', () {
      final services = _read('lib/services/services.dart');
      expect("if (jobRole != null && jobRole.isNotEmpty) 'job_role': jobRole,"
          .allMatches(services).length, 2,
          reason: 'both create and update must stamp the post');
    });
  });

  group('the hero badge names the post, not the permission', () {
    test('it no longer upper-cases a raw role', () {
      // "ADMIN" is not a job anyone holds in this service.
      expect(profileScreen, isNot(contains('Text(role.toUpperCase()')));
      expect(profileScreen, contains('role: profile.postTitle'));
    });
  });

  group('the yard is shown with its directorate', () {
    test('both the hero and the details use the combined label', () {
      expect('_yardWithDirectorate(profile)'.allMatches(profileScreen).length, 2);
    });

    test('the helper prefixes the directorate when there is one', () {
      // A yard alone is ambiguous: NNR is both CED and PSD.
      expect(profileScreen, contains("return prefix.isEmpty ? yard : '\$prefix / \$yard';"));
    });
  });

  group('the edit form matches the yard forms', () {
    test('it is a StyledFormDialog, not a bare AlertDialog', () {
      expect(profileScreen, contains('StyledFormDialog('));
      expect(profileScreen, isNot(contains('AlertDialog(')));
    });

    test('its fields sit in the same titled sections', () {
      expect(profileScreen, contains("title: 'Your Details'"));
      expect(profileScreen, contains("title: 'Change Password'"));
      expect('StyledFormSection('.allMatches(profileScreen).length, 2);
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
