// "Decided" answered a question nobody was asking.
//
// The Unsold Goods page filtered All / Awaiting decision / Decided -- but an
// officer looking at decided goods does not need to be told they were decided;
// every row says so. What they want is the ones going to auction, or back out
// of the country. "Decided" put all six outcomes in one bucket.
//
// Perishable Goods had no filter at all, and needs a seventh choice the others
// do not: a perishable that SELLS at tender ends there and never reaches the
// DG, so on that page a sale is a final outcome in its own right.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/models/models.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final unsold =
      File('lib/screens/packages/unsold_packages_screen.dart').readAsStringSync();
  final perishable =
      File('lib/screens/packages/perishable_goods_screen.dart').readAsStringSync();
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('the filter names an outcome, not a state', () {
    test('the decided/awaiting flag is gone', () {
      expect(services.contains('bool? decided,'), isFalse);
      expect(providers.contains('final bool? decided;'), isFalse);
      expect(unsold.contains('bool? _decidedFilter'), isFalse);
      // And the three chips it drove.
      expect(unsold.contains("_statusChip('Decided'"), isFalse);
      expect(unsold.contains('Widget _statusChip('), isFalse,
          reason: 'the chip helper outlived its callers');
    });

    test('the query carries an outcome instead', () {
      expect(providers, contains('final String? outcome;'));
      expect(services, contains("q = q.eq('proposal', outcome)"));
      // Awaiting is still reachable -- it is the null test the flag used.
      expect(services, contains("if (outcome == kOutcomeAwaiting)"));
    });

    test('the sentinels are not outcomes', () {
      // ⚠️ Deliberately outside kUnsoldProposals: no package is ever DECIDED
      // to be awaiting, and a sale is not a proposal.
      expect(kUnsoldProposals.contains(kOutcomeAwaiting), isFalse);
      expect(kUnsoldProposals.contains(kOutcomeSold), isFalse);
      expect(kOutcomeAwaiting, isNot(kOutcomeSold));
    });

    test('two queries differing only by outcome are not equal', () {
      const all = ExhaustedUnsoldQuery();
      const auction = ExhaustedUnsoldQuery(outcome: 'auction');
      const awaiting = ExhaustedUnsoldQuery(outcome: kOutcomeAwaiting);
      expect(all == auction, isFalse);
      expect(auction == awaiting, isFalse);
      expect(all.hashCode == auction.hashCode, isFalse);
    });

    test('the perishable query hashes it too', () {
      // ⚠️ A family key that stays equal across a filter change means the
      // provider never refetches and the table never updates.
      const a = PerishableQuery();
      const b = PerishableQuery(outcome: kOutcomeSold);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });
  });

  group('sold is a choice on Perishable and nowhere else', () {
    test('the service tells the three apart', () {
      final fn = flat(services.substring(
          services.indexOf('getPerishableRowsPaged')));
      final body = fn.substring(0, 3000);
      expect(body, contains("if (outcome == kOutcomeSold) { q = q.eq('sold', true)"));
      // ⚠️ Awaiting means NEITHER has happened. A sold row has no proposal
      // either, so testing only for a null proposal would call it awaiting.
      //
      // The three CONDITIONS, not the order they were chained in -- pinning
      // the exact expression broke this test when a fourth was added, while
      // the rule it guards had not changed at all.
      // Comment lines dropped first, from the RAW source -- flat() has
      // already collapsed the newlines out of `fn`, so there are no lines
      // left there to drop. Without this the slice starts at the doc comment
      // above the parameter, which names kOutcomeAwaiting too.
      final code = flat(services
          .substring(services.indexOf('getPerishableRowsPaged'))
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .take(120)
          .join('\n'));
      final awaiting = code.substring(code.indexOf('kOutcomeAwaiting'));
      for (final clause in [
        "isNull('proposal')",
        "eq('sold', false)",
        "eq('marked_unsold', true)",
      ]) {
        expect(awaiting.substring(0, 400), contains(clause));
      }
    });

    test('only the perishable page offers it', () {
      expect(perishable, contains('includeSold: true'));
      expect(unsold.contains('includeSold'), isFalse);
      expect(dash.contains('includeSold'), isFalse);
    });

    test('the widget puts awaiting first', () {
      // On a page waiting for the DG it is the state most rows are in.
      final f = File('lib/widgets/outcome_filter.dart').readAsStringSync();
      expect(f.indexOf("StyledDropdownOption(awaiting"),
          lessThan(f.indexOf('for (final o in outcomes)')));
    });
  });

  group('an outcome page does not filter by outcome', () {
    test('the yard hides it there', () {
      // Every row is already that outcome: the filter could only ever return
      // all of them or none.
      expect(unsold, contains('if (widget.proposalFilter == null)'));
    });

    test('Central Disposal hides it there too', () {
      expect(dash, contains('if (proposalFilter == null) ...['));
      expect(flat(dash), contains('final outcomeFilter = proposalFilter == null'));
    });

    test('the filter is keyed per tab', () {
      // ⚠️ Five outcome pages are five instances of ONE widget; a shared
      // provider would carry one page's filter into the next.
      expect(dash, contains('final _unsoldOutcomeFilterProvider ='));
      expect(dash, contains('StateProvider.family<String?, String>'));
    });

    test('changing it starts at page one', () {
      final blk = flat(dash.substring(
          dash.indexOf('_unsoldOutcomeFilterProvider(tabKey).notifier')));
      expect(blk.substring(0, 200),
          contains('_unsoldPageProvider(tabKey).notifier).state = 0'));
    });
  });

  group('the marks belong to their portal', () {
    test('a heading icon takes an accent', () {
      final f = File('lib/widgets/page_title.dart').readAsStringSync();
      expect(f, contains('final Color? accent;'));
      expect(f, contains('accent ?? context.colors.primaryGold'));
    });

    test('Central Disposal passes its green', () {
      // Gold marks on a green portal looked borrowed from somewhere else.
      expect('accent: context.colors.successGreen'.allMatches(dash).length,
          greaterThanOrEqualTo(7));
    });

    test('the held-goods pages have no mark at all', () {
      // ⚠️ These are YARD pages. The marks were only ever meant for Central
      // Disposal's tab strip.
      for (final path in [
        'lib/screens/packages/abandoned_packages_screen.dart',
        'lib/screens/packages/detained_packages_screen.dart',
        'lib/screens/packages/other_packages_screen.dart',
        'lib/screens/forfeited_packages/forfeited_packages_screen.dart',
      ]) {
        expect(File(path).readAsStringSync().contains('titleIcon:'), isFalse,
            reason: '$path has a heading icon again');
      }
    });

    test('the yard copy of Perishable has none either', () {
      // Its READ-ONLY copy is Central Disposal's and keeps one.
      final yardHeader = perishable.substring(perishable.indexOf('] else'));
      expect(yardHeader.contains('titleIcon:'), isFalse);
      expect(perishable, contains("PageTitle('Perishable Goods'"));
    });
  });

  group('every filter line has the same shape', () {
    // ⚠️ Destroyed Goods sets it, and it is three lines:
    //
    //     Title                        search   yard
    //     [filter]  ·················  [count]
    //     Table
    //
    // The outcome dropdown first went onto the TITLE row beside the yard
    // picker, which is a fourth layout: an officer moving between tabs should
    // find each control in the same place every time.
    /// Everything after the title Row -- the title Row ends at its own
    /// entrance animation, so the next Row is the filter line.
    String secondLine(String src, String titleAnchor) {
      final i = src.indexOf(titleAnchor);
      expect(i, greaterThan(-1), reason: 'no title found');
      return src.substring(src.indexOf('.animate().fadeIn(', i));
    }

    test('Perishable puts the filter on the line under the title', () {
      final per = File('lib/screens/packages/perishable_goods_screen.dart')
          .readAsStringSync();
      final ro = per.substring(per.indexOf('if (widget.readOnly) ...['),
          per.indexOf('] else'));
      final line = secondLine(ro, 'PageTitle(');
      expect(line, contains('OutcomeFilter('),
          reason: 'the filter is not on the second line');
      expect(line, contains('StatChip('));
      // Filter at the left, count at the right.
      expect(line.indexOf('OutcomeFilter('),
          lessThan(line.indexOf('const Spacer()')));
      expect(line.indexOf('const Spacer()'), lessThan(line.indexOf('StatChip(')));
    });

    test('the title row carries only the search and the yard picker', () {
      final per = File('lib/screens/packages/perishable_goods_screen.dart')
          .readAsStringSync();
      final ro = per.substring(per.indexOf('if (widget.readOnly) ...['),
          per.indexOf('] else'));
      final titleRow = ro.substring(
          ro.indexOf('PageTitle('), ro.indexOf('.animate().fadeIn('));
      expect(titleRow.contains('OutcomeFilter('), isFalse,
          reason: 'the filter is up on the title row again');
      expect(titleRow, contains('_searchBox(context)'));
      expect(titleRow, contains('YardAllFilter('));
    });

    test('Unsold Goods does the same', () {
      final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync();
      final tab = dash.substring(dash.indexOf('class UnsoldProposalsTab'));
      final line = tab.substring(0, tab.indexOf('DataTable2('));
      expect(line.indexOf('OutcomeFilter('),
          lessThan(line.indexOf('StatChip(')));
    });
  });

  group('the dropdown is drawn as a chip, like its neighbours', () {
    final dd = File('lib/widgets/styled_dropdown.dart').readAsStringSync();
    final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync();

    /// The segmented filter chip's own numbers, read from the widget rather
    /// than typed here -- if someone restyles the chips, this test says the
    /// dropdown no longer matches instead of silently drifting.
    String chipBody() {
      final i = dash.indexOf('Widget seg(String label');
      return dash.substring(i, dash.indexOf('return Row(children: [', i));
    }

    test('the chip and the dropdown share every measurement', () {
      final chip = chipBody().replaceAll(RegExp(r'\s+'), ' ');
      // The chipStyle branch, to where the default OutlinedButton begins.
      final flatDd = dd.replaceAll(RegExp(r'\s+'), ' ');
      final from = flatDd.indexOf('if (chipStyle) {');
      final to = flatDd.indexOf('return OutlinedButton.icon(', from);
      expect(from, greaterThan(-1));
      expect(to, greaterThan(from));
      final drop = flatDd.substring(from, to);
      for (final m in [
        'EdgeInsets.symmetric(horizontal: 14, vertical: 8)',
        'BorderRadius.circular(10)',
        'withOpacity(0.15)',
        'withOpacity(0.6)',
        'size: 15',
        'fontSize: 13',
        'FontWeight.w700 : FontWeight.w500',
      ]) {
        expect(chip, contains(m), reason: 'the chip changed: $m');
        expect(drop, contains(m), reason: 'the dropdown does not match: $m');
      }
    });

    test('it is opt-in, so the other twenty dropdowns are untouched', () {
      expect(dd, contains('this.chipStyle = false'));
      final f = File('lib/widgets/outcome_filter.dart').readAsStringSync();
      expect(f, contains('this.chipStyle = false'),
          reason: 'the filter forces a shape on every caller again');
    });

    test('the shape follows the company the control keeps', () {
      // ⚠️ The two portals put this in different rows, and it has to
      // match whichever it is in:
      //
      //   Central Disposal -- beside the All / Destroyed / Pending CHIPS.
      //   The yard         -- in a row of filter BUTTONS (Date Range, Post
      //                       Status Activity, the year), which are smaller
      //                       and outlined.
      //
      // Forcing the chip shape on the yard made it taller than its
      // neighbours and filled where they are not.
      final cd = File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(cd, contains('chipStyle: true'));

      final yardUnsold =
          File('lib/screens/packages/unsold_packages_screen.dart')
              .readAsStringSync();
      expect(yardUnsold.contains('chipStyle'), isFalse,
          reason: 'the yard is forcing the chip shape again');

      // Perishable has BOTH copies in one file: the read-only one is Central
      // Disposal's and takes the chip; the yard's own does not.
      final per = File('lib/screens/packages/perishable_goods_screen.dart')
          .readAsStringSync();
      final ro = per.substring(per.indexOf('if (widget.readOnly) ...['),
          per.indexOf('] else'));
      final yard = per.substring(per.indexOf('] else'));
      expect(ro, contains('chipStyle: true'));
      expect(yard.contains('chipStyle'), isFalse);
    });

    test('the colour is the portal accent, and the yard keeps gold', () {
      // Gold is the yard's: its nav rail, its other filter buttons, and this
      // button's own default. Central Disposal passes its green.
      expect(dd, contains('accentColor ?? context.colors.primaryGold'));
      final yardUnsold =
          File('lib/screens/packages/unsold_packages_screen.dart')
              .readAsStringSync();
      final i = yardUnsold.indexOf('OutcomeFilter(');
      expect(yardUnsold.substring(i, i + 400).contains('accent:'), isFalse,
          reason: 'the yard should fall through to gold');
    });

    test('a chosen value takes the portal accent, not always gold', () {
      expect(dd, contains('accentColor ?? context.colors.primaryGold'));
      final dashF = dash.replaceAll(RegExp(r'\s+'), ' ');
      expect(dashF, contains('accent: context.colors.successGreen'));
    });
  });
}
