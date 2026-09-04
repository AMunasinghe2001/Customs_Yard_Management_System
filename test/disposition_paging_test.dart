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

  group('the screen actually uses it', () {
    final screen =
        File('lib/screens/packages/disposition_category_screen.dart')
            .readAsStringSync();
    final flat = screen.replaceAll(RegExp(r'\s+'), ' ');

    test('it reads the paged provider, not every package in the yard', () {
      expect(screen, contains('dispositionPageWithPackagesProvider(_query)'));
      expect(screen, isNot(contains('ref.watch(livePackagesProvider)')));
    });

    test('every filter is in the query key, so every filter runs in SQL', () {
      final q = screen.substring(screen.indexOf('DispositionQuery get _query'));
      for (final field in ['finalTag:', 'page:', 'search:', 'dateStart:',
                           'dateEnd:', 'year:', 'delivered:']) {
        expect(q, contains(field), reason: '$field must reach the database');
      }
    });

    test('the row builders are gone, not duplicated', () {
      // ⚠️ Keeping a Dart copy beside the view is how the two drift: the page
      // would show one set of rows and the pager count another.
      expect(screen, isNot(contains('List<_CategoryRow> _buildRows(')));
      expect(screen, isNot(contains('List<_CategoryRow> _topManagementRows()')));
      expect(screen, contains('List<_CategoryRow> _rowsFrom('));
    });

    test('the count and the pager both come from the server total', () {
      // A count taken from the loaded list can only ever say "20 of 20".
      expect(flat, contains(r"Text('${p.total} ${widget.countLabel}'"));
      expect(flat, contains('total: result.total,'));
      expect(flat, contains('pageSize: kDispositionPageSize,'));
    });

    test('the year filter runs its own query', () {
      // ⚠️ One page holds twenty rows, which would offer only the years
      // visible right now.
      expect(screen, contains('dispositionYearSourceProvider('));
    });

    test('which route a row took comes from the view, not from a lookup', () {
      // ⚠️ Deriving it from a second provider means a row reports itself as a
      // yard row while that provider is still loading, and the Decided By
      // pill flips under the reader's eyes.
      expect(screen, contains('fromTopManagement: r.isTopManagement,'));
      expect(screen, isNot(contains('bool get fromTopManagement => proposal != null')));
    });

    test('a package missing between the two queries is skipped, not half-built',
        () {
      expect(screen, contains('if (pkg == null) continue;'));
    });
  });

  group('a release is the disposition with NO tag', () {
    final released =
        File('postgres/21_disposition_rows_released.sql').readAsStringSync();
    final filters =
        File('postgres/22_disposition_rows_release_filters.sql')
            .readAsStringSync();
    final screen = File('lib/screens/packages/returned_packages_screen.dart')
        .readAsStringSync();

    test('it matches the ABSENCE of a bracket, which a tag list cannot', () {
      // ⚠️ This is why RELEASED is a fourth source rather than another entry
      // in the tag list: the other three match a tag, this one matches not
      // having one.
      expect(released, contains("coalesce(trim(w.return_notes), '') = ''"));
      expect(released, contains("trim(w.return_notes) not like '[%'"));
      expect(released, contains("like '[FINAL:RELEASED]%'"));
      expect(released, contains("like '[RELEASE%'"));
    });

    test('a released row cannot also be a disposed one', () {
      // Both rules run over the same entries, so they have to be mutually
      // exclusive or the same goods show on two pages.
      expect(released, contains('an entry is both released and disposed'));
    });

    test('a release has no separate hand-over step', () {
      // The release IS the hand-over.
      expect(released,
          contains('a released row claims a separate delivery state'));
    });

    test('the receipt number is split out so it can be searched in SQL', () {
      // ⚠️ It is one field of a pipe-separated note, not a column. Leaving it
      // for the app to parse is what forced the fetch-everything.
      expect(filters, contains('as receipt_no'));
      expect(filters, contains('Receipt No:'));
      // And the verify proves the split actually happened.
      expect(filters, contains('still carry the rest of the note'));
    });

    test('the view is DROPPED, not replaced, when columns move', () {
      // ⚠️ Postgres refuses `create or replace` when the new column list is
      // not a pure append, and these land inside the subquery.
      expect(filters, contains('drop view if exists public.disposition_rows;'));
    });

    test('the screen reads the paged provider', () {
      expect(screen, contains("finalTag: 'RELEASED',"));
      expect(screen, contains('dispositionPageWithPackagesProvider(query)'));
      expect(screen, isNot(contains('_buildReturnedRows')));
    });

    test('its two extra filters reach the database', () {
      // The Reason dropdown and the receipt-number search are the reason this
      // page needed two columns no other page uses.
      expect(screen, contains('holdReason: rFilter,'));
      final services = File('lib/services/services.dart').readAsStringSync();
      expect(services, contains("q = q.eq('hold_reason', holdReason);"));
      expect(services, contains('receipt_no.ilike'));
    });

    test("'all' means no filter, not a reason named all", () {
      final services = File('lib/services/services.dart').readAsStringSync();
      final m = services.substring(services.indexOf('getDispositionRowsPaged'));
      expect(m, contains("holdReason != 'all'"));
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
