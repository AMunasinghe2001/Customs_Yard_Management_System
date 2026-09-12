import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hovering a portal tile made it look greyed-out instead of picking up the
/// team colour.
///
/// ⚠️ The cause was a combination, which is why it is asserted at source
/// level rather than by pixel. Each hovered card filled itself with a
/// RadialGradient of TRANSLUCENT white (0.55 / 0.32) and sat that over a
/// `BackdropFilter` blurring the page behind it. The blurred page therefore
/// showed through the card's own fill: the white lost its brightness and the
/// accent came through as a muddy wash rather than the portal's colour over
/// white — "අවපැහැ ගතිය", exactly as reported.
///
/// The fix is that a hovered card paints an OPAQUE fill, tinted towards the
/// accent, with no backdrop blur underneath it. Both screens had the same
/// code copied, so both are checked.
void main() {
  const screens = {
    'the home portal cards': 'lib/screens/home/home_screen.dart',
    'the yard access tiles': 'lib/screens/home/yard_access_screen.dart',
  };

  screens.forEach((what, path) {
    group(what, () {
      final src = File(path).readAsStringSync();

      test('do not blur the page through the card', () {
        // A BackdropFilter is what let the background reach the fill. Behind
        // an opaque fill it would also blur nothing at all, so its presence
        // means the translucent fill has returned with it.
        // ⚠️ Matches a CONSTRUCTOR CALL, not the bare word: the comments
        // left in both files explain why the filter was removed and name it
        // to do so. Asserting on the word alone failed on its own
        // explanation.
        expect(src, isNot(contains('BackdropFilter(')),
            reason: 'the page is frosted through the card again, which is '
                'what greyed the hover state');
      });

      test('fill the hovered card with opaque white, not a translucent one',
          () {
        // The specific values that caused it. `Colors.white.withOpacity(...)`
        // as a card FILL is the defect; an opaque `Colors.white` or a
        // `Color.lerp(Colors.white, accent, ...)` is the fix.
        expect(src, isNot(contains('Colors.white.withOpacity(0.5)')),
            reason: 'a translucent white fill is back');
        expect(src, isNot(contains('Colors.white.withOpacity(0.55)')),
            reason: 'a translucent white fill is back');
        expect(src, isNot(contains('Colors.white.withOpacity(0.32)')),
            reason: 'a translucent white fill is back');
      });

      test('do not change the card geometry on hover', () {
        // ⚠️ A Border paints INSIDE the box. Growing it on hover
        // (`width: _hovered ? 1.6 : 1`) shrank the content area by 0.6px on
        // every side, so the card's contents reflowed and the logo and
        // heading laid out above them visibly jumped up and down as the
        // pointer crossed a card.
        //
        // Colour may change on hover; SIZE may not. BoxShadow and
        // AnimatedScale are both exempt and deliberately still used: a
        // shadow paints outside the box, and a scale is a transform that
        // keeps its layout size, so neither moves a sibling.
        expect(RegExp(r'width:\s*_hovered').hasMatch(src), isFalse,
            reason: 'a hover-dependent border width reflows the card and '
                'makes everything above it jump');
      });

      test('keep the accent as a tint of white so the hue survives', () {
        // Lerping towards the accent keeps both the team colour AND the
        // brightness. A bare `accent.withOpacity(0.28)` over a see-through
        // white was what read as dull.
        expect(src, contains('Color.lerp(Colors.white'),
            reason: 'the hover fill no longer tints white towards the accent, '
                'so it cannot show the team colour and stay bright');
      });
    });
  });
}
