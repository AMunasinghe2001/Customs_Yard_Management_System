import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/theme.dart';

/// The ICT Staff Accounts controls row: a search field, three filter
/// dropdowns and the Add button, all on one line.
///
/// It painted the yellow/black overflow stripes on a normal window. `Flexible`
/// alone did NOT fix it: a DropdownButtonFormField reports an intrinsic width
/// from its label, prefix icon and longest menu item, and Flexible only lets a
/// child shrink if the child agrees to. `isExpanded: true` is what makes the
/// dropdown take the width it is given.
void main() {
  Widget dropdown({required String label, required IconData icon}) => Flexible(
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          value: 'all',
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 18),
            filled: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Yards')),
            // The longest real option — what drives the intrinsic width.
            DropdownMenuItem(
                value: 'long', child: Text('Social Protection & Security')),
          ],
          onChanged: (_) {},
        ),
      );

  Widget row() => Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by Name, Salary No, Email, Username...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        dropdown(label: 'Yard Location', icon: Icons.warehouse_outlined),
        const SizedBox(width: 14),
        dropdown(label: 'Role Filter', icon: Icons.badge_outlined),
        const SizedBox(width: 14),
        dropdown(label: 'Status', icon: Icons.filter_alt_outlined),
        const SizedBox(width: 14),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Add Officer / DC'),
        ),
      ]);

  // The screenshots showed stripes at roughly 1900 and 1536 logical pixels;
  // the app's minimum window is 1000.
  for (final w in <double>[1900, 1536, 1280, 1100, 1000]) {
    testWidgets('the controls row does not overflow at ${w.toInt()}px',
        (tester) async {
      tester.view.physicalSize = Size(w, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: row()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the row overflowed at ${w.toInt()}px');
    });
  }

  // The Create/Edit Staff dialog's own row: Account Role + Directorate side by
  // side inside a 520px dialog. The role dropdown had no isExpanded, so its
  // longest item ("DC / SDDC (Yard Admin)") overflowed the row by 49px.
  group('the staff dialog row', () {
    // dropdown() already returns a Flexible, so it goes straight into the Row.
    Widget dialogRow() => Row(children: [
          dropdown(label: 'Account Role *', icon: Icons.shield_outlined),
          const SizedBox(width: 12),
          dropdown(
              label: 'Directorate *', icon: Icons.account_balance_outlined),
        ]);

    for (final w in <double>[520, 460, 400, 340]) {
      testWidgets('does not overflow inside a ${w.toInt()}px dialog',
          (tester) async {
        tester.view.physicalSize = Size(w, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(16), child: dialogRow()),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'the dialog row overflowed at ${w.toInt()}px');
      });
    }
  });
}
