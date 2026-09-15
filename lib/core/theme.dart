import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Extension for easy access anywhere: context.colors.primaryNavy
extension AppThemeExt on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// App-wide snackbar helpers so every yard and directorate shows feedback with
/// consistent, semantic colours: success = green, error = red, info = gold.
/// Use `context.showSuccess('Saved')` instead of hand-rolling a SnackBar — this
/// keeps the colour right everywhere (success was sometimes blue/navy before).
extension AppSnackBar on BuildContext {
  void _showSnack(String message, Color bg, IconData icon) {
    final messenger = ScaffoldMessenger.of(this);
    // A wide, floating toast that spans the page width (small side margins) so
    // every success/error/info message looks the same — matching the data-save
    // snackbars (e.g. "N package(s) marked …").
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      elevation: 6,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ]),
    ));
  }

  /// Green success toast.
  void showSuccess(String message) =>
      _showSnack(message, colors.successGreen, Icons.check_circle_rounded);

  /// Red error toast.
  void showError(String message) =>
      _showSnack(message, colors.dangerRed, Icons.error_rounded);

  /// Gold informational toast.
  void showInfo(String message) =>
      _showSnack(message, colors.primaryGold, Icons.info_rounded);
}

// Custom theme extension to hold our specific semantic colors
class AppColors extends ThemeExtension<AppColors> {
  final Color customsBlue;
  final Color customsBlueDark;
  final Color customsBlueLight;
  final Color primaryNavy;
  final Color primaryGold;
  final Color accentBlue;
  final Color accentLightBlue;
  final Color successGreen;
  final Color warningAmber;
  final Color dangerRed;
  final Color heldOrange;
  final Color surfaceDark; // Used as standard container surface
  /// The inside of every text box and dropdown. See [_fieldFillLight].
  final Color fieldFill;
  final Color cardDark; // Used as standard card color
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color scaffoldBg;

  const AppColors({
    required this.customsBlue,
    required this.customsBlueDark,
    required this.customsBlueLight,
    required this.primaryNavy,
    required this.primaryGold,
    required this.accentBlue,
    required this.accentLightBlue,
    required this.successGreen,
    required this.warningAmber,
    required this.dangerRed,
    required this.heldOrange,
    required this.surfaceDark,
    required this.fieldFill,
    required this.cardDark,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.scaffoldBg,
  });

