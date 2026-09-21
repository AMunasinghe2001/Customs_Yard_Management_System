// A text box must be ONE colour, and that colour is the portal's own.
//
// ⚠️ THE BUG: `inputDecorationTheme.focusedBorder` hardcoded `primaryGold`,
// so clicking a field turned it gold on EVERY portal — a gold ring on the
// purple Appeal form, on the green Disposal form, on the teal Top Management
// one. Reported from two screenshots of the same box: "text boxes using two
// colours — make it a single colour like it was before, on every portal."
//
// The accent is per-portal, so the fix has to be too: each sign-in and
// sign-up screen already names its accent for its BrandPanel, and
// PortalFieldTheme hands that same colour to the fields inside it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/portal_field_theme.dart';

/// Every screen that mounts a [BrandPanel] — i.e. every auth screen.
List<File> _authScreens() => Directory('lib/screens')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => f.readAsStringSync().contains('BrandPanel('))
    .toList();

void main() {
  group('every portal form colours its own fields', () {
    test('there are auth screens to check', () {
      expect(_authScreens().length, greaterThanOrEqualTo(15));
    });

    test('each one wraps its form in PortalFieldTheme', () {
      final missing = <String>[];
      for (final f in _authScreens()) {
        if (!f.readAsStringSync().contains('PortalFieldTheme(')) {
          missing.add(f.path);
        }
      }
      expect(missing, isEmpty,
          reason: 'these screens still focus their fields in gold');
    });

    test('and hands it the SAME accent its BrandPanel uses', () {
      // ⚠️ A wrapper with the wrong colour is worse than none: the box would
      // still be two colours, just a different second one.
      for (final f in _authScreens()) {
        final src = f.readAsStringSync();
        final panel =
            RegExp(r'BrandPanel\(\s*\n?\s*accent: ([^,]+),').firstMatch(src);
        final field =
            RegExp(r'PortalFieldTheme\(\s*\n?\s*accent: ([^,]+),')
                .firstMatch(src);
        expect(panel, isNotNull, reason: '${f.path}: no BrandPanel accent');
        expect(field, isNotNull, reason: '${f.path}: no field accent');
        expect(field!.group(1)!.trim(), panel!.group(1)!.trim(),
            reason: '${f.path}: the panel and the fields disagree');
      }
    });
  });

  group('PortalFieldTheme recolours everything that would stay gold', () {
    testWidgets('the focus ring takes the accent', (tester) async {
      const accent = AppTheme.appealPurple;
      late InputDecorationThemeData themed;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: PortalFieldTheme(
          accent: accent,
          child: Builder(builder: (context) {
            themed = Theme.of(context).inputDecorationTheme;
            return const SizedBox();
          }),
        ),
      ));
      final side = (themed.focusedBorder as OutlineInputBorder).borderSide;
      expect(side.color, accent,
          reason: 'a focused field is still gold on this portal');
      expect(side.width, 2);
    });

    testWidgets('so do the caret, the label and the scheme', (tester) async {
      // ⚠️ The ring alone is not enough — the floating label rides the
      // border, and the caret and checkboxes read from the scheme. Any one
      // of them left gold is the same fault in miniature.
      const accent = AppTheme.executiveTeal;
      late ThemeData themed;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: PortalFieldTheme(
          accent: accent,
          child: Builder(builder: (context) {
            themed = Theme.of(context);
            return const SizedBox();
          }),
        ),
      ));
      expect(themed.inputDecorationTheme.floatingLabelStyle?.color, accent);
      expect(themed.colorScheme.primary, accent);
      expect(themed.textSelectionTheme.cursorColor, accent);
    });

    testWidgets('but the RESTING look is untouched, so portals match',
        (tester) async {
      // The fill and the idle border must stay shared: a form should look
      // identical everywhere until the officer interacts with it.
      final base = AppTheme.lightTheme;
      late InputDecorationThemeData themed;
      await tester.pumpWidget(MaterialApp(
        theme: base,
        home: PortalFieldTheme(
          accent: AppTheme.appealPurple,
          child: Builder(builder: (context) {
            themed = Theme.of(context).inputDecorationTheme;
            return const SizedBox();
          }),
        ),
      ));
      expect(themed.fillColor, base.inputDecorationTheme.fillColor);
      expect(themed.enabledBorder, base.inputDecorationTheme.enabledBorder);
    });
  });
}
