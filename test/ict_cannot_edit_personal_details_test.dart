import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// Who owns which field.
///
/// The officer owns their name, sign-in username and mobile number, and
/// changes them from their own profile in the yard. The DEPARTMENT owns the
/// salary number, the post and the yard, and ICT sets those.
void main() {
  final ict = _read('lib/screens/ict/ict_dashboard_screen.dart');

  String editDialog() {
    // ⚠️ Anchored on the METHOD, not on the dialog's title: the save block
    // that posts the values sits ABOVE the title in this file, so a window
    // starting at the title saw the form but not the save — and the
    // assertion about what is actually written would have been meaningless.
    final start = ict.indexOf('void _showEditStaffDialog(');
    final end = ict.indexOf('Future<void> _toggleStaffStatus(');
    expect(start, greaterThan(0), reason: '_showEditStaffDialog was renamed');
    expect(end, greaterThan(start), reason: 'end anchor not after start');
    final body = ict.substring(start, end);
    // ⚠️ Prove the window is real before asserting about its contents.
    expect(body.length, greaterThan(1500),
        reason: 'the window is too small to be the whole dialog');
    return body;
  }

  group('ICT may not retype an officer\'s personal details', () {
    test('name, username and mobile are read-only', () {
      final body = editDialog();
      // ⚠️ `dart format` wraps only the calls that are too long, so some read
      // `_ReadOnlyDetail(label:` and others `_ReadOnlyDetail( label:`. Match
      // on the pair of values instead of on one exact spelling.
      final flat = body.replaceAll(RegExp(r'\s+'), ' ');
      for (final f in const ['Full Name', 'Username', 'Mobile Number']) {
        expect(
            RegExp("_ReadOnlyDetail\\(\\s*label: '$f'").hasMatch(flat), isTrue,
            reason: '$f is still an editable field in the ICT console');
      }
    });

    test('no TextField carries those values any more', () {
      final body = editDialog();
      // The controllers that used to back them are gone entirely; a leftover
      // one is how this would quietly come back.
      for (final c in const ['nameC', 'unameC', 'mobileC']) {
        expect(body.contains('controller: $c'), isFalse,
            reason: '$c still backs an editable field');
      }
    });

    test('the save sends the officer\'s own values, not form input', () {
      final body = editDialog();
      // ⚠️ Read-only in the UI is not enough on its own: if the save still
      // posted a controller's text, the field would just be uneditable while
      // remaining overwritable.
      expect(body, contains('fullName: staff.fullName'));
      expect(body, contains('username: staff.username'));
      expect(body, contains('mobileNumber: staff.mobileNumber'));
    });

    test('what ICT DOES own stays editable', () {
      final body = editDialog();
      expect(body, contains('controller: salaryC'),
          reason: 'ICT must still set the salary number');
      expect(body, contains("label: 'Post *'"),
          reason: 'ICT must still set the post');
      expect(body, contains('_YardField('),
          reason: 'ICT must still set the yard');
      expect(body, contains('badgeNumber: salaryC.text.trim()'));
    });
  });

  group('the staff table does not list sign-in usernames', () {
    test('the column shows the salary number alone', () {
      expect(ict, contains("ictCol('Salary No'"));
      expect(ict.contains(r"'@${staff.username ?? '—'}'"), isFalse,
          reason: 'every officer\'s username is back on screen');
    });
  });

  group('the salary number belongs to ICT, not the officer', () {
    final profile = _read('lib/screens/profile/edit_profile_screen.dart');

    test('the yard profile shows it read-only', () {
      final flat = profile.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          RegExp(r"controller: _salaryCtrl!, readOnly: true, enabled: false")
              .hasMatch(flat),
          isTrue,
          reason: 'an officer can still retype their own salary number');
    });

    test('the save posts the stored value, not the field', () {
      // ⚠️ Read-only in the UI is not unwritable: posting the controller
      // would leave it overwritable by anything that set that text.
      expect(profile, contains('badgeNumber: profile.badgeNumber'));
      expect(profile.contains('badgeNumber: _salaryCtrl!.text.trim()'), isFalse,
          reason: 'the profile form still posts the salary field');
    });
  });

  group('the profile counts down the PASSWORD, not the account', () {
    final profile = _read('lib/screens/profile/edit_profile_screen.dart');

    test('the tile reads from daysUntilPasswordExpiry', () {
      // ⚠️ It used to show account dormancy, which read "Never expires" for
      // anyone signing in regularly — nothing the officer could act on. The
      // password rotates every 90 days and locks them out when it lapses.
      expect(profile, contains('daysUntilPasswordExpiry'));
      expect(profile, contains("'Password Resets In'"));
      expect(profile.contains("'Disables In'"), isFalse,
          reason: 'the dormancy countdown is back on the profile');
    });
  });

  group('every text box is one height, and does not glow white', () {
    final theme = _read('lib/core/theme.dart');

    test('the fill is a field colour of its own', () {
      // ⚠️ This asserted `cardDark` when it was written. That was a step, not
      // the answer: a field painted the CARD colour disappears into the card
      // it sits on, so the same form held boxes that looked grey and boxes
      // that looked white. `fieldFill` differs from both the card and the
      // surface — the full rule lives in one_field_height_test.dart.
      expect(theme, contains('fillColor: colors.fieldFill'));
      expect(theme.contains('fillColor: colors.surfaceDark'), isFalse,
          reason: 'the fields are pure white on an off-white card again');
    });

    test('one dense height for every field', () {
      expect(theme, contains('isDense: true'));
      expect(theme, contains('contentPadding:'));
    });
  });

  group('Edit Profile wears the YARD dialog design', () {
    final profile = _read('lib/screens/profile/edit_profile_screen.dart');

    test('it opts into the yard header', () {
      // ⚠️ There are THREE looks, not two: the yard's navy gradient bar, the
      // directorates' 15% tint of their team colour, and the ICT console's
      // flat panel. The tint is the DEFAULT, so a yard dialog that passes
      // nothing silently gets the directorate design in gold — which is
      // exactly how this dialog came to look like a directorate form.
      expect(profile, contains('yard: true'),
          reason: 'the profile dialog falls back to the directorate tint');
    });

    test('it does not take the ICT console variant either', () {
      expect(profile.contains('erp: true'), isFalse,
          reason: 'the profile dialog switched to the ICT console design');
      expect(profile, contains('StyledFormDialog'));
    });

    test('the yard header is the SR Register Entry recipe', () {
      final dlg = _read('lib/widgets/styled_form_dialog.dart');
      expect(dlg, contains('context.colors.customsBlue'),
          reason: 'the yard variant is not the navy gradient');
      // On a dark bar the title must be white in light mode, or it is navy
      // text on navy.
      expect(dlg, contains('yard && !isDark'));
    });

    test('the yard flag stays opt-in, and only yard screens take it', () {
      // ⚠️ Not a fixed COUNT any more — Yard Administration's warehouse and
      // category dialogs legitimately take it too. The rule being guarded is
      // that no DIRECTORATE screen does: the tint is their design, and a
      // navy bar on a directorate popup is the same mistake in reverse.
      final callers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('yard: true'))
          // Windows reports back-slashed paths; compare on one spelling.
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList()
        ..sort();

      const directorates = [
        '/screens/ict/',
        '/screens/disposal/',
        '/screens/valuation/',
        '/screens/appeal/',
        '/screens/executive/',
      ];
      final wrong = callers
          .where((c) => directorates.any(c.contains))
          .toList();
      expect(wrong, isEmpty,
          reason: 'a directorate screen took the yard header: $wrong');
      expect(callers, isNotEmpty,
          reason: 'nothing takes the yard header any more');
    });
  });
}
