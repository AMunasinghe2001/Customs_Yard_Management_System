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

/// Source with comment lines dropped, then flattened.
///
/// ⚠️ The comments go from the RAW text, LINE BY LINE, before the
/// whitespace collapse -- flattening first removes the newlines a `//` runs
/// to, and every assertion below then matches prose as readily as code. It
/// caught fire exactly that way: a comment in `_navOutcomes` explaining why
/// re-export is NOT in that section -- which necessarily names it -- failed
/// the assertion that the section does not mention it.
String _flat(String p) => File(p)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final page = _flat('lib/screens/packages/disposition_category_screen.dart');
  // The row-building rules live in the view now; the page renders what it
  // returns. Read unflattened -- the assertions below match its own layout.
  final view = File('postgres/18_disposition_rows_view.sql').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();

  group('both routes reach the page', () {
    test("re_export is a decision Top Management can actually make", () {
      // If this ever stops being true the second route is dead and the merge
      // below is pointless — so it is asserted, not assumed.
      expect(kUnsoldProposals, contains('re_export'));
      expect(unsoldProposalLabel('re_export'), 'Re-export');
    });

    test('the view carries the unsold decisions as well as the yard rows', () {
      // ⚠️ The merge moved from Dart into SQL when this page started paging on
      // the server -- paging in SQL needs the rows to exist in SQL. The
      // BEHAVIOUR is unchanged and is asserted here against the view.
      expect(view, contains("'proposal'::text"));
      expect(view, contains("where up.proposal = 're_export'"));
      expect(view, contains("'RE-EXPORTED'::text                        as final_tag"));
      // Only this page has two routes; the other categories have one each.
      expect(view, contains('public.unsold_proposals up'));
    });

    test('the two are merged BEFORE the sort, and dated by their own event',
        () {
      // One union, so both routes are in the same result set before the ORDER
      // BY -- a Top Management row is dated by its DECISION and a yard row by
      // the warehouse movement, and sorting on one field only would bunch the
      // newer route at the bottom.
      expect('union all'.allMatches(view).length, 2);
      expect(view, contains('up.decided_at                              as happened_at'));
      expect(view, contains('coalesce(w.returned_at, w.admitted_at, p.updated_at)'));
      // And the query asks for them in that one order, newest first.
      expect(services, contains(".order('happened_at', ascending: false)"));
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
      // The NavItems, not the prose beside them -- see [_flat].
      expect(outcomes.substring(0, outcomes.indexOf(']')),
          isNot(contains('Re-export')));
    });
  });
}
