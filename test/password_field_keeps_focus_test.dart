import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The requirements checklist must not be inserted with a bare `if`.
///
/// ⚠️ On both profile dialogs the checklist appeared via `if (...) ...[`, so
/// two children were added ABOVE the password field the moment the first
/// character was typed. The field lost focus and typing stopped until the
/// officer clicked back into the box.
///
/// The fix is a slot that is always in the tree, whose CONTENTS change — which
/// also keeps the layout from jumping under the cursor as the checklist
/// appears.
///
/// ⚠️ A source check, not a widget test. `tester.enterText` focuses the field
/// itself, so a widget test of this passes either way — it cannot tell the two
/// shapes apart, and a test that passes against the broken code is worse than
/// none. This asserts the shape that was actually changed.
void main() {
  test('no profile dialog inserts the checklist with a bare if', () {
    const surfaces = [
      'lib/screens/profile/edit_profile_screen.dart',
      'lib/widgets/disposal_profile_dialog.dart',
    ];
    for (final path in surfaces) {
      final src = File(path).readAsStringSync();
      expect(src.contains('if (_newPasswordCtrl!.text.isNotEmpty) ...['),
          isFalse,
          reason: '$path adds siblings above the field while it is focused');
      expect(src.contains('if (_newPassCtrl.text.isNotEmpty) ...['), isFalse,
          reason: '$path adds siblings above the field while it is focused');
      expect(src.contains('AnimatedSize('), isTrue,
          reason: '$path must keep the slot and vary only its contents');
    }
  });

  test('the checklist is still hidden on an untouched optional form', () {
    // Changing the password is optional on these two screens (blank keeps the
    // current one), so unmet rules on a form nobody has typed into would read
    // as an error blocking an unrelated edit.
    for (final path in const [
      'lib/screens/profile/edit_profile_screen.dart',
      'lib/widgets/disposal_profile_dialog.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('.text.isEmpty'), isTrue,
          reason: '$path must still hide the checklist before typing starts');
    }
  });
}
