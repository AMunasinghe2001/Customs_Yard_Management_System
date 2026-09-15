import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The portal cards on the home page spread a ripple from the pointer when
/// clicked. The Yard Access cards did not, so the same gesture felt dead in
/// the yard.
void main() {
  final yard = _read('lib/screens/home/yard_access_screen.dart');
  final home = _read('lib/screens/home/home_screen.dart');

  group('a Yard Access card ripples like a home portal card', () {
    test('the tap is an InkWell, not a bare GestureDetector', () {
      // ⚠️ A GestureDetector catches the tap and paints nothing. The card is
      // the thing being clicked, so it has to be the thing that responds.
      expect(yard, contains('onTap: widget.onSignIn'));
      final flat = yard.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat.contains('InkWell( onTap: widget.onSignIn'), isTrue,
          reason: 'the card tap does not paint a ripple');
      expect(flat.contains('GestureDetector( onTap: widget.onSignIn'), isFalse,
          reason: 'the silent GestureDetector is back on the card');
    });

    test('it uses the same splash recipe as the home cards', () {
      // Same colours, so the two pages feel like one app.
      for (final s in const [
        'splashColor: accent.withOpacity(0.12)',
        'highlightColor: accent.withOpacity(0.06)',
      ]) {
        expect(yard.replaceAll(RegExp(r'\s+'), ' '), contains(s));
      }
      final homeFlat = home.replaceAll(RegExp(r'\s+'), ' ');
      expect(homeFlat,
          contains('splashColor: widget.accentColor.withOpacity(0.12)'),
          reason: 'the home recipe this copies has changed');
    });

    test('the ripple is painted over the card, not under it', () {
      // ⚠️ The card paints its own gradient background. An InkWell outside
      // that Container would splash underneath it and never be seen, which is
      // the usual way this "fix" silently does nothing.
      final inkAt = yard.indexOf('onTap: widget.onSignIn');
      final decorAt = yard.indexOf('decoration: BoxDecoration(');
      expect(inkAt, greaterThan(decorAt),
          reason: 'the InkWell sits above the card background and will not '
              'be visible');
      expect(yard, contains('color: Colors.transparent'),
          reason: 'an opaque Material would hide the hover gradient');
    });

    test('the Create Account button inside still works', () {
      // It is nested inside the InkWell's child, so it must keep winning the
      // hit test rather than the whole card swallowing the tap.
      expect(yard, contains('onTap: widget.onCreateAccount'));
    });
  });

  group('the ICT edit form is grouped like the add form', () {
    final ict = _read('lib/screens/ict/ict_dashboard_screen.dart');

    test('both forms use the same two sections', () {
      // ⚠️ The edit dialog was a bare column while "Create Yard Staff
      // Account" grouped its fields into titled cards, so the two forms that
      // describe one account looked unrelated and the edit rows sat right on
      // top of each other.
      expect("title: 'Role & Yard Assignment'".allMatches(ict).length, 2,
          reason: 'only one form groups the posting fields');
      expect("title: 'Personal & Contact Details'".allMatches(ict).length, 2,
          reason: 'only one form groups the personal fields');
    });
  });
}
