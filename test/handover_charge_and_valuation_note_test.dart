import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comment lines dropped, then flattened.
///
/// ⚠️ Comments go from the RAW text LINE BY LINE, before the whitespace
/// collapse — flatten first and the newline a `//` runs to is gone, so every
/// assertion below would match prose as readily as code.
String code(String raw) => raw
    .split('\n')
    .where((l) =>
        !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('--'))
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final services = code(File('lib/services/services.dart').readAsStringSync());
  final form =
      code(File('lib/widgets/handover_form_dialog.dart').readAsStringSync());
  final cell = code(File('lib/widgets/handover_cell.dart').readAsStringSync());
  final note =
      code(File('lib/widgets/storage_charge_note.dart').readAsStringSync());
  final mig60 = File('postgres/60_handover_receipt.sql').readAsStringSync();

  group('a hand-over collects the storage charge', () {
    test('the button opens a FORM, it does not just set a flag', () {
      // ⚠️ Storage has been accruing since the goods arrived; the owner pays
      // it, the officer writes a receipt, and only then do the goods leave.
      // The button used to skip all of it, so the charge on the row beside it
      // was a figure nobody had a record of collecting.
      expect(cell, contains('showHandoverForm('));
      expect(cell, contains('if (result == null) return;'),
          reason: 'cancelling must write nothing');
    });

    test('the form shows the charge, a receipt field and the date', () {
      expect(form, contains('Receipt Number *'));
      expect(form, contains('Hand-over Date'));
      expect(form, contains('LKR \${money.format(widget.charge)}'));
    });

    test("today is pre-filled, and the future is not selectable", () {
      // ⚠️ Nearly every hand-over is recorded on the day it happens, and an
      // empty date field makes the officer type what the system already
      // knows — then get it wrong under pressure. But it stays EDITABLE:
      // goods collected on Friday and recorded on Monday are normal.
      expect(form, contains('DateTime _date = DateTime.now();'));
      expect(form, contains('lastDate: DateTime.now()'));
    });

    test('a receipt is required before the goods can go', () {
      // ⚠️ Without it the money has no record, and the goods have left.
      expect(form, contains('Enter the receipt number for the storage charge'));
    });

    test('the receipt lands in the SAME statement as the flag', () {
      // ⚠️ Two writes leave a window where the goods are marked gone with no
      // record of the money, and a failure between them leaves it that way
      // for good.
      expect(code(mig60), contains('handover_receipt_no = case when p_delivered'));
      expect(services, contains("'p_receipt_no': receiptNo"));
      expect(services, contains("'p_charge': charge"));
    });

    test('the migration DROPS the old 2-argument functions', () {
      // ⚠️ `create or replace` matches on the ARGUMENT LIST, so adding
      // parameters creates an OVERLOAD rather than replacing anything — and
      // the old version stays resolvable. A caller that forgot the receipt
      // would silently take it and hand the goods over with no record of the
      // money. The verify block caught exactly this on the first run.
      expect(code(mig60),
          contains('drop function if exists public.yard_toggle_reexport_delivery(uuid, boolean)'));
      expect(code(mig60), contains('an old overload survives'));
    });

    test('the stored amount is what was collected, not a recomputation', () {
      // ⚠️ Rates change — `storage_rates` is a history ICT edits — so a
      // charge recalculated next year would not match the receipt in the
      // owner's hand. What was collected is a fact about that day.
      expect(mig60, contains('The AMOUNT is stored, not recomputed'));
      expect(code(mig60), contains('handover_charge numeric'));
    });

    test('a receipt cannot exist without a delivery', () {
      expect(code(mig60),
          contains('warehouse_entries_handover_receipt_consistent'));
    });
  });

  group('a valuation sees what the goods have already cost', () {
    test('every form that sets a price carries the note', () {
      // ⚠️ A valuation set without it is a number chosen in ignorance: goods
      // worth Rs 40,000 that have run up Rs 90,000 in storage are worth
      // tendering at a different figure than the same goods admitted last
      // week, and the officer could not see that from the form.
      final valuation = code(
          File('lib/screens/valuation/valuation_dashboard_screen.dart')
              .readAsStringSync());
      final committee = code(
          File('lib/screens/executive/tender_committee_tab.dart')
              .readAsStringSync());
      final disposal = code(
          File('lib/screens/disposal/disposal_dashboard_screen.dart')
              .readAsStringSync());

      // Pending Valuation, and the re-valuation after a failed tender.
      expect('StorageChargeNote('.allMatches(valuation).length, 2,
          reason: 'both valuation forms need it');
      // The committee's figure, priced after four or more failed tenders.
      expect(committee, contains('StorageChargeNote('));
      // And the sale itself.
      expect(disposal, contains('StorageChargeNote('));
    });

    test('it charges only entries still HELD, and only this item', () {
      // ⚠️ A returned entry stopped accruing the day it closed, and a package
      // holds several items with separate entries — charging the whole
      // package on a form about one of them would overstate it, sometimes
      // several times over.
      expect(note, contains('if (e.isReturned) return false;'));
      expect(note, contains('return e.packageItemId == packageItemId;'));
    });

    test('it is a NOTE, never an input', () {
      // Nothing here changes what is charged: the charge is the rate history
      // times the days, and it goes on accruing whatever anybody types into
      // the form beside it.
      expect(note.contains('TextField('), isFalse);
      expect(note.contains('onChanged'), isFalse);
    });

    test('it moves when a warehouse entry does', () {
      // ⚠️ A charge that keeps the value it had when the dialog opened is
      // worse than none: the officer reads a stale number and writes it on a
      // receipt.
      final providers =
          code(File('lib/core/providers.dart').readAsStringSync());
      final start = providers.indexOf('final packageByIdProvider');
      expect(start, greaterThan(0));
      expect(providers.substring(start, start + 300),
          contains('warehouseRefreshTriggerProvider'));
    });
  });

  group("Central Disposal's Sold popup shows what the yard's does", () {
    test('it carries the tender history', () {
      // ⚠️ The yard's Sold Goods popup has carried every round, re-valuation,
      // bid and committee since it was written. The directorate that RUNS the
      // tenders opened the same package and saw none of it.
      final disposal = code(
          File('lib/screens/disposal/disposal_dashboard_screen.dart')
              .readAsStringSync());
      final start = disposal.indexOf('isSoldPage: true');
      expect(start, greaterThan(0));
      final around = disposal.substring(
          (start - 600).clamp(0, disposal.length), start + 300);
      expect(around, contains('tenderHistoryFor: saleItem?.forfeited'));
    });
  });
}
