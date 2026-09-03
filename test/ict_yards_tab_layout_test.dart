// The Yards & Directorates tab actually lays out.
//
// ⚠️ This tab is the one ICT screen that scrolls its whole page, so it is the
// one that can hit an unbounded-height layout error — and the only ICT table
// built by hand rather than by DataTable2, so nothing else would catch it.
// Rendering it here is the check; a layout assertion fails the test on its
// own, without needing anything asserted about it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/ict/yard_directorate_tab.dart';

const _directorates = [
  DirectorateModel(code: 'CED', name: 'Customs Enforcement', srPrefix: 'CED'),
  DirectorateModel(code: 'BA', name: 'Baggage / Airport', srPrefix: 'B/A'),
  DirectorateModel(
      code: 'EXD', name: 'Export Directorate', srPrefix: 'EXD', isActive: false),
];

const _yards = [
  YardModel(code: 'GL1', name: 'Grey Line 1', srPrefix: 'GL1'),
  YardModel(code: 'NNR', name: 'New North Road', srPrefix: 'NNR'),
];

Widget _harness({
  List<DirectorateModel> directorates = _directorates,
  List<YardModel> yards = _yards,
}) =>
    ProviderScope(
      overrides: [
        directoratesProvider.overrideWith((ref) => Future.value(directorates)),
        yardsProvider.overrideWith((ref) => Future.value(yards)),
        yardDirectoratesProvider.overrideWith((ref) => Future.value({
              'GL1': ['CED'],
              'NNR': ['CED', 'BA'],
            })),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: YardDirectorateTab(accent: Color(0xFF8E3A5F)),
        ),
      ),
    );

void main() {
  // Wide enough for both tables: a narrow view would overflow on WIDTH and
  // report a failure that says nothing about the layout under test.
  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  testWidgets('both sections render inside their own cards', (tester) async {
    await pump(tester, _harness());

    // Each section names itself on its card header, with its count and its
    // Add button beside it — the header that used to float above the table.
    expect(find.text('Directorates'), findsOneWidget);
    expect(find.text('Yards'), findsOneWidget);
    expect(find.text('Add Directorate'), findsOneWidget);
    expect(find.text('Add Yard'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // directorates
    expect(find.text('2'), findsOneWidget); // yards
  });

  testWidgets('the rows are there, headings uppercased', (tester) async {
    await pump(tester, _harness());

    expect(find.text('Customs Enforcement'), findsOneWidget);
    expect(find.text('Grey Line 1'), findsOneWidget);
    // The hand-built heading row follows the same rule as every DataTable2 in
    // the console — see IctTableTheme.
    expect(find.text('SR PREFIX'), findsOneWidget);
    expect(find.text('EXAMPLE SR'), findsOneWidget);
  });

  testWidgets('a deactivated row still says so, at the console pill width',
      (tester) async {
    await pump(tester, _harness());

    // Two directorates active + two yards active = 4; one directorate off.
    expect(find.text('ACTIVE'), findsNWidgets(4));
    expect(find.text('INACTIVE'), findsOneWidget);
  });

  testWidgets('an empty section shows the empty state, not a bare card',
      (tester) async {
    await pump(tester, _harness(directorates: const [], yards: const []));

    expect(find.text('No directorates yet'), findsOneWidget);
    expect(find.text('No yards yet'), findsOneWidget);
  });
}
