import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An Appeal Directorate ruling is an INSTRUCTION. The yard carries it out; it
/// does not choose afresh.
///
/// ⚠️ The seed picked the recorded outcome at random from every after-appeal
/// phrase, ignoring what had actually been decided. That produced rows the app
/// could only render as a contradiction — the popup bannered "Proceed with:
/// Sell" while the row beneath it read "Re-exported per appeal ruling". Eight
/// such rows existed in the seeded data, and the reviewer who noticed it could
/// not tell whether the app or the data was wrong. It was the data.
void main() {
  final seed = File('tool/seed_test_data.dart').readAsStringSync();

  group('the seeded outcome is derived from the ruling', () {
    test('there is a mapping from decision to phrasing', () {
      expect(seed, contains('_outcomeForRuling('));
      for (final pair in const [
        ["'RE-EXPORT'", 'Re-exported per appeal ruling'],
        ["'RELEASE'", 'Released on appeal ruling'],
      ]) {
        expect(seed, contains(pair[0]),
            reason: 'no branch for the ${pair[0]} ruling');
        expect(seed, contains(pair[1]));
      }
    });

    test('SALE and DESTROY are never an "Other" outcome', () {
      // ⚠️ The subtler half of this bug, and one my own first repair got
      // wrong. SALE and DESTROY are carried out by CENTRAL DISPOSAL: the
      // goods leave for Sold Goods or Destroyed Goods under their own
      // [FINAL:SOLD] / [FINAL:DESTROYED] marker. Writing "Destroyed per
      // appeal ruling" into a [FINAL:OTHER] row put a destroyed item on the
      // Other Goods page — a state the app itself cannot produce, and how the
      // contradiction was spotted.
      expect(seed, contains("'SALE' || 'DESTROY' => null"),
          reason: 'a SALE/DESTROY ruling must not become an Other outcome');
      expect(seed.contains("'Destroyed per appeal ruling'"), isFalse,
          reason: 'destruction is recorded by Central Disposal, not here');
      expect(seed.contains("'Auctioned per appeal ruling'"), isFalse,
          reason: 'a sale is recorded by Central Disposal, not here');
      // And the caller must actually skip those items.
      expect(seed, contains('if (outcome == null) continue;'));
    });

    test('the random after-appeal list is gone entirely', () {
      // ⚠️ Left in place but unused, it is an invitation to pick from it at
      // random again — which is exactly how this happened.
      expect(seed.contains('_finalOtherAfterAppeal'), isFalse,
          reason: 'the list that caused the contradiction is still present');
    });

    test('the query actually reads the decision', () {
      // It knew WHETHER there had been an appeal and never WHAT was decided,
      // so no amount of care at the call site could have helped.
      expect(seed, contains('iao.decision as appeal_decision'));
      expect(seed, contains('item_appeal_outcomes iao'));
    });

    test('no Other outcome claims a sale, auction or destruction', () {
      // ⚠️ The rule, rather than the three symptoms I happened to notice —
      // I fixed this data twice and it was still wrong the third time,
      // because each pass filtered on what I had just seen: first the
      // DECISION being SALE/DESTROY, then auction WORDING on an OTHER
      // decision, and only then "Disposed of by public auction" sitting in
      // the yard's own list. All three are the same rule: an [FINAL:OTHER]
      // row is the yard finishing goods on its own authority, and a sale, an
      // auction and a destruction are Central Disposal's.
      final list = seed.substring(seed.indexOf('const _finalOtherDirect = ['));
      final body = list.substring(0, list.indexOf('];'));
      for (final banned in const ['auction', 'destroy', 'sold', 'sale']) {
        expect(body.toLowerCase().contains(banned), isFalse,
            reason: '"$banned" is work for Central Disposal, not an '
                'outcome the yard records itself');
      }
    });

    test('an unruled item is not given a ruling-shaped outcome', () {
      // A package can reach appeal without every item being ruled on. Those
      // must not claim a ruling decided them.
      expect(seed, contains('Handed to the owner after appeal'));
    });
  });
}
