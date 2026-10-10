import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final mig = File('migrations/016_perishable_flag_on_outcome_views.sql')
      .readAsStringSync();
  final screen = File('lib/screens/packages/disposition_category_screen.dart')
      .readAsStringSync();
  final helper = File('lib/widgets/perishable_row.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();

  group('perishables are identifiable in a mixed table', () {
    test('the flag is resolved in the view, not in Dart', () {
      // These pages are server-paged: filtering after the page arrives
      // would leave the pager counting rows the screen had just removed.
      expect(mig, contains('item_is_perishable'));
      expect(mig, contains('is_perishable'));
      expect(services, contains("q.eq('is_perishable', true)"));
    });

    test('the forfeited source is the authority, nature the fallback', () {
      // postgres/07 made 'perishable' a real source; nature catches goods
      // sold or released straight out of the yard with no forfeit record.
      expect(mig, contains("lower(trim(coalesce(fp.source, ''))) = 'perishable'"));
      expect(mig, contains('package_items'));
    });

    test('null means "all goods", not "non-perishable"', () {
      // false would hide every perishable row instead of showing them all.
      expect(screen, contains('bool? _perishableOnly'));
      expect(screen, contains('_perishableOnly = v ? true : null'));
    });

    test('the row wash is far fainter than the tender cards amber', () {
      // There the colour means "act now, these are spoiling"; here it only
      // marks a different kind of goods.
      expect(helper, contains('warningAmber.withOpacity(0.06)'));
      expect(screen, contains('perishableRowColor('));
    });
  });

  group('the migration survives a fresh database', () {
    test('a missing nature column does not break the function', () {
      // postgres/06 adds it and is applied by hand — it is not folded into
      // 02_schema.sql, the file that stands a new server up.
      expect(mig, contains('language plpgsql'));
      expect(mig, contains("column_name = 'nature'"));
    });

    test('the views are only wrapped if they already exist', () {
      // postgres/18 creates disposition_rows and is likewise manual.
      expect(mig, contains("c.relname = 'disposition_rows'"));
      expect(mig, contains('return;'));
    });

    test('both views must still run as the caller', () {
      // Recreating a view drops security_invoker, and without it every
      // per-yard policy underneath is bypassed.
      expect(mig, contains('security_invoker = true'));
      expect(mig, contains('must run as the caller'));
    });
  });

  test('the settled chip does not vanish into the grey card', () {
    // It only ever appears on a settled card, and that card is washed
    // grey — a grey-on-grey chip disappeared exactly where it was read.
    expect(dash, contains('green.withOpacity(0.14)'));
    expect(dash, contains("Text('All items decided'"));
  });

  group('a perishable tender card stays recognisable at every stage', () {
    test('the leaf follows what the goods ARE, not their urgency', () {
      // It keyed off `urgentPerishable`, which goes false the moment a
      // sale is settled or before bidding opens — so a DECIDED perishable
      // sale and an APPEALING one both lost the only mark separating them
      // from an ordinary tender.
      expect(dash, contains('final isPerishableSale = widget.sale.isPerishableSale;'));
      expect(dash, contains('isPerishableSale ? amber : green'));
      expect(dash, contains('? Icons.eco_rounded'));
    });

    test('urgency is still a separate signal', () {
      // The amber wash and the thicker border say "act now"; the leaf says
      // "these are perishable". Two questions, two marks.
      expect(dash, contains('!settled && isPerishableSale && widget.sale.saleTimePassed'));
      expect(dash, contains('urgentPerishable ? 1.5 : 1'));
    });

    test('the badge is shown for every special sale', () {
      // A SPECIAL sale carries only perishables, so the type alone proves
      // what is in it — no stage condition on the tag.
      expect(dash, contains("widget.sale.tenderType == 'special'"));
      expect(dash, contains('PerishableTag(compact: true)'));
    });
  });
  // ── Unsold + Final Outcome pages: both routes, or perishables vanish ──
  group('unsold pages list both routes', () {
    final unsold = File('lib/screens/packages/unsold_packages_screen.dart')
        .readAsStringSync();

    test('the yard page asks for both unsold routes', () {
      // ⚠️ `exhausted_unsold` gates on `tender_count > 3` AND a committee —
      // two conditions a perishable can never meet, because it runs ONE
      // special sale and is never valued by a committee. Reading that view
      // alone hid every unsold perishable from the page whose job is to
      // list unsold goods, decided ones included.
      expect(unsold.contains('includeAllRoutes: true'), isTrue,
          reason: 'the Unsold and Final Outcome pages must read both routes');
    });

    test('the perishable filter narrows in SQL, not in Dart', () {
      // These pages are server-paged: a Dart-side filter would cut rows out
      // of a page the pager had already counted.
      expect(unsold.contains('perishableOnly: _perishableOnly'), isTrue);
      final svc = File('lib/services/services.dart').readAsStringSync();
      expect(svc.contains("q.eq('is_perishable', true)"), isTrue,
          reason: 'the filter belongs in the query');
    });

    test('the chip turning off means "all goods", never "hide perishables"',
        () {
      expect(unsold.contains('_perishableOnly = v ? true : null'), isTrue,
          reason: 'false would hide every perishable row');
    });

    test('perishable rows are tinted on the unsold table too', () {
      expect(unsold.contains('perishableRowColor('), isTrue);
      expect(unsold.contains('isPerishableGoods(forfeited: f)'), isTrue);
    });

    test('one chip widget serves both tables', () {
      // Two copies of the same control drift apart.
      final shared = File('lib/widgets/perishable_row.dart').readAsStringSync();
      expect(shared.contains('class PerishableFilterChip'), isTrue);
      final disp =
          File('lib/screens/packages/disposition_category_screen.dart')
              .readAsStringSync();
      expect(disp.contains('class _PerishableFilterChip'), isFalse,
          reason: 'the local copy should be gone');
    });
  });

  group('a settled perishable tender still reads as perishable', () {
    final src = File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync();

    test('its wash greys towards amber, not to neutral', () {
      // Plain grey answers "finished?" but erases the kind of goods at
      // exactly the point there are most finished cards to scan.
      expect(src.contains('final settledWash = isPerishableSale'), isTrue,
          reason: 'a settled perishable must not wash to plain grey');
    });

    test('the settled border leans amber for a perishable', () {
      expect(
          src.contains('? amber.withOpacity(0.45)'), isTrue,
          reason: 'the edge carries the distinction too');
    });

    test('the inner table stays lighter than the grey around it', () {
      // The grey belongs to the surround and the border; the table is the
      // panel cut out of it, so header < data < surround in weight.
      expect(src.contains('context.colors.textMuted.withOpacity(0.28)'), isTrue,
          reason: 'the 0.45 edge made the table heavier than its own card');
      expect(src.contains('dataRowColor: settled'), isTrue,
          reason: 'data must not be the faintest band on the card');
    });
  });

  group('the chip is offered only where it can act', () {
    final disp = File('lib/screens/packages/disposition_category_screen.dart')
        .readAsStringSync();
    final unsold = File('lib/screens/packages/unsold_packages_screen.dart')
        .readAsStringSync();
    final svc = File('lib/services/services.dart').readAsStringSync();

    test('Destroyed does not offer a filter that can only empty the table',
        () {
      // Left switched on, such a chip makes the page read "0 Destroyed" —
      // which looks like nothing was ever destroyed, not like a filter
      // matched nothing.
      expect(disp.contains('dispositionHasPerishablesProvider'), isTrue);
      expect(unsold.contains('unsoldHasPerishablesProvider'), isTrue);
    });

    test('the question is asked of the DATA, not hardcoded per page', () {
      // A perishable CAN be destroyed — one is ruled `destroy` right now
      // and simply has not been carried out. Hardcoding "Sold only" would
      // hide the chip exactly when it started to matter.
      expect(svc.contains('dispositionHasPerishables'), isTrue);
      expect(svc.contains('is_perishable'), isTrue,
          reason: 'the chip must follow the data, not a page name');
    });

    test('each Final Outcome page asks about its OWN population', () {
      // Converted has a perishable; Auction has none.
      expect(unsold.contains('proposal: widget.proposalFilter'), isTrue);
      expect(svc.contains('unsoldHasPerishables({String? yard, String? proposal})'),
          isTrue);
    });

    test('it costs a count, not a page of rows', () {
      final m = svc.substring(svc.indexOf('dispositionHasPerishables'));
      expect(m.substring(0, 600), contains('.count()'));
    });
  });

  group('expiry and perishable are not the same pale rose', () {
    final forf =
        File('lib/screens/forfeited_packages/forfeited_packages_screen.dart')
            .readAsStringSync();

    test('an expired appeal is an EDGE, not a wash', () {
      // dangerRed at 4% and warningAmber at 6% are both a pale rose over
      // white, so "the appeal window closed" and "these goods are
      // perishable" became one colour a reader had to guess at.
      expect(forf.contains('withOpacity(0.04)'), isFalse,
          reason: 'the wash collided with the perishable tint');
      expect(forf.contains('width: 3'), isTrue);
      expect(forf.contains('isExpired'), isTrue);
    });

    test('the perishable tint keeps the colour, since it marks a KIND', () {
      // It appears in mixed tables where the row beside it is ordinary
      // goods; an edge bar there would compete with nothing to compare to.
      final shared = File('lib/widgets/perishable_row.dart').readAsStringSync();
      expect(shared.contains('warningAmber.withOpacity(0.06)'), isTrue);
    });
  });

  group('every disposition page carries the perishable marks', () {
    final released =
        File('lib/screens/packages/returned_packages_screen.dart')
            .readAsStringSync();
    final view =
        File('postgres/70_disposition_rows_released_status.sql')
            .readAsStringSync();

    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('the view that REPLACES disposition_rows keeps is_perishable', () {
      // The regression this locks: postgres/70 drops and recreates
      // disposition_rows outright. Migration 016 had added is_perishable by
      // re-wrapping whatever the view was at the time, and a plain
      // `create view` silently drops that column again -- taking the chip
      // off Sold, Destroyed, Re-exported and Released all at once, with no
      // error anywhere, because the only symptom is a count query that
      // now returns zero.
      expect(flat(view), contains('public.item_is_perishable(r.item_id) as is_perishable'));
    });

    test('Released washes its perishable rows like its neighbours', () {
      // It had the chip and the flag already, so the filter worked -- but
      // the rows it returned looked identical to ordinary goods, which is
      // the one page where that was true.
      expect(flat(released),
          contains('color: WidgetStateProperty.all( perishableRowColor( context, row.isPerishable))'));
    });

    test('Released offers the narrowing chip too', () {
      expect(released, contains('PerishableFilterChip'));
      expect(released, contains('_perishableOnly = v ? true : null'));
    });
  });

  group('the perishable button is one of the row, not a guest in it', () {
    final helper = File('lib/widgets/perishable_row.dart').readAsStringSync();

    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('it is built from the same control as its neighbours', () {
      // ⚠️ It was a hand-rolled Container on the SEGMENTED-CHIP metrics
      // (padding 14/9, radius 10, icon 15, 12.5pt) sitting in a row of
      // OutlinedButtons (padding 12, radius 8, icon 16, 12pt) -- a different
      // control's shape, so it came out visibly shorter and rounder, and a
      // Wrap's `spacing` cannot even out the gaps when the boxes differ.
      expect(helper, contains('OutlinedButton.icon'));
      expect(helper.contains('vertical: 9'), isFalse,
          reason: 'the chip is back on its own padding');
      final f = flat(helper);
      expect(f, contains('fontSize: 12,'));
      expect(f, contains('BorderRadius.circular(8)'));
      expect(f, contains('EdgeInsets.symmetric(horizontal: 12)'));
    });

    test('it is the LAST control in every filter row', () {
      // One position across all four pages, so the reader finds it in the
      // same place whichever outcome they are looking at.
      for (final path in [
        'lib/screens/packages/disposition_category_screen.dart',
        'lib/screens/packages/returned_packages_screen.dart',
        'lib/screens/packages/unsold_packages_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        final chip = src.indexOf('PerishableFilterChip(');
        expect(chip, greaterThan(-1), reason: '$path has no chip');
        final date = src.indexOf('DateFilterButton(');
        if (date > -1) {
          expect(date, lessThan(chip),
              reason: '$path still draws the chip before the date filter');
        }
        // Nothing but the closing of the children list may follow it.
        final after = src.substring(chip);
        expect(after.contains('_deliveryFilterChip('), isFalse,
            reason: '$path draws a delivery button after the chip');
        expect(after.contains('OutcomeFilter('), isFalse,
            reason: '$path draws the outcome filter after the chip');
      }
    });
  });
}
