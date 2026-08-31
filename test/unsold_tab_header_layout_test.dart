import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/disposal/disposal_dashboard_screen.dart';

/// Guards the header-Row overflow that used to throw
/// "A RenderFlex overflowed by 47 pixels on the right" at 752px wide.
///
/// The search box (300) and yard filter (220) are fixed widths, so the title
/// must be the part that gives. Narrow widths are the real case here: the
/// dashboard's own nav rail eats into the window, and the app's minimum window
/// is 1000px.
void main() {
  Widget harness(String title) => ProviderScope(
        overrides: [
          exhaustedUnsoldProvider
              .overrideWith((ref) => Future.value(const <ReTenderSaleInfo>[])),
          unsoldProposalsProvider.overrideWith(
              (ref) => Future.value(const <String, UnsoldProposalModel>{})),
          storageRateProvider.overrideWith(
              (ref) => Future.value(const <DateTime, double>{})),
          // Stubbed for the same reason as the others: the Valuation column now
          // reads the Top Management committee's figure, and without this the
          // widget opens a real socket to PostgreSQL.
          tenderCommitteesProvider.overrideWith(
              (ref) => Future.value(const <String, TenderCommitteeModel>{})),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: UnsoldProposalsTab(title: title)),
        ),
      );

  for (final width in <double>[1400, 900, 752, 700, 620]) {
    testWidgets('header does not overflow at ${width.toInt()}px',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness('Unsold Goods'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the longest real tab title still does not overflow',
      (tester) async {
    // The widest title any tab passes today.
    tester.view.physicalSize = const Size(752, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness('Removed from the Premises'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
