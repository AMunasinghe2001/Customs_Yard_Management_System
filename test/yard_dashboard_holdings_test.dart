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

    test('the two rows use the SAME tile as the panel below', () {
      // ⚠️ The dashboard drew its top strip with one shape and the
      // lifecycle panel under it with another, for the same kind of figure.
      // Two shapes made the reader work out twice what they were looking at,
      // and the strip's cards were the larger of the two.
      final c = code(screen);
      expect(c.contains('class _StatCard'), isFalse,
          reason: 'the second shape is back');
      // Six a row: five holdings plus the rate, then three waiting, today
      // and the accrued total.
      //
      // ⚠️ Both rows hold SIX, so the two line up column for column.
      // Nine of them are written here; the rate and accrued tiles are their
      // own widgets and carry the flag inside.
      expect('stretch: true'.allMatches(c).length, 11);
    });

    test('both rows are titled, with the shared heading', () {
      // ⚠️ One definition of the heading, or a dashboard whose two
      // halves are labelled in slightly different type reads as two
      // dashboards.
      final c = code(screen);
      expect(c, contains("title: 'Held in Yard'"));
      expect(c, contains("title: 'Waiting on Another Directorate'"));
      expect(c, contains('class _GroupHeading'));
      // The lifecycle groups use it too.
      expect(c, contains('_GroupHeading(title: title, icon: icon)'));
    });
  });

  group('the lifecycle figures count GOODS', () {
    // ⚠️ Cut at the method's own END, not at a character count. A
    // fixed substring silently stops covering the tail of the method the
    // moment it grows -- and the symptom is a test that passes because it
    // never saw the code it was asserting about.
    final fn = code(services.substring(
        services.indexOf('getForfeitLifecycleSummary() async {')));
    final bodyEnd = fn.indexOf("'nextTenderSaleDate': nextTenderSaleDate");
    final body = bodyEnd > 0 ? fn.substring(0, bodyEnd) : fn;

    test('appeals cover every kind of goods, not just forfeits', () {
      // ⚠️ This read `forfeited_packages` filtered to source='forfeit',
      // so it saw 3 holds and 12 decisions while the directorate had ruled
      // on 77 items and frozen 26. Detained, abandoned and other goods raise
      // appeals exactly as forfeits do, and theirs were the majority.
      expect(body, contains("from('item_appeal_outcomes')"));
      expect(body.contains("eq('source', 'forfeit')"), isFalse,
          reason: 'the appeal count is narrowed to forfeits again');
    });

    test('the outcomes view carries its own yard', () {
      // ⚠️ It is a VIEW, so PostgREST has no foreign key to embed
      // through -- `package_items!inner(...)` fails to resolve, which is how
      // the column came to be added. postgres/47 carries `yard` and
      // `sr_number` for this caller.
      final view =
          File('postgres/47_item_appeal_outcomes_view.sql').readAsStringSync();
      expect(view, contains('p.yard'));
      expect(view, contains('p.sr_number'));
      expect(body, contains('yard,sr_number.ilike'));
    });

    test('tender figures count PACKAGES on their latest round', () {
      // ⚠️ tender_sale_items rows are ATTEMPTS. A package that fails
      // four times has four rows, so counting rows reported 109 unsold when
      // 27 lots of goods were unsold -- wrong by a factor of four. And a
      // package that failed twice and then sold is SOLD; its failures are
      // history, not an outcome.
      expect(body, contains('everSold'));
      expect(body, contains('latestOutcome'));
      expect(body, contains("tender_sales!inner(created_at)"));
      expect(code(screen), contains("label: 'Unsold, needs re-tender'"));
    });

    test('appeals count only goods still in a warehouse', () {
      // ⚠️ A ruling on goods that have since left the yard is history:
      // the directorate ruled, the yard acted, the goods are gone. Counting
      // those gave 26 held and 77 decided; 15 and 31 are goods the yard is
      // still holding, and only those are anybody's outstanding work.
      //
      // `warehouse_rows` is the same view the Warehouses page reads, so a
      // hold counted here and a row on that page cannot disagree about what
      // is present.
      expect(body, contains("from('warehouse_rows')"));
      expect(body, contains('inWarehouse.contains'));
    });

    test('an outcome and its delivery split share one tile', () {
      // ⚠️ Delivered and not-yet-delivered are two halves of ONE fact,
      // and two tiles said they were two facts -- a reader had to notice
      // they added up to a third tile's total to see the relationship at
      // all. With sold, destroyed and re-exported each split that way the
      // panel grew to nine tiles saying what three can.
      final c = code(screen);
      expect(c, contains('class _SplitTile'));
      expect(c, contains("label: 'Sold, all rounds'"));
      expect(c, contains("label: 'Re-exported'"));
      // ⚠️ A row with no hand-over step at all is in NEITHER half --
      // delivery is null, not false, where nothing was ever handed over.
      // The tile says so rather than letting the reader find that the
      // arithmetic does not close.
      expect(c, contains('total - delivered - pending'));
    });

    test('the final outcome comes from the pages\u0027 own view', () {
      // ⚠️ `disposition_rows` is what Sold / Destroyed / Re-exported
      // page through, so a figure here and a row count there cannot
      // disagree. Counting the source tables instead would drift: one
      // package reached destroyed through a warehouse entry alone, with no
      // destruction_items row behind it.
      expect(body, contains("from('disposition_rows')"));
      expect(body, contains("'SOLD', 'DESTROYED', 'RE-EXPORTED'"));
    });

    test('destroyed splits by DONE, never by delivery', () {
      // ⚠️ Nothing is handed over to be burnt. 23 of the 39 destroyed
      // rows carry no delivery state at all, so a delivered/pending split
      // read "9 delivered \u00b7 7 awaiting" of 39 and left the reader to
      // wonder about the other 23. Done or not done is the question the
      // page answers, and `is_destroyed` is the column that answers it.
      expect(body, contains("m['is_destroyed'] == true"));
      final c = code(screen);
      expect(c, contains("deliveredLabel: 'destroyed'"));
      expect(c, contains("pendingLabel: 'awaiting destruction'"));
      expect(c, contains("title: 'Destroyed \u00b7 goods'"));
    });

    test('the destroyed figure comes from the PAGE, not the list', () {
      // ⚠️ They disagree, and the page wins. `destruction_items` says
      // 16 destroyed -- what an officer scheduled. /destroyed-packages says
      // 17, because one package (Copper Wire Coils, CED/GL1/SR/24/2026)
      // reached destroyed on a warehouse entry tagged [FINAL:DESTROYED]
      // with no destruction_items row behind it at all. A tile that opens a
      // page showing a different number is worse than no tile, so the table
      // is read for its IDS alone -- which packages are already placed, so
      // "forwarded, not yet placed" can exclude them.
      expect(body, contains("from('destruction_items')"));
      expect(body, contains("select('forfeited_package_id')"));
      expect(body.contains('queuedForDestruction'), isFalse,
          reason: 'the list count is back on the panel');
      expect(code(screen), contains("route: '/destroyed-packages'"));
    });

    test('every Top Management ruling has its own tile', () {
      // ⚠️ The rail's "Final Outcomes" section is five pages, all
      // reading `unsold_proposals.proposal`, and the panel showed none of
      // them. One tile each, in the rail's order, each opening its page.
      final c = code(screen);
      // ⚠️ Four, not the rail's five -- re-export is counted under
      // Re-exported instead, and has its own test above.
      for (final route in const [
        '/government-use-packages',
        '/auction-packages',
        '/converted-packages',
        '/removed-packages',
      ]) {
        expect(c, contains("route: '\u0024route'".replaceAll('\u0024route', route)),
            reason: '\u0024route has no tile');
      }
      expect(body, contains("from('unsold_proposals')"));
    });

    test('re-export is ONE tile, not two', () {
      // ⚠️ The rail lists re-export under Final Outcomes, so the panel
      // grew a tile for it beside the other four rulings -- and counted the
      // same goods twice. Measured, not assumed: both re_export proposals
      // in this yard resolve to a `disposition_rows` row tagged
      // RE-EXPORTED, while auction, government_use, convert and
      // remove_from_premises resolve to none at all. The 2 ruled goods are
      // a SUBSET of the 19, not a separate population.
      //
      // Where the split matters it already exists: the Re-exported Goods
      // page carries a Decided By column, because the difference is between
      // ROWS on one page, not between two counts.
      final c = code(screen);
      expect(c, contains("label: 'Re-exported'"));
      expect(c, contains("route: '/reexported-packages'"));
      expect(c.contains("route: '/re-export-packages'"), isFalse,
          reason: 'the ruled goods are counted twice again');
      expect(body.contains("'re_export',"), isFalse,
          reason: 'the service emits a re_export figure again');
    });

    test('disposal requests split outstanding from forwarded', () {
      // ⚠️ It counted every request the yard had EVER raised -- 168 --
      // under a heading about pending work. 135 had long since moved on.
      expect(body, contains("m['forwarded'] == true"));
      expect(code(screen), contains("label: 'Sent, awaiting valuation'"));
      expect(code(screen).contains("label: 'Sent for Sale'"), isFalse);
    });

    test('valuation is counted in items, like everything beside it', () {
      // ⚠️ `valuation_rows` is one row per REQUEST, so counting rows
      // gave 9 while the Valuation Directorate had 33 goods to cost -- and
      // every card beside it counts goods.
      final holdings = code(services.substring(
          services.indexOf('Future<Map<String, int>> getYardHoldingCounts')));
      expect(holdings.substring(0, 3000), contains('pending_count'));
    });

    test('the group titles say what a figure counts', () {
      final c = code(screen);
      expect(c, contains("title: 'Appeal Directorate \u00b7 goods'"));
      expect(c, contains("title: 'At Tender \u00b7 goods'"));
      expect(c, contains("title: 'Sent to Central Disposal \u00b7 goods'"));
      expect(c, contains("title: 'Destroyed \u00b7 goods'"));
    });
  });

  group('the header names the yard and keeps time', () {
    test('the title names the directorate and the yard', () {
      // ⚠️ "Admin Dashboard" said who was looking, while every page
      // under it is filtered to one yard. The yard code alone was no
      // better: GL1 means nothing until you know it belongs to CED, and
      // ICT groups yards under directorates precisely because that is the
      // division that matters. So the header reads "CED · Grey Line 1
      // Dashboard" and the badge opposite carries the directorate alone --
      // the yard is spelled out once, not twice.
      final c = code(screen);
      expect(c, contains('yardName(myYard)} Dashboard'));
      expect(c, contains('myPrefix'));
      expect(c.contains("'Admin Dashboard'"), isFalse);
      expect(c, contains('_yardBadge(context, myYard, myPrefix)'));
      // ⚠️ The badge is the FULL code, "CED/GL1" -- the form an
      // officer types and reads off an SR number. The title spells the
      // yard out in words; either half alone is the one they cannot use.
      expect(c, contains("'\u0024prefix/\u0024code'"));
    });

    test('the directorate is READ, never hardcoded', () {
      // ⚠️ ICT re-pairs yards and directorates from the portal at run
      // time, so a const map would be a header that goes quietly wrong
      // after an edit nobody remembers making. The profile's own
      // directorate wins where it is set -- a yard under two of them (NNR
      // is CED and PSD) has no single answer, and the account registered
      // under one -- with `yard_directorates` as the fallback, and null
      // where the yard sits under several, because a guess would put the
      // wrong directorate on every page the officer opens.
      final providers =
          code(File('lib/core/providers.dart').readAsStringSync());
      expect(providers, contains('myDirectoratePrefixProvider'));
      expect(providers, contains('yardDirectoratesProvider.future'));
      expect(providers, contains('if (forYard.length != 1) return null;'));
    });

    test('the clock ticks', () {
      // ⚠️ A dashboard that auto-refreshes every 25 seconds while
      // showing a time frozen at whenever it was opened is worse than one
      // showing no time -- the reader trusts it.
      final c = code(screen);
      expect(c, contains('StreamBuilder<DateTime>'));
      expect(c, contains('HH:mm:ss'));
    });

    test('the rail shows the POST, not the permission level', () {
      // ⚠️ `role` has only two yard values, so a Deputy Commissioner
      // and a Senior Deputy Commissioner read identically and an officer read
      // "OFFICER". Which post an officer holds is `job_role`, set by ICT at
      // provisioning; postShortTitle falls back to the old text for an
      // account provisioned before that was recorded.
      final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
      expect(code(shell), contains('profile.postShortTitle.toUpperCase()'));
      expect(code(shell).contains("profile.isAdmin ? 'DC / SDDC'"), isFalse);
    });
  });

  group('the storage figures', () {
    final view =
        File('postgres/52_accrued_storage_view.sql').readAsStringSync();

    test('accrued is computed in SQL, not walked in Dart', () {
      // ⚠️ This walked `livePackagesProvider` -- every package in the
      // yard with its items and warehouse entries -- adding up charges. The
      // same whole-table fetch the rest of the app has been moved off, on the
      // one figure that changes every single day. Measured: 1132ms against
      // 14ms, for the identical total.
      expect(services, contains('getAccruedStorage()'));
      final fn = code(services.substring(services.indexOf('getAccruedStorage()')));
      expect(fn.substring(0, 900), contains("from('accrued_storage_by_yard')"));
      final prov = code(providers.substring(
          providers.indexOf('final currentWarehouseChargeProvider')));
      expect(prov.substring(0, 500).contains('livePackagesProvider'), isFalse,
          reason: 'the whole-yard walk is back');
    });

    test('accrued is NOT the ledger total', () {
      // ⚠️ Two different questions. `sr_financials.sr_charges` is the
      // whole bill ever raised, returned goods included -- 368,984,450 on
      // live data. This is what is still ticking -- 242,304,500. The
      // migration refuses to apply if the two ever agree.
      expect(view, contains('accrued equals the ledger total'));
      expect(view, contains('242304500'));
    });

    test('the day is pinned to Asia/Colombo and proven', () {
      // ⚠️ This figure grows by a day every day, so a date that
      // follows the reader's timezone gives the app and psql different
      // totals.
      expect(view, contains("at time zone 'Asia/Colombo'"));
      expect(view, contains("set local timezone to 'UTC'"));
      expect(view, contains('accrued depends on the reader'));
    });

    test('the rate and the accrued total are separate tiles', () {
      // ⚠️ They were one card: "Current W/H Rate · Accrued: LKR
      // 242,3…". The accrued figure is nine digits, so the line it shared with
      // a label was always going to end in an ellipsis -- and the number an
      // officer most wants was the part that got cut.
      final c = code(screen);
      expect(c.contains('class _WarehouseChargeCard'), isFalse);
      expect(c, contains('class _StorageRateTile'));
      expect(c, contains('class _AccruedStorageTile'));
      // Compact, because a fifth of a row cannot hold nine digits.
      expect(c, contains('String _compactLkr(double v)'));
      // Rounded to one decimal, so the digit that moves day to day survives.
      expect(c, contains('toStringAsFixed(1)}M'));
    });
  });

  group('recent activity says what it shows', () {
    test('it lists STATES, not activities', () {
      // ⚠️ These are the distinct statuses a package's items are in
      // right now. SR/24/2026 reads "Detain, destroyed" and said "2
      // activities", which sounds like two things happened today -- one of
      // them may have been recorded months ago. What put the package on the
      // list is that SOMETHING touched it today.
      final c = code(screen);
      expect(c, contains('states'));
      expect(c.contains('activities'), isFalse);
    });
  });
}
