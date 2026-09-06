// Three things the tender page got wrong.
//
// 1. Marking an item Unsold navigated to Re-export. `animateTo(10)` was
//    written when 10 meant Unsold Tenders; adding the Re-export tab shifted
//    every index after Auction and nothing complained, so the officer was
//    thrown to a page about goods leaving the country -- with a RED bar over
//    it, as though something had failed.
// 2. The page opened two different kinds of dialog: StyledFormDialog for its
//    forms and a bare AlertDialog for its confirmations. The confirmation --
//    the one asking the officer to commit -- was the plainer of the two.
// 3. Nothing said what marking an item Unsold would actually do. The route
//    changes at round 4: rounds 2-4 go back to tender after Valuation
//    re-prices them, round 5 goes to a Top Management committee, and past that
//    the package has run out of road.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/disposal/disposal_dashboard_screen.dart';

void main() {
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('tabs are addressed by name, never by number', () {
    test('the enum lists them in strip order', () {
      // ⚠️ The order IS the contract: DisposalTab.reExport must be the tab the
      // strip shows eleventh, or every lookup after it is wrong.
      const expected = [
        'disposalRequests', 'tenderSales', 'unsoldTenders', 'committees',
        'perishable', 'soldGoods', 'unsoldGoods', 'destroyedGoods',
        'governmentUse', 'auction', 'reExport', 'converted', 'removed',
        'taxes', 'expenses', 'reports',
      ];
      expect(DisposalTab.values.map((t) => t.name).toList(), expected);
    });

    test('the enum matches the labels the strip actually renders', () {
      final strip =
          dash.substring(dash.indexOf('TabBar('), dash.indexOf('TabBarView('));
      final labels = RegExp(r"Text\('([^']+)'\)")
          .allMatches(strip)
          .map((m) => m.group(1)!)
          .toList();
      expect(labels.length, DisposalTab.values.length,
          reason: '${labels.length} tabs but ${DisposalTab.values.length} '
              'enum entries');
      // Spot-check the two the bug turned on.
      expect(labels[DisposalTab.unsoldTenders.index], 'Unsold Tenders');
      expect(labels[DisposalTab.reExport.index], 'Re-export');
    });

    test('no raw animateTo survives', () {
      // ⚠️ Comments dropped first: the enum's own doc NAMES the old
      // animateTo(10) to explain why it is gone, and a plain search reads
      // that as the call still being there.
      final code = dash
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(RegExp(r'animateTo\(\d').hasMatch(code), isFalse,
          reason: 'a tab is being addressed by number again');
      // ⚠️ And nothing navigates at all now: the officer is working THROUGH a
      // sale, marking items one after another, and a jump means going back
      // before the next one can be marked. The row leaves the page on its own
      // and the message says where it went.
      expect(code.contains('animateTo('), isFalse,
          reason: 'marking an item navigates away again');
    });

    test('the controller length comes from the enum', () {
      expect(dash, contains('length: DisposalTab.values.length'));
    });

    test('the snackbar is not dressed as an error', () {
      // ⚠️ Marking an item unsold is a completed action. Red beside a page the
      // officer did not ask for read as a failure when nothing was wrong.
      final fn = flat(dash.substring(dash.indexOf('Future<void> _markUnsold')));
      // The whole method, to its closing brace -- it grew when the round
      // lookup was added ahead of the dialog.
      final body = fn.substring(0, 3400);
      expect(body, contains('backgroundColor: context.colors.warningAmber'));
      expect(body.contains('dangerRed'), isFalse);
    });
  });

  group('the route out of Unsold is spelled out', () {
    test('round 1 is the Valuation Tender, not Tender 1', () {
      // The first attempt is priced by the Valuation Directorate, not by bids.
      expect(tenderRoundLabel(1), 'Valuation Tender');
      expect(tenderRoundLabel(2), 'Tender 1');
      expect(tenderRoundLabel(4), 'Tender 3');
      expect(tenderRoundLabel(5), 'Committee Tender 1');
    });

    test('after 1 round it goes back to tender, re-priced', () {
      final s = nextStepAfterUnsold(1);
      expect(s, contains('Tender 1'));
      expect(s, contains('re-prices'));
    });

    test('after 4 rounds a committee is appointed, not another tender', () {
      // ⚠️ This is where the route changes, and the reason the count has to be
      // on screen: Tenders 1-3 are exhausted.
      final s = nextStepAfterUnsold(4);
      expect(s, contains('committee'));
      expect(s, contains('Top Management'));
      expect(s.contains('goes to Tender'), isFalse);
    });

    test('past the committee round it has run out of road', () {
      final s = nextStepAfterUnsold(5);
      expect(s, contains('Every avenue is exhausted'));
      expect(s, contains('final outcome'));
    });

    test('the count is one SQL count, read on the tap', () {
      expect(services, contains('Future<int> tenderRoundCount('));
      final fn = flat(services.substring(services.indexOf('tenderRoundCount')));
      expect(fn.substring(0, 400), contains("from('tender_sale_items')"));
      expect(fn.substring(0, 400), contains(".eq('forfeited_package_id'"));
      expect(fn.substring(0, 400), contains('.count()'));
    });

    test('a failed count still lets the officer record the outcome', () {
      // ⚠️ The count is context, not permission.
      final fn = flat(dash.substring(dash.indexOf('Future<void> _markUnsold')));
      expect(fn.substring(0, 1200), contains('} catch (_) {'));
      expect(fn.substring(0, 1600), contains('ConfirmDialog.show('));
    });

    test('the badge tooltip says where it is and where it goes', () {
      final fn = flat(dash.substring(dash.indexOf('class _AttemptsBadge')));
      expect(fn.substring(0, 1200), contains('tenderRoundLabel(count)'));
      expect(fn.substring(0, 1200), contains('nextStepAfterUnsold(count)'));
    });
  });

  group('confirmations look like the rest of the app', () {
    test('there is one shared confirm dialog', () {
      final f = File('lib/widgets/confirm_dialog.dart').readAsStringSync();
      expect(f, contains('class ConfirmDialog'));
      // Built on the same chrome as every form in the app.
      expect(f, contains('StyledFormDialog('));
      expect(f, contains('StyledDialogPrimaryButton('));
    });

    test('show() returns a plain bool, so a dismiss is not null', () {
      final f = File('lib/widgets/confirm_dialog.dart').readAsStringSync();
      expect(f, contains('static Future<bool> show('));
      expect(f, contains('return ok == true;'));
    });

    test('the tender page no longer builds its own AlertDialogs', () {
      // ⚠️ Two dialog shapes on ONE screen was the problem: the forms had a
      // gradient header and the confirmations did not.
      expect(dash.contains('AlertDialog('), isFalse,
          reason: 'a hand-rolled dialog is back on this page');
      expect('ConfirmDialog.show('.allMatches(dash).length, 2);
    });

    test('recording an outcome is amber, not red', () {
      // Red is for destruction — something that cannot be undone.
      final f = File('lib/widgets/confirm_dialog.dart').readAsStringSync();
      expect(f, contains('Red is for DESTRUCTION'));
      expect('accent: context.colors.warningAmber'.allMatches(dash).length, 2);
    });
  });
}
