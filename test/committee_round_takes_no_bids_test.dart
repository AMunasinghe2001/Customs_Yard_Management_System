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
}