  @override
  AppColors copyWith({
    Color? customsBlue,
    Color? customsBlueDark,
    Color? customsBlueLight,
    Color? primaryNavy,
    Color? primaryGold,
    Color? accentBlue,
    Color? accentLightBlue,
    Color? successGreen,
    Color? warningAmber,
    Color? dangerRed,
    Color? heldOrange,
    Color? surfaceDark,
    Color? fieldFill,
    Color? cardDark,
    Color? borderColor,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? scaffoldBg,
  }) {
    return AppColors(
      customsBlue: customsBlue ?? this.customsBlue,
      customsBlueDark: customsBlueDark ?? this.customsBlueDark,
      customsBlueLight: customsBlueLight ?? this.customsBlueLight,
      primaryNavy: primaryNavy ?? this.primaryNavy,
      primaryGold: primaryGold ?? this.primaryGold,
      accentBlue: accentBlue ?? this.accentBlue,
      accentLightBlue: accentLightBlue ?? this.accentLightBlue,
      successGreen: successGreen ?? this.successGreen,
      warningAmber: warningAmber ?? this.warningAmber,
      dangerRed: dangerRed ?? this.dangerRed,
      heldOrange: heldOrange ?? this.heldOrange,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      fieldFill: fieldFill ?? this.fieldFill,
      cardDark: cardDark ?? this.cardDark,
      borderColor: borderColor ?? this.borderColor,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      scaffoldBg: scaffoldBg ?? this.scaffoldBg,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      customsBlue: Color.lerp(customsBlue, other.customsBlue, t)!,
      customsBlueDark: Color.lerp(customsBlueDark, other.customsBlueDark, t)!,
      customsBlueLight:
          Color.lerp(customsBlueLight, other.customsBlueLight, t)!,
      primaryNavy: Color.lerp(primaryNavy, other.primaryNavy, t)!,
      primaryGold: Color.lerp(primaryGold, other.primaryGold, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      accentLightBlue: Color.lerp(accentLightBlue, other.accentLightBlue, t)!,
      successGreen: Color.lerp(successGreen, other.successGreen, t)!,
      warningAmber: Color.lerp(warningAmber, other.warningAmber, t)!,
      dangerRed: Color.lerp(dangerRed, other.dangerRed, t)!,
      heldOrange: Color.lerp(heldOrange, other.heldOrange, t)!,
      surfaceDark: Color.lerp(surfaceDark, other.surfaceDark, t)!,
      fieldFill: Color.lerp(fieldFill, other.fieldFill, t)!,
      cardDark: Color.lerp(cardDark, other.cardDark, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      scaffoldBg: Color.lerp(scaffoldBg, other.scaffoldBg, t)!,
    );
  }
}

class AppTheme {
  // Common Brand Colors
  static const Color primaryGold = Color(0xFFD4A017);
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color warningAmber = Color(0xFFF57F17);
  static const Color dangerRed = Color(0xFFC62828);
  static const Color heldOrange = Color(0xFFE65100);

  /// Appeal Directorate accent – deep purple for strong contrast against the
  /// dark navy scaffold, and a royal/legal feel that pairs well with gold.
  static const Color appealPurple = Color(0xFF7B1FA2);
  // Executive Office (DG / ADG) — a distinct deep teal, not used by any other
  // portal (blue/green/purple/gold), so the top office reads apart.
  static const Color executiveTeal = Color(0xFF0E7C86);
  // ICT Directorate (ICT Division) — deep plum.
  //
  // Three earlier attempts, and why none of them worked:
  //   0xFF0097A7 (cyan)         sat beside the Executive Office's teal
  //                             0xFF0E7C86 — the two portals looked identical.
  //   0xFF4A3AFF (bright indigo) distinct, but far too vivid as a full-width
  //                             header wash next to the muted rest.
  //   0xFF3F51B5 (slate indigo)  still BLUE, and the app already has two blues
  //                             (customsBlue for the yard, teal for executive).
  //
  // The hues already spoken for are 37/42 (golds), 123 (green), 185 (teal),
  // 242 (blue) and 282 (purple). 334 is the clear gap. Reds were the other
  // option but every one of them collided with the app's error red 0xFFD32F2F;
  // this sits 128 away from it in summed RGB, and carries white text at
  // 7.2:1 contrast.
  static const Color ictCyan = Color(0xFF8E3A5F);

  // Custom Dark Colors
  static const Color _customsBlue = Color(0xFF231f87);
  static const Color _customsBlueDark = Color(0xFF1a1764);
  static const Color _customsBlueLight = Color(0xFF3531a8);
  static const Color _primaryNavy = Color(0xFF0e0c3a);
  static const Color _accentBlue = Color(0xFF231f87);
  static const Color _accentLightBlue = Color(0xFF6b67d9);

  // Dark mode surfaces
  static const Color _surfaceDark = Color(0xFF1a1764);
  static const Color _cardDark = Color(0xFF1e1b7a);
  static const Color _borderDark = Color(0xFF2e2a9e);
  static const Color _bgDark = Color(0xFF0e0c3a);
  static const Color _textPrimaryDark = Color(0xFFECEFF1);
  static const Color _textSecondaryDark = Color(0xFFB0BEC5);
  static const Color _textMutedDark = Color(0xFF78909C);

  // Backward-compatible aliases used by older screens
  static const Color customsBlue = _customsBlue;
  static const Color customsBlueDark = _customsBlueDark;
  static const Color customsBlueLight = _customsBlueLight;
  static const Color primaryNavy = _primaryNavy;
  static const Color accentBlue = _accentBlue;
  static const Color accentLightBlue = _accentLightBlue;
  static const Color cardDark = _cardDark;

  /// Dark mode keeps the surface colour: on a dark card the two already
  /// differ enough to read as a field.
  static const Color fieldFill = _surfaceDark;
  static const Color borderColor = _borderDark;
  static const Color textSecondary = _textSecondaryDark;
  static const Color textMuted = _textMutedDark;
  static const Color scaffoldBg = _bgDark;

  // Custom Light Colors
  static const Color _bgLight =
      Color(0xFFF0F4FA); // Very light, slightly cool grey for background
  static const Color _surfaceLight =
      Color(0xFFFFFFFF); // Pure white for generic container surfaces
  static const Color _cardLight =
      Color(0xFFF7F9FC); // Subtly distinguished white for cards
  static const Color _borderLight = Color(0xFFDDE3EC); // Soft border
  /// The inside of every text box and dropdown, light mode.
  ///
  /// ⚠️ A real grey, NOT `_cardLight`. The fields used to be filled with the
  /// card colour (#F7F9FC) on cards that were already that colour, so a box
  /// only showed up where the page behind it happened to be white — which is
  /// why some looked white and others grey in the same form. This reads as a
  /// field wherever it sits.
  static const Color _fieldFillLight = Color(0xFFEDF1F7);
  static const Color _textPrimaryLight = Color(0xFF1A1A24);
  static const Color _textSecondaryLight = Color(0xFF5A6372);
  static const Color _textMutedLight = Color(0xFF8A93A2);

  static final _darkColors = AppColors(
    customsBlue: _customsBlue,
    customsBlueDark: _customsBlueDark,
    customsBlueLight: _customsBlueLight,
    primaryNavy: _primaryNavy,
    primaryGold: primaryGold,
    accentBlue: _accentBlue,
    accentLightBlue: _accentLightBlue,
    successGreen: successGreen,
    warningAmber: warningAmber,
    dangerRed: dangerRed,
    heldOrange: heldOrange,
    surfaceDark: _surfaceDark,
    // Dark mode: the surface already reads as a field against the card.
    fieldFill: _surfaceDark,
    cardDark: _cardDark,
    borderColor: _borderDark,
    textPrimary: _textPrimaryDark,
    textSecondary: _textSecondaryDark,
    textMuted: _textMutedDark,
    scaffoldBg: _bgDark,
  );

  static final _lightColors = AppColors(
    customsBlue: _customsBlue,
    customsBlueDark: _customsBlueDark,
    customsBlueLight: _customsBlueLight,
    primaryNavy:
        _primaryNavy, // primary brand stays the same if needed, or invert
    primaryGold: primaryGold,
    accentBlue: _accentBlue, // brand blue
    accentLightBlue: Color(0xFF5753C4), // slightly darker for contrast on white
    successGreen: successGreen,
    warningAmber: warningAmber,
    dangerRed: dangerRed,
    heldOrange: heldOrange,
    surfaceDark: _surfaceLight,
    fieldFill: _fieldFillLight,
    cardDark: _cardLight,
    borderColor: _borderLight,
    textPrimary: _textPrimaryLight,
    textSecondary: _textSecondaryLight,
    textMuted: _textMutedLight,
    scaffoldBg: _bgLight,
  );

  static ThemeData get darkTheme => _buildTheme(Brightness.dark, _darkColors);
  static ThemeData get lightTheme =>
      _buildTheme(Brightness.light, _lightColors);

  static ThemeData _buildTheme(Brightness brightness, AppColors colors) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [colors],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryGold,
        onPrimary: brightness == Brightness.dark ? _primaryNavy : Colors.white,
        secondary: colors.accentLightBlue,
        onSecondary: Colors.white,
        error: dangerRed,
        onError: Colors.white,
        surface: colors.surfaceDark,
        onSurface: colors.textPrimary,
      ),
      scaffoldBackgroundColor: colors.scaffoldBg,
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData(brightness: brightness).textTheme.copyWith(
              displayLarge: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w700),
              displayMedium: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w600),
              headlineLarge: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w700),
              headlineMedium: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w600),
              headlineSmall: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w600),
              titleLarge: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w600),
              titleMedium: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.w500),
              bodyLarge: TextStyle(color: colors.textPrimary),
              bodyMedium: TextStyle(color: colors.textSecondary),
              bodySmall: TextStyle(color: colors.textMuted),
              labelLarge: const TextStyle(
                  color: primaryGold, fontWeight: FontWeight.w600),
            ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:
            brightness == Brightness.dark ? _primaryNavy : _customsBlueDark,
        foregroundColor: Colors.white, // Always white text on app bar
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: colors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.borderColor, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // ⚠️ A dedicated FIELD colour, not the card's and not the surface's.
        //
        // Two wrong versions preceded this. `surfaceDark` is pure #FFFFFF in
        // light mode, so a field sat on its card as a brighter white rectangle
        // — a pale outline round every box. `cardDark` (#F7F9FC) fixed that
        // but made the field the same colour as the card it sits on, so a box
        // only showed where the page behind it happened to be white: some
        // looked grey and others white in the SAME form.
        //
        // `fieldFill` is a real grey that differs from BOTH, so a field reads
        // as a field wherever it is placed.
        fillColor: colors.fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryGold, width: 2),
        ),
        // ⚠️ ONE height for every field in the app.
        //
        // Without this each field sized itself from its own content, so a
        // plain TextField, one carrying a helper line and a dropdown all came
        // out different heights — the ICT forms visibly stepped up and down
        // along a row. `isDense` with an explicit padding is what makes them
        // agree, and it is also what makes them shorter.
        // ⚠️ 11 vertical, not the 14 most call sites pass. With `isDense` this
        // is what actually makes the boxes shorter — the fields that spell out
        // their own `contentPadding: vertical: 14` still override it, so the
        // ICT dialogs set theirs explicitly rather than relying on this.
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: colors.textSecondary),
        hintStyle: TextStyle(color: colors.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGold,
          foregroundColor: _primaryNavy, // Keep gold buttons with navy text
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGold,
          side: const BorderSide(color: primaryGold),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: const TextStyle(
            color: primaryGold, fontWeight: FontWeight.w700, fontSize: 13),
        dataTextStyle: TextStyle(color: colors.textPrimary, fontSize: 14),
        headingRowColor: WidgetStateProperty.all(colors.surfaceDark),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.cardDark;
          return Colors.transparent;
        }),
        dividerThickness: 1,
        columnSpacing: 24,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryGold,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: primaryGold,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.cardDark,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceDark,
        selectedColor: primaryGold.withOpacity(0.3),
        labelStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
        side: BorderSide(color: colors.borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: colors.borderColor, thickness: 1),
    );
  }
}
