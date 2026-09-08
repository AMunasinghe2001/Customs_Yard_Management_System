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
    final fn = code(services.substring(
        services.indexOf('getForfeitLifecycleSummary() async {')));
    final body = fn.substring(0, 4600);

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
      expect(code(screen), contains("label: 'Unsold so far'"));
    });

    test('disposal requests split outstanding from forwarded', () {
      // ⚠️ It counted every request the yard had EVER raised -- 168 --
      // under a heading about pending work. 135 had long since moved on.
      expect(body, contains("r['forwarded'] == true"));
      expect(code(screen), contains("label: 'Sent, awaiting valuation'"));
      expect(code(screen).contains("label: 'Sent for Sale'"), isFalse);
    });

    test('destruction shows the queue as well as the done', () {
      // ⚠️ 23 items sitting in a queue -- the ones an officer still has
      // to go and do -- were invisible behind a card showing only what had
      // been destroyed.
      expect(body, contains('queuedForDestruction'));
      expect(code(screen), contains("label: 'Scheduled, not yet done'"));
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
      expect(c, contains("title: 'Destruction \u00b7 goods'"));
    });
  });

  group('the header names the yard and keeps time', () {
    test('the title is the yard, not the role', () {
      // ⚠️ Every page under this dashboard is filtered to one yard, and
      // which yard that was appeared only in a badge on the far side of the
      // header. An officer signed into two yards on two machines could not
      // tell the screens apart.
      final c = code(screen);
      expect(c, contains('yardName(myYard)} Dashboard'));
      expect(c.contains("'Admin Dashboard'"), isFalse);
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
