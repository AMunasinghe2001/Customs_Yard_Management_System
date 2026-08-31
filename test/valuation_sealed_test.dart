import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/sealed_valuation.dart';

void main() {
  // The valuation is the RESERVE PRICE. Showing it while bidding is open tells
  // anyone who sees it the lowest bid that will be accepted, which is exactly
  // the collusion risk management asked us to close.
  group('valuationSealed', () {
    test('sealed while the sale has not yet run', () {
      expect(valuationSealed(saleTimePassed: false), isTrue);
    });

    test('open once the sale has run', () {
      expect(valuationSealed(saleTimePassed: true), isFalse);
    });
  });

  testWidgets('the sealed placeholder says WHY the figure is missing',
      (tester) async {
    // An empty cell reads as "not valued yet" and sends someone hunting for the
    // number elsewhere; the placeholder has to be explicit.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: Center(child: SealedValuation())),
    ));
    expect(find.text('Sealed until sale'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(SealedValuation.tooltip, contains('reserve price'));
  });

  testWidgets('compact form fits a narrow table cell', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        body: Center(
          child: SizedBox(width: 120, child: SealedValuation(compact: true)),
        ),
      ),
    ));
    // A 120px column is what the tender-sale table gives this cell.
    expect(tester.takeException(), isNull);
    expect(find.text('Sealed'), findsOneWidget);
  });
  // The widget above is only half the protection: the real risk is a future
  // edit that renders a valuation on a LIVE sale card without passing the gate.
  // These scan the actual source, so that regression fails the suite by name.
  group('the live sale cards actually pass the gate', () {
    final dashboard =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();

    test('the tender sale card seals its valuation cell', () {
      expect(dashboard, contains('sealedUntilSale: !widget.sale.saleTimePassed'),
          reason: 'The Tender Sales card must hide the reserve price until '
              'the sale has run.');
    });

    test('the destruction sale card seals its valuation cell', () {
      expect(dashboard, contains('sealedUntilSale: !sale.saleTimePassed'),
          reason: 'The Destructions card must hide the reserve price until '
              'the destruction sale has run.');
    });

    test('both details popups seal the valuation too', () {
      // The popup is just another way to read the same number.
      expect('valuationSealedUntilSale:'.allMatches(dashboard).length,
          greaterThanOrEqualTo(2),
          reason: 'Both the tender and destruction popups must pass the gate.');
    });

    test('the popup seals the per-round tender history as well', () {
      // Each round in the history carries its own valuation.
      final dialog =
          File('lib/widgets/package_details_dialog.dart').readAsStringSync();
      // Collapse whitespace so this survives reformatting and CRLF/LF
      // differences — it is the condition that matters, not the layout.
      final flat = dialog.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          flat,
          contains('widget.tenderHistoryFor != null && '
              '!widget.valuationSealedUntilSale'),
          reason: 'Tender history exposes every round\'s valuation.');
    });
  });
}
