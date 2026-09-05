// Detained, Abandoned and Other had NO pager at all.
//
// They fetched every package in the yard and handed the whole list to
// DataTable2 -- worse than the paged screens ever were, because there the cost
// was at least bounded by what came back. All three now read one page of
// held_goods_rows.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';

void main() {
  final view = File('postgres/25_held_goods_view.sql').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final detained = File('lib/screens/packages/detained_packages_screen.dart')
      .readAsStringSync();
  final abandoned = File('lib/screens/packages/abandoned_packages_screen.dart')
      .readAsStringSync();
  final other =
      File('lib/screens/packages/other_packages_screen.dart').readAsStringSync();

  group('one view, three pages', () {
    test('each page has its own kind', () {
      expect(view, contains("'DETAINED'::text"));
      expect(view, contains("'ABANDONED'::text"));
      expect(view, contains("'OTHER'::text"));
    });

    test('a row is an ITEM, not a package', () {
      // ⚠️ CED/GL1/SR/67/2026 is two rows -- Ceramic Floor Tiles and Copper
      // Wire Coils -- because detention is decided per item.
      expect(view, contains('as item_id'));
      expect(view, contains('as row_key'));
    });

    test('the row keys cannot collide across sources', () {
      for (final prefix in ["'D:'", "'AE:'", "'AS:'", "'OE:'", "'OS:'", "'OF:'"]) {
        expect(view, contains(prefix), reason: '$prefix source missing');
      }
    });
  });

  group('detention is a holding STATUS, not an event', () {
    test('it ends when some other disposition arrives', () {
      // ⚠️ There is no [DETAIN] event to look for, so what marks the end of
      // detention is a settled note from somewhere else.
      expect(view, contains("in ('detain', 'detained', 'held')"));
      expect(view, contains("like '[ABANDONED]%'"));
      expect(view, contains("like '[FORFEIT%'"));
      expect(view, contains('settled item(s) are still listed as detained'));
    });

    test('a detained item is exactly one row', () {
      // Detention is a state; an abandonment can be several partial events.
      expect(view, contains('detained item(s) appear more than once'));
      expect(view, contains('duplicated row key(s)'));
    });
  });

  group('nothing finalised may be offered for action', () {
    test('the guard exists', () {
      // Otherwise an officer could dispose of the same goods twice.
      expect(view, contains('finalised item(s) are still listed as actionable'));
    });

    test('completed OTHER rows are the one exception, and only there', () {
      // [FINAL:OTHER] rows are read-only records, like Released and Sold on
      // their own pages.
      expect(view, contains('as completed'));
      expect(view, contains("like '[FINAL:OTHER]%'"));
      expect(view,
          contains('a completed row appeared on a page with no such state'));
    });
  });

  group('the legacy Other status keeps its guard', () {
    test('a free-text status qualifies only while actually held', () {
      // ⚠️ Without this a typo in the status field masquerades as an Other
      // package.
      expect(view, contains("lower(trim(pi.status)) not in ("));
      expect(view, contains('coalesce(wl.is_returned, false) = false'));
    });
  });

  group('the query', () {
    final method = services.substring(services.indexOf('getHeldGoodsPaged'));

    test('one filter closure serves the rows and the count', () {
      expect(method, contains('PgQuery narrow(PgQuery q)'));
      expect(method, contains('.range(offset, offset + limit - 1)'));
      expect(method, contains("narrow(supabase.from('held_goods_rows')).count()"));
    });

    test('sent items are excluded by the query, not by a set in Dart', () {
      expect(method, contains("if (!includeSent) q = q.eq('sent', false)"));
    });

    test('the yard filter matches the SR NUMBER, not the yard column', () {
      expect(method, contains(r"q.ilike('sr_number', '%/$yardSrPrefix/%')"));
    });
  });

  group('the header counts have their own query', () {
    final counts = services.substring(services.indexOf('getHeldGoodsCounts'));

    test('a hold always blocks; a decision releases early', () {
      // ⚠️ One place applies the rule. Counting it on the screen as well would
      // let the header and the query disagree.
      expect(counts, contains('if (hold || (!decided && deadline != null'));
      expect(counts, contains('actionable: list.length - inAppeal'));
    });

    test('it counts what the page shows, so it excludes sent items', () {
      expect(counts, contains(".eq('sent', false)"));
    });
  });

  group('the query key', () {
    test('two identical queries are the same key', () {
      const a = HeldGoodsQuery(kind: 'DETAINED', page: 1, search: 'tyre');
      const b = HeldGoodsQuery(kind: 'DETAINED', page: 1, search: 'tyre');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every filter takes part, the page kind included', () {
      const base = HeldGoodsQuery(kind: 'DETAINED');
      expect(base, isNot(const HeldGoodsQuery(kind: 'ABANDONED')));
      expect(base, isNot(const HeldGoodsQuery(kind: 'DETAINED', page: 1)));
      expect(base, isNot(const HeldGoodsQuery(kind: 'DETAINED', search: 'x')));
      expect(base, isNot(const HeldGoodsQuery(kind: 'DETAINED', year: '2026')));
      expect(base,
          isNot(const HeldGoodsQuery(kind: 'DETAINED', activity: 'Pending Licence')));
      expect(base,
          isNot(const HeldGoodsQuery(kind: 'DETAINED', yardSrPrefix: 'GL1')));
    });
  });

  group('all three screens are wired the same way', () {
    for (final entry in {
      'Detained': (src: () => detained, kind: 'DETAINED'),
      'Abandoned': (src: () => abandoned, kind: 'ABANDONED'),
      'Other': (src: () => other, kind: 'OTHER'),
    }.entries) {
      final name = entry.key;
      final src = entry.value.src();
      final kind = entry.value.kind;

      test('$name reads the paged provider', () {
        expect(src, contains("kind: '$kind',"));
        expect(src, contains('heldGoodsPageProvider(query)'));
        expect(src, isNot(contains('ref.watch(livePackagesProvider)')));
      });

      test('$name has a pager, and it uses the server total', () {
        expect(src, contains('TablePager('));
        expect(src, contains('total: result.total,'));
        expect(src, contains('pageSize: kDispositionPageSize,'));
      });

      test('$name counts its header in SQL', () {
        expect(src, contains("heldGoodsCountsProvider('$kind')"));
      });

      test('$name gets its years from their own query', () {
        expect(src, contains("heldGoodsYearsProvider('$kind')"));
      });

      test('$name no longer builds rows from every package', () {
        expect(src, isNot(contains('_buildRows(')));
        expect(src, contains('_rowsFrom('));
      });

      test('$name resets to page 1 when the year changes', () {
        // ⚠️ A narrowed result otherwise strands the reader on a page that no
        // longer exists.
        expect(src, contains('_page = 0;'));
      });
    }
  });
}
