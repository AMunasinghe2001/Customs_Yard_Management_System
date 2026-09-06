import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/packages/perishable_goods_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

PackageItem _item(String name, {String nature = kNatureNormal}) => PackageItem(
      id: name,
      packageId: 'p1',
      itemName: name,
      quantity: 10,
      nature: nature,
    );

PackageModel _pkg(List<PackageItem> items, {DateTime? entry}) => PackageModel(
      id: 'p1',
      srNumber: 'CED/GL1/SR/01/2026',
      consigneeName: 'Probe Traders',
      status: 'detained',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      entryDate: entry ?? DateTime.now(),
      items: items,
    );

Widget _harness({
  required List<PackageModel> packages,
  Set<String> sent = const {},
  Map<String, UnsoldProposalModel> outcomes = const {},
  bool readOnly = false,
}) =>
    ProviderScope(
      overrides: [
        // ⚠️ The page pages on the SERVER now: which items are listed is the
        // `perishable_rows` view's job (postgres/24), not a Dart walk over
        // every package. So the harness supplies the PAGE the view would have
        // returned, applying the same two membership rules the view applies —
        // nature is perishable, and a SENT item stays only if a decision came
        // back for it. The rules themselves are asserted against the SQL in
        // the "membership lives in SQL" group below.
        perishablePageProvider.overrideWith((ref, q) {
          final keys = <({String packageId, String itemId})>[];
          for (final p in packages) {
            for (final i in p.items) {
              if (i.nature != kNaturePerishable) continue;
              if (sent.contains('${p.id}:${i.id}') &&
                  !outcomes.containsKey(i.id)) {
                continue;
              }
              keys.add((packageId: p.id, itemId: i.id));
            }
          }
          return Future.value((
            keys: keys,
            packages: {for (final p in packages) p.id: p},
            total: keys.length,
          ));
        }),
        perishableYearsProvider.overrideWith(
            (ref) => Future.value([for (final p in packages) p.srNumber])),
        livePackagesProvider.overrideWith((ref) => Future.value(packages)),
        sentPerishableKeysProvider.overrideWith((ref) => Future.value(sent)),
        // The DG's rulings, shown on this page so the yard and Central
        // Disposal see what was decided. Overridden here or the widget opens
        // a real database socket.
        unsoldProposalsByItemProvider
            .overrideWith((ref) => Future.value(outcomes)),
        // Central Disposal's copy carries a yard dropdown, which fetches the
        // yard list -- overridden here or the widget opens a real socket.
        yardFilterOptionsProvider.overrideWith((ref) => Future.value(const [])),
        storageRateProvider
            .overrideWith((ref) => Future.value(const <DateTime, double>{})),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: PerishableGoodsScreen(readOnly: readOnly)),
      ),
    );

