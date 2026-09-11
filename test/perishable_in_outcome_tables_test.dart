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
}
