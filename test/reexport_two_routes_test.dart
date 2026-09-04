// Goods reach Re-exported by TWO routes, and only one of them worked.
//
// ⚠️ The yard's Final Disposition writes an item status of 're-exported', and
// that is all this page ever looked for. Top Management can ALSO rule
// "Re-export" on goods that failed every tender — the outcome is offered in
// the decision dialog and stored as an unsold_proposal — but nothing listed
// the result. Those goods left Unsold Goods and appeared on no page in the
// app at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

String _flat(String p) =>
    File(p).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final page = _flat('lib/screens/packages/disposition_category_screen.dart');

  group('both routes reach the page', () {
    test("re_export is a decision Top Management can actually make", () {
      // If this ever stops being true the second route is dead and the merge
      // below is pointless — so it is asserted, not assumed.
      expect(kUnsoldProposals, contains('re_export'));
      expect(unsoldProposalLabel('re_export'), 'Re-export');
    });

    test('the page reads the unsold decisions as well as the yard rows', () {
      expect(page, contains('List<_CategoryRow> _topManagementRows()'));
      // The same pair of providers the Government Use page reads — that page
      // is the model every Top Management outcome follows.
      expect(page, contains('ref.watch(exhaustedUnsoldProvider)'));
      expect(page, contains('ref.watch(unsoldProposalsProvider)'));
      expect(page, contains("proposal?.proposal != 're_export'"));
      // Only on this page: the other categories have one route each.
      expect(page, contains("if (widget.finalTag != 'RE-EXPORTED') return const []"));
    });

    test('the two are merged BEFORE the sort, and dated by their own event',
        () {
      expect(page, contains('rows.addAll(_topManagementRows());'));
      // A Top Management row is dated by its DECISION; a yard row by the
      // warehouse movement. Sorting on one field only would bunch the newer
      // route at the bottom.
      expect(page, contains('a.proposal?.decidedAt ?? a.entry?.returnedAt'));
    });
  });

  group('the table and the popup are ready for them', () {
    // ⚠️ The two events are not the same and a reader must be able to tell
    // them apart: the yard decided before the goods ever went to tender; Top
    // Management decided after every round failed.
    test('a Decided By column says which route the row took', () {
      expect(page, contains("label: Text('Decided By')"));
      expect(page, contains('class _OriginPill'));
      expect(page, contains("Text(fromTopManagement ? 'Top Management' : 'Yard'"));
    });

    test('the popup shows the tender history a Top Management row has', () {
      // The sale-item lookup only knows about goods that went through a sale
      // on the yard's own route, so it returns nothing here — and a package
      // with a full tender history would have shown none.
      expect(page, contains('tenderHistoryFor: row.forfeited ?? saleItem?.forfeited'));
      expect(page, contains('final ForfeitedPackageModel? forfeited;'));
    });

    // The column only ever printed an em dash: `officer` reads
    // `returnedByName ?? returnedByBadge ?? '—'` and a re-export sets neither.
    test('the Officer column is gone from this page', () {
      expect(
          page,
          contains("widget.finalTag != 'DESTROYED' && widget.finalTag != "
              "'RE-EXPORTED') const DataColumn2( label: Text('Officer')"));
    });
  });

  group('where the page sits in the rail', () {
    final shell = _flat('lib/widgets/app_shell.dart');

    // ⚠️ Re-exported stays under Disposed even though Top Management can now
    // send goods to it. That group answers "where did the goods GO", and
    // re-exported goods left the country whichever route decided it. Final
    // Outcomes answers "what did Top Management rule", and each of its four
    // pages has exactly one origin.
    test('Re-exported is grouped by destination, not by who decided', () {
      final disposed = shell.substring(
          shell.indexOf('const _navDisposed'), shell.indexOf('const _navOutcomes'));
      expect(disposed, contains("'Re-exported Goods'"));
      final outcomes = shell.substring(shell.indexOf('const _navOutcomes'));
      expect(outcomes.substring(0, outcomes.indexOf(']')),
          isNot(contains('Re-exported')));
    });
  });
}
