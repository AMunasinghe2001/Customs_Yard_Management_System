import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comment lines dropped, then flattened.
///
/// ⚠️ Comments go from the RAW text LINE BY LINE, before the whitespace
/// collapse — flatten first and the newline a `//` runs to is gone, so every
/// assertion below would match prose as readily as code.
String code(String raw) => raw
    .split('\n')
    .where((l) =>
        !l.trimLeft().startsWith('//') &&
        !l.trimLeft().startsWith('--') &&
        !l.trimLeft().startsWith('///'))
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final dialog =
      File('lib/widgets/package_details_dialog.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final mig62 =
      File('postgres/62_perishable_never_bids.sql').readAsStringSync();

  group('a perishable takes no bids', () {
    test('the database refuses one, and cleared the 20 that existed', () {
      // ⚠️ Perishables run ONE special tender sale. If it fails the goods go
      // straight to Top Management through Unsold Perishables — there is no
      // re-valuation and no second round, because the goods are rotting.
      // `unsold_retender_pool` has excluded them since migration 44, so no UI
      // offers the cell; nothing stopped the WRITE, and 20 bids sat against
      // 28 perishable packages, recorded through the special sale.
      expect(code(mig62), contains('create trigger tender_bids_no_perishable'));
      expect(code(mig62), contains('perishable goods take no bids'));
      expect(code(mig62), contains('delete from public.tender_bids'));
    });

    test('the migration proves the trigger FIRES', () {
      // ⚠️ A trigger that exists and does not reject is worse than none: the
      // rule reads as enforced and is not. The verify block attempts a real
      // insert and requires the rejection.
      expect(code(mig62), contains('the trigger did not reject a perishable bid'));
    });

    test('the service refuses first, with a sentence', () {
      // ⚠️ So the officer reads about perishables rather than a Postgres
      // check_violation.
      final c = code(services);
      final i = c.indexOf('saveTenderRoundBids(');
      expect(i, greaterThan(0));
      final fn = c.substring(i, i + 1400);
      expect(fn, contains("== 'perishable'"));
      expect(fn, contains('Perishable goods take no bids.'));
    });
  });

  group('the popup describes the process these goods actually have', () {
    final c = code(dialog);

    test('no bids, no re-valuation, no committee are even fetched', () {
      // ⚠️ Migration 62 deleted the rows and added a trigger, but a stale row
      // must not be able to put a bid chip under a round nobody can re-price.
      expect(c, contains('bool get _isPerishable'));
      expect(c, contains('final bids = _isPerishable ? const <String, List<double>>{}'));
      expect(c, contains('_isPerishable ? null : committeeAsync.valueOrNull'));
    });

    test('the round is a SPECIAL TENDER SALE, not "Valuation Tender"', () {
      // ⚠️ That name only means something as the first of a series — the
      // price the goods went to tender at, before the re-valuations that
      // follow. A perishable has no series, and the name implied a Tender 1
      // that is never coming.
      expect(c, contains("_isPerishable ? 'Special Tender Sale'"));
    });

    test('an empty bid list says WHICH case it is', () {
      // ⚠️ "No bids recorded" reads as an omission — somebody forgot to enter
      // them. For a perishable it is the rule.
      // ⚠️ Two assertions, not one line: dart format wraps at 80
      // columns and puts the ternary's arms on their own lines.
      expect(c, contains('isPerishableRound'));
      expect(c, contains("'Perishable goods take no bids'"));
    });

    test('the waiting line does not claim four rounds were exhausted', () {
      // ⚠️ A perishable reaches Top Management after ONE failed sale, not
      // after exhausting four rounds and a committee.
      expect(c, contains('Perishables go straight to Top Management'));
      expect(c, contains('isPerishable: _isPerishable'));
    });
  });

  group('a tender that has not closed is not an outcome', () {
    final c = code(dialog);

    test('a running tender does not read as awaiting the DG', () {
      // ⚠️ The tile knew sold, decided, and "awaiting Top Management" --
      // so a package on its FIRST round, in a sale opened three days ago,
      // was told every tender had been exhausted. 71 forfeited packages in
      // this yard have exactly one round.
      //
      // Goods reach Top Management when every round has RUN and none sold.
      // `hasRun` is the same clock the round tiles seal prices on, so the
      // outcome and the rounds above it cannot disagree.
      expect(c, contains('mine.every((s) => s.hasRun)'));
      expect(c, contains('stillRunning'));
      expect(c, contains('At tender'));
      expect(c, contains('in a tender that has not closed yet'));
    });

    test('sold and decided still win over it', () {
      // ⚠️ A package can be sold in a sale whose window is still open.
      // Selling ends the story, and so does a DG ruling.
      expect(c, contains('stillRunning && sold == null && !decided'));
    });
  });

  group('a portal opens packages in its own colour', () {
    test('the card takes an accent instead of inferring one from readOnly', () {
      // ⚠️ `readOnly` means "cannot mark an item sold" — true of the yard AND
      // of the Top Management Directorate, which are two different portals
      // with two different colours. So Top Management opened a package and
      // got the yard's blue header on a page that is teal everywhere else.
      final disposal = code(
          File('lib/screens/disposal/disposal_dashboard_screen.dart')
              .readAsStringSync());
      expect(disposal, contains('final Color? popupAccent;'));
      expect(disposal, contains('headerAccentColor: widget.popupAccent ??'));

      final tm = code(File('lib/screens/executive/tender_sales_view_tab.dart')
          .readAsStringSync());
      expect(tm, contains('popupAccent: accent'));
    });
  });
}
