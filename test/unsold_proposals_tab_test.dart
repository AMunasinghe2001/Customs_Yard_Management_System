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
          unsoldTenderSalesProvider.overrideWith((ref) => Future.value([
            ReTenderSaleInfo(forfeited: forfeited, sales: const []),
          ])),
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

    expect(find.text('Unresolved / Unsold Packages'), findsOneWidget);
    expect(find.text('SR-100'), findsWidgets);
    expect(find.text('Copper Wire'), findsOneWidget);
    expect(find.text('Destroy'), findsWidgets);
    expect(find.text('Remand'), findsWidgets);
    expect(find.text('Government Use'), findsWidgets);
    expect(find.text('Auction'), findsWidgets);
  });
}