void main() {
  group('what a nature is, and what it defaults to', () {
    test('the two kinds, and nothing else', () {
      expect(kGoodsNatures.keys.toList(), [kNatureNormal, kNaturePerishable]);
    });

    test('an item is normal unless it says otherwise', () {
      // What leaves every item registered before this behaving as it did.
      expect(_item('Bolts').nature, kNatureNormal);
    });

    test('a row with no nature column parses as normal', () {
      final m = PackageItem.fromJson({
        'id': 'i1',
        'package_id': 'p1',
        'item_name': 'Bolts',
        'quantity': 5,
      });
      expect(m.nature, kNatureNormal);
    });

    test('a blank nature is treated as normal, not as a third kind', () {
      final m = PackageItem.fromJson({
        'id': 'i1',
        'package_id': 'p1',
        'item_name': 'Bolts',
        'quantity': 5,
        'nature': '   ',
      });
      expect(m.nature, kNatureNormal);
    });

    test('it survives a round trip', () {
      final m = PackageItem.fromJson({
        'id': 'i1',
        'package_id': 'p1',
        'item_name': 'Prawns',
        'quantity': 5,
        'nature': kNaturePerishable,
      });
      expect(m.nature, kNaturePerishable);
      expect(m.toInsertJson('p1')['nature'], kNaturePerishable);
      expect(m.copyWith().nature, kNaturePerishable,
          reason: 'copyWith dropped the nature');
    });

    test('the database refuses a third kind', () {
      final sql = _read('postgres/06_perishable_goods.sql');
      expect(sql, contains("check (nature in ('normal', 'perishable'))"));
      expect(sql, contains("default 'normal'"));
      expect(sql, contains('VERIFY FAILED: an unknown nature was accepted'));
    });
  });

  group('the page lists perishables and nothing else', () {
    testWidgets('a perishable item appears, a normal one does not',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(packages: [
        _pkg([
          _item('Fresh Prawns', nature: kNaturePerishable),
          _item('Steel Bolts'),
        ])
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Fresh Prawns'), findsOneWidget);
      expect(find.text('Steel Bolts'), findsNothing,
          reason: 'a normal item belongs on the disposition pages');
    });

    testWidgets('a decided item STAYS, carrying the DG\'s outcome',
        (tester) async {
      // ⚠️ It has been sent, so `sentKeys` holds it -- but dropping it would
      // mean the yard and Central Disposal never see what was decided: the
      // goods would simply vanish from the only page that lists them.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(
        packages: [
          _pkg([_item('Fresh Prawns', nature: kNaturePerishable)])
        ],
        sent: {'p1:Fresh Prawns'},
        outcomes: {
          'Fresh Prawns': UnsoldProposalModel(
            id: 'u1',
            forfeitedPackageId: 'f1',
            proposal: 'destroy',
            note: 'Unsold and spoiling',
            yard: 'GL1',
            decidedAt: DateTime(2026, 5, 1),
          ),
        },
      ));
      await tester.pumpAndSettle();
      expect(find.text('Fresh Prawns'), findsOneWidget,
          reason: 'a decided item must not vanish');
      expect(find.text('Destroy'), findsOneWidget,
          reason: "the DG's outcome is shown on the row");
    });

    testWidgets('an item already sent leaves the page', (tester) async {
      // It belongs to the disposal request from then on.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(
        packages: [
          _pkg([_item('Fresh Prawns', nature: kNaturePerishable)])
        ],
        sent: {'p1:Fresh Prawns'},
      ));
      await tester.pumpAndSettle();
      expect(find.text('Fresh Prawns'), findsNothing);
      expect(find.text('No perishable goods'), findsOneWidget);
    });

    testWidgets('the yard can send a request; Central Disposal cannot',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(packages: [
        _pkg([_item('Fresh Prawns', nature: kNaturePerishable)])
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Send Disposal Request'), findsOneWidget);

      await tester.pumpWidget(_harness(
        packages: [
          _pkg([_item('Fresh Prawns', nature: kNaturePerishable)])
        ],
        readOnly: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Send Disposal Request'), findsNothing,
          reason: 'Central Disposal only watches; the yard sends');
    });

    testWidgets('no waiting time is shown — there is nothing to wait for',
        (tester) async {
      // ⚠️ A countdown here read as an APPEAL WINDOW running down, and a
      // perishable has no appeal window at all -- that is the whole point of
      // the nature. Nothing is being waited out, so nothing is counted.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(packages: [
        _pkg([_item('Fresh Prawns', nature: kNaturePerishable)],
            entry: DateTime.now().subtract(const Duration(days: 5)))
      ]));
      await tester.pumpAndSettle();
      expect(find.text('5 days'), findsNothing);
      expect(find.text('Waiting'), findsNothing);
      // The goods themselves are still listed.
      expect(find.text('Fresh Prawns'), findsOneWidget);
    });
  });

  group('a perishable item skips the warehouse and the appeal window', () {
    final svc = _read('lib/services/services.dart');
    final fn = svc.substring(
        svc.indexOf('getRequestableExpiredPackages'));

    test('a package holding one is never skipped for the window', () {
      // The window would outlast the goods.
      expect(fn, contains('final hasPerishable ='));
      expect(fn, contains('!hasPerishable &&'));
    });

    test('the item itself has no window to pass', () {
      expect(fn, contains('if (it != null && it.nature == kNaturePerishable) return true;'));
    });

    test('it is requestable at once, under its own source', () {
      expect(fn, contains("source: 'perishable'"));
      expect(fn, contains("id: '\${pkg.id}:\${item.id}:perishable'"));
    });

    test('it never takes the abandoned or other branches', () {
      // Those describe a path it does not follow.
      expect(fn, contains('if (item.nature == kNaturePerishable) {'));
      final branch = fn.substring(fn.indexOf('if (item.nature == kNaturePerishable) {'));
      expect(branch.substring(0, 1400), contains('continue;'));
    });

    test('one already sent is not offered twice', () {
      expect(fn, contains('perishableFpItemKeys'));
    });
  });

  group('the SR form asks, and hides what no longer applies', () {
    final form = _read('lib/screens/inspection/inspection_screen.dart');

    test('nature is asked on every goods row', () {
      expect(form, contains("label: 'Nature *'"));
      expect(form, contains('for (final e in kGoodsNatures.entries)'));
    });

    test('it is saved with the item', () {
      expect(form, contains('nature: r.nature,'));
    });

    test('a perishable item is not asked for a status', () {
      // Detain / Forfeit describe nothing that will happen to it.
      expect(form, contains("if (widget.row.nature != kNaturePerishable) ...["));
    });

    test('it carries its own status, so no disposition page claims it', () {
      expect(form, contains("widget.row.status = 'Perishable';"));
    });

    test('switching back restores an ordinary status', () {
      expect(form, contains("} else if (widget.row.status == 'Perishable') {"));
      expect(form, contains("widget.row.status = 'Detain';"));
    });
  });

  group('perishables tender only as a Special sale', () {
    final dash = _read('lib/screens/disposal/disposal_dashboard_screen.dart');

    test('the pool is gated on the tender type', () {
      // The rule holds both ways, so the two are never mixed into one lot.
      expect(dash,
          contains("return isPerishable == (_tenderType == 'special');"));
    });

    test('the special type is the one meant for goods that spoil', () {
      expect(kTenderSaleTypes['special'], contains('perishable'));
    });

    test('Central Disposal shows the page read-only', () {
      expect(dash, contains('PerishableGoodsScreen(readOnly: true)'));
      expect(dash, contains("Text('Perishable')"));
      expect(dash, contains('length: 16,'),
          reason: 'the new tab needs a slot, or the view throws');
    });
  });

  group('its toolbar is laid out like every other cross-yard page', () {
    // The page used to stack the search box, the year filter and the yard
    // picker VERTICALLY inside a gold-bordered card -- three rows of controls
    // no other tab has, which made Central Disposal's Perishable tab look
    // like a different product from the ones either side of it.

    testWidgets('search, year and yard sit on ONE row', (tester) async {
      await tester.pumpWidget(_harness(
        packages: [
          _pkg([_item('Milk', nature: kNaturePerishable)])
        ],
        readOnly: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final search = tester.getRect(find.byType(TextField).first);
      // ⚠️ The YARD picker, not a year filter. Central Disposal's copy has no
      // year filter any more: not one cross-yard tab in that portal carries
      // one, and it was the extra control that made this header a different
      // shape from the tab beside it.
      expect(find.text('All Years'), findsNothing,
          reason: 'no cross-yard tab in this portal has a year filter');
      final yard = tester.getRect(find.text('All Yards').first);

      // Same band, side by side -- not one under the other.
      expect((search.center.dy - yard.center.dy).abs(), lessThan(8),
          reason: 'the yard picker must sit beside the search box');
      expect(yard.left, greaterThan(search.right - 1),
          reason: 'the yard picker belongs to the RIGHT of the search box');
    });

    testWidgets('the controls are not boxed in a bordered card',
        (tester) async {
      await tester.pumpWidget(_harness(
        packages: [
          _pkg([_item('Milk', nature: kNaturePerishable)])
        ],
        readOnly: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final src = _read('lib/screens/packages/perishable_goods_screen.dart');
      // ⚠️ Scoped to CENTRAL DISPOSAL's branch. The gold-bordered filter card
      // is right on the YARD — every held-goods page there wears one — and
      // wrong here, where no cross-yard tab does. So this asserts the card is
      // absent from the readOnly branch, not from the file.
      final central = src.substring(src.indexOf('if (widget.readOnly) ...['),
          src.indexOf('] else'));
      expect(central, isNot(contains('primaryGold.withOpacity(0.5)')),
          reason: 'the gold filter card belongs to the yard, not here');
      // The controls sit in a Row, fading in like the other tabs' headers
      // rather than sliding up as a panel.
      expect(central, contains('.animate().fadeIn(duration: 300.ms)'));
    });

    testWidgets('the search box matches the other tabs', (tester) async {
      // DisposalSearch elsewhere: 14px radius, gold border, gold search icon,
      // a clear button once something is typed.
      final src = _read('lib/screens/packages/perishable_goods_screen.dart');
      expect(src, contains('BorderRadius.circular(14)'));
      expect(src, contains('primaryGold.withOpacity(0.06)'));

      await tester.pumpWidget(_harness(
        packages: [
          _pkg([_item('Milk', nature: kNaturePerishable)])
        ],
        readOnly: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.close_rounded), findsNothing,
          reason: 'nothing typed yet, so no clear button');
      await tester.enterText(find.byType(TextField).first, 'Milk');
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget,
          reason: 'a typed query is clearable, as on every other tab');
    });

    testWidgets('the yard picker still only appears for Central Disposal',
        (tester) async {
      await tester.pumpWidget(_harness(
        packages: [
          _pkg([_item('Milk', nature: kNaturePerishable)])
        ],
      ));
      // pump twice past the entrance animation: a bare pump leaves its timer
      // running and the binding fails the test on teardown.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('All Yards'), findsNothing,
          reason: "the yard's own copy shows one yard and needs no filter");
    });
  });

  group('the details popup explains what is absent, rather than looking broken',
      () {
    final dialog = _read('lib/widgets/package_details_dialog.dart');

    test('an empty warehouse summary says WHY, for a perishable', () {
      // Perishables never enter a warehouse -- the page's own subtitle says
      // "no warehouse, no appeal window". So the blank section is the correct
      // answer, and it must not show the same "No warehouse details" empty
      // state that a failed load produces.
      expect(dialog, contains("'Not stored in a warehouse'"));
      expect(dialog, contains('go straight '),
          reason: 'the reason line explains the empty section');
      expect(dialog, contains('nature == kNaturePerishable'),
          reason: 'the section has to know the item is perishable');
    });

    test('a missing officer is "Not recorded", never "Unknown"', () {
      // 116 of the 176 packages were carried over when the register was
      // migrated: no inspected_by, no creation audit row, so no name exists.
      // "Unknown Officer" read as a lookup that had failed and sent people
      // hunting for a bug that was not there.
      expect(dialog, isNot(contains("'Unknown Officer'")));
      expect(dialog, contains("_kNoEntrantRecorded = 'Not recorded'"));
      expect(dialog, contains('predates officer tracking'),
          reason: 'the popup must say why the name is absent');
    });

    test('an absent name is set in muted type, not the gold used for a person',
        () {
      expect(dialog, contains('_unrecorded'));
      expect(dialog, contains('? context.colors.textMuted'));
    });
  });

  group('the yard reaches the page from its nav rail', () {
    test('both rails list it, and the route exists', () {
      final shell = _read('lib/widgets/app_shell.dart');
      // ⚠️ Declared ONCE, not once per rail. The officer and DC/SDDC rails
      // used to be two hand-maintained copies, so this counted 2 occurrences
      // to prove neither had been forgotten. They are now built from one
      // definition by navSectionsFor(), which makes the omission impossible
      // rather than merely detectable -- so one occurrence is the correct
      // count, and counting 2 would mean the duplication had come back.
      expect("NavItem('Perishable Goods'".allMatches(shell).length, 1,
          reason: 'one shared definition feeds both rails');
      expect(shell, contains('navSectionsFor('),
          reason: 'both rails must come from the same definition');
      final router = _read('lib/core/router.dart');
      expect(router, contains("path: '/perishable-goods'"));
      expect(router, contains('PerishableGoodsScreen()'));
    });
  });

  group('the page reads like the page beside it', () {
    final src = File('lib/screens/packages/perishable_goods_screen.dart')
        .readAsStringSync();

    // ⚠️ This screen is TWO pages from one file, and it had one arrangement
    // for both — so on whichever portal you were looking at, it was the odd
    // one out. The yard's copy is a held-goods page and must read like Other
    // Goods; Central Disposal's is a cross-yard list and must read like Sold
    // Goods.
    // ⚠️ Every held-goods page on the yard — Forfeited, Other, Abandoned —
    // puts its search box and filters INSIDE one gold-bordered card, so they
    // read as a panel and the table starts at a clear edge. This page left
    // them bare on the page, which is why it looked like a different screen
    // however closely the individual controls matched.
    test('the yard copy boxes its filters like its neighbours', () {
      final yardBranch =
          src.substring(src.indexOf('Boxed, like Forfeited and Other beside it'));
      expect(yardBranch, contains('primaryGold.withOpacity(0.5)'));
      expect(yardBranch, contains('BorderRadius.circular(12)'));

      // The same card the page beside it draws.
      final other = File('lib/screens/packages/other_packages_screen.dart')
          .readAsStringSync();
      expect(other, contains('primaryGold.withOpacity(0.5)'));
    });

    test('the yard copy offers the held-goods filters', () {
      expect(src, contains('custom.DateRangePickerDialog'));
      expect(src, contains("allLabel: 'Post Status Activity'"));
      // Every activity, not a narrowed list -- the SR form offers them all
      // for a perishable, so the filter has to be able to match them all.
      expect(src, contains('kAllPostStatusActivities'));
      expect(src, contains('YearFilterButton('));
    });

    test('the two arrangements are chosen by which portal it is', () {
      expect(src, contains('if (widget.readOnly)'));
      // Central Disposal's copy carries the yard picker; the yard's does not.
      expect(src, contains('YardAllFilter('));
    });

    // ⚠️ Central Disposal builds every cross-yard tab the same way: a plain
    // 22pt title, the search box and the yard picker on THAT line, then a
    // StatChip on its own line under it. This page used DisposalPageHeader —
    // a title with a subtitle and a big trailing count box — and put its
    // controls on a third row, so beside Sold Goods and Unsold Tenders it was
    // taller, with the count in the wrong place and in a different shape.
    test('the Central Disposal copy is built the way its neighbours are', () {
      final ro = src.substring(src.indexOf('if (widget.readOnly) ...['),
          src.indexOf('] else'));
      // The 22pt heading now comes from PageTitle, which every one of those
      // neighbours also uses -- so this asserts the shared widget rather than
      // a font size typed out again here.
      expect(ro, contains('PageTitle('));
      expect(ro, contains('_searchBox(context)'));
      expect(ro, contains('YardAllFilter('));
      expect(ro, contains('StatChip('));
      // DisposalPageHeader is the YARD's header, and stays on that side.
      expect(ro.contains('DisposalPageHeader'), isFalse);
      expect(ro.contains('_CountChip'), isFalse);

      // ⚠️ And NO year filter. Not one cross-yard tab in that portal has one
      // — they narrow by yard and by search — so it was the extra control
      // that made this header a different shape from the tab beside it. The
      // yard's copy keeps it, where every held-goods page has one.
      expect(ro.contains('YearFilterButton'), isFalse);
      expect(src, contains('YearFilterButton('),
          reason: "the yard's copy still needs it");

      // The same three pieces the neighbours use, in the same order.
      final disposal =
          File('lib/screens/disposal/disposal_dashboard_screen.dart')
              .readAsStringSync();
      expect(disposal, contains('StatChip('));
      expect(disposal, contains('YardAllFilter('));
    });

    // ⚠️ Central Disposal tints every one of its dialogs with the portal's
    // green. This page passed none, so it fell back to the default indigo and
    // was the only popup in that portal wearing another colour.
    // ⚠️ Every tab in Central Disposal pads at 24. At 28 this page's title
    // and its table both sat lower than the tab you had just switched from,
    // which is what "why is the table so far down" was.
    test('it pads like the portal it sits in', () {
      // ⚠️ 16 in the portal, 28 on the yard — and the number has to track
      // whatever Central Disposal uses, or this page sits at a different
      // inset from every tab beside it. The portal tightened to 16 to give
      // its tables more rows; this followed.
      expect(src, contains('EdgeInsets.all(widget.readOnly ? 16 : 28)'));
      final disposal =
          File('lib/screens/disposal/disposal_dashboard_screen.dart')
              .readAsStringSync();
      expect(disposal, contains('padding: const EdgeInsets.all(16)'));
      // ⚠️ The count pill no longer has a row of its own. It sits on the
      // TITLE line, so there is exactly one Gap between the header and the
      // table -- the pill carrying its own bottom padding as well would
      // double it, which is what the old stacked layout did.
      final ro = src.substring(src.indexOf('if (widget.readOnly) ...['),
          src.indexOf('] else'));
      expect(ro, contains('StatChip('));
      expect(ro, isNot(contains('EdgeInsets.only(bottom: 14)')));
      expect('const Gap(14)'.allMatches(ro).length, 1);
      expect(src, contains('if (!widget.readOnly) const Gap(16)'));
    });

    test('the details popup matches the portal it opens in', () {
      expect(src, contains('headerAccentColor:'));
      // Matched on the name alone: the formatter breaks the property access
      // across lines, and where it breaks is not what this test is about.
      expect(src, contains('successGreen'));
    });
  });

  group('membership lives in SQL', () {
    final view =
        File('postgres/24_perishable_rows_view.sql').readAsStringSync();
    final services = File('lib/services/services.dart').readAsStringSync();
    final src = _read('lib/screens/packages/perishable_goods_screen.dart');

    test('only perishable goods are listed', () {
      expect(view, contains("where pi.nature = 'perishable'"));
      expect(view, contains('non-perishable row(s) leaked in'));
    });

    test('a SENT item stays only if a decision came back', () {
      // ⚠️ The important half. Perishables never reach a warehouse and never
      // sit out the appeal window, so no disposition page can show them --
      // this is the ONLY page they appear on. Dropping a sent-and-decided item
      // would mean the yard and Central Disposal never see the ruling at all.
      expect(view, contains(
          'and (dri.forfeited_package_id is null or up.id is not null)'));
      expect(view, contains('sent row(s) remain with no decision to show'));
    });

    test('one row per item, so nothing shows twice', () {
      expect(view, contains('item(s) appear more than once'));
    });

    test('the date the page sorts on falls back like the app does', () {
      // entryDate is nullable; a row without one must not vanish from a date
      // filter its neighbours answer.
      expect(view, contains('coalesce(p.entry_date, p.created_at)'));
      expect(view, contains('as effective_date'));
    });

    test('the yard filter matches the SR NUMBER, not the yard column', () {
      // ⚠️ The package's yard column can be the filing directorate rather
      // than the yard actually holding the goods -- every cross-yard page
      // matches on the SR number's own segment.
      final m = services.substring(services.indexOf('getPerishableRowsPaged'));
      expect(m, contains(r"q.ilike('sr_number', '%/$yardSrPrefix/%')"));
    });

    test('one filter closure serves the rows and the count', () {
      final m = services.substring(services.indexOf('getPerishableRowsPaged'));
      expect(m, contains('PgQuery narrow(PgQuery q)'));
      expect(m, contains("narrow(supabase.from('perishable_rows')).count()"));
      expect(m, contains('.range(offset, offset + limit - 1)'));
    });

    test('the screen reads the paged provider and the server count', () {
      expect(src, contains('perishablePageProvider(query)'));
      expect(src, contains('total: result.total,'));
      expect(src, isNot(contains('final perishableRowsProvider')));
      expect(src, isNot(contains('List<PerishableRow> _filter(')));
    });

    test('the year filter runs its own query', () {
      expect(src, contains('perishableYearsProvider'));
    });
  });
}
