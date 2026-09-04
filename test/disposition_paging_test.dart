// Paging in SQL needs the ROWS to exist in SQL.
//
// The disposition pages do not list packages -- they list ITEMS, and one
// package can produce several rows from three different sources, merged and
// re-sorted by date. The screen built that shape in Dart from every package in
// the yard, then called .skip().take(): drawing page 1 cost the whole table,
// and the cost grew with the yard rather than with the page.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/widgets/table_pager.dart';

void main() {
  final view = File('postgres/18_disposition_rows_view.sql').readAsStringSync();
  final delivery =
      File('postgres/20_disposition_rows_delivery.sql').readAsStringSync();
  final indexes =
      File('postgres/19_disposition_rows_indexes.sql').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();

  group('the view carries every row the page shows', () {
    test('all three sources are present', () {
      // An entry with a [FINAL:] tag, an item whose status says so with no
      // tagged entry, and a Top Management re-export ruling.
      expect(view, contains("'entry'::text"));
      expect(view, contains("'item'::text"));
      expect(view, contains("'proposal'::text"));
    });

    test('the item source excludes anything a tagged entry already covers', () {
      // ⚠️ This is the screen's coveredItemIds guard. Without it the same
      // goods appear twice on one page, once from each source.
      final src2 = view.substring(view.indexOf("'item'::text"));
      expect(src2, contains('and not exists ('));
      expect(src2, contains('w2.package_item_id = pi.id'));
    });

    test('the pending destruction tag is kept', () {
      // ⚠️ FINAL:DESTROY (no ED) is what disposeWarehouseItem writes -- it
      // upper-cases the action name. Dropping it hides every package awaiting
      // destruction, which is how they get confirmed.
      expect(view, contains("'FINAL:DESTROY'"));
    });

    test('one date column, whatever the source', () {
      // The page sorts on it; a column that is null for half the rows would
      // scatter them.
      expect(view, contains('as happened_at'));
      expect(view,
          contains('coalesce(w.returned_at, w.admitted_at, p.updated_at)'));
    });

    test('the row key cannot collide across sources', () {
      expect(view, contains("('E:' || w.id::text)"));
      expect(view, contains("('I:' || pi.id::text)"));
      expect(view, contains("('P:' || up.id::text)"));
    });
  });

  group('delivery is answered in SQL too', () {
    test('each page reads its own source', () {
      expect(delivery, contains('tender_sale_items ti'));
      expect(delivery, contains('destruction_items di'));
      expect(delivery, contains('unsold_proposals up2'));
    });

    test('it resolves per SALE, not per package', () {
      // ⚠️ An item sold across two partial tenders has two receipts and two
      // delivery states; the old package-keyed map flattened them.
      expect(delivery,
          contains('coalesce(ti.package_item_id, fp2.item_id) = r.item_id'));
      expect(delivery, contains('order by ti.sold_at desc nulls last'));
    });

    test('a page with no hand-over step reads NULL, not false', () {
      // "Not applicable" and "still waiting" are different answers -- false
      // would put every OTHER row under the Pending filter.
      expect(delivery,
          contains("where final_tag = 'OTHER' and delivered is not null"));
    });

    test('the three-source body is reused, not retyped', () {
      // Two copies of it would drift, and the symptom is a page that shows
      // different rows depending on which migration ran last.
      expect(delivery,
          contains("The three-source body below is migration 18's, unchanged"));
    });
  });

  group('it stays fast at the volume it exists for', () {
    test('the tag expression is indexed', () {
      // ⚠️ The filter is on an EXPRESSION, so an ordinary index on
      // return_notes cannot serve it. This one matches the view's predicate
      // character for character.
      expect(indexes, contains('warehouse_entries_disposition_tag_idx'));
      expect(indexes, contains(r"from '^\[([^\]]+)\]'"));
    });

    test('the item scan is indexed, and only over the statuses that qualify',
        () {
      expect(indexes, contains('package_items_disposition_status_idx'));
      expect(indexes, contains('where lower(coalesce(status'));
    });

    test('the sort column is indexed', () {
      expect(indexes, contains('warehouse_entries_returned_at_idx'));
    });
  });

  group('the query goes out once, and the count agrees with it', () {
    test('one filter closure serves both queries', () {
      // ⚠️ Two separately-written filters drift, and the symptom is a pager
      // whose total disagrees with the rows under it.
      final m = services.substring(services.indexOf('getDispositionRowsPaged'));
      expect(m, contains('PgQuery narrow(PgQuery q)'));
      expect(m, contains("narrow(supabase.from('disposition_rows').select('*'))"));
      expect(m, contains("narrow(supabase.from('disposition_rows')).count()"));
    });

    test('it asks for one page, not the table', () {
      final m = services.substring(services.indexOf('getDispositionRowsPaged'));
      expect(m, contains('.range(offset, offset + limit - 1)'));
      expect(m, contains(".order('happened_at', ascending: false)"));
    });
  });

  group('the query key', () {
    test('two identical queries are the same key', () {
      // ⚠️ A provider family key without value equality opens a fresh request
      // on every rebuild, and the page flickers through loading forever.
      const a = DispositionQuery(finalTag: 'SOLD', page: 2, search: 'tyre');
      const b = DispositionQuery(finalTag: 'SOLD', page: 2, search: 'tyre');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every filter takes part in the key', () {
      const base = DispositionQuery(finalTag: 'SOLD');
      expect(base, isNot(const DispositionQuery(finalTag: 'DESTROYED')));
      expect(base, isNot(const DispositionQuery(finalTag: 'SOLD', page: 1)));
      expect(base, isNot(const DispositionQuery(finalTag: 'SOLD', search: 'x')));
      expect(base, isNot(const DispositionQuery(finalTag: 'SOLD', yard: 'GL1')));
      expect(
          base, isNot(const DispositionQuery(finalTag: 'SOLD', year: '2026')));
      expect(base,
          isNot(const DispositionQuery(finalTag: 'SOLD', delivered: true)));
    });

    test('All is a third answer, not the absence of one', () {
      // Delivered / Pending / All: null must differ from both.
      const all = DispositionQuery(finalTag: 'SOLD');
      const delivered = DispositionQuery(finalTag: 'SOLD', delivered: true);
      const pending = DispositionQuery(finalTag: 'SOLD', delivered: false);
      expect({all, delivered, pending}.length, 3);
    });
  });

  group('the page size the query uses is the page size the pager draws', () {
    test('they agree', () {
      // ⚠️ If these drift the page numbers mean nothing: the pager would draw
      // 20 rows per page while the query fetched 25.
      expect(kDispositionPageSize, kClientPageSize);
    });
  });

  group('a row of the view', () {
    test('parses into the model the screen reads', () {
      final row = DispositionRow.fromJson({
        'row_key': 'E:abc',
        'source': 'entry',
        'package_id': 'p1',
        'sr_number': 'CED/GL1/SR/07/2025',
        'consignee_name': 'Palm Grove',
        'yard': 'GL1',
        'item_id': 'i1',
        'entry_id': 'e1',
        'proposal_id': null,
        'final_tag': 'SOLD',
        'item_name': 'Truck Tyres',
        'hs_code': '4011.20.00',
        'quantity': 40,
        'note': 'sold at auction',
        'officer': 'A. Munasinghe',
        'happened_at': '2026-09-04T00:00:00Z',
      });
      expect(row.srNumber, 'CED/GL1/SR/07/2025');
      expect(row.quantity, 40);
      expect(row.isTopManagement, isFalse);
    });

    test('a Top Management row says so', () {
      final row = DispositionRow.fromJson({
        'row_key': 'P:xyz',
        'source': 'proposal',
        'package_id': 'p2',
        'sr_number': 'CED/GL1/SR/16/2026',
        'consignee_name': 'Metro',
        'final_tag': 'RE-EXPORTED',
        'item_name': 'Cotton Bed Sheets',
        'quantity': 130,
        'happened_at': '2026-08-26T00:00:00Z',
      });
      expect(row.isTopManagement, isTrue);
      // The Decided By pill needs this to tell the two routes apart.
      expect(row.source, 'proposal');
    });
  });
}
