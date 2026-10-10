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
    test('a RULED item is not finished as an "Other" outcome at all', () {
      // ⚠️ Every named ruling sends the goods to the page that ruling names —
      // Released, Re-exported, Sold or Destroyed Goods — each under its own
      // marker ([RELEASED], [FINAL:RE-EXPORTED], [FINAL:SOLD],
      // [FINAL:DESTROYED]). None is an "Other" outcome.
      //
      // I got this wrong twice while repairing this data: first writing
      // "Destroyed per appeal ruling" into a [FINAL:OTHER] row, then
      // "Released on appeal ruling". Both produced states the app cannot
      // create — a destroyed item and a released item sitting on Other Goods,
      // describing themselves as destroyed and released.
      expect(seed,
          contains("const ruledElsewhere = {'RELEASE', 'RE-EXPORT', 'SALE', 'DESTROY'}"),
          reason: 'a ruled item must be skipped, not given an Other outcome');
      expect(seed, contains('if (ruledElsewhere.contains(decision)) continue;'));
    });

    test('no ruling wording is left in the outcome list', () {
      // ⚠️ Scoped to the LIST, not the whole file: the comments above it
      // quote these phrases to explain why they are banned, and a blunt
      // file-wide search fails on its own documentation.
      final list = seed.substring(seed.indexOf('const _finalOtherDirect = ['));
      final body = list.substring(0, list.indexOf('];'));
      for (final banned in const [
        'per appeal ruling',
        'on appeal ruling',
        'after appeal',
      ]) {
        expect(body.contains(banned), isFalse,
            reason: '"$banned" belongs to another page, not Other Goods');
      }
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

  });
}
