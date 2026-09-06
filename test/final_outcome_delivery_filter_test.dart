// Three things, all about the Final Outcome pages.
//
// 1. Destroyed Goods had All / Destroyed / Pending; the four outcome pages had
//    nothing, so an officer could not ask "what is still waiting to be handed
//    over" on the pages where handing over is the whole job.
// 2. Re-export was a decision the DG could always make -- it is in
//    kUnsoldProposals and unsoldProposalLabel renders it -- but no page in the
//    app showed the result, so goods sent back out of the country left Unsold
//    Goods and appeared nowhere.
// 3. The filter row and the count pill sat on two lines with a gap under each,
//    about 60px of chrome above a table whose whole job is showing rows.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/models/models.dart';

void main() {
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();

  group('the outcome pages can filter by delivery', () {
    test('the shared tab carries the control', () {
      expect(dash, contains('_unsoldDeliveryFilterProvider'));
      // The same segmented widget Sold and Destroyed use, so all six pages
      // filter the same way.
      expect(dash, contains('_DeliverySegmentedFilter'));
    });

    test('the filter is keyed per page, not shared across the four', () {
      // ⚠️ Government Use, Auction, Re-export, Converted and Removed are five
      // instances of ONE widget. A single provider would carry one page's
      // filter into the next, exactly as the page number would.
      expect(providers, isNot(contains('StateProvider<bool?>((ref) => null)')));
      final decl = dash.substring(dash.indexOf('_unsoldDeliveryFilterProvider ='));
      expect(decl.substring(0, 200),
          contains('StateProvider.family<bool?, String>'));
    });

    test('Unsold Goods itself does NOT get the control', () {
      // Nothing has been decided there, so there is nothing to hand over --
      // an All/Pending/Delivered filter would filter on a column every row
      // shares.
      expect(dash, contains('if (proposalFilter != null)'));
      // ⚠️ Matched without the line break: the file is CRLF, so a literal
      // '\n' in the expectation never matches.
      expect(dash, contains('proposalFilter == null'));
      expect(dash, contains('? null'));
    });

    test('changing it starts at page one', () {
      final blk = dash.substring(dash.indexOf('_unsoldDeliveryFilterProvider(tabKey).notifier'));
      expect(blk.substring(0, 300),
          contains('_unsoldPageProvider(tabKey).notifier).state = 0'));
    });
  });

  group('the filter reaches SQL, not a Dart list', () {
    test('the service takes it', () {
      expect(services, contains('bool? delivered,'));
      expect(services, contains("q = q.eq('delivered', true)"));
    });

    test('Pending includes a package with no outcome row yet', () {
      // ⚠️ A NULL delivered means the join found no proposal. eq(false) alone
      // would drop those, hiding undecided packages from Pending entirely.
      expect(services,
          contains("q.or('delivered.is.null,delivered.eq.false')"));
    });

    test('the query type compares AND hashes it', () {
      // ⚠️ Both. A family key that stays equal across a filter change means
      // the provider never refetches and the table never updates.
      expect(providers, contains('other.delivered == delivered'));
      final hash = providers.substring(
          providers.indexOf('int get hashCode => Object.hash(page, search, yard'));
      expect(hash.substring(0, 160), contains('delivered'));
    });

    test('two queries differing only by the filter are not equal', () {
      const all = ExhaustedUnsoldQuery(proposal: 're_export');
      const pending =
          ExhaustedUnsoldQuery(proposal: 're_export', delivered: false);
      const done =
          ExhaustedUnsoldQuery(proposal: 're_export', delivered: true);
      expect(all == pending, isFalse);
      expect(pending == done, isFalse);
      expect(all.hashCode == pending.hashCode, isFalse);
    });

    test('the provider passes it through', () {
      expect(providers, contains('delivered: q.delivered,'));
    });
  });

  group('Re-export has a page at last', () {
    test('the outcome was always available to the DG', () {
      // This is why the missing page was a hole rather than a feature: the
      // decision could be made, it just could not be seen.
      expect(kUnsoldProposals, contains('re_export'));
      expect(unsoldProposalLabel('re_export'), 'Re-export');
    });

    test('Central Disposal has a tab for it', () {
      expect(dash, contains("proposalFilter: 're_export'"));
      expect(dash, contains("tabKey: 'outcome-re-export'"));
      expect(dash, contains("title: 'Re-export Goods'"));
    });

    test('the controller length matches BOTH the tabs and the bodies', () {
      // ⚠️ This found a bug that was already there: length said 16 while
      // there were 15 tabs and 15 bodies. Flutter tolerates a length ABOVE
      // the child count -- the extra index just has nothing to show -- so it
      // sat unnoticed. Adding Re-export made the real count 16, which is why
      // the number did not have to change.
      final len = RegExp(r'length: (\d+),').firstMatch(dash)!.group(1)!;

      final strip =
          dash.substring(dash.indexOf('TabBar('), dash.indexOf('TabBarView('));
      final tabs = "Text('".allMatches(strip).length;

      final viewStart = dash.indexOf('TabBarView(');
      final view = dash.substring(viewStart, dash.indexOf('\n          ],', viewStart));
      final bodies = RegExp(
              r'^\s+(UnsoldProposalsTab|_[A-Z][A-Za-z]*Tab|TaxesTab|ExpensesTab|ReportsScreen|PerishableGoodsScreen)\(',
              multiLine: true)
          .allMatches(view)
          .length;

      expect(tabs, int.parse(len), reason: '$tabs tabs but length $len');
      expect(bodies, int.parse(len), reason: '$bodies bodies but length $len');
    });

    test('the yard side has the page too', () {
      final router = File('lib/core/router.dart').readAsStringSync();
      expect(router, contains("path: '/re-export-packages'"));
      expect(router, contains("proposalFilter: 're_export'"));
      final rail = File('lib/widgets/app_shell.dart').readAsStringSync();
      expect(rail, contains("'/re-export-packages'"));
    });

    test('it uses the icon the app already gave re-export', () {
      // unsold_shared.dart has mapped re_export to a departing plane since
      // before this page existed -- the new page reuses it rather than
      // inventing a second mark for the same thing.
      final shared =
          File('lib/screens/executive/unsold_shared.dart').readAsStringSync();
      expect(shared, contains('Icons.flight_takeoff_rounded'));
      expect(dash, contains('titleIcon: Icons.flight_takeoff_rounded'));
    });
  });

  group('the filter and the count share one line', () {
    test('Sold reads its count from the same async value as the table', () {
      // ⚠️ Moving the pill above the `data:` callback means it no longer has
      // `total` in scope. Reading valueOrNull keeps one source of truth: the
      // number and the list cannot disagree.
      expect(dash, contains("label: 'Sold in \$yardLabel'"));
      expect(dash, contains('if (sold.valueOrNull != null)'));
    });

    test('Destroyed does the same', () {
      expect(dash, contains('if (destroyed.valueOrNull != null)'));
      expect(dash, contains("label: 'Destroyed in \$yardLabel'"));
    });

    test('the old stacked pill is gone from both', () {
      // It was a Padding(bottom: 14) wrapping the StatChip, under a filter row
      // that already had a Gap(14) of its own.
      expect(
          dash,
          isNot(contains("padding: const EdgeInsets.only(bottom: 14),\n"
              "                      child: StatChip(")));
    });

    test('the outcome pages put their pill on the filter line too', () {
      final tab = dash.substring(dash.indexOf('class UnsoldProposalsTab'));
      // Everything above the table: the header, the filter line, the pill.
      final row = tab.substring(0, tab.indexOf('DataTable2('));
      expect(row, contains('_DeliverySegmentedFilter'));
      expect(row, contains('StatChip('));
      // One Row, so one line: the Spacer between them is what puts the count
      // on the right.
      expect(row, contains('const Spacer(),'));
    });
  });
}
