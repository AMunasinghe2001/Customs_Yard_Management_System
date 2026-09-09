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

  group('the Valuation Directorate sees what it is pricing', () {
    final val = code(File(
            'lib/screens/valuation/valuation_dashboard_screen.dart')
        .readAsStringSync());
    final c = code(dialog);

    test('both its popups carry the tender history', () {
      // ⚠️ Unsold Tenders is a page of goods that FAILED at least one
      // round, and the directorate is setting the price for the next one.
      // The rounds, the re-valuations and the bids are the whole evidence
      // for that decision, and the popup showed none of it.
      expect('tenderHistoryFor: f,'.allMatches(val).length, 2);
    });

    test('a valuer is never sealed out of their own figure', () {
      // ⚠️ The seal keeps a live reserve price from BIDDERS. The
      // directorate that set it is not a bidder, and sealing there hid a
      // number from the only people whose job is to decide it -- on the
      // very page where they decide the next round's.
      expect('valuerView: true,'.allMatches(val).length, 2);
      expect(c, contains('final sealed = !valuerView'));
      expect(c, contains('widget.valuationSealedUntilSale && !widget.valuerView'));
      // ⚠️ The NEXT round's tile too. `sealed: true` was hardcoded there,
      // so the popup told the directorate its own pending re-valuation was
      // "shown once the tender closes" -- on the page where it had just
      // typed the number. That tile IS the figure they set.
      expect(c, contains('sealed: !valuerView'));
      expect(c, contains('upcoming: valuerView'));
      expect(c, contains('Set for the next round.'));
      // The seal is not decoration -- it stays for every other reader.
      expect(c.contains('sealed: true,'), isFalse,
          reason: 'a hardcoded seal is back');
    });
  });

  group('every popup says what the space cost', () {
    final c = code(dialog);
    final note =
        code(File('lib/widgets/storage_charge_note.dart').readAsStringSync());

    test('the gap the old section left is filled', () {
      // ⚠️ The Warehouse Charges section is skipped in three cases and
      // each leaves a real gap: `useLegacySummary` (nearly every popup in
      // the app), a no-charge status, and a sale.
      expect(c, contains('widget.useLegacySummary || isNoChargeContext || isSoldContext'));
      expect(c, contains('StorageChargeNote('));
    });

    test('a CLOSED entry still counts, to the day it closed', () {
      // ⚠️ It used to skip returned entries entirely, so all 146 rows on
      // the disposition pages -- every sold, released, re-exported and
      // "other" package in this yard -- showed nothing. Those are exactly
      // the goods whose storage cost somebody wants to know.
      expect(note.contains('if (e.isReturned) return false;'), isFalse,
          reason: 'closed entries are being skipped again');
      expect(note, contains('e.isReturned ? (e.returnedAt ?? DateTime.now()) : null'));
      expect(note, contains('until: ends'));
    });

    test('the days count to the last day, not to today', () {
      // ⚠️ "703 days in storage" about goods that left in 2024 is a
      // figure and a lie in the same line.
      expect(note, contains('(lastDay ?? DateTime.now()).difference(since)'));
    });

    test('the wording distinguishes owed, settled and never-billed', () {
      // ⚠️ Telling a reader goods are "payable on collection" when they
      // were collected two years ago is worse than saying nothing.
      expect(note, contains('payable on collection'));
      expect(note, contains('the goods have left the yard'));
      expect(note, contains('not billable, the state holds these goods'));
    });
  });

  group('the popup shows only what it has', () {
    final c = code(dialog);
    final note =
        code(File('lib/widgets/storage_charge_note.dart').readAsStringSync());

    test('an empty Storage section is not drawn at all', () {
      // ⚠️ A widget returning SizedBox.shrink() still leaves its
      // PARENT's frame on screen -- the heading, the border, the padding.
      // So "show nothing" rendered as an empty box with STORAGE over it,
      // on every package that never reached a zone.
      expect(note, contains('storageChargeVisibleProvider'));
      expect(c, contains('ref.watch(storageChargeVisibleProvider(p.id))'));
    });

    test('storage reads BEFORE the signatures', () {
      // ⚠️ Storage is a fact about the GOODS; System Entry By and
      // Released By name the officers who signed for them. Every paper form
      // in this office puts the signature at the bottom.
      final storage = c.indexOf("title: 'Storage'");
      final entry = c.indexOf('_SystemEntrySection(');
      expect(storage, greaterThan(0));
      expect(entry, greaterThan(0));
      expect(storage, lessThan(entry));
    });

    test('the valuer is shown no ending', () {
      // ⚠️ Its work is one step of a process with several still to run:
      // the price it sets goes to Central Disposal, which re-tenders, and
      // only after that does anything reach Top Management. Announcing an
      // ending on the form where the next round is priced describes a
      // future nobody has decided.
      expect(c, contains('if (showFinalOutcome && !valuerView)'));
    });

    test('the entry panel wears the same frame as every other section', () {
      // ⚠️ It had a gradient card of its own, so the last thing on every
      // popup looked like it came from a different screen. Same header bar
      // now -- tinted strip, gold icon, spaced capitals -- with an avatar
      // of the officer's initials rather than a second copy of the icon
      // already in the heading.
      expect(c, contains('String get _initials'));
      expect(c, contains('shape: BoxShape.circle'));
      final i = c.indexOf('class _SystemEntrySection');
      final body = c.substring(i, i + 2600);
      expect(body.contains('gradient: LinearGradient'), isFalse,
          reason: 'the odd-one-out card is back');
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
