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
}
