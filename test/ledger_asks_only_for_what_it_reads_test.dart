// The Financials page lagged for the same reason the Destroyed tab did: it
// loaded far more than it read.
//
// srFinancialsProvider fetched getAllPackages() -- every package in all
// twenty-eight yards with three embeds, including each warehouse entry's
// warehouse row and the returning officer's profile, plus the inspecting
// officer's -- and getTenderSales(), which the service's own comment calls the
// heaviest query in the app, five levels deep through forfeited rows into
// packages, their items and their warehouse entries.
//
// buildSrFinancials reads none of that. Measured against the live database:
//
//     getAllPackages()          187ms  ->  getPackagesForLedger()     67ms
//     getTenderSales()           95ms  ->  getTenderSalesForLedger()  39ms
//
// with identical figures out: sale proceeds 38,159,662.00 either way, 395
// items, 332 warehouse entries, 188 items carrying a forfeited row.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();

  /// Whitespace collapsed: every one of these calls wraps across lines, and a
  /// single-line pattern is exactly what let a wrapped call hide twice before.
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('the ledger asks for what it reads, and no more', () {
    test('there is a packages query cut to the ledger', () {
      expect(services, contains('Future<List<PackageModel>> getPackagesForLedger'));
      // ⚠️ Sliced to this method's own body. A fixed character count ran
      // straight into getAllPackages() below it, so the test saw that
      // method's embeds and failed on its own subject.
      final start = services.indexOf('getPackagesForLedger');
      final body = flat(services.substring(
          start, services.indexOf('Future<List<PackageModel>> getAllPackages(')));

      expect(body, contains('package_items('));
      expect(body, contains('warehouse_entries('));

      // ⚠️ And not the three it never touches. warehouses() and the two
      // profile joins are 419 kB of JSON for figures nobody adds up.
      expect(body.contains('warehouse_entries(*, warehouses'), isFalse,
          reason: 'the warehouse rows are not read by any financial figure');
      expect(body.contains('returned_profile'), isFalse);
      expect(body.contains('profiles(*)'), isFalse);
    });

    test('every field the roll-up reads is in the select', () {
      // ⚠️ The PROPERTY, not the mechanism. The select was narrowed from
      // `package_items(*)` to a named list, which is faster and also silent
      // when it is wrong: a missing nullable column does not throw, it just
      // reports zero. destroying_deposit was dropped exactly that way and
      // every deposit on the page read LKR 0 until this test was written.
      //
      // So the check is against what buildSrFinancials and
      // calculatePackageCharge actually touch. Adding a figure to either means
      // adding its column here and to the select -- which is the point.
      final start = services.indexOf('getPackagesForLedger');
      final body = flat(services.substring(
          start, services.indexOf('Future<List<PackageModel>> getAllPackages(')));

      const readByTheRollUp = [
        // The row itself
        'sr_number', 'yard', 'status', 'created_at', 'consignee_name',
        'destroying_deposit',
        // Per item: the split key, its share, whether it is chargeable, its name
        'quantity', 'item_name',
        // Per entry: which item it bills, how many units, and the days
        'package_item_id', 'item_count', 'admitted_at', 'returned_at',
        'is_returned',
      ];
      for (final column in readByTheRollUp) {
        expect(body, contains(column),
            reason: '$column is read by the financial roll-up but is not '
                'asked for -- it will silently read as zero or null');
      }
    });

    test('it does not ask for the rate column it never uses', () {
      // calculatePackageCharge takes its rate from the historical rates map,
      // day by day; warehouse_entries.daily_rate is not consulted. It is the
      // one column that was safe to drop, so dropping it is worth pinning.
      //
      // ⚠️ Comment lines dropped first. The comment above the select NAMES
      // daily_rate to record why it is absent, and a plain substring check
      // reads that as the column still being asked for -- the same trap the
      // provider check below already carries a warning about.
      final start = services.indexOf('getPackagesForLedger');
      final body = flat(services
          .substring(start,
              services.indexOf('Future<List<PackageModel>> getAllPackages('))
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n'));
      expect(body.contains('daily_rate'), isFalse,
          reason: 'the rate comes from the rates map, not the stored column');
    });

    test('there is a sales query that stops at the forfeited row', () {
      expect(services,
          contains('Future<List<TenderSaleModel>> getTenderSalesForLedger'));
      final start = services.indexOf('getTenderSalesForLedger');
      final body = flat(services.substring(start,
          services.indexOf('Future<List<TenderSaleModel>> getTenderSales(')));

      expect(body, contains('tender_sale_items('));
      expect(body, contains('forfeited_packages('));

      // The four fields the proceeds and tax totals read off each sale item.
      for (final column in ['sold', 'sold_price', 'applied_taxes']) {
        expect(body, contains(column),
            reason: '$column is summed by buildSrFinancials');
      }

      // ⚠️ The three levels below it: the roll-up reads the forfeited row's
      // item id and SR number, and nothing under it.
      expect(body.contains('packages(*'), isFalse,
          reason: 'the ledger never reads the package beneath a sale item');
      expect(body.contains('package_items(*)'), isFalse);
      expect(body.contains('warehouse_entries('), isFalse);
    });

    test('the forfeited row still carries its required fields', () {
      // ⚠️ ForfeitedPackageModel.fromJson casts consignee_name, forfeited_at
      // and appeal_deadline as non-null. Trimming the select without them
      // throws "type 'Null' is not a subtype of type 'String'" at parse time,
      // which is how this was found.
      final start = services.indexOf('getTenderSalesForLedger');
      final fn = flat(services.substring(start,
          services.indexOf('Future<List<TenderSaleModel>> getTenderSales(')));
      for (final field in ['consignee_name', 'forfeited_at', 'appeal_deadline',
                           'item_id', 'sr_number']) {
        expect(fn, contains(field));
      }
    });
  });

  group('the ledger provider uses them', () {
    test('both, and not the heavy pair', () {
      // ⚠️ Comment lines dropped first: the comments beside these calls
      // NAME the heavy methods to explain why they are not used, and a plain
      // substring check reads that as the call still being there.
      final block = providers.substring(
          providers.indexOf('final srFinancialsProvider'),
          providers.indexOf('/// Totals a set of SR rows'));
      final code = flat(block
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n'));

      expect(code, contains('getPackagesForLedger()'));
      expect(code, contains('getTenderSalesForLedger()'));
      expect(code.contains('.getAllPackages()'), isFalse);
      expect(code.contains('.getTenderSales()'), isFalse);
    });

    test('the per-page financials builder does too', () {
      // The same roll-up, so the same cut of the data.
      final code = flat(providers
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n'));
      expect(code.contains('disposal.getTenderSales(),'), isFalse,
          reason: 'a caller of buildSrFinancials still loads the heavy sales');
    });

    test('they run one after another, not in Future.wait', () {
      // ⚠️ This test used to assert the OPPOSITE, and was wrong.
      //
      // Future.wait looks like the fast shape and is not, because the wait is
      // not the network. Postgres answers the packages query in 15ms; the rest
      // is the driver decoding rows into Dart objects on this isolate.
      // Issued together the four responses arrive together and then queue for
      // that one thread, so every query's latency grows for the same total
      // work. Measured against the live database, warm, three runs:
      //
      //     one after another   167ms  186ms  204ms
      //     Future.wait         298ms  303ms  371ms
      //
      // If this is ever changed back, change it because a measurement says so.
      final fn = flat(providers
          .substring(providers.indexOf('final srFinancialsProvider'),
              providers.indexOf('/// Totals a set of SR rows'))
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n'));
      expect(fn.contains('Future.wait('), isFalse,
          reason: 'measured slower than awaiting them one after another');
      // All four are still fetched -- serial, not dropped.
      for (final call in [
        'getPackagesForLedger()',
        'getTenderSalesForLedger()',
        'getFinancialExpenses()',
        'storageRateProvider',
      ]) {
        expect(fn, contains(call));
      }
    });
  });

  group('the heavy queries are still there for the pages that need them', () {
    test('getAllPackages and getTenderSales are not deleted', () {
      // ⚠️ Other screens read the warehouse names, the officer names and the
      // packages under a sale. This change narrows the LEDGER's query, it does
      // not narrow theirs.
      expect(services, contains('Future<List<PackageModel>> getAllPackages('));
      expect(services, contains('Future<List<TenderSaleModel>> getTenderSales('));
    });
  });
}
