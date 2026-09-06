// Two pages disagreeing about the same goods, and a worklist that would not
// let go of finished work.
//
//   * CED/GL1/SR/30/2026 (Butter Blocks 25kg) sold at tender for
//     Rs 5,533,000 and appears on Sold Goods -- while the Perishable page
//     still read "Awaiting Top Management". A perishable that SELLS never
//     reaches the DG: selling IS the outcome, and nothing recorded that, so
//     the row sat waiting for a decision nobody was going to make.
//
//   * Central Disposal's Tender Sales tab kept showing items already marked
//     Sold or Unsold, offering an action that had been taken. Its page is a
//     WORKLIST; the yard's is a RECORD.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
      .readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final shared =
      File('lib/screens/executive/unsold_shared.dart').readAsStringSync();
  final popup =
      File('lib/widgets/package_details_dialog.dart').readAsStringSync();
  final perishable =
      File('lib/screens/packages/perishable_goods_screen.dart').readAsStringSync();

  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('a sold perishable shows as sold', () {
    final view = File('postgres/36_perishable_sold_outcome.sql').readAsStringSync();

    test('the view reports the sale, not just the proposal', () {
      expect(view, contains('as sold'));
      expect(view, contains('sale.sold_price'));
      // ⚠️ Read from tender_sale_items, never written into unsold_proposals:
      // inventing a proposal row would put sold goods on the DG's Unsold Goods
      // desk and double-count them in every report reading that table.
      expect(view, contains('from public.tender_sale_items ti'));
      expect(view, contains('and ti.sold'));
    });

    test('a sold item no longer drops off the page', () {
      // The old WHERE kept a sent item only if a PROPOSAL came back, so a sold
      // one vanished from the page that exists to say what became of it.
      expect(view, contains('or sale.sold is not null'));
    });

    test('the migration asserts sold and proposal are exclusive', () {
      // Selling means the goods never reached the DG; a row with both is a
      // contradiction, so the migration fails rather than shipping it.
      expect(view, contains('are both sold and have a proposal'));
      expect(view, contains('sold perishable(s) have no price'));
    });

    test('the page asks for the sale with the page', () {
      expect(services, contains('Map<String, double> soldPriceByItem'));
      final fn = flat(services.substring(
          services.indexOf('getPerishableRowsPaged')));
      expect(fn.substring(0, 1800),
          contains("select('package_id, item_id, sold, sold_price')"));
    });

    test('the chip shows Sold and says what it fetched', () {
      expect(shared, contains('final double? soldPrice;'));
      final f = flat(shared);
      // ⚠️ Checked BEFORE the proposal: selling ends the story, so a pending
      // label would be wrong even if a proposal row somehow existed too.
      expect(f.indexOf('final sold = soldPrice;'),
          lessThan(f.indexOf('final p = proposal;')));
      expect(f, contains("label: 'Sold'"));
      expect(f, contains('never went to the Top Management Directorate'));
    });

    test('the perishable table passes the price through', () {
      expect(perishable, contains('soldPrice: result'));
      expect(perishable, contains('.soldPriceByItem[r.item.id]'));
    });

    test('the popup draws the outcome instead of hiding it', () {
      // ⚠️ It used to omit the tile entirely for a sold package, which left
      // the popup with no answer at all for goods that had plainly ended.
      expect(popup.contains('if (soldById.isEmpty) {'), isFalse,
          reason: 'the outcome tile is hidden for sold goods again');
      expect(popup, contains('final soldPrice = mine.where((s) => s.sold)'));
      expect(popup, contains('soldPrice: soldPrice'));
      expect(flat(popup), contains("sold != null ? 'Sold'"));
    });
  });

  group('the worklist lets go of finished work', () {
    final view =
        File('postgres/35_tender_summary_counts_unsold.sql').readAsStringSync();

    test('pending means UNDECIDED, not merely unsold', () {
      // ⚠️ These were the same thing only while a clock decided unsold. Now
      // that an officer marks each item, an item marked Unsold is finished.
      expect(view, contains('undecided_count'));
      expect(view, contains('(agg.undecided_count > 0)                  as has_pending'));
      expect(view, contains('count(*) filter (where ti.unsold)'));
    });

    test('the migration checks the counts add up', () {
      expect(view, contains('s.item_count <> s.sold_count + s.unsold_count + s.undecided_count'));
      expect(view, contains('are both sold and unsold'));
    });

    test('the item list drops anything already marked', () {
      final fn = flat(dash.substring(dash.indexOf('List<_TsRow> _rows()')));
      expect(fn.substring(0, 900),
          contains('widget.sale.items.where((s) => !s.sold && !s.unsold)'));
    });

    test('the yard keeps every item — its page is a record', () {
      final fn = flat(dash.substring(dash.indexOf('List<_TsRow> _rows()')));
      expect(fn.substring(0, 900), contains('widget.readOnly ? widget.sale.items'));
    });

    test('marking an item does not throw the officer to another tab', () {
      // They are working THROUGH a sale, item by item; a jump means
      // navigating back before the next one can be marked.
      final fn = flat(dash.substring(dash.indexOf('Future<void> _markUnsold')));
      expect(fn.substring(0, 3400).contains('goToDisposalTab'), isFalse,
          reason: 'marking an item navigates away again');
      expect(fn.substring(0, 3400), contains('marked as Unsold'));
    });
  });

  group('tax is a column, not a footnote', () {
    test('the sold table has Total Tax and Total Amount', () {
      expect(dash, contains("label: Text('Total Tax')"));
      expect(dash, contains("label: Text('Total Amount')"));
    });

    test('the total is price plus tax', () {
      final f = flat(dash);
      expect(f, contains('final total = item.soldPrice + saleItemTaxTotal(item);'));
    });

    test('the tax total reads the STORED taxes', () {
      // ⚠️ Not the tax table. The stored list is what was active at the moment
      // of sale: enabling a tax later must not change what a past sale was
      // charged, and disabling one must not make the charge disappear.
      expect(dash, contains('double saleItemTaxTotal(TenderSaleItemModel item)'));
      final fn = flat(dash.substring(dash.indexOf('double saleItemTaxTotal')));
      expect(fn.substring(0, 400), contains('item.appliedTaxes'));
      expect(fn.substring(0, 400).contains('disposalTaxesProvider'), isFalse);
    });

    test('the popup lists each stored tax and subtotals them', () {
      expect(popup, contains("label: '\${t['name']} (\${t['percentage']}%)'"));
      expect(popup, contains("label: 'Total Tax'"));
      expect(popup, contains('never today'));
    });
  });
}
