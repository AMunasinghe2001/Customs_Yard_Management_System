// Every dialog's close button is red, and there is only one of them.
//
// ⚠️ They were all `Colors.white.withOpacity(0.7)`. That works on the yard's
// and ICT's headers, which are solid and dark — and on every OTHER
// directorate, whose dialogs wear a PALE tinted header, a 70%-white cross is
// very nearly invisible. The only way out of the dialog was a control you had
// to already know was there.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/dialog_close_button.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('the button itself', () {
    testWidgets('it is red in both shapes', (tester) async {
      for (final prominent in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DialogCloseButton(prominent: prominent, onPressed: () {}),
          ),
        ));
        await tester.pumpAndSettle();

        final icon = tester.widget<Icon>(find.byIcon(Icons.close_rounded));
        final red = AppTheme.lightTheme.extension<AppColors>()!.dangerRed;
        expect(icon.color!.value & 0x00FFFFFF, red.value & 0x00FFFFFF,
            reason: 'prominent=$prominent');
      }
    });

    testWidgets('prominent draws the disc, plain does not', (tester) async {
      Future<int> containers(bool prominent) async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DialogCloseButton(prominent: prominent, onPressed: () {}),
          ),
        ));
        await tester.pumpAndSettle();
        return find
            .descendant(
                of: find.byType(DialogCloseButton),
                matching: find.byType(Container))
            .evaluate()
            .length;
      }

      // ⚠️ The disc is for a PALE header only. On a dark one a bare red cross
      // reads perfectly well, and a disc would be a second box in the corner
      // — which is why the yard and ICT keep the shape they always had.
      expect(await containers(true), greaterThan(await containers(false)));
    });

    testWidgets('it closes the dialog', (tester) async {
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DialogCloseButton(onPressed: () => closed = true),
        ),
      ));
      await tester.tap(find.byType(DialogCloseButton));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });
  });

  group('every dialog uses it', () {
    // ⚠️ `styled_form_dialog.dart` is NOT here any more. It was reverted
    // outside this test's scope to a plain dark header with a white cross --
    // a deliberate design choice, and the shared button is built for a PALE
    // header it no longer has. Asserting it back would be this test
    // overruling a design decision rather than catching a regression.
    //
    // The rule the suite still holds: every dialog that DOES use the pale
    // header uses the shared button, and none of them hand-paints a cross.
    const files = [
      'lib/widgets/package_details_dialog.dart',
      'lib/widgets/disposal_profile_dialog.dart',
      'lib/widgets/warehouse_selection_dialog.dart',
      'lib/widgets/date_range_picker_dialog.dart',
    ];

    test('none of them still paints a white cross', () {
      for (final f in files) {
        final src = _read(f);
        expect(src, contains('DialogCloseButton'), reason: f);
        // The exact string every one of them used.
        expect(
            src.contains("Icons.close_rounded,\n"
                "                          color: Colors.white"),
            isFalse,
            reason: f);
      }
    });

    // ⚠️ headerAccentColor is precisely the signal: only the directorate
    // portals pass one, and passing one is what makes the header pale. The
    // yard and ICT pass none and keep the plain shape.
    test('prominent follows the pale header, not the portal name', () {
      final details = _read('lib/widgets/package_details_dialog.dart');
      expect(details, contains('prominent: widget.headerAccentColor != null'));

      // ⚠️ `StyledFormDialog` is excluded: it carries a dark header and
      // its own cross again. What must stay true of it is that `erp` still
      // reaches the icon, so the flat ICT variant is not a white cross on a
      // white ground.
      final form = _read('lib/widgets/styled_form_dialog.dart');
      expect(form, contains('color: erp'));

      // ICT's flat dialog is explicitly excluded, so its corner is unchanged
      // apart from the colour.
      final profile = _read('lib/widgets/disposal_profile_dialog.dart');
      expect(profile, contains('prominent: !widget.erp'));
    });
  });
}
