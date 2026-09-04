import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/widgets/package_details_dialog.dart';

/// A `tender_revaluations` row is the RESERVE PRICE OF THE ROUND IT IS KEYED
/// TO. Proven against live data — SR/37/2025, Pipe Tees, qty 180:
///
///   round 1  820 x180 = 147,600  vs best bid 110,700  -> unsold
///   round 2  738 x180 = 132,840  vs best bid 103,320  -> unsold
///   round 3  656 x180 = 118,080  vs best bid  95,940  -> unsold
///   round 4  574 x180 = 103,320  vs best bid 174,168  -> SOLD
///
/// Every round's bids sit below its own figure, and the round whose bid
/// finally cleared it is the one that sold. This file pins that mapping, so a
/// future "off by one" reading of the table fails here instead of shipping.
void main() {
  final now = DateTime.now();
  DateTime ago(int d) => now.subtract(Duration(days: d));

  ForfeitedPackageModel fp() => ForfeitedPackageModel(
        id: 'fp-1',
        packageId: 'pkg-1',
        srNumber: 'CED/GL1/SR/37/2025',
        consigneeName: 'Test',
        forfeitedAt: ago(200),
        appealDeadline: now,
        reason: 'Unsold',
        yard: 'GL1',
        itemId: 'item-1',
        entryQty: 180,
        valuationCost: 820,
      );

  TenderRevaluationModel rv(String round, double cost, int d) =>
      TenderRevaluationModel(
        id: 'rv-$round',
        forfeitedPackageId: 'fp-1',
        tenderSaleId: round,
        valuationCost: cost,
        note: null,
        createdAt: ago(d),
      );

  /// [lastRan] models the newest round: false = scheduled but not yet held.
  Widget harness({bool lastRan = true}) => ProviderScope(
        overrides: [
          tenderRoundsForPackageProvider('fp-1').overrideWith((ref) async => [
                (id: 'S116', createdAt: ago(126), hasRun: true),
                (id: 'S084', createdAt: ago(94), hasRun: true),
                (id: 'S052', createdAt: ago(62), hasRun: true),
                (id: 'S020', createdAt: ago(30), hasRun: lastRan),
              ]),
          tenderRevaluationsProvider('fp-1').overrideWith((ref) async => {
                'S084': rv('S084', 738, 94),
                'S052': rv('S052', 656, 62),
                'S020': rv('S020', 574, 30),
              }),
          tenderBidsProvider('fp-1').overrideWith((ref) async => {
                'S116': [110700, 94464],
                'S084': [103320, 87084],
                'S052': [95940, 79704],
                'S020': [174168, 138744, 119556],
              }),
          tenderCommitteesProvider.overrideWith(
              (ref) async => const <String, TenderCommitteeModel>{}),
          // ⚠️ The section reads this to decide whether the package's story
          // has ENDED — a decided package gets no next-tender tile. Without
          // the override it opens a real database socket under test.
          unsoldProposalsProvider.overrideWith(
              (ref) async => const <String, UnsoldProposalModel>{}),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TenderHistorySection(forfeited: fp(), qty: 180),
            ),
          ),
        ),
      );

  testWidgets('every round shows ITS OWN reserve price', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    // Round 1 ran at the original valuation; rounds 2-4 at their own figures.
    // Assert the UNIT price too: the totals alone cannot tell a correct
    // mapping from one shifted by a round (an off-by-one still prints three
    // plausible totals, just against the wrong rounds), and 103,320 also
    // happens to be a BID in round 2.
    for (final unit in ['@ 820', '@ 738', '@ 656', '@ 574']) {
      expect(find.textContaining(unit), findsOneWidget,
          reason: '$unit is the reserve price of one round.');
    }
    expect(find.textContaining('147,600'), findsOneWidget);
    expect(find.textContaining('132,840'), findsOneWidget);
    expect(find.textContaining('118,080'), findsOneWidget);
  });

  testWidgets('a package whose rounds have all run seals NOTHING',
      (tester) async {
    // Sold goods are the clearest case: the tender is over and the sale is
    // done, so there is nothing left to protect.
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Sealed'), findsNothing);
    expect(find.textContaining('shown once the tender closes'), findsNothing);
  });

  testWidgets('a round still to be held keeps its reserve sealed',
      (tester) async {
    await tester.pumpWidget(harness(lastRan: false));
    await tester.pumpAndSettle();
    expect(find.text('Sealed'), findsOneWidget);
    // 574 x 180 = 103,320 is the reserve of the round not yet held. Match the
    // unit-price part of the label: the bare total collides with a BID of the
    // same amount in an earlier round, which is not what this is testing.
    expect(find.textContaining('@ 574'), findsNothing);
    // The rounds that DID run are unaffected.
    expect(find.textContaining('147,600'), findsOneWidget);
  });

  testWidgets('the quantity multiplies the unit price', (tester) async {
    // The popup printed "@ 950 x 1" beside a table reading "@ 665 x 150": the
    // Sold rows are built from warehouse entries, where `item` is null, so the
    // caller passed a null qty and the history quietly fell back to 1.
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.textContaining('x 1)'), findsNothing,
        reason: 'A qty of 1 here means the real quantity never arrived.');
    expect(find.textContaining('180)'), findsWidgets);
  });

  test('the Sold popup passes the same qty its table cell uses', () {
    final src = File('lib/screens/packages/disposition_category_screen.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src, contains('valuationQty: row.entry?.itemCount ?? row.item?.quantity'),
        reason: 'These rows come from warehouse entries, so item is null.');
  });

  group('there is only ever ONE committee round', () {
    final src = File('lib/widgets/package_details_dialog.dart')
        .readAsStringSync();

    // ⚠️ The committee price was written BOTH onto tender_committees (where
    // the UI reads it) AND as a PENDING re-valuation — a row whose meaning is
    // "a price for a round not yet placed". The screen then drew both:
    //     Committee Tender 1   LKR 26,676,100
    //     Committee Tender 2   sealed
    // A package gets exactly one committee round, and on these pages it is
    // already over — every one carries a decided outcome.
    test('a pending figure equal to the committee price is not a new round',
        () {
      expect(src, contains('final isCommitteePrice = pending != null'));
      expect(src, contains('committee?.submittedValue != null'));
      expect(src, contains('!isCommitteePrice'));
    });

    // ⚠️ And nothing may announce a next tender after a FINAL outcome:
    // converted, auctioned, government use, removed.
    test('a decided package shows no next-tender tile', () {
      expect(src, contains('final decided = ref.watch(unsoldProposalsProvider)'));
      expect(src, contains('!decided'));
    });

    test('the seeder keys the committee price to the round that ran at it',
        () {
      final seed = File('tool/seed_test_data.dart').readAsStringSync();
      expect(seed, contains('update public.tender_revaluations set tender_sale_id'));
      // And the migration that cleaned what it had already written.
      final sql = File('postgres/10_committee_price_not_a_pending_round.sql')
          .readAsStringSync();
      expect(sql, contains('delete from public.tender_revaluations'));
      expect(sql, contains(r'do $verify$'));
    });
  });

  group('the valuation is stated once', () {
    final src = File('lib/widgets/package_details_dialog.dart')
        .readAsStringSync();

    // ⚠️ Tender History opens with the Valuation Tender — the first round and
    // the figure it ran at — so the Valuation card above it was the same fact
    // twice. And the two did not AGREE: the card showed the original
    // valuation while the first round showed the re-valuation keyed to it,
    // with nothing on screen to say which was which.
    test('the Valuation card yields to the tender history', () {
      // Matched on the guard's own words with whitespace collapsed, rather
      // than on its exact wrapping, which the formatter decides.
      final flat = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          flat,
          contains('!(widget.tenderHistoryFor != null && '
              '!widget.valuationSealedUntilSale)'));
    });

    // A package that never went to tender has no history section, and still
    // needs its valuation — so the card is kept for exactly that case.
    test('the card survives where there is no history', () {
      expect(src, contains('widget.valuationUnitCost != null &&'));
    });
  });
}
