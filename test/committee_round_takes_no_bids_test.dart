import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/models/models.dart';

/// A package goes through five attempts at most:
///
///   1  Valuation Tender   — priced by the Valuation Directorate
///   2  Tender 1           — priced from the previous round's bids
///   3  Tender 2
///   4  Tender 3
///   5  Committee Tender   — Top Management sets the value
///
/// ⚠️ Only attempts 1–4 are open to offers. The committee round is a decision,
/// not an auction: the committee sets a value, and if the goods still do not
/// move they fall straight through to Unsold Goods. The Tender History showed
/// a "Committee Tender 1" card carrying bids of Rs. 119,687 and Rs. 96,806 —
/// money nobody could have offered, because that round was never open.
void main() {
  group('the rounds are named for what they are', () {
    test('five attempts, and the fifth is the committee', () {
      expect(tenderRoundLabel(1), 'Valuation Tender');
      expect(tenderRoundLabel(2), 'Tender 1');
      expect(tenderRoundLabel(3), 'Tender 2');
      expect(tenderRoundLabel(4), 'Tender 3');
      expect(tenderRoundLabel(5), 'Committee Tender 1');
    });
  });

  group('the seed stops inventing bids for it', () {
    final seed = File('tool/seed_test_data.dart').readAsStringSync();

    test('a committee round is seeded with none', () {
      expect(seed, contains('isCommitteeRound'));
      expect(seed, contains('isCommitteeRound ? 0 :'),
          reason: 'the committee round is still given bids');
    });

    test('it uses the shared round limit, not a literal', () {
      // A hand-written 4 here would drift from kMaxBidTenderRounds the first
      // time the rule changed.
      expect(seed, contains('round > kMaxBidTenderRoundsSeed + 1'));
    });
  });

  group('the database refuses one', () {
    final sql = File('migrations/030_the_committee_round_takes_no_bids.sql')
        .readAsStringSync();

    test('a trigger rejects a bid on attempt 5 or later', () {
      // ⚠️ A trigger, not a check at the call site: bids are written from
      // more than one place, and the rule has to hold for all of them.
      expect(sql, contains('before insert on public.tender_bids'));
      expect(sql, contains('if v_attempt > 4 then'));
    });

    test('the message explains what happens instead', () {
      // "Rejected" without a reason reads as a fault in the app.
      expect(sql, contains('the committee sets a value'));
      expect(sql, contains('Unsold Goods'));
    });

    test('an ordinary round is still allowed to take bids', () {
      // ⚠️ Proving only the refusal would leave a migration that could have
      // broken tendering entirely and still reported success.
      expect(sql, contains('an ordinary round still takes them'));
      expect(sql, contains('where x.rn = 2'));
    });
  });

  group('the committee round happens once, and only after a value', () {
    final sql = File(
            'migrations/031_one_committee_round_and_a_value_before_it.sql')
        .readAsStringSync();

    test('a fifth round needs a SUBMITTED committee value', () {
      // ⚠️ postgres/38 let any EXISTING committee re-open the pool, valued
      // or not. So the committee round could run before the committee had
      // priced anything, and the Committee Value cell then offered "Enter
      // Value" for a round already over. OA/07/2025 sat in exactly that
      // state.
      expect(sql, contains('tc.submitted_value is not null'));
      expect(sql, contains('Top Management has not yet submitted one'));
    });

    test('a sixth round is refused outright', () {
      // Once a committee existed there was no cap at all.
      expect(sql, contains('if v_rounds >= 5 then'));
      expect(sql, contains('A sixth'));
    });

    test('it is a trigger, so a stale screen cannot get past it', () {
      expect(sql, contains('before insert on public.tender_sale_items'));
    });

    test('the migration proves both refusals', () {
      expect(sql, contains('a SIXTH round was accepted'));
      expect(sql, contains('a 5th round ran before the committee had valued'));
    });
  });

  group('Top Management is not offered a dead button', () {
    final tab =
        File('lib/screens/executive/tender_committee_tab.dart').readAsStringSync();

    test('Enter Value is withheld once the round has run', () {
      // A value entered after the committee round is over would have nothing
      // to attach to.
      expect(tab, contains('info.tenderCount > kMaxBidTenderRounds + 1'));
      expect(tab, contains("'Round already run'"));
    });
  });

  group('the seed proves the invariant instead of assuming it', () {
    test('it throws if a fifth round has no submitted value', () {
      final seed = File('tool/seed_test_data.dart').readAsStringSync();
      expect(seed, contains('having count(*) >= 5'));
      expect(seed, contains('The seed has broken the tender route'));
    });
  });

  group('rewriting the view kept every column the app reads', () {
    final sql = File(
            'migrations/031_one_committee_round_and_a_value_before_it.sql')
        .readAsStringSync();
    final services = File('lib/services/services.dart').readAsStringSync();

    test('the columns the service selects are all still defined', () {
      // ⚠️ The first draft of 031 copied the view from postgres/38's SOURCE
      // file, not from the live database. A later migration had added
      // `valued` (and `latest_unsold`) since 38 was written, so the rewrite
      // silently dropped them and the Unsold Tenders page fell over with
      // "column t.valued does not exist". A view is a contract with every
      // caller; rebuild it from what is live, and check what the app asks
      // for is still there.
      final sel = RegExp(r"from\('unsold_retender_pool'\)[\s\S]{0,200}?select\('([^']+)'\)")
          .allMatches(services)
          .map((m) => m.group(1)!)
          .expand((cols) => cols.split(',').map((c) => c.trim()))
          .toSet();
      expect(sel, isNotEmpty, reason: 'the service no longer reads the pool?');
      for (final col in sel) {
        expect(sql, contains(' as $col'),
            reason: 'the app selects "$col" but the view no longer defines it');
      }
    });

    test('latest_unsold is back in the WHERE clause', () {
      expect(sql, contains('and l.latest_unsold'));
    });
  });
}
