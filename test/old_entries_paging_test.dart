// Old Entries: legacy SR numbers, paged in SQL.
//
// The page fetched every package in the yard and kept the 18 carrying an old
// SR number. "Has a legacy number" is not a filter the user can clear -- it is
// the list's definition -- so it belongs in the query, not in a Dart `where`.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';

void main() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final screen =
      File('lib/screens/packages/old_entries_screen.dart').readAsStringSync();
  final method =
      services.substring(services.indexOf('getOldEntriesPaged'));

  group('the list defines itself in the query', () {
    test('a legacy SR number is required, and is not a clearable filter', () {
      expect(method, contains("q.not('old_sr_number', 'is', null)"));
      // ⚠️ Null is not the only empty: the column carries '' too, and a blank
      // string is not a legacy number.
      expect(method, contains("q.neq('old_sr_number', '')"));
    });

    test('it pages and counts through one closure', () {
      expect(method, contains('PgQuery narrow(PgQuery q)'));
      expect(method, contains('.range(offset, offset + limit - 1)'));
      expect(method, contains("narrow(supabase.from('packages')).count()"));
    });

    test('newest first, like every other register page', () {
      expect(method, contains(".order('created_at', ascending: false)"));
    });
  });

  group('this page searches things no other page does', () {
    test('the OLD number and the CusDec number are searchable', () {
      // ⚠️ The whole point of the page is finding goods by what they were
      // called BEFORE. Searching only the new number would defeat it.
      expect(method, contains('old_sr_number.ilike'));
      expect(method, contains('cusdec_no.ilike'));
      expect(method, contains('sr_number.ilike'));
      expect(method, contains('consignee_name.ilike'));
    });

    test('the year matches any of the places a year can appear', () {
      // ⚠️ A legacy entry filed under one numbering and re-registered under
      // another has to be findable by EITHER year -- SR/1290/2021 became
      // CED/GL1/OA/05/2024, and both years must find it.
      expect(method, contains(r'old_sr_number.ilike.%$year%'));
      expect(method, contains(r'sr_number.ilike.%$year%'));
      expect(method, contains(r'cusdec_date.ilike.%$year%'));
    });
  });

  group('the year list comes from the whole table', () {
    final years = services.substring(services.indexOf('getOldEntryYears'));

    test('it reads all four sources', () {
      expect(years,
          contains("select('old_sr_number, sr_number, entry_date, cusdec_date')"));
      expect(years, contains("for (final key in ['old_sr_number', 'sr_number', 'cusdec_date'])"));
      expect(years, contains("parseDbDate(m['entry_date'])"));
    });

    test('it is scoped to legacy rows, not the whole packages table', () {
      expect(years, contains(".not('old_sr_number', 'is', null)"));
      expect(years, contains(".neq('old_sr_number', '')"));
    });

    test('newest first, as every year filter reads', () {
      expect(years, contains('..sort((a, b) => b.compareTo(a))'));
    });
  });

  group('the query key', () {
    test('two identical queries are the same key', () {
      const a = OldEntryQuery(page: 2, search: '1290');
      const b = OldEntryQuery(page: 2, search: '1290');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every filter takes part in it', () {
      const base = OldEntryQuery();
      expect(base, isNot(const OldEntryQuery(page: 1)));
      expect(base, isNot(const OldEntryQuery(search: 'x')));
      expect(base, isNot(const OldEntryQuery(year: '2021')));
      expect(
          base,
          isNot(OldEntryQuery(dateStart: DateTime(2024, 1, 1))));
    });
  });

  group('the screen reads it', () {
    test('the paged provider, and the count from the server', () {
      expect(screen, contains('oldEntriesPageProvider(query)'));
      expect(screen, contains('total: result.total,'));
      expect(screen, isNot(contains('total: rows.length')));
    });

    test('the Dart filtering is gone', () {
      // ⚠️ Leaving any of it behind would mean the pager's total and the rows
      // under it disagree: the count comes from the database, so the rows must
      // come from the same narrowing.
      expect(screen, isNot(contains('// Apply Year filter')));
      expect(screen, isNot(contains('// Apply Date Range filter')));
      expect(screen, isNot(contains('.skip(_page * kClientPageSize)')));
      expect(screen, isNot(contains('List<String> _extractYears(')));
    });

    test('the year filter runs its own query', () {
      expect(screen, contains('oldEntryYearsProvider'));
    });

    test('a new search still starts at the top', () {
      expect(screen,
          contains('ref.listen(oldEntrySearchProvider, (_, __) => setState(() => _page = 0));'));
    });
  });
}
