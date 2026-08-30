import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/db/pg_select_parser.dart';

/// The select strings in this file are copied verbatim from lib/services.
/// If the parser gets one of them wrong the app breaks in a way that only
/// shows up as a null deep inside a model, so they are pinned here.
void main() {
  group('plain fields', () {
    test('empty select means everything', () {
      final f = PgSelectParser.parse('');
      expect(f, hasLength(1));
      expect(f.first.isStar, isTrue);
    });

    test('a column list', () {
      final f = PgSelectParser.parse('id, status, created_at');
      expect(f.map((e) => e.name), ['id', 'status', 'created_at']);
      expect(f.every((e) => !e.isEmbed), isTrue);
    });

    test('whitespace and newlines are ignored', () {
      final f = PgSelectParser.parse('  id ,\n  status  ');
      expect(f.map((e) => e.name), ['id', 'status']);
    });
  });

  group('embeds', () {
    test('a simple embed', () {
      final f = PgSelectParser.parse('*, package_items(*)');
      expect(f, hasLength(2));
      expect(f[0].isStar, isTrue);
      expect(f[1].name, 'package_items');
      expect(f[1].isEmbed, isTrue);
      expect(f[1].children.single.isStar, isTrue);
    });

    test('nested two deep', () {
      final f = PgSelectParser.parse('*, warehouse_entries(*, warehouses(*))');
      final we = f[1];
      expect(we.name, 'warehouse_entries');
      expect(we.children, hasLength(2));
      expect(we.children[1].name, 'warehouses');
      expect(we.children[1].isEmbed, isTrue);
    });

    test('an aliased embed with a foreign-key hint', () {
      final f = PgSelectParser.parse(
          'returned_profile:profiles!returned_by(full_name, badge_number)');
      final p = f.single;
      // The alias is the key the model reads; the hint picks which of the two
      // profiles foreign keys to follow.
      expect(p.alias, 'returned_profile');
      expect(p.outputName, 'returned_profile');
      expect(p.name, 'profiles');
      expect(p.hint, 'returned_by');
      expect(p.children.map((c) => c.name), ['full_name', 'badge_number']);
    });

    test('!inner is a filter, not a hint', () {
      final f = PgSelectParser.parse(
          'forfeited_packages!inner(package_id, item_id, source)');
      expect(f.single.inner, isTrue);
      expect(f.single.hint, isNull);
    });

    test('outputName falls back to the table name', () {
      final f = PgSelectParser.parse('profiles(full_name)');
      expect(f.single.outputName, 'profiles');
    });
  });

  group('real select strings from the app', () {
    test('the packages query, five levels deep', () {
      const src = '*, package_items(*), warehouse_entries(*, warehouses(*), '
          'returned_profile:profiles!returned_by(full_name, badge_number)), '
          'profiles(*)';
      final f = PgSelectParser.parse(src);
      expect(f.map((e) => e.outputName),
          ['*', 'package_items', 'warehouse_entries', 'profiles']);

      final we = f[2];
      expect(we.children.map((c) => c.outputName),
          ['*', 'warehouses', 'returned_profile']);
      expect(we.children[2].hint, 'returned_by');
    });

    test('the deepest tender query', () {
      const src = '*, forfeited_packages(*, '
          'disposal_request_items!forfeited_package_id(valuation_cost), '
          'packages(*, package_items(*), '
          'warehouse_entries(*, warehouses(*))))';
      final f = PgSelectParser.parse(src);
      final fp = f[1];
      expect(fp.name, 'forfeited_packages');

      final dri = fp.children[1];
      expect(dri.name, 'disposal_request_items');
      expect(dri.hint, 'forfeited_package_id');

      final pkgs = fp.children[2];
      final we = pkgs.children[2];
      expect(we.name, 'warehouse_entries');
      expect(we.children[1].name, 'warehouses');
    });

    test('a two-hint embed keeps both parts', () {
      final f = PgSelectParser.parse('*, profiles!created_by(full_name), '
          'valued_profile:profiles!valued_by(full_name)');
      expect(f[1].hint, 'created_by');
      expect(f[1].outputName, 'profiles');
      expect(f[2].hint, 'valued_by');
      expect(f[2].outputName, 'valued_profile');
    });
  });

  group('malformed input', () {
    test('an unclosed bracket is rejected', () {
      expect(() => PgSelectParser.parse('*, package_items(*'),
          throwsA(isA<FormatException>()));
    });

    test('a missing name is rejected', () {
      expect(() => PgSelectParser.parse('*, ,id'),
          throwsA(isA<FormatException>()));
    });
  });
}
