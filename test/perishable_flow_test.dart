// The perishable path, which differs from the normal one at every step.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/post_status_activities.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final form = _read('lib/screens/inspection/inspection_screen.dart');
  final perishablePage =
      _read('lib/screens/packages/perishable_goods_screen.dart');
  final exec = _read('lib/screens/executive/executive_dashboard_screen.dart');
  final decision = _read('lib/screens/executive/unsold_decision_tab.dart');

  group('the SR form asks nothing that cannot apply', () {
    // ⚠️ Category routes goods to a WAREHOUSE ZONE. A perishable never reaches
    // a warehouse, so the field has nothing to decide and the zone-capacity
    // hint under it would report space the goods will never occupy.
    test('category is hidden for a perishable', () {
      // The field itself, and the zone-capacity hint that follows it.
      expect(form, contains('if (widget.row.nature != kNaturePerishable) ...['));
      expect(
          'if (widget.row.nature != kNaturePerishable)'.allMatches(form).length,
          greaterThanOrEqualTo(2),
          reason: 'the Category field AND its zone hint are both hidden');
    });

    // ⚠️ Every activity, not the status's own subset. A perishable has NO
    // status, so the filtered list left it with nothing to choose from.
    test('every post-status activity is offered', () {
      expect(form, contains('final activities = kAllPostStatusActivities;'));
      expect(kAllPostStatusActivities, contains('Supposed to be Sold / Auction'));
      expect(kAllPostStatusActivities, contains('Supposed to be Destroyed'));
      expect(kAllPostStatusActivities, contains('Pending Inquiry'));
      expect(kAllPostStatusActivities, contains('Pending Licence'));
    });

    test('the two forms offer the same activities', () {
      // The edit dialog must not drop an activity the SR form allowed.
      final dialog = _read('lib/widgets/package_details_dialog.dart');
      expect(dialog, contains('final activities = kAllPostStatusActivities;'));
    });
  });

  group('warehouse confirmation tells the truth', () {
    // "Assign each item to its destination warehouse" over goods that will
    // never see one told the officer to do something impossible.
    test('a perishable-only package says no warehouse is needed', () {
      expect(form, contains('NO WAREHOUSE NEEDED'));
      expect(form, contains('else if (_allPerishable)'));
    });

    // ⚠️ EVERY item, not any: a mixed package still has normal goods that need
    // a warehouse, and hiding the allocation would strand them.
    test('a mixed package still gets the allocation step', () {
      expect(form,
          contains('items.every((i) => i.nature == kNaturePerishable)'));
    });
  });

  group('a perishable waits for nothing', () {
    // A countdown read as an appeal window running down — and a perishable has
    // no appeal window at all.
    test('the Perishable table has no Waiting column', () {
      expect(perishablePage.contains("Text('Waiting')"), isFalse);
      expect(perishablePage.contains('_WaitingChip'), isFalse);
    });
  });

  group('Top Management sees perishables on their own page', () {
    test('the tab exists', () {
      expect(exec, contains("Text('Unsold Perishables')"));
      expect(exec, contains('UnsoldDecisionTab(perishable: true)'));
    });

    // ⚠️ The count, the Tab widgets and the TabBarView children must move
    // together: a short controller still PAINTS every tab, but clicks resolve
    // against the shorter one, so tapping does nothing while swiping works.
    test('the tab count matches the tabs and the views', () {
      final count =
          int.parse(RegExp(r'_kTabCount = (\d+)').firstMatch(exec)!.group(1)!);
      final tabs = RegExp(r'^\s{18}Tab\(', multiLine: true)
          .allMatches(exec)
          .length;
      final viewBlock = exec.substring(exec.indexOf('children: const ['));
      final views = viewBlock
          .substring(0, viewBlock.indexOf('],'))
          .split('\n')
          .where((l) => RegExp(r'^\s+[A-Z]\w*\(').hasMatch(l))
          .length;
      expect(tabs, count, reason: 'a Tab was added without the count');
      expect(views, count, reason: 'a view was added without the count');
    });

    // ⚠️ Perishables get ONE chance. Normal goods run the Valuation Tender
    // plus Tenders 1-3, a committee valuation and one more round.
    test('no committee and no round count gate the perishable list', () {
      final services = _read('lib/services/services.dart');
      final fn = services.substring(
          services.indexOf('Future<List<ReTenderSaleInfo>> getUnsoldPerishables'));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body.contains('kMaxBidTenderRounds'), isFalse,
          reason: 'a perishable is not gated on the round count');
      expect(body.contains('committee'), isFalse,
          reason: 'a perishable never reaches a committee');
      // ⚠️ It judges on the SOURCE, not the item's nature through a join.
      // postgres/07_perishable_source.sql made 'perishable' a real
      // forfeited_packages source, so the row says what the goods are.
      expect(body, contains("source == 'perishable'"));
    });
  });

  group('the two decision lists stay apart', () {
    // ⚠️ Both tabs are built from one widget and live in the same TabBarView,
    // so shared filter state would let a search typed on one filter the other.
    test('filter state is keyed by list', () {
      expect(decision, contains('StateProvider.family<String, bool>'));
      expect(decision, contains('_uSearchProvider(perishable)'));
      expect(decision, contains('_uPageProvider(perishable)'));
    });

    test('each list watches its own provider', () {
      expect(decision,
          contains('perishable ? unsoldPerishablesProvider : exhaustedUnsoldProvider'));
    });
  });
}
