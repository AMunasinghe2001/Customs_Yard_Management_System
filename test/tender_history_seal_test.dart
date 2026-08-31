import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/widgets/package_details_dialog.dart';

/// Renders the real Tender History against a package shaped like Costume
/// jewellery: two rounds, both already run, and a re-valuation recorded after
/// the LAST one — i.e. a new price with no tender placed for it yet.
///
/// A `tender_revaluations` row is keyed to the round that just FAILED, so that
/// 4,418.48 is the price of a tender that has not happened. It must not be
/// printed against Tender 1, and the history must say a sealed round exists.
void main() {
  final now = DateTime.now();
  final past1 = now.subtract(const Duration(days: 60));
  final past2 = now.subtract(const Duration(days: 30));

  final forfeited = ForfeitedPackageModel(
    id: 'fp-1',
    packageId: 'pkg-1',
    srNumber: 'CED/GL1/SR/33/2025',
    consigneeName: 'Test',
    forfeitedAt: past1,
    appealDeadline: now,
    reason: 'Unsold',
    yard: 'GL1',
    itemId: 'item-1',
    entryQty: 121,
    valuationCost: 5021,
  );

  Widget harness() => ProviderScope(
        overrides: [
          tenderRoundsForPackageProvider('fp-1').overrideWith((ref) async => [
                (id: 'R060', createdAt: past1, hasRun: true),
                (id: 'R025', createdAt: past2, hasRun: true),
              ]),
          tenderRevaluationsProvider('fp-1').overrideWith((ref) async => {
                // Keyed to the LAST round: the price for the NEXT tender.
                'R025': TenderRevaluationModel(
                  id: 'rv-1',
                  forfeitedPackageId: 'fp-1',
                  tenderSaleId: 'R025',
                  valuationCost: 4418.48,
                  note: null,
                  createdAt: past2,
                ),
              }),
          tenderBidsProvider('fp-1').overrideWith((ref) async => {
                'R060': [473881.98, 407052.47, 340222.96],
                'R025': [449580.34, 382750.83, 315921.32],
              }),
          tenderCommitteesProvider
              .overrideWith((ref) async => const <String, TenderCommitteeModel>{}),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TenderHistorySection(forfeited: forfeited, qty: 121),
            ),
          ),
        ),
      );

  testWidgets('the pending price is NOT printed against the last round',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    // 4,418.48 x 121 = 534,636.08 -- the figure that used to appear on
    // "Tender 1". It belongs to a tender that has not been held.
    expect(find.textContaining('534,636'), findsNothing,
        reason: 'That is the reserve price of an unheld tender.');
    expect(find.textContaining('4,418.48'), findsNothing);
  });

  testWidgets('a sealed row says the next round is withheld', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Sealed'), findsWidgets);
    expect(find.textContaining('shown once the tender is over'), findsWidgets);
  });

  testWidgets('the rounds that DID run still show their own price',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    // The Valuation Tender ran at the original valuation: 5,021 x 121.
    expect(find.textContaining('607,541'), findsOneWidget);
  });
}
