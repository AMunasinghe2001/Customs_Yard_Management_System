import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/disposal/disposal_dashboard_screen.dart';

void main() {
  testWidgets('shows live unsold package data and proposal actions', (tester) async {
    final now = DateTime.now();
    final item = PackageItem(
      id: 'item-1',
      packageId: 'pkg-1',
      itemName: 'Copper Wire',
      quantity: 12,
    );
    final pkg = PackageModel(
      id: 'pkg-1',
      srNumber: 'SR-100',
      caseNumber: 'CASE-100',
      consigneeName: 'Test Consignee',
      status: 'forfeited',
      createdAt: now,
      updatedAt: now,
      items: [item],
      warehouseEntries: const [],
    );
    final forfeited = ForfeitedPackageModel(
      id: 'fp-1',
      packageId: 'pkg-1',
      srNumber: 'SR-100',
      consigneeName: 'Test Consignee',
      forfeitedAt: now,
      appealDeadline: now.add(const Duration(days: 2)),
      reason: 'Unsold tender',
      yard: 'Yard A',
      source: 'forfeit',
      packageDetails: pkg,
      itemId: item.id,
      itemName: item.itemName,
      valuationCost: 15000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The tab reads exhaustedUnsoldProvider ("every avenue exhausted"),
          // not unsoldTenderSalesProvider. Overriding the latter left the real
          // provider live, so the widget queried a database that isn't there
          // and rendered an empty table.
          exhaustedUnsoldProvider.overrideWith((ref) => Future.value([
                ReTenderSaleInfo(forfeited: forfeited, sales: const []),
              ])),
          // Also stubbed, for the same reason: both are read during build.
          unsoldProposalsProvider.overrideWith(
              (ref) => Future.value(const <String, UnsoldProposalModel>{})),
          storageRateProvider.overrideWith(
              (ref) => Future.value(const <DateTime, double>{})),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: UnsoldProposalsTab(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // The tab's default title. It was renamed from the old
    // "Unresolved / Unsold Packages" when the outcome tabs were split out, and
    // this assertion was left behind pointing at a string the app no longer
    // renders anywhere.
    expect(find.text('Unsold Goods'), findsOneWidget);

    // The package itself renders.
    expect(find.text('SR-100'), findsWidgets);
    expect(find.text('Copper Wire'), findsOneWidget);
    expect(find.text('Test Consignee'), findsWidgets);

    // The count pill reflects the one overridden row.
    expect(find.text('1'), findsWidgets);

    // With no outcome recorded yet, the Final Outcome column reads as awaiting
    // the Top Management Directorate rather than showing a decision.
    expect(find.text('Awaiting Top Management Directorate'), findsWidgets);
  });

  testWidgets('shows the recorded final outcome once one exists',
      (tester) async {
    // Central Disposal's tab is READ-ONLY: the outcome is chosen in the Top
    // Management Directorate's portal (unsold_decision_tab.dart) and this tab
    // only reports it. The old version of this test expected Destroy / Remand /
    // Government Use / Auction action buttons here, which is a capability this
    // widget deliberately no longer has.
    final now = DateTime.now();
    final item = PackageItem(
      id: 'item-1',
      packageId: 'pkg-1',
      itemName: 'Copper Wire',
      quantity: 12,
    );
    final pkg = PackageModel(
      id: 'pkg-1',
      srNumber: 'SR-100',
      caseNumber: 'CASE-100',
      consigneeName: 'Test Consignee',
      status: 'forfeited',
      createdAt: now,
      updatedAt: now,
      items: [item],
      warehouseEntries: const [],
    );
    final forfeited = ForfeitedPackageModel(
      id: 'fp-1',
      packageId: 'pkg-1',
      srNumber: 'SR-100',
      consigneeName: 'Test Consignee',
      forfeitedAt: now,
      appealDeadline: now.add(const Duration(days: 2)),
      reason: 'Unsold tender',
      yard: 'Yard A',
      source: 'forfeit',
      packageDetails: pkg,
      itemId: item.id,
      itemName: item.itemName,
      valuationCost: 15000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exhaustedUnsoldProvider.overrideWith((ref) => Future.value([
                ReTenderSaleInfo(forfeited: forfeited, sales: const []),
              ])),
          unsoldProposalsProvider.overrideWith((ref) => Future.value({
                'fp-1': UnsoldProposalModel(
                  id: 'prop-1',
                  forfeitedPackageId: 'fp-1',
                  proposal: 'government_use',
                  note: null,
                  yard: 'Yard A',
                  decidedAt: now,
                ),
              })),
          storageRateProvider.overrideWith(
              (ref) => Future.value(const <DateTime, double>{})),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: UnsoldProposalsTab(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('SR-100'), findsWidgets);
    // The decision is reported, not offered as a choice.
    expect(find.text('Government Use'), findsWidgets);
    expect(find.text('Awaiting Top Management Directorate'), findsNothing);
  });
}
