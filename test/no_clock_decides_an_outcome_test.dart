// A clock used to decide whether goods were sold.
//
// An item not marked by Central Disposal fell to Unsold on its own once a
// working-day window closed -- and `workingDeadline` skips weekends AND Sri
// Lankan public holidays fetched from an API at runtime, so WHICH packages
// reached the DG's desk depended on the holiday calendar. Worse, once the
// window expired the sale left the tab, leaving the officer no way to record
// what had actually happened.
//
// Two things were found while removing it, both live bugs the auto-lapse had
// been covering for:
//
//   * `tender_sale_items.unsold` and `destruction_items.undestroyed` did not
//     exist in the database, though the app wrote to both. "Mark Unsold" and
//     "Mark Undestroyed" had never worked. (postgres/33, /34)
//   * The "Destruction Sales" tab and the Undestroyed / Re-destruction pool
//     had been dropped from the tab strip, but 361 lines of their widgets
//     stayed behind, carrying this rule with them.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

void main() {
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final models = File('lib/models/models.dart').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  TenderSaleModel sale({DateTime? date, String? start, String? end}) =>
      TenderSaleModel(
        id: 't',
        saleNumber: 'T/1',
        saleDate: date,
        saleTime: start,
        saleEndTime: end,
        items: const [],
        createdAt: DateTime(2026, 1, 1),
      );

  group('nothing lapses on a deadline any more', () {
    test('a month-old unmarked sale is still awaiting a decision', () {
      final old = sale(
          date: DateTime.now().subtract(const Duration(days: 30)),
          start: '10:00',
          end: '11:00');
      expect(old.stage, TenderStage.awaitingDecision);
    });

    test('TenderStage has no fourth, lapsed state', () {
      expect(TenderStage.values, hasLength(3));
      expect(models.contains('lapsed('), isFalse);
    });

    test('unsoldDeadline is gone from the model entirely', () {
      // ⚠️ Leaving the getter would invite the rule back one call site at a
      // time. Nothing may compute it.
      expect(models.contains('unsoldDeadline'), isFalse,
          reason: 'the deadline getter is back');
      expect(models.contains('workingDeadline('), isFalse,
          reason: 'a working-day deadline is being computed again');
    });

    test('no screen hides a sale behind a closed window', () {
      for (final path in [
        'lib/screens/disposal/disposal_dashboard_screen.dart',
        'lib/screens/executive/tender_sales_view_tab.dart',
        'lib/screens/reports/reports_screen.dart',
      ]) {
        final src = flat(File(path).readAsStringSync());
        expect(src.contains('unsoldDeadline'), isFalse, reason: path);
        expect(src.contains('windowClosed'), isFalse, reason: path);
      }
    });
  });

  group('a pool is entered by a MARK', () {
    test('the unsold pool reads the item flag, not a clock', () {
      final fn = flat(services.substring(
          services.indexOf('getUnsoldTenderSales'),
          services.indexOf('getUnsoldRetenderPaged')));
      expect(fn, contains('it.forfeitedPackageId == id && it.unsold'));
      // ⚠️ Not "no deadline anywhere" -- APPEAL deadlines are a different
      // thing and belong here. What must be gone is the unsold one.
      expect(fn.contains('unsoldDeadline'), isFalse,
          reason: 'a clock is deciding entry to the Unsold pool again');
    });

    test('the undestroyed pool does the same', () {
      final i = services.indexOf('getUndestroyedDestructions');
      final fn = flat(services.substring(i, i + 2500));
      expect(fn, contains('it.forfeitedPackageId == id && it.undestroyed'));
      expect(fn.contains('unsoldDeadline'), isFalse,
          reason: 'a selling clock is back on the destruction side');
    });

    test('the columns those flags need exist', () {
      // ⚠️ They did not. The app wrote to them and the writes failed; the
      // auto-lapse hid that for as long as it was there.
      final m34 = File('postgres/34_tender_unsold_columns.sql').readAsStringSync();
      expect(m34, contains('add column if not exists unsold boolean'));
      expect(m34, contains('add column if not exists unsold_at timestamptz'));
      // Sold and unsold are two outcomes of one decision, not two flags.
      expect(m34, contains('check (not (sold and unsold))'));

      final m33 = File('postgres/33_destruction_undestroyed_columns.sql')
          .readAsStringSync();
      expect(m33, contains('add column if not exists undestroyed boolean'));
      expect(m33, contains('check (not (destroyed and undestroyed))'));
    });

    test('the backfill is one-shot, so it cannot re-run and re-mark', () {
      final m34 = File('postgres/34_tender_unsold_columns.sql').readAsStringSync();
      expect(m34, contains("flag = 'tender_unsold_backfilled'"));
      expect(m34, contains('app_migration_flags'));
    });
  });

  group('the header says how long, instead of how long is left', () {
    test('the model measures from when bidding STARTED', () {
      expect(models, contains('Duration? get sinceSaleStarted'));
    });

    test('a sale that has not started reports nothing', () {
      final future =
          sale(date: DateTime.now().add(const Duration(days: 2)), start: '10:00');
      expect(future.sinceSaleStarted, isNull);
    });

    test('an old sale reports the days', () {
      final old =
          sale(date: DateTime.now().subtract(const Duration(days: 5)), start: '09:00');
      expect(old.sinceSaleStarted!.inDays, greaterThanOrEqualTo(4));
    });

    test('the countdown widget is now an elapsed one', () {
      expect(dash.contains('_DeadlineCountdown'), isFalse);
      expect(dash, contains('class _ElapsedSinceSale'));
      expect(dash, contains('since bidding started'));
    });

    test('destruction has no timer at all', () {
      // It is not a sale: nothing is bid for, so a selling clock never
      // belonged there.
      expect(dash.contains("label: 'Destroy within'"), isFalse);
    });
  });

  group('a perishable sale that has started stands out', () {
    test('the model names the special sale rather than testing a string', () {
      expect(models, contains('bool get isPerishableSale'));
      expect(models, contains("tenderType == 'special'"));
    });

    test('the card is highlighted, and only once bidding has started', () {
      final f = flat(dash);
      expect(f, contains('final urgentPerishable ='));
      expect(f, contains('widget.sale.isPerishableSale'));
      // ⚠️ Before bidding starts there is nothing to act on, and marking every
      // future special sale would make the mark mean nothing.
      expect(f, contains('widget.sale.saleTimePassed'));
      // Not once every item is marked, either.
      //
      // ⚠️ `settled`, not `allSold`. This assertion's own intent is "every
      // item MARKED", and all-sold is a narrower thing: a sale whose items
      // all went Unsold is equally finished. `settled` is all-decided on the
      // yard's page and stays all-sold for the directorates, which measure
      // progress by the sold count.
      expect(f, contains('!settled && widget.sale.isPerishableSale'));
      expect(f, contains(
          'final settled = widget.closeWhenAllDecided ? widget.sale.allDecided : allSold;'));
    });

    test('it carries the leaf the rest of the app uses for perishables', () {
      expect(flat(dash), contains('urgentPerishable ? Icons.eco_rounded : Icons.receipt_long_rounded'));
    });

    test('the elapsed chip warms up sooner for them', () {
      // These goods spoil while a decision is outstanding.
      expect(flat(dash), contains('final warmAt = widget.urgent ? 1 : 3;'));
      expect(flat(dash), contains('final hotAt = widget.urgent ? 3 : 7;'));
    });
  });

  group('the dead destruction-sale code is gone', () {
    test('neither widget is left in the file', () {
      expect(dash.contains('class _DestructionsTab'), isFalse);
      expect(dash.contains('class _UndestroyedReDestructionTab'), isFalse);
    });

    test('DestructionCard stays — the yard still uses it', () {
      expect(dash, contains('class DestructionCard'));
      final yard =
          File('lib/screens/forfeited_packages/destruction_disposal_screen.dart')
              .readAsStringSync();
      expect(yard, contains('DestructionCard('));
    });
  });
}
