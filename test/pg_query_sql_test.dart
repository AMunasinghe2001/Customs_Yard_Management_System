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
      // audit_logs -> profiles, for the embed-filter tests below.
      PgForeignKey(
          constraint: 'audit_logs_user_id_fkey',
          table: 'audit_logs',
          column: 'user_id',
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

  group('filters on an embedded table', () {
    // PostgREST let a filter name a column on an EMBED (`profiles.role`), and
    // the app relies on it: AuditLogService.getAllLogs keeps only rows whose
    // ACTOR is yard staff. The builder used to quote the whole thing as one
    // identifier, emitting t."profiles.role" -> `column t.profiles.role does
    // not exist`, which the dashboard reported to the user as
    // "check your internet connection".
    test('embed.column becomes a correlated EXISTS, not a bare column', () {
      final sql = PgQuery('audit_logs')
          .select('*, profiles!inner(full_name, role)')
          .inFilter('profiles.role', ['admin', 'officer']).debugSql();

      // The bug, stated directly.
      expect(sql, isNot(contains('"profiles.role"')),
          reason: 'the embed filter was quoted as a single identifier');

      expect(sql, contains('exists (select 1 from "profiles"'));
      // Correlated back to the parent row through the foreign key.
      expect(sql, contains('"user_id"'));
      expect(sql, contains('"role" = any('));
    });

    test('an ordinary column filter is untouched', () {
      final sql = PgQuery('audit_logs')
          .select('*')
          .eq('yard', 'GL1')
          .debugSql();
      expect(sql, isNot(contains('exists (select 1')));
      expect(sql, contains('"yard" ='));
    });

    test('a dotted name that is NOT an embed stays a plain column', () {
      // Nothing named `foo` is embedded here, so this must not be rewritten
      // into an EXISTS against a table that does not exist.
      final sql =
          PgQuery('audit_logs').select('*').eq('foo.bar', 1).debugSql();
      expect(sql, isNot(contains('exists (select 1')));
      expect(sql, contains('"foo.bar"'));
    });

    // A schema-qualified TABLE must split; a dotted COLUMN must not. One
    // shared quoting helper cannot do both -- making it split fixed
    // `auth.users` (42P01: relation does not exist) and simultaneously broke
    // the column case above, which had no relation-side test to catch it.
    test('a schema-qualified table splits into "schema"."table"', () {
      final sql = PgQuery('auth.users').select('*').debugSql();
      expect(sql, contains('"auth"."users"'));
      expect(sql, isNot(contains('"auth.users"')),
          reason: 'Postgres reads that as ONE table with a dot in its name.');
    });

    test('an unqualified table is still quoted as one name', () {
      expect(PgQuery('audit_logs').select('*').debugSql(),
          contains('"audit_logs"'));
    });

    test('every filter operator gets wrapped, not just `in`', () {
      final eq = PgQuery('audit_logs')
          .select('*, profiles(role)')
          .eq('profiles.role', 'admin')
          .debugSql();
      expect(eq, contains('exists (select 1 from "profiles"'));

      final isNull = PgQuery('audit_logs')
          .select('*, profiles(role)')
          .is_('profiles.role', null)
          .debugSql();
      expect(isNull, contains('exists (select 1 from "profiles"'));
      expect(isNull, contains('is null'));
    });
  });

  group('or() boolean groups', () {
    // The appeal portal asks for "inside the window, OR undated and created
    // inside the window". The parser used to split every term on '.', so the
    // nested and(...) became the column `and(entry_date` and the query died
    // with `syntax error at or near "$2"` — shown to the user as
    // "Something went wrong".
    test('a nested and(...) group is parsed, not split on dots', () {
      final sql = PgQuery('packages')
          .select('*')
          .or('entry_date.gte.2026-01-01,'
              'and(entry_date.is.null,created_at.gte.2026-01-01)')
          .debugSql();

      expect(sql, isNot(contains('and(entry_date')),
          reason: 'the nested group was treated as a column name');
      // Outer OR of a leaf and a parenthesised AND.
      expect(sql, contains(' or '));
      expect(sql, contains(' and '));
      expect(sql, contains('"entry_date" is null'));
      expect(sql, contains('"created_at" >='));
    });

    test('is.null becomes SQL syntax, not a bound parameter', () {
      // `col is @p` does not parse, so `is` must inline its operand.
      final sql =
          PgQuery('packages').select('*').or('entry_date.is.null').debugSql();
      expect(sql, contains('is null'));
      expect(sql, isNot(matches(RegExp(r'is\s+@'))));
    });

    test('a flat or() still works', () {
      final sql = PgQuery('packages')
          .select('*')
          .or('sr_number.ilike.%X%,consignee_name.ilike.%X%')
          .debugSql();
      expect(sql, contains(' or '));
      expect(sql, contains('"sr_number"'));
      expect(sql, contains('"consignee_name"'));
    });

    test('a nested or(...) inside an or() nests correctly', () {
      final sql = PgQuery('packages')
          .select('*')
          .or('status.eq.held,or(status.eq.pending,status.eq.cleared)')
          .debugSql();
      expect(sql, isNot(contains('or(status')));
      // Three comparisons in total.
      expect('@'.allMatches(sql).length, greaterThanOrEqualTo(3));
    });
  });

  group('RETURNING on a write', () {
    // ⚠️ THE BUG, reported from the app: registering an SR whose goods are
    // marked Forfeit died with `Exception: column "*" does not exist`, and
    // the package was never saved. createForfeitedPackage asks for its
    // embeds back -- `.select('*, packages(*, package_items(*)))'` -- which
    // reaches the RETURNING builder as SEVERAL fields, so the
    // "exactly one field and it is a star" shortcut missed it and the star
    // fell through to the identifier quoter: `returning "*"`. Postgres reads
    // that as a column literally named `*`.

    test('a star among embeds still returns every column', () {
      final sql = PgQuery('forfeited_packages')
          .insert({'package_id': 'p', 'sr_number': 'SR/1'})
          .select('*, packages(*, package_items(*))')
          .debugSql();
      expect(sql, contains('returning *'));
      expect(sql.contains('returning "*"'), isFalse,
          reason: 'the star is quoted as a column name again');
    });

    test('a lone star still returns every column', () {
      final sql = PgQuery('packages')
          .insert({'sr_number': 'SR/1'})
          .select('*')
          .debugSql();
      expect(sql, contains('returning *'));
    });

    test('named columns are still listed, and quoted', () {
      final sql = PgQuery('packages')
          .insert({'sr_number': 'SR/1'})
          .select('id, sr_number')
          .debugSql();
      expect(sql, contains('returning "id", "sr_number"'));
    });

    test('a write that asks for nothing back has no RETURNING', () {
      final sql = PgQuery('packages').insert({'sr_number': 'SR/1'}).debugSql();
      expect(sql.contains('returning'), isFalse);
    });
  });
}
