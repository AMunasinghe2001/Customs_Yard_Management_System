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

      // What the roll-up genuinely needs.
      expect(body, contains('package_items(*)'));
      expect(body, contains('warehouse_entries(*)'));

      // ⚠️ And not the three it never touches. warehouses() and the two
      // profile joins are 419 kB of JSON for figures nobody adds up.
      expect(body.contains('warehouse_entries(*, warehouses'), isFalse,
          reason: 'the warehouse rows are not read by any financial figure');
      expect(body.contains('returned_profile'), isFalse);
      expect(body.contains('profiles(*)'), isFalse);
    });

    test('there is a sales query that stops at the forfeited row', () {
      expect(services,
          contains('Future<List<TenderSaleModel>> getTenderSalesForLedger'));
      final start = services.indexOf('getTenderSalesForLedger');
      final body = flat(services.substring(start,
          services.indexOf('Future<List<TenderSaleModel>> getTenderSales(')));

      expect(body, contains('tender_sale_items(*'));
      expect(body, contains('forfeited_packages('));

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

    test('they still run in parallel', () {
      // ⚠️ Awaiting one after another means waiting for the sum. This was
      // already true and must stay true: the saving is per-query, and serial
      // execution would give half of it back.
      final fn = flat(providers.substring(
          providers.indexOf('final srFinancialsProvider')));
      expect(fn.substring(0, 900), contains('await Future.wait(['));
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
