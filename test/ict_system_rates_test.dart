// The Rates & Taxes tab actually lays out, at the width it really gets.
//
// ⚠️ Both tables here are DataTable2, which fails at RUNTIME in two ways the
// compiler cannot see: a row whose cells do not match the columns, and an
// assert that the fixed-width columns leave room for the flexible ones. The
// Sale Taxes table carries 360px of fixed columns against a single flexible
// one, so it is the table that would trip the second. Rendering it is the
// check — a layout assertion fails the test by itself.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/ict/system_rates_tab.dart';

final _now = DateTime(2026, 9, 10);

final _history = [
  AuditLogModel(
    id: 'r2',
    userId: 'u1',
    action: 'storage_rate_set',
    entityType: 'storage_rate',
    entityId: 'r2',
    createdAt: _now,
    details: const {'rate': 250.0, 'set_by': 'W. Perera'},
  ),
  // A row from before postgres/64 added `set_by`: unattributed, and it must
  // still render rather than throwing on a null author.
  AuditLogModel(
    id: 'r1',
    userId: 'u0',
    action: 'storage_rate_set',
    entityType: 'storage_rate',
    entityId: 'r1',
    createdAt: DateTime(2026, 1, 1),
    details: const {'rate': 180.0},
  ),
];

final _taxes = [
  DisposalTaxModel(
      id: 't1',
      name: 'VAT',
      percentage: 18,
      isActive: true,
      createdAt: _now),
  DisposalTaxModel(
      id: 't2',
      name: 'Withheld Levy',
      percentage: 2.5,
      isActive: false,
      createdAt: _now),
];

Widget _harness() => ProviderScope(
      overrides: [
        // ⚠️ The realtime trigger too, or its channel leaves a timer pending
        // past the end of the test.
        storageRatesChangeTriggerProvider.overrideWith((ref) => Stream.value(0)),
        storageRateProvider
            .overrideWith((ref) => Future.value({_now: 250.0})),
        storageRateHistoryProvider.overrideWith((ref) => Future.value(_history)),
        taxesProvider.overrideWith((ref) => Future.value(_taxes)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SystemRatesTab(accent: Color(0xFF8E3A5F)),
        ),
      ),
    );

void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
  }

  testWidgets('both sections render with their rows', (tester) async {
    await pump(tester, 1600);

    expect(find.text('Storage Rate'), findsOneWidget);
    expect(find.text('Sale Taxes'), findsOneWidget);
    expect(find.text('Set Rate'), findsOneWidget);
    expect(find.text('Add Levy'), findsOneWidget);

    // The history renders, author and all, including the row that has none.
    expect(find.text('W. Perera'), findsOneWidget);
    expect(find.text('VAT'), findsOneWidget);
    expect(find.text('Withheld Levy'), findsOneWidget);
  });

  // ⚠️ The real reason this file exists. ICT's content column is narrower than
  // the window, so the tables must survive a width the assert would catch.
  testWidgets('the tables survive a narrow content column', (tester) async {
    await pump(tester, 1100);
    expect(find.text('Sale Taxes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
