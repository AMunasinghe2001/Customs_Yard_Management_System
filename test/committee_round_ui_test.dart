import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The committee round is a decision, not an auction.
void main() {
  final disposal =
      File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync();

  group('the bid form is not offered on a committee round', () {
    test('the round is recognised', () {
      expect(disposal, contains('_currentRoundIsCommittee'));
      expect(disposal, contains('_rounds.length > kMaxBidTenderRounds + 1'));
    });

    test('it locks the editor', () {
      // ⚠️ Migration 030 refuses such a bid at the DATABASE. Leaving the form
      // on screen would let an officer type an amount, press Save and be
      // handed a raw error for doing exactly what the screen invited.
      final at = disposal.indexOf('bool get _currentRoundLocked');
      expect(at, greaterThan(-1));
      final body = disposal.substring(at, at + 900);
      expect(body, contains('if (_currentRoundIsCommittee) return true;'));
    });

    test('the notice says why, rather than talking about bids', () {
      // "The valuation was set from these bids" would describe bids that do
      // not exist; "can no longer be changed" implies there was once
      // something to change.
      expect(disposal, contains('It does '));
      expect(disposal, contains('not go out to bidders'));
    });

    test('the heading does not claim it was valued from bids', () {
      expect(disposal, contains("· No bidding"));
    });
  });

  group('all three tender dialogs are built the same way', () {
    test('they share one width', () {
      // ⚠️ Tender History opened at 540 and Record Bids at 480, so the same
      // package arrived in two visibly different windows depending on which
      // button was pressed.
      expect('width: 540,'.allMatches(disposal).length, 0,
          reason: 'a tender dialog is still wider than the others');
    });

    test('the cards are not wrapped in a second panel', () {
      // ⚠️ History wrapped every card in an outer StyledFormSection while
      // Record Bids listed them plainly — so one read as cards-inside-a-panel
      // and the other as a column of cards, for the same rounds.
      expect(disposal.contains("title: 'Tendered \${info.tenderCount}"), isFalse,
          reason: 'the outer section box is back');
      expect(disposal, contains("Text('Tendered \${info.tenderCount} time(s)'"));
    });

    test('the label wording agrees', () {
      // "Tender Sale History" in one place and "Tender History" in the other.
      expect(disposal.contains("'Tender Sale History'"), isFalse);
    });
  });

  group('the two tender dialogs look alike', () {
    test('the history card matches the bids card', () {
      // ⚠️ They sit one click apart on the same page and describe the same
      // rounds, but the history card used cardDark with a gold border while
      // the bids card used surfaceDark with a plain one — so the same tender
      // looked like two different kinds of record depending on which button
      // opened it.
      final at = disposal.indexOf('Widget _saleCard(');
      expect(at, greaterThan(-1));
      final body = disposal.substring(at, at + 700);
      expect(body, contains('color: context.colors.surfaceDark'));
      expect(body, contains('margin: const EdgeInsets.only(bottom: 12)'));
      expect(body, contains('BorderRadius.circular(12)'));
    });
  });

  group('a dialog wears the colour of the portal that opened it', () {
    final dlg = File('lib/widgets/styled_form_dialog.dart').readAsStringSync();
    final ref =
        File('lib/widgets/package_details_dialog.dart').readAsStringSync();

    test('the header is the SAME recipe as the SR Register Entry popup', () {
      // ⚠️ Two wrong versions preceded this. The original was a fixed
      // customsBlue gradient, so every dialog wore the same navy whatever
      // portal opened it. The first fix made the bar the accent at full
      // strength with white text — the right colour, but a heavy saturated
      // slab matching nothing else on the page. The reference popup uses a
      // 15% wash of the accent fading into the card, and so does this now.
      expect(dlg, contains('accent.withOpacity(0.15)'));
      expect(ref, contains('headerAccentColor!.withOpacity(0.15)'),
          reason: 'the reference recipe this copies has changed');
      expect(dlg.contains('context.colors.customsBlue,'), isFalse,
          reason: 'the fixed navy header is back');
      expect(dlg.contains('accent.withOpacity(0.92)'), isFalse,
          reason: 'the heavy full-strength bar is back');
    });

    test('icon and label are the accent, title is the page text colour', () {
      // Dark-on-tint, exactly as the reference reads.
      expect(dlg, contains('Icon(icon, color: accent'));
      final flat = dlg.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat,
          contains('color: context.colors.textPrimary, fontSize: erp ? 17 : 22'));
    });

    test('it closes with the shared red button', () {
      // A white-on-tint IconButton would be invisible on a light header.
      expect(dlg, contains('DialogCloseButton(prominent: true)'));
    });
  });

  group('every popup opens over the same blurred page', () {
    test('nothing calls the raw showDialog', () {
      // ⚠️ showAppDialog is what puts the dark blurred barrier behind a
      // popup. One call site in the Perishable screen had slipped past it, so
      // that dialog alone opened over a plain, unblurred page.
      final raws = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) {
            final src = f.readAsStringSync();
            return src.contains('showDialog(') &&
                !src.contains('Future<T?> showDialog');
          })
          .map((f) => f.path)
          .toList();
      expect(raws, isEmpty,
          reason: 'these open an unblurred dialog: ${raws.join(", ")}');
    });
  });
}
