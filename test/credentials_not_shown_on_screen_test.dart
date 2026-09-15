import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) =>
    File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// A generated password is a working credential for somebody else's account.
/// It belongs in that person's mailbox, not on an ICT officer's monitor in an
/// open office.
void main() {
  final ict = _read('lib/screens/ict/ict_dashboard_screen.dart');

  String dialogBody() {
    final start = ict.indexOf('void _showSuccessCredentialsDialog(');
    final end = ict.indexOf('Widget _credRow(');
    expect(start, greaterThan(0), reason: 'the dialog was renamed');
    expect(end, greaterThan(start), reason: 'end anchor not after start');
    final body = ict.substring(start, end);
    // ⚠️ Prove the window is real before asserting about what is inside it:
    // a -1 or a wrong anchor would otherwise let every assertion below pass
    // while reading almost nothing.
    expect(body.length, greaterThan(800),
        reason: 'the window is too small to be the whole dialog');
    return body;
  }

  group('the new account dialog keeps the credentials off the screen', () {
    test('they are shown only when the e-mail did NOT go out', () {
      final body = dialogBody();

      // The password row must be behind the `!emailed` branch.
      final guarded = RegExp(
              r"if\s*\(!emailed\)[\s\S]{0,600}?_credRow\(\s*'Temporary Password'")
          .hasMatch(body);
      expect(guarded, isTrue,
          reason: 'the temporary password is rendered unconditionally — it '
              'was on screen for every account ICT created');
    });

    test('the normal path says so instead of printing them', () {
      expect(dialogBody(), contains('deliberately not shown here'));
    });

    test('the fallback warns that it is the only copy', () {
      // Without this an officer could dismiss the one screen carrying a
      // credential that never reached a mailbox.
      expect(dialogBody(), contains('ONLY copy of these credentials'));
    });
  });

  group('the directorate reset already did this, and still does', () {
    test('it reports the username and never the password', () {
      final tab = _read('lib/screens/ict/directorate_access_tab.dart');
      expect(tab, contains('The new username is'));
      expect(tab.contains(r"$password"), isFalse,
          reason: 'the reset snackbar is printing a password');
    });
  });
}
