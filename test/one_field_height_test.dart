import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One text-box height and one text-box colour, everywhere.
///
/// ⚠️ The rule is enforced by ABSENCE: the theme sets both once, and a screen
/// gets them by NOT overriding them. A survey at the time this was written
/// found nine different `vertical:` values and 46 overrides across the app, so
/// two fields side by side in one form sat at different heights — and fields
/// painted the card colour vanished into the card they sat on.
void main() {
  /// EVERY portal except the ICT console, which keeps its own denser `erp`
  /// look on purpose, and the theme itself, which is where the rule lives.
  const exempt = ['lib/screens/ict/', 'lib/core/theme.dart'];

  final padding = RegExp(
      r'contentPadding:\s*(?:const\s*)?EdgeInsets\.symmetric\(([^)]*)\)',
      dotAll: true);

  List<String> coveredFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) => p.endsWith('.dart'))
      .where((p) => !exempt.any(p.startsWith))
      .toList();

  group('every text box in the app is the same height', () {
    test('no screen hardcodes its own contentPadding', () {
      final offenders = <String>[];
      for (final path in coveredFiles()) {
        final src = File(path).readAsStringSync();
        for (final m in padding.allMatches(src)) {
          final body = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
          offenders.add('$path -> $body');
        }
      }
      expect(offenders, isEmpty,
          reason: 'these override the shared field height, so their fields '
              'will not line up with the ones beside them:\n'
              '${offenders.join("\n")}');
    });

    test('the theme is the one place that sets it', () {
      final theme = File('lib/core/theme.dart').readAsStringSync();
      expect(theme, contains('isDense: true'));
      expect(padding.hasMatch(theme), isTrue,
          reason: 'the theme no longer sets a field height at all');
    });

    test('a dropdown takes the theme height, not its own', () {
      // ⚠️ A dropdown that falls back to its own number is the subtle half of
      // this: it looks right on its own and wrong beside a TextField.
      final dd = File('lib/widgets/styled_dropdown.dart').readAsStringSync();
      expect(
          dd,
          contains('Theme.of(context).inputDecorationTheme.contentPadding'),
          reason: 'the dropdown has its own fallback height again');
    });

    test('no screen forces a dropdown out of the shared size', () {
      // `isDense: false` makes one dropdown taller than everything near it.
      final offenders = <String>[];
      for (final path in coveredFiles()) {
        if (File(path).readAsStringSync().contains('isDense: false')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'these dropdowns opt out of the shared height: '
              '${offenders.join(", ")}');
    });
  });

  group('the inside of every field is the same colour', () {
    test('the theme paints them with a field colour of their own', () {
      // ⚠️ `fieldFill` is a colour of its own, not the card's. It used to be
      // `cardDark` — what a card is painted with — so a box only showed up
      // where the page behind it happened to be white, and the same form held
      // boxes that looked grey and boxes that looked white.
      final theme = File('lib/core/theme.dart').readAsStringSync();
      expect(theme, contains('fillColor: colors.fieldFill'));
      expect(theme.contains('fillColor: colors.cardDark'), isFalse,
          reason: 'fields are painted the card colour again');
    });

    test('no screen paints a field the card or surface colour', () {
      final offenders = <String>[];
      for (final path in coveredFiles()) {
        final src = File(path).readAsStringSync();
        for (final bad in const [
          'fillColor: context.colors.cardDark,',
          'fillColor: context.colors.surfaceDark,',
        ]) {
          if (src.contains(bad)) offenders.add('$path -> $bad');
        }
      }
      expect(offenders, isEmpty,
          reason: 'these paint a field the card colour, so it disappears into '
              'the card:\n${offenders.join("\n")}');
    });
  });

  group('the SR registration form reads as one form', () {
    final src = File('lib/screens/inspection/inspection_screen.dart')
        .readAsStringSync();

    test('Next and Reset are a matched pair', () {
      // Both the same height and both shaped the same, rather than a
      // full-width slab beside a small default button.
      expect(RegExp(r'height: 44').allMatches(src).length,
          greaterThanOrEqualTo(2),
          reason: 'the two actions are not the same height');

      // ⚠️ Narrowly: the NEXT button must not be a full-width Expanded slab
      // again. A blanket ban on `height: 52` was wrong — the form's tab strip
      // is 52 too, and banning that would have pushed me to "fix" a container
      // that was never part of this.
      // ⚠️ Whitespace-insensitive: `dart format` rewraps this label whenever
      // the lines around it change width, and an exact anchor then vanishes.
      final flat = src.replaceAll(RegExp(r'\s+'), ' ');
      final anchor = flat.indexOf("'Processing...' : 'Next'");
      expect(anchor, greaterThan(0), reason: 'the Next button was renamed');
      final from = anchor - 900 < 0 ? 0 : anchor - 900;
      expect(flat.substring(from, anchor).contains('Expanded('), isFalse,
          reason: 'the full-width Next slab is back');
    });

    test('the rows are not spaced like a page', () {
      expect(src.contains('const Gap(24),'), isFalse,
          reason: 'the wide page-level gaps are back between form rows');
    });
  });
}
