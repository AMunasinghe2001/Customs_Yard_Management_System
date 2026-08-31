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
      expect(valuationSealed(saleEnded: false), isTrue);
    });

    test('open once the sale has run', () {
      expect(valuationSealed(saleEnded: true), isFalse);
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
    expect(find.text('Sealed'), findsOneWidget);
    // The reason has to be on screen, not only in the tooltip.
    expect(find.text('shown once the tender is over'), findsOneWidget);
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

  testWidgets('the two-line form fits the 145px Latest Valuation column',
      (tester) async {
    // The explanation is only useful if it actually fits: an overflow would
    // paint the yellow stripes over the table instead.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        body: Center(
          child: SizedBox(
              width: 145, height: 52, child: SealedValuation(compact: true)),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('shown once the tender is over'), findsOneWidget);
  });
  // The widget above is only half the protection: the real risk is a future
  // edit that renders a valuation on a LIVE sale card without passing the gate.
  // These scan the actual source, so that regression fails the suite by name.
  group('the live sale cards actually pass the gate', () {
    final dashboard =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();

    test('the tender sale card seals its valuation cell', () {
      expect(dashboard, contains('sealedUntilSale: !widget.sale.saleEnded'),
          reason: 'The Tender Sales card must hide the reserve price until '
              'the sale has run.');
    });

    test('the destruction sale card seals its valuation cell', () {
      expect(dashboard, contains('sealedUntilSale: !sale.saleEnded'),
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

  // The first version of this feature sealed only the live sale CARDS, which
  // was too narrow. A package that fails a round is re-valued and entered into
  // ANOTHER tender straight away, so the Unsold/Undestroyed tables were showing
  // the new reserve price while that new round was still open. Confirmed
  // against the real database: CED/GL1/SR/27/2026 sat in an open round
  // (CDU/TS/2026/6(Special)) with its re-valuation of 3,695.12 x 79 = 291,914
  // on screen. The gate now follows the goods, not the screen.
  group('the seal follows the goods into the next round', () {
    final dashboard =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();
    final shared =
        File('lib/screens/executive/unsold_shared.dart').readAsStringSync();

    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('Unsold Tenders seals on the newest tender round', () {
      // A scheduled-but-unheld round means its reserve price is live.
      expect(flat(dashboard),
          contains('sealed = !ordered.last.saleEnded'),
          reason: 'A re-valued package goes straight into another tender.');
    });

    test('Undestroyed seals on the newest destruction round', () {
      expect(flat(dashboard),
          contains('info.latestDestruction?.saleEnded == false'),
          reason: 'Re-destruction rounds carry the same reserve price.');
    });

    test('the shared Unsold table derives the gate itself', () {
      // Derived from `info` inside unsoldCells rather than passed by each of
      // the three portals, so a caller cannot forget it.
      expect(flat(shared),
          contains('final sealed = currentSale != null && !currentSale.saleEnded'));
      expect(flat(shared), contains('if (sealed) const DataCell(SealedValuation(compact: true))'),
          reason: 'All three portals share this one cell.');
    });
  });

  // The user walked through the whole disposal workflow to check it: Valuation
  // Tender + Tenders 1-3 (Valuation Directorate prices each), then a Top
  // Management committee, then ONE more tender at the committee's price, and
  // only if THAT fails does the package reach the DG's Unsold Goods table.
  // These pin the two rules that ordering depends on.
  group('the disposal workflow gates', () {
    final services = File('lib/services/services.dart').readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('the committee pool is EXACTLY the committee stage', () {
      // Valuation Tender + Tenders 1-3 have failed (4 rounds) and Central
      // Disposal has not re-tendered yet. Re-tendering makes 5, and the
      // package leaves for good — to Sold, or to the DG's Unsold Goods when
      // that round fails too. `>= 4` listed re-tendered packages on BOTH the
      // Tender Committees tab and the DG's tab at once.
      expect(
          flat(services),
          contains('all .where((i) => i.tenderCount == kMaxBidTenderRounds + 1) '
              '.toList()'));
      expect(flat(services), isNot(contains('i.tenderCount >= 4')));
    });

    test('the DG sees a package only after the committee-priced tender fails',
        () {
      // Reaching the DG the moment the ADG submitted would have put the final
      // outcome of a package that still had a live chance of selling in front
      // of them. Judged by when the round RAN — see the dedicated test below
      // for why createdAt was wrong.
      expect(flat(services),
          contains('moment.isAfter(submittedAt) && s.saleEnded'));
    });
  });

  // "කොහේවත්" — nowhere. Any popup that is handed a valuation must also be
  // handed the gate, or the reserve price leaks through the details dialog.
  test('every valuation-bearing popup passes the seal', () {
    final leaks = <String>[];
    for (final path in [
      'lib/screens/disposal/disposal_dashboard_screen.dart',
      'lib/screens/executive/tender_committee_tab.dart',
      'lib/screens/executive/unsold_decision_tab.dart',
      'lib/screens/packages/unsold_packages_screen.dart',
    ]) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('valuationUnitCost:')) continue;
        final lo = i - 30 < 0 ? 0 : i - 30;
        final hi = i + 30 > lines.length ? lines.length : i + 30;
        final block = lines.sublist(lo, hi).join('\n');
        if (block.contains('valuationSealedUntilSale')) continue;
        // Disposal Requests used to be exempt here: it is the stage BEFORE
        // any tender exists. But the figure is still a reserve price for
        // whatever tender it eventually joins, so it is sealed unconditionally
        // now — no exemption survives.
        leaks.add('$path:${i + 1}');
      }
    }
    expect(leaks, isEmpty,
        reason: 'These popups show a valuation with no seal:\n'
            '${leaks.join('\n')}');
  });


  // Toilet Seat Covers sat on 5 rounds and never reached the DG, while Wash
  // Basins — same 5 rounds, same shared F01 sale row — did. The rule keyed on
  // tender_sales.created_at (when the ROW was inserted, 04:25 for both), so a
  // package whose committee value was submitted after that (18:31) failed the
  // test even though F01 ran on 08-19 and failed.
  test('the DG gate keys on when a round RAN, not when its row was made', () {
    final services = File('lib/services/services.dart').readAsStringSync();
    final flat = services.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains('moment.isAfter(submittedAt) && s.saleEnded'));
    expect(flat, isNot(contains('i.sales.any((s) => s.createdAt.isAfter(submittedAt))')),
        reason: 'createdAt is when the row was inserted, not when the tender ran.');
  });

  // The details popup leaked in two more places, both showing a price for a
  // tender that had not opened yet:
  //   * Tender History rendered EVERY round's valuation, including the
  //     committee round the ADG had only just priced; and
  //   * Central Disposal's "Top Management Directorate Committee Valuation"
  //     block showed the committee figure the moment it was recorded.
  group('the popup seals a round that has not run', () {
    final dialog =
        File('lib/widgets/package_details_dialog.dart').readAsStringSync();
    final dashboard =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('each history round is gated on its OWN sale moment', () {
      expect(flat(dialog),
          contains('final sealed = !(ranById[id] ?? false)'));
      expect(flat(dialog), contains('priceLabel: (unit == null || sealed)'),
          reason: 'A round still to be tendered must not print its price.');
    });

    test('a sealed round still renders, saying why', () {
      // Dropping it would end the history early and hide that a round exists.
      expect(flat(dialog),
          contains('if (sealed) const Flexible(child: SealedValuation(compact: true))'));
    });

    test('hasRun comes from the sale moment, not created_at', () {
      final services = File('lib/services/services.dart').readAsStringSync();
      expect(flat(services),
          contains('hasRun: moment != null && DateTime.now().isAfter(moment)'));
    });

    test('the committee block waits for the committee-priced tender to run',
        () {
      expect(
          flat(dashboard),
          contains('m.isAfter(submittedAt) && x.saleEnded'),
          reason: 'Recording or submitting a figure is not the same as having '
              'tendered at it.');
      expect(flat(dashboard), contains('if (!priced) {'));
    });
  });



  // A `tender_revaluations` row is the RESERVE PRICE OF THE ROUND IT IS KEYED
  // TO. Proven against live data (SR/37/2025, Pipe Tees x180): each round's
  // bids sit below its own figure, and the round whose bid finally cleared it
  // is the one that sold. An earlier reading had this shifted by one round,
  // which printed every price against the wrong tender.
  group('a round is priced by its OWN re-valuation', () {
    final dashboard =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();
    final dialog =
        File('lib/widgets/package_details_dialog.dart').readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('the history reads the round own key', () {
      expect(flat(dialog), contains('final reval = revals[id]'));
      expect(flat(dialog), isNot(contains('revals[ordered[i - 1]]')),
          reason: 'That shift printed each price against the wrong round.');
    });

    test('a next-round tile appears only for a PENDING row', () {
      // The old one was INFERRED from a re-valuation on the last round, which
      // was the shifted reading. The caller now states it outright, and the
      // figure itself never reaches the widget — only the fact that one is
      // set — so a sealed row can say so without carrying the reserve price.
      expect(flat(dialog), contains("if (revals[''] != null) {"));
      expect(flat(dialog), isNot(contains('final pending = revals[lastId]')));
    });

    test('the table seals only while the newest round is still to run', () {
      expect(flat(dashboard),
          contains('sealed = !ordered.last.saleEnded'));
      expect(flat(dashboard), contains('sealedUntilSale: sealed'));
    });

    test('a package whose rounds have all run seals nothing', () {
      // Sold goods are the clearest case: tender over, sale done. Nothing in
      // the table rule can seal them, because sealing turns on that one flag.
      expect('sealed = true'.allMatches(flat(dashboard)).length, 0,
          reason: 'Sealing must follow the round clock, nothing else.');
    });
  });

  // The Unsold table (yard, Central Disposal and Top Management all share
  // unsoldCells) showed `committeeValue` — the committee's bare recommendation.
  // A recorded committee figure with no ADG submission is a reserve price that
  // has NOT been tendered, so printing it would leak it.
  group('the Unsold table shows the price actually tendered', () {
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('all three portals pass the SUBMITTED value', () {
      for (final path in [
        'lib/screens/disposal/disposal_dashboard_screen.dart',
        'lib/screens/executive/unsold_decision_tab.dart',
        'lib/screens/packages/unsold_packages_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        final i = src.indexOf('committeeUnitValue:');
        expect(i, greaterThan(-1), reason: path);
        // Read the argument itself rather than matching a formatted string:
        // the line wrapping puts a space before "?." and defeats that.
        final arg = src.substring(i, i + 400).replaceAll(RegExp(r'\s+'), '');
        expect(arg, contains('?.submittedValue'), reason: path);
        expect(arg, isNot(contains('?.committeeValue')),
            reason: '\$path shows a committee price that was never tendered.');
      }
    });

    test('sealing there orders rounds by the sale moment', () {
      // latestSale is newest-by-created_at, and the two can disagree.
      final shared =
          flat(File('lib/screens/executive/unsold_shared.dart').readAsStringSync());
      expect(shared, contains('final am = a.saleMoment, bm = b.saleMoment'));
      expect(shared,
          contains('final sealed = currentSale != null && !currentSale.saleEnded'));
    });
  });

  // Setting a new valuation used to OVERWRITE the round it was decided from,
  // destroying the price that round actually went to tender at. Live damage:
  // CED/GL1/SR/20/2026 round R018 ran at 5,400 and 6,800 per unit, a new
  // valuation of 5,000 was saved against it, and the history then read 5,000
  // for both. A new figure is now stored PENDING (tender_sale_id NULL) and is
  // claimed by the next round when the package is re-tendered.
  group('a new valuation never rewrites a finished round', () {
    final services = File('lib/services/services.dart').readAsStringSync();
    final valuation =
        File('lib/screens/valuation/valuation_dashboard_screen.dart')
            .readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('the dialog stores it pending once the round has run', () {
      expect(flat(valuation),
          contains('_current.saleEnded ? null : _current.id'));
    });

    test('the service accepts a null round and deletes the pending row', () {
      expect(flat(services),
          contains('String forfeitedPackageId, String? tenderSaleId'));
      expect(flat(services),
          contains("del.isNull('tender_sale_id') : del.eq('tender_sale_id'"));
    });

    test('re-tendering claims the pending valuation for the new round', () {
      // Otherwise the new round would carry no reserve and the pending row
      // would linger against every future tender.
      expect(flat(services),
          contains("update({'tender_sale_id': saleId})"));
      expect(flat(services), contains(".isNull('tender_sale_id')"));
    });

    test('eligibility requires a PENDING valuation', () {
      // A figure on the latest round is that round's own reserve and says
      // nothing about whether the next one has been priced.
      expect(flat(services), contains('if (saleId != null) continue;'));
    });
  });

  // "Re-valued" and "Committee valued" both mean a price is set for a tender
  // that has NOT been held, so the figure is a live reserve.
  group('a price for an unheld tender is sealed', () {
    final dashboard =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('the table seals Re-valued and Committee valued', () {
      expect(
          flat(dashboard),
          contains('sealed = !ordered.last.saleEnded || reTenderable || '
              'committee?.committeeValue != null'));
      expect(flat(dashboard), contains('reTenderable: eligible.contains(f.id)'));
    });

    test('"Re-valued" means the NEXT round is priced', () {
      expect(flat(dashboard), contains("final hasReval = revals[''] != null;"));
    });

    test('the history detects the pending row itself', () {
      // Derived inside TenderHistorySection, not passed by each caller, so
      // EVERY popup that shows tender history gets the sealed row.
      final dialog = File('lib/widgets/package_details_dialog.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(dialog, contains("if (revals[''] != null) {"));
      expect(dialog, isNot(contains('nextTenderValued')),
          reason: 'Two sources of truth would drift.');
    });
  });

  // Storing a new figure PENDING made it invisible to every reader that keyed
  // on the round: the Valuation Directorate's own table read "Set Value" again
  // after saving, and the Save button stayed live for a second edit.
  group('the pending valuation is visible to its own portal', () {
    final valuation =
        File('lib/screens/valuation/valuation_dashboard_screen.dart')
            .readAsStringSync();
    final services = File('lib/services/services.dart').readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('the issued figure follows the round being priced', () {
      // Pricing the NEXT round: only a PENDING row can already hold it.
      // Falling back to the current round's own reserve made the dialog read
      // "Valuation set" and hide Save before anything had been entered.
      // Matched in parts: explanatory comments sit inside the ternary, so the
      // whole expression does not survive whitespace-flattening as one string.
      expect(flat(valuation),
          contains('TenderRevaluationModel? get _issued => _current.saleEnded'));
      expect(flat(valuation), contains("? _revals[''] "),
          reason: 'Pricing the next round: only a pending row can hold it.');
      expect(flat(valuation), contains(': _revals[_current.id];'),
          reason: 'A scheduled-but-unheld round is priced directly.');
      expect(flat(valuation), contains('bool get _alreadyValued => _issued != null'),
          reason: 'A saved valuation must lock, like every other round.');
    });

    test('the table cell shows only the figure this portal still owes', () {
      expect(flat(valuation), contains("final unit = revals['']?.valuationCost;"));
    });

    test('only a pending row counts as valued', () {
      // Every held round has its own reserve, so counting those marked every
      // package valued and hid the Set Value button.
      expect(flat(services), contains('if (saleId == null) valued.add(fpId);'));
    });
  });

  test('Record Bids shows a sealed block for the next tender', () {
    // Mirrors the committee block: says a valuation exists, withholds it.
    final dashboard =
        File('lib/screens/disposal/disposal_dashboard_screen.dart')
            .readAsStringSync()
            .replaceAll(RegExp(r'\s+'), ' ');
    expect(dashboard, contains('Widget _nextTenderValuationSection() {'));
    expect(dashboard, contains('_nextTenderValuationSection(),'));
    expect(dashboard, contains("if (revals[''] == null) return const SizedBox.shrink()"),
        reason: 'A round-keyed figure belongs to that round, shown above.');
  });

  // Saving a valuation left the Valuation Directorate's own row reading
  // "Set Value", and Central Disposal's Record Bids dialog went on offering
  // "Add bid" for a round that was already priced.
  group('a pending valuation takes effect everywhere at once', () {
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('saving refreshes the providers the tables actually read', () {
      final valuation = flat(
          File('lib/screens/valuation/valuation_dashboard_screen.dart')
              .readAsStringSync());
      expect(valuation, contains('ref.invalidate(valuedCurrentRoundProvider)'));
      expect(valuation, contains('ref.invalidate(reTenderEligibleProvider)'),
          reason: 'Central Disposal reads a third provider again.');
    });

    test('bids close once a figure is issued, pending or not', () {
      final dashboard = flat(
          File('lib/screens/disposal/disposal_dashboard_screen.dart')
              .readAsStringSync());
      // Locked once the Valuation Directorate has priced the NEXT round FROM
      // these bids. NOT on the round's own reserve: that exists before any bid
      // is recorded, so it stopped bids being entered at all.
      expect(dashboard,
          contains("bool get _currentRoundLocked => _revals[''] != null;"));
    });
  });

  // The chain: a round is HELD at its own valuation, its bids come in against
  // that figure, and those bids decide the price of the NEXT round. So the
  // figure being entered prices the round AFTER the one whose bids are shown.
  // It was labelled with the current round, so a valuation for Tender 3 read
  // as "Tender 2 · New Valuation".
  group('the new-valuation panel names the round it prices', () {
    final valuation = File(
            'lib/screens/valuation/valuation_dashboard_screen.dart')
        .readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('it is the NEXT round once the current one has been held', () {
      expect(
          flat(valuation),
          contains('int get _valuedRoundIndex => _current.saleEnded ? '
              '_rounds.length + 1 : _rounds.length'),
          reason: 'Bids decide the price of the round after them.');
    });

    test('the title and the blurb both use it', () {
      expect(flat(valuation), contains("title: '\$_valuedRoundLabel · New Valuation'"));
      expect(flat(valuation),
          contains("'Decide the value for \$_valuedRoundLabel from the bids above. '"));
      // The old wording named the round whose bids are listed.
      expect(flat(valuation), isNot(contains("Decide this round’s value")));
    });

    test('it lines up with where the figure is stored', () {
      // Same condition: pricing the next round means no round id yet.
      expect(flat(valuation),
          contains('_current.saleEnded ? null : _current.id'));
    });
  });

  // The ADG's committee figure prices the round the package is about to be
  // re-tendered in, exactly like a Valuation Directorate re-valuation. Writing
  // it to the round just held overwrote that round's own reserve AND left no
  // "next round is priced" signal, so the package showed "Committee valued"
  // forever while vanishing from the Committees table.
  group('the committee submission follows the same rule', () {
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');
    final tab = flat(File('lib/screens/executive/tender_committee_tab.dart')
        .readAsStringSync());

    test('it stores pending once the round has been held', () {
      expect(tab, contains('tenderSaleId: round.saleEnded ? null : round.id'));
    });

    test('it refreshes what the two tables read', () {
      expect(tab, contains('ref.invalidate(reTenderEligibleProvider)'));
      expect(tab, contains('ref.invalidate(valuedCurrentRoundProvider)'));
    });

    test('the service accepts a null round', () {
      expect(flat(File('lib/services/services.dart').readAsStringSync()),
          contains('required String? tenderSaleId,'));
    });
  });

  // A package used to vanish from Tender Committees the moment the ADG
  // submitted, so the finished committee work disappeared and the two tables
  // disagreed about how many committee cases existed.
  group('the Committees tab keeps a submitted package', () {
    final tab = File('lib/screens/executive/tender_committee_tab.dart')
        .readAsStringSync();
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');

    test('no row is dropped for having been submitted', () {
      expect(flat(tab),
          isNot(contains('return c == null || !c.isSubmitted;')),
          reason: 'It leaves on its own once its tender has been held.');
      expect(flat(tab), contains('var rows = list.toList();'));
    });

    test('the cell already has a submitted state to show', () {
      // Green, a verified icon and a "Final" label — it simply never rendered.
      expect(flat(tab), contains("submitted ? 'Final'"));
      expect(flat(tab), contains('final submitted = c.submittedValue != null;'));
    });
  });

  // A reserve price must stay hidden for as long as bidding is OPEN. Sealing
  // on the sale's START time unsealed it at exactly the wrong moment — the
  // instant the tender opened. It now unseals only when the sale has ENDED.
  group('the seal lifts at the sale END, not its start', () {
    String flat(String x) => x.replaceAll(RegExp(r'\s+'), ' ');
    final models = flat(File('lib/models/models.dart').readAsStringSync());
    final dash = flat(File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync());

    test('both sale models expose an end moment', () {
      expect(models, contains('DateTime? get saleEndMoment => '
          'combineSaleMoment(saleDate, saleEndTime) ?? saleMoment;'));
      // Two models: tender sales and destructions.
      expect('bool get saleEnded {'.allMatches(models).length, 2);
    });

    test('a missing end time falls back to the start', () {
      // Rows created before the column existed must behave exactly as before.
      expect(models, contains('combineSaleMoment(saleDate, saleEndTime) ?? saleMoment'));
    });

    test('Mark Sold and Mark Destroyed still unlock on the START', () {
      expect(dash, contains('final canSell = widget.sale.saleTimePassed;'));
      expect(dash, contains('final canDestroy = sale.saleTimePassed;'));
    });

    test('the sale cards seal on the end', () {
      expect(dash, contains('sealedUntilSale: !widget.sale.saleEnded'));
      expect(dash, contains('sealedUntilSale: !sale.saleEnded'));
    });

    test('both forms collect an end time and validate it', () {
      // Exactly ONE field per form (2 total): a leftover partial edit once
      // duplicated it in the Tender Sale form while leaving the Destruction
      // Sale form without one at all.
      expect("label: 'Sale End Time',".allMatches(dash).length, 2);
      expect(
          "if (_saleEndTime == null) return 'Sale End Time is required.';"
              .allMatches(dash)
              .length,
          2);
      expect(dash,
          contains("if (endM <= startM) return 'Sale End Time must be after the start time.';"));
    });

    test('the sale pages call the column Latest Valuation', () {
      // Both the directorate card AND the yard's read-only view now share the
      // one name and the one seal — the yard's figure is a different number
      // (the SR item's declared value) but it is still commercially sensitive
      // to a bidder, so it is sealed on the same clock.
      expect("Center(child: const Text('Latest Valuation'))".allMatches(dash).length, 2);
    });

    test('the yard read-only column seals too, not just the directorate one',
        () {
      final flatDash = dash.replaceAll(RegExp(r'\s+'), ' ');
      expect(flatDash, contains('if (sealedUntilSale) { return const SealedValuation(compact: true); }'));
      expect(dash, isNot(contains('if (sealedUntilSale && !useItemValue)')));
    });
  });
}
