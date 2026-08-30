import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/db/pg_query.dart';
import 'package:cus_yard_management/core/db/pg_schema.dart';

/// Renders SQL without a database.
///
/// The foreign keys normally come from the live catalog. Here they are stated
/// explicitly so the generated SQL can be checked on its own — the interesting
/// bugs (a to-many embed rendered as an object, the wrong join column for
/// returned_by) are all visible in the SQL text, and catching them here is far
/// cheaper than noticing a null inside fromJson at run time.
void main() {
  setUpAll(() {
    PgSchema.instance.loadForTest(const [
      PgForeignKey(
          constraint: 'package_items_package_id_fkey',
          table: 'package_items',
          column: 'package_id',
          target: 'packages',
          targetColumn: 'id'),
      PgForeignKey(
          constraint: 'warehouse_entries_package_id_fkey',
          table: 'warehouse_entries',
          column: 'package_id',
          target: 'packages',
          targetColumn: 'id'),
      PgForeignKey(
          constraint: 'warehouse_entries_warehouse_id_fkey',
          table: 'warehouse_entries',
          column: 'warehouse_id',
          target: 'warehouses',
          targetColumn: 'id'),
      // The two that make `profiles` ambiguous, and why hints exist.
      PgForeignKey(
          constraint: 'warehouse_entries_returned_by_fkey',
          table: 'warehouse_entries',
          column: 'returned_by',
          target: 'profiles',
          targetColumn: 'id'),
      PgForeignKey(
          constraint: 'warehouse_entries_admitted_by_fkey',
          table: 'warehouse_entries',
          column: 'admitted_by',
          target: 'profiles',
          targetColumn: 'id'),
      PgForeignKey(
          constraint: 'packages_inspected_by_fkey',
          table: 'packages',
          column: 'inspected_by',
          target: 'profiles',
          targetColumn: 'id'),
    ]);
  });

  group('embed shape', () {
    test('to-many becomes a json array', () {
      final sql = PgQuery('packages').select('*, package_items(*)').debugSql();
      // A list, because package_items points AT packages.
      expect(sql, contains('json_agg'));
      expect(sql, contains("coalesce(json_agg"));
      // Joined on the child's own foreign key.
      expect(sql, contains('"package_id" = '));
    });

    test('to-one becomes a single object', () {
      final sql =
          PgQuery('packages').select('*, profiles(full_name)').debugSql();
      // An object, because packages points AT profiles.
      expect(sql, isNot(contains('json_agg')));
      expect(sql, contains('limit 1'));
      expect(sql, contains('jsonb_build_object'));
    });

    test('an ambiguous embed is refused rather than guessed', () {
      // warehouse_entries has two foreign keys into profiles. Picking one at
      // random would put the wrong officer's name on the record.
      expect(
        () => PgQuery('warehouse_entries').select('*, profiles(*)').debugSql(),
        throwsA(isA<PgQueryException>()),
      );
    });

    test('a hint picks the right foreign key', () {
      final sql = PgQuery('warehouse_entries')
          .select('*, returned_profile:profiles!returned_by(full_name)')
          .debugSql();
      expect(sql, contains('"returned_by"'));
      expect(sql, isNot(contains('"admitted_by"')));
      // Comes back under the alias the model reads.
      expect(sql, contains('as "returned_profile"'));
    });

    test('nested embeds nest in the SQL', () {
      final sql = PgQuery('packages')
          .select('*, warehouse_entries(*, warehouses(*))')
          .debugSql();
      // The inner subquery sits inside the outer one.
      final agg = 'json_agg'.allMatches(sql).length;
      expect(agg, 1, reason: 'warehouses is to-one, so only one json_agg');
      expect(sql, contains('"warehouse_id"'));
    });

    test('star plus columns keeps every column', () {
      final sql = PgQuery('packages')
          .select('*, warehouse_entries(*, warehouses(name, code))')
          .debugSql();
      // `*` merges the whole row with the built object.
      expect(sql, contains('to_jsonb'));
      expect(sql, contains('||'));
    });
  });

  group('filters', () {
    test('eq is parameterised, never interpolated', () {
      final q = PgQuery('packages').select('id').eq('sr_number', "'; drop--");
      final sql = q.debugSql();
      expect(sql, contains('@p0'));
      expect(sql, isNot(contains('drop--')));
      expect(q.debugParams()['p0'], "'; drop--");
    });

    test('an empty inFilter matches nothing instead of failing', () {
      // `in ()` is a syntax error, and an empty set legitimately matches
      // nothing — this used to be a crash waiting for an empty list.
      final sql = PgQuery('packages').select('id').inFilter('id', []).debugSql();
      expect(sql, contains('false'));
    });

    test('not(is null) becomes is not null', () {
      // The one .not() in the app: tender_committees, submitted_value.
      final sql = PgQuery('tender_committees')
          .select('forfeited_package_id')
          .not('submitted_value', 'is', null)
          .debugSql();
      expect(sql, contains('is not null'));
      // The operand is syntax, not a value — binding it would not parse.
      expect(sql, isNot(contains('is not @')));
    });

    test('is null renders as SQL, not a parameter', () {
      final sql = PgQuery('packages').select('id').is_('yard', null).debugSql();
      expect(sql, contains('is null'));
    });

    test('or() splits into real terms and binds the values', () {
      final q = PgQuery('packages')
          .select('id')
          .or('created_at.gte.2026-01-01,updated_at.gte.2026-01-01');
      final sql = q.debugSql();
      expect(sql, contains(' or '));
      expect(sql, contains('@or_0'));
      expect(sql, contains('@or_1'));
      // Coerced to a real timestamp so Postgres compares dates, not strings.
      expect(q.debugParams()['or_0'], isA<DateTime>());
    });

    test('order and limit come through', () {
      final sql = PgQuery('packages')
          .select('id')
          .order('created_at', ascending: false)
          .limit(25)
          .debugSql();
      expect(sql, contains('order by'));
      expect(sql, contains('desc'));
      expect(sql, contains('limit 25'));
    });

    test('range becomes offset + limit', () {
      final sql = PgQuery('packages').select('id').range(20, 39).debugSql();
      expect(sql, contains('limit 20'));
      expect(sql, contains('offset 20'));
    });
  });

  group('mutations', () {
    test('insert lists columns once and binds every value', () {
      final q = PgQuery('packages').insert({'sr_number': 'X', 'yard': 'GL1'});
      final sql = q.debugSql();
      expect(sql, startsWith('insert into "packages"'));
      expect(sql, contains('@v0'));
      expect(sql, contains('@v1'));
    });

    test('a batch insert with ragged maps still lines up', () {
      final q = PgQuery('package_items').insert([
        {'name': 'a', 'hs_code': '1'},
        {'name': 'b'}, // no hs_code
      ]);
      final sql = q.debugSql();
      // One column list, two tuples — the missing value binds as null.
      expect('values'.allMatches(sql).length, 1);
      expect(q.debugParams().length, 4);
    });

    test('upsert names the conflict target', () {
      final sql = PgQuery('profiles')
          .upsert({'id': 'x', 'full_name': 'Y'}).debugSql();
      expect(sql, contains('on conflict ("id")'));
      expect(sql, contains('do update set'));
      // The conflict column itself is not re-assigned.
      expect(sql, isNot(contains('"id" = excluded."id"')));
    });

    test('update strips the alias the where clause was built with', () {
      final sql = PgQuery('packages')
          .update({'status': 'sold'})
          .eq('id', 'abc')
          .debugSql();
      expect(sql, startsWith('update "packages" set'));
      expect(sql, isNot(contains('t.')));
    });

    test('delete without a filter is refused', () {
      // Every call site has a filter today. If a refactor drops one, this
      // must fail rather than empty the table.
      expect(() => PgQuery('packages').delete().debugSql(),
          throwsA(isA<PgQueryException>()));
    });

    test('delete with a filter is fine', () {
      final sql = PgQuery('packages').delete().eq('id', 'abc').debugSql();
      expect(sql, startsWith('delete from "packages"'));
      expect(sql, contains('where'));
    });
  });

  group('count', () {
    test('counts rows without selecting them', () {
      // How services.dart calls it: filters applied, then .count() last.
      final sql = PgQuery('packages').eq('yard', 'GL1').count().debugSql();
      expect(sql, contains('count(*)'));
      expect(sql, isNot(contains('json_agg')));
      // The filter still applies — a count of everything would be wrong.
      expect(sql, contains('@p0'));
    });
  });

  group('the real queries from the app', () {
    test('the packages query renders', () {
      final sql = PgQuery('packages')
          .select('*, package_items(*), warehouse_entries(*, warehouses(*), '
              'returned_profile:profiles!returned_by(full_name, badge_number)), '
              'profiles(*)')
          .eq('sr_number', 'X')
          .debugSql();
      // Two to-many embeds, so two aggregates.
      expect('json_agg'.allMatches(sql).length, 2);
      // Top-level embeds come back as named columns...
      expect(sql, contains('as "package_items"'));
      expect(sql, contains('as "warehouse_entries"'));
      expect(sql, contains('as "profiles"'));
      // ...while one nested inside another is a key in its parent object.
      expect(sql, contains("'returned_profile',"));
      // And it follows returned_by, not admitted_by.
      expect(sql, contains('"returned_by"'));
      expect(sql, isNot(contains('"admitted_by"')));
      // packages -> profiles is the inspected_by key, the only one there.
      expect(sql, contains('"inspected_by"'));
    });
  });
}
