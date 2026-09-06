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
      expect(body, contains("q.isNull('proposal').eq('sold', false)"));
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
}
