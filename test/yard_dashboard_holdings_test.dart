// The yard dashboard could not answer "what is in my yard?".
//
// Its top row was five "today" cards — forfeited today, abandoned today,
// destroyed today, released today — which read 0 on any day nothing happened,
// which is most days. Meanwhile the yard held 226 items across four Held Goods
// pages and the dashboard said nothing about any of them:
//
//     Detained    43        Perishable awaiting DG    6
//     Abandoned   50        Awaiting valuation        9
//     Other       83        Re-tenderable            10
//     Forfeited   50        Unsold — exhausted        8
//
// The figures now come from the SAME views the nav rail's own pages read, so a
// number on the dashboard and the page it links to cannot disagree — and each
// card opens that page.
//
// Today's activity is kept, as one card with a breakdown rather than four
// cards of zero.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final screen = File('lib/screens/admin/admin_dashboard_screen.dart')
      .readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String code(String s) => flat(s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//') &&
          !l.trimLeft().startsWith('///'))
      .join('\n'));

  group('the counts come from the pages they link to', () {
    test('each figure reads the view its own page reads', () {
      expect(services, contains('getYardHoldingCounts()'));
      final fn = code(services.substring(
          services.indexOf('Future<Map<String, int>> getYardHoldingCounts')));
      final body = fn.substring(0, 2600);

      // ⚠️ The same views, not a second definition of "detained". A count
      // computed separately from the page it links to is a count that can
      // disagree with it.
      expect(body, contains("countOf('held_goods_rows'"));
      expect(body, contains("eq('kind', 'DETAINED')"));
      expect(body, contains("eq('kind', 'ABANDONED')"));
      expect(body, contains("eq('kind', 'OTHER')"));
      expect(body, contains("countOf('forfeit_rows')"));
      // Whitespace collapsed, so a wrapped call still matches: this one
      // wraps because its filter is three conditions long.
      expect(body, contains("countOf( 'perishable_rows'"));
      expect(body, contains("countOf('unsold_retender_pool')"));
      expect(body, contains("countOf('exhausted_unsold')"));
      expect(body, contains("from('valuation_rows')"));
    });

    test('the yard match includes the SR number segment', () {
      // ⚠️ A row filed by one directorate can sit in another's yard, and
      // matching the yard column alone hides it from the yard actually
      // holding the goods — the rule every cross-yard page already applies.
      final fn = code(services.substring(
          services.indexOf('Future<Map<String, int>> getYardHoldingCounts')));
      expect(fn.substring(0, 2600), contains(r"sr_number.ilike.%/$yard/%"));
    });

    test('valuation_rows gets its own narrowing', () {
      // ⚠️ It is one row per REQUEST, and a request can hold goods from
      // several yards — so it carries pipe-wrapped `sr_numbers` and
      // `item_yards`, not the single `sr_number` the per-item views have.
      // Reusing the shared filter asks for a column that does not exist, and
      // Postgres says so: 42703.
      final fn = code(services.substring(
          services.indexOf('Future<Map<String, int>> getYardHoldingCounts')));
      final body = fn.substring(0, 2600);
      expect(body, contains(r"item_yards.ilike.%|$yard|%"));
      expect(body, contains(r"sr_numbers.ilike.%/$yard/%"));
    });

    test('perishable counts the ones that are STUCK', () {
      // ⚠️ Not every perishable. The page lists them all; what a yard admin
      // needs from a dashboard is the ones waiting on a DG ruling — marked
      // unsold at tender, not sold, no proposal yet. 6 of 47 on live data.
      final fn = code(services.substring(
          services.indexOf('Future<Map<String, int>> getYardHoldingCounts')));
      final body = fn.substring(0, 2600);
      expect(body, contains("eq('marked_unsold', true)"));
      expect(body, contains("isNull('proposal')"));
      expect(body, contains("eq('sold', false)"));
    });
  });

  group('the dashboard shows them', () {
    test('the screen watches the counts', () {
      expect(providers, contains('final yardHoldingCountsProvider'));
      expect(code(screen), contains('yardHoldingCountsProvider'));
    });

    test('the four holding cards open their pages', () {
      // ⚠️ A number an officer cannot act on is a number they have to go and
      // find.
      final c = code(screen);
      for (final route in [
        "route: '/detained-packages'",
        "route: '/abandoned-packages'",
        "route: '/other-packages'",
        "route: '/forfeited-packages'",
        "route: '/perishable-goods'",
        "route: '/unsold-packages'",
      ]) {
        expect(c, contains(route), reason: '$route is not wired up');
      }
    });

    test("today's activity survives, as one card", () {
      // ⚠️ Four cards of zero became one card with the breakdown under it.
      // The information is still there; it just stopped taking the whole row.
      final c = code(screen);
      expect(c, contains("label: 'Recorded today'"));
      expect(c.contains("label: 'Forfeited Today'"), isFalse);
      expect(c.contains("label: 'Abandoned Today'"), isFalse);
      expect(c.contains("label: 'Destroyed Today'"), isFalse);
      expect(c.contains("label: 'Released Today'"), isFalse);
    });

    test('five cards a row, which is what fits', () {
      // ⚠️ Measured at a 1400px window: the body is 1124px, so six cards
      // leave 86px for the label and five leave 124px. "Awaiting Valuation"
      // with "sent, not yet costed" under it needs about 114px — six would
      // clip both.
      //
      // Counting Expanded children inside the two rows is the closest a
      // source test can get to that without pumping the screen.
      final c = code(screen);
      final firstRow = c.substring(c.indexOf("label: 'Detained'"));
      final secondRowAt = c.indexOf("label: 'Awaiting Valuation'");
      expect(secondRowAt, greaterThan(-1));

      // Row one: Detained, Abandoned, Other, Forfeited, Perishable.
      final rowOne = firstRow.substring(0, firstRow.indexOf("label: 'Awaiting"));
      expect('_StatCard('.allMatches(rowOne).length, 5);

      // Row two: Valuation, Re-tenderable, Unsold, Recorded today, plus the
      // charge card, which is its own widget.
      final rowTwo = c.substring(secondRowAt);
      expect('_StatCard('.allMatches(rowTwo).length, 4);
      expect(rowTwo, contains('_WarehouseChargeCard('));
    });
  });
}
