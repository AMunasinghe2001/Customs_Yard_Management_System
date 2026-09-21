import 'package:flutter/material.dart';

/// Makes every text box inside it use ONE colour — the portal's own accent.
///
/// ⚠️ THE BUG THIS EXISTS FOR: `inputDecorationTheme.focusedBorder` hardcoded
/// `primaryGold`, so a focused field turned **gold on every portal** — a gold
/// ring on the purple Appeal form, on the green Disposal form, on the teal
/// Top Management one. Reported as "text boxes using two colours": the box is
/// one colour until you click it and a different one after.
///
/// The fix is per-portal rather than global because the accent IS per-portal.
/// Each sign-in and sign-up screen already names its accent for [BrandPanel];
/// wrapping its form in this hands the same colour to the fields.
///
/// ⚠️ Only the FOCUS ring changes. The fill and the resting border stay the
/// theme's, because those must match across portals — the whole point of a
/// shared field colour is that a form looks the same everywhere until the
/// officer interacts with it.
class PortalFieldTheme extends StatelessWidget {
  /// The portal's colour — the same value its `BrandPanel` is given.
  final Color accent;

  final Widget child;

  const PortalFieldTheme({
    super.key,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final input = base.inputDecorationTheme;
    return Theme(
      data: base.copyWith(
        inputDecorationTheme: input.copyWith(
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accent, width: 2),
          ),
          // The floating label rides the border, so it has to move with it —
          // a gold label over an accent-coloured ring is the same fault in
          // miniature.
          floatingLabelStyle: TextStyle(color: accent),
        ),
        // Checkboxes, the caret and the selection handles all read from the
        // scheme; left alone they stay gold beside an accent-coloured field.
        colorScheme: base.colorScheme.copyWith(primary: accent),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: accent,
          selectionColor: accent.withOpacity(0.25),
          selectionHandleColor: accent,
        ),
      ),
      child: child,
    );
  }
}
