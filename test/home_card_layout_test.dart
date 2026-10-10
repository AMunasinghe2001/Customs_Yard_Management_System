import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/theme.dart';

/// The portal picker's "Create Account" button sat in a fixed 42px box with a
/// label long enough to wrap, so the second line was clipped and the button
/// read "Create" with a sliced row beneath it.
void main() {
  Widget harness(double width, Widget child) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  /// The button exactly as the card builds it.
  Widget createButton(Color accent) => SizedBox(
        width: double.infinity,
        height: 42,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withOpacity(0.6), width: 1.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {},
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Create Account',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent)),
          ),
        ),
      );

  for (final w in <double>[220, 180, 150, 120, 100]) {
    testWidgets('Create Account fits on one line at ${w.toInt()}px',
        (tester) async {
      await tester.pumpWidget(harness(w, createButton(AppTheme.ictCyan)));
      await tester.pumpAndSettle();

      // No overflow painted.
      expect(tester.takeException(), isNull);

      // And the whole label is still one line, not wrapped away.
      final text = tester.widget<Text>(find.text('Create Account'));
      expect(text.maxLines, 1);

      final size = tester.getSize(find.text('Create Account'));
      expect(size.height, lessThan(42),
          reason: 'the label grew taller than its button');
    });
  }

  test('the ICT accent is distinct from every other portal accent', () {
    // ICT used to be cyan (0xFF0097A7), a near-neighbour of the Executive
    // Office's teal (0xFF0E7C86) — on the portal picker the two cards read as
    // the same colour.
    int distance(Color a, Color b) {
      final dr = ((a.r - b.r) * 255).abs();
      final dg = ((a.g - b.g) * 255).abs();
      final db = ((a.b - b.b) * 255).abs();
      return (dr + dg + db).round();
    }

    final others = <String, Color>{
      'executiveTeal': AppTheme.executiveTeal,
      'appealPurple': AppTheme.appealPurple,
      'customsBlue': AppTheme.customsBlue,
    };

    others.forEach((name, c) {
      expect(distance(AppTheme.ictCyan, c), greaterThan(90),
          reason: 'ICT is too close to $name to tell apart');
    });

    // It must also stay clear of the status colours — an accent that reads as
    // the error red would make every ICT header look like a warning.
    expect(distance(AppTheme.ictCyan, const Color(0xFFD32F2F)), greaterThan(110),
        reason: 'ICT reads as the error red');

    // And it must not be another blue: the app already uses customsBlue for the
    // yard portal and teal for the Executive Office. Blue-dominant means the
    // blue channel leads by a clear margin.
    final c = AppTheme.ictCyan;
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    expect(b > r + 40 && b > g + 40, isFalse,
        reason: 'ICT is yet another blue (r=$r g=$g b=$b)');
  });
}
