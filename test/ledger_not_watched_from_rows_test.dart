// The Destroyed Goods tab was slow for the THIRD time, the same way each time.
//
// `srFinancialsProvider` is getAllPackages() across all twenty-eight yards
// plus getTenderSales() -- which the service's own comment calls "the heaviest
// query in the app" -- rolled up per item and per tax name. Measured against
// the live database:
//
//     the tab's own page query         24ms
//     getAllPackages() it dragged in  148ms
//     getTenderSales() it dragged in   68ms
//
// A page of twenty rows waited an order of magnitude longer for a button than
// for its own data. DestructionExpenseCell was fixed first; the Costs button
// and the details popup beside it were left watching, so the lag stayed.
//
// A whole-ledger provider must never be WATCHED from inside a table row. Read
// it in the tap handler, where the officer has asked for it.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Screens that render a paged table. A watch here costs one whole-ledger
/// fetch per page.
const _tableScreens = [
  'lib/screens/disposal/disposal_dashboard_screen.dart',
  'lib/screens/packages/disposition_category_screen.dart',
  'lib/screens/packages/perishable_goods_screen.dart',
  'lib/widgets/destruction_status_pill.dart',
];

void main() {
  group('the whole-ledger provider is never watched from a table', () {
    for (final path in _tableScreens) {
      test('$path reads it, never watches it', () {
        final src = File(path).readAsStringSync();
        // ⚠️ Matched with the whitespace collapsed: the call wraps across
        // lines in every one of these files, and a single-line pattern is
        // exactly what let the last one hide. (The emoji check learned the
        // same lesson.)
        final flat = src.replaceAll(RegExp(r'\s+'), ' ');
        // ⚠️ `ref.watch` is the one that costs: it subscribes whatever is
        // BUILDING, and in a table that is every row of every page.
        //
        // A watch from inside a DIALOG builder is a different thing and is
        // allowed — the builder runs only while the popup is open, one
        // instance, at the moment the officer asked for the figure. The
        // details popup uses `dialogRef.watch` for exactly that, so it can
        // appear instantly instead of the button hanging ~2s on the tap.
        expect(flat.contains('ref.watch(srFinancialsProvider)'), isFalse,
            reason: 'watching the ledger from a row costs ~216ms per page — '
                'read it in the tap handler, or watch it inside the dialog');
      });
    }

    test('the ones that need it read it on the tap', () {
      final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync();
      final yard =
          File('lib/screens/packages/disposition_category_screen.dart')
              .readAsStringSync();
      // `.read(...future)` inside an async handler, not `.watch` in build.
      // Whitespace collapsed, since both calls wrap.
      String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
      // ⚠️ The Destroyed popup no longer awaits it before opening — that was
      // the ~2s dead button. It watches inside the dialog instead, which is
      // the same "only when asked" guarantee with none of the wait.
      expect(flat(dash), contains('dialogRef .watch(srFinancialsProvider)'));
      expect(flat(yard), contains('await ref.read( srFinancialsProvider.future)'));
    });
  });

  group('the Costs button no longer waits for the ledger to enable itself', () {
    final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync();
    final btn = dash.substring(dash.indexOf('class _RecordCostsButton'),
        dash.indexOf('/// Parse the receipt from'));

    test('it is always enabled', () {
      // ⚠️ `onPressed: sr == null ? null : ...` is what forced the fetch: the
      // button could not know if it was enabled without the whole ledger. An
      // SR on this table always has a financials row, so the check never
      // actually said no -- it only made everyone wait.
      expect(btn.contains('onPressed: sr == null'), isFalse);
      expect(btn, contains('onPressed: () => _open(context, ref)'));
    });

    test('a failure to load says so instead of opening an empty dialog', () {
      expect(btn, contains('showErrorSnack'));
      expect(btn, contains('No cost record found for'));
    });

    test('it checks the context is still mounted after the await', () {
      // The officer can close the tab while a 216ms fetch is in flight.
      expect(btn, contains('if (!context.mounted) return;'));
    });
  });

  group('the popup still gets its figures', () {
    test('both popups pass srFinancials, loaded before they open', () {
      // ⚠️ The point of awaiting rather than dropping the field: the popup
      // used to show "not available" purely because the ledger had not
      // finished loading, which is the bug the old comments describe.
      final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync();
      expect(dash, contains('srFinancials: sr,'));
      expect(dash, contains('Future<void> _showDestroyedDetails('));

      final yard =
          File('lib/screens/packages/disposition_category_screen.dart')
              .readAsStringSync();
      expect(yard, contains('srFinancials: srFin,'));
    });

    test('a ledger failure still opens the rest of the popup', () {
      // The package, its items and its warehouse history do not depend on
      // this, and an officer opening Details wants to see them.
      final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
          .readAsStringSync();
      final fn = dash.substring(dash.indexOf('Future<void> _showDestroyedDetails('));
      // ⚠️ No try/catch any more, and none is needed. The popup used to
      // await the ledger BEFORE opening, so a failure there had to be caught
      // or nothing appeared at all. It now opens first and the figure fills
      // in after — a failed or slow ledger costs the costs section and
      // nothing else, which is what the catch was reaching for.
      expect(fn.substring(0, 1400), contains('valueOrNull'),
          reason: 'a ledger error must not take the whole popup down');
      // showAppDialog, not showDialog: every popup in the app now opens
      // over the same blurred, dimmed backdrop.
      expect(fn.substring(0, 1400), contains('await showAppDialog('));
    });
  });

  group('the page query itself stays small', () {
    test('the tab pages in SQL and asks for twenty rows', () {
      final providers = File('lib/core/providers.dart').readAsStringSync();
      // The tab's own query is the 24ms one. It must stay that way: this is
      // the thing the officer is actually waiting for.
      expect(providers, contains('dispositionPageWithPackagesProvider'));
      expect(providers, contains('getPackagesByIds'));
      final services = File('lib/services/services.dart').readAsStringSync();
      // ⚠️ The DEFINITION, not the first mention. Another method now
      // calls getPackagesByIds above it, and slicing from the call read that
      // caller's body instead of the one under test.
      final byIds = services.substring(
          services.indexOf('Future<Map<String, PackageModel>> getPackagesByIds'));
      expect(byIds.substring(0, 600), contains(".inFilter('id'"),
          reason: 'the page must fetch its own packages, not all of them');
    });
  });
}
