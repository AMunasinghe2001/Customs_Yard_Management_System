// Three things, all about the committee stage.
//
// 1. Central Disposal re-tendered a package a FIFTH time with no committee.
//    The route is finite -- Valuation Tender, then Tenders 1-3, and after
//    those Top Management appoints a committee to price it -- but
//    `unsold_retender_pool` never said so, and CED/GL1/OA/07/2025 ran five
//    rounds: TS/GL1/2026/009, /010, /012, /011 and /068.
//
// 2. Stopping that orphaned it. The Committees tab read the same pool, so the
//    package the new rule held OUT of the pool vanished from the page that
//    appoints its committee -- and from the DG's Unsold Goods, which only
//    lists packages whose committee round has failed. It appeared nowhere.
//
// 3. Before pricing a package that has failed four rounds, the DG had no way
//    to see what the market had already said. The bids and re-valuations were
//    reachable only from Central Disposal's Unsold Tenders table.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final committees = File('lib/screens/executive/tender_committee_tab.dart')
      .readAsStringSync();
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('four rounds is the most Central Disposal can run', () {
    final pool = File('postgres/38_retender_stops_at_four.sql').readAsStringSync();

    test('the pool holds out a fifth round with no committee', () {
      expect(pool, contains('a.round_count <= 4'));
      expect(pool, contains('exists (select 1 from public.tender_committees tc'));
    });

    test('the migration proves the rule against live data', () {
      expect(pool,
          contains('can be re-tendered past four rounds with'));
    });

    test('it does not rewrite the history it found', () {
      // ⚠️ Round 5 already happened for that package. Deleting or editing the
      // rows would be falsifying a record; the package simply stops being
      // offered again until a committee exists.
      expect(pool, contains('does NOT touch the existing rows'));
      expect(pool.toLowerCase().contains('delete from'), isFalse);
      expect(pool.toLowerCase().contains('update public.tender'), isFalse);
    });

    test('the app agrees on where the rounds stop', () {
      // Valuation Tender + Tenders 1-3 = four, then a committee.
      expect(kMaxBidTenderRounds, 3);
      expect(tenderRoundLabel(4), 'Tender 3');
      expect(tenderRoundLabel(5), 'Committee Tender 1');
    });
  });

  group('nothing is left with nowhere to go', () {
    final cpool = File('postgres/39_committee_pool_view.sql').readAsStringSync();

    test('the Committees tab has its own view', () {
      // ⚠️ It read unsold_retender_pool, which postgres/38 now holds these
      // packages OUT of -- so the tab that appoints their committee could no
      // longer see them.
      expect(cpool, contains('create view public.committee_pool'));
      expect(cpool, contains('a.round_count >= 4'));
      final fn = flat(services.substring(services.indexOf('getCommitteesPaged')));
      expect(fn.substring(0, 1500), contains("from('committee_pool')"));
      expect(fn.substring(0, 1500).contains("from('unsold_retender_pool')"),
          isFalse,
          reason: 'the Committees tab reads the pool it is held out of');
    });

    test('the migration asserts no package is invisible', () {
      // The whole point of the view.
      expect(cpool, contains('appear on NO page'));
    });

    test('a perishable never reaches a committee', () {
      // One failed Special Tender Sale is the end of the road for goods that
      // spoil; they go straight to the DG.
      expect(cpool, contains("coalesce(fp.source, '') <> 'perishable'"));
      expect(cpool, contains('% perishable(s) in the committee pool'));
    });

    test('nothing sold can be in it', () {
      expect(cpool, contains('% SOLD package(s) in the committee pool'));
    });
  });

  group('the DG can see what the market said', () {
    test('the bids dialog is shared, and read-only there', () {
      // ⚠️ Recording a bid is Central Disposal's act. The same dialog serves
      // both, so the two portals cannot describe one package's history
      // differently.
      expect(dash, contains('class EnterBidsDialog'));
      expect(dash, contains('final bool readOnly;'));
      expect(committees, contains('EnterBidsDialog('));
      expect(flat(committees), contains('readOnly: true'));
    });

    test('read-only reuses the LOCK, not a second hiding rule', () {
      // Two rules for hiding the same fields would drift into showing
      // different things.
      final fn = flat(dash.substring(dash.indexOf('bool get _currentRoundLocked')));
      expect(fn.substring(0, 400), contains('if (widget.readOnly) return true;'));
    });

    test('a viewer is not told they are locked out', () {
      // Recording a bid was never theirs to do; "can no longer be changed"
      // would report a restriction where there is a division of work.
      expect(dash, contains('Bids are recorded by Central Disposal'));
      expect(flat(dash), contains("widget.readOnly ? 'Tender History'"));
    });

    test('the tab offers two ways in', () {
      // The round count, and the bid count beside it.
      expect(committees, contains("label: Center(child: Text('Bids'))"));
      expect(committees, contains('_CommitteeBidsCell'));
      expect(committees, contains('_showHistory(context, info)'));
    });

    test('the bid count survives a re-fetch', () {
      // ⚠️ asData goes null while the provider re-fetches, so the count would
      // flip to 0 and back and the table would look like it was constantly
      // refreshing.
      // Comments dropped: the one beside the line NAMES asData to explain
      // why it is not used.
      final code = committees
          .substring(committees.indexOf('class _CommitteeBidsCell'))
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final fn = flat(code);
      expect(fn.substring(0, 900), contains('.valueOrNull'));
      expect(fn.substring(0, 900).contains('asData?.value'), isFalse);
    });
  });

  group('appointing a committee reaches the other portal', () {
    test('the paged providers are invalidated, not just the by-id map', () {
      // ⚠️ The map is what each CELL reads; the paged providers decide which
      // packages BELONG on a page. Appointing a committee moves a package onto
      // Central Disposal's Committees tab -- which did not show it until that
      // portal was reloaded by hand.
      expect('ref.invalidate(committeesPageProvider);'.allMatches(committees).length, 3);
      expect('ref.invalidate(unsoldRetenderPageProvider);'.allMatches(committees).length, 3);
      expect('ref.invalidate(exhaustedUnsoldPageProvider);'.allMatches(committees).length, 3);
    });

    test('every write does it, not just the appointment', () {
      // Appointing, recording the committee's value, and the ADG submitting
      // it all change which page a package belongs on.
      expect('ref.invalidate(tenderCommitteesProvider);'.allMatches(committees).length, 3);
    });
  });
}
