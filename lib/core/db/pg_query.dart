import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'pg_connection.dart';
import 'pg_schema.dart';
import 'pg_select_parser.dart';

/// Thrown for a query the shim cannot express, so it surfaces as a clear
/// message rather than malformed SQL.
class PgQueryException implements Exception {
  PgQueryException(this.message);
  final String message;
  @override
  String toString() => 'PgQueryException: $message';
}

/// One `where` term.
@immutable
class _Filter {
  const _Filter(this.column, this.op, this.value, {this.raw});

  final String column;
  final String op;
  final Object? value;

  /// A ready-made SQL fragment, for `or()` which does not decompose.
  final String? raw;
}

@immutable
class _Order {
  const _Order(this.column, {required this.ascending, required this.nullsFirst});
  final String column;
  final bool ascending;
  final bool nullsFirst;
}

/// A PostgREST-shaped query that runs as SQL.
///
/// The point of this class is that call sites do not change. The app has 152
/// `supabase.from(...).select(...)` chains, 62 of them with nested embeds up
/// to five levels deep. Rewriting each into hand-written SQL would be 152
/// chances to change behaviour by accident, and the embeds in particular
/// (`packages(*, package_items(*), warehouse_entries(*, warehouses(*)))`)
/// would become large, near-duplicate JOIN blocks.
///
/// So instead the embed syntax is *implemented*: this builder parses it and
/// generates the same shape of result PostgREST returned — to-one embeds as a
/// nested object, to-many as a list — using a correlated subquery per embed.
///
/// A `Future`, so `await query` works exactly as it did.
class PgQuery implements Future<dynamic> {
  PgQuery(this.table);

  final String table;

  List<PgField> _fields = const [PgField(name: '*')];
  final List<_Filter> _filters = [];
  final List<_Order> _orders = [];
  int? _limit;
  int? _offset;
  bool _single = false;
  bool _maybeSingle = false;
  bool _countOnly = false;

  // Write operations. When set, the query is a mutation, and _fields is what
  // its RETURNING clause selects.
  String? _mutation; // 'insert' | 'update' | 'upsert' | 'delete'
  List<Map<String, Object?>> _payload = const [];
  List<String> _onConflict = const [];
  bool _returning = false;

  // ── Builder API (mirrors PostgrestFilterBuilder) ──────────────────────────

  PgQuery select([String columns = '*']) {
    _fields = PgSelectParser.parse(columns);
    _returning = true;
    return this;
  }

  PgQuery insert(dynamic values) {
    _mutation = 'insert';
    _payload = _normalisePayload(values);
    return this;
  }

  PgQuery upsert(dynamic values, {String? onConflict}) {
    _mutation = 'upsert';
    _payload = _normalisePayload(values);
    _onConflict = onConflict == null
        ? const ['id']
        : onConflict.split(',').map((c) => c.trim()).toList();
    return this;
  }

  PgQuery update(Map<String, Object?> values) {
    _mutation = 'update';
    _payload = [values];
    return this;
  }

  PgQuery delete() {
    _mutation = 'delete';
    return this;
  }

  static List<Map<String, Object?>> _normalisePayload(dynamic values) {
    if (values is Map) return [Map<String, Object?>.from(values)];
    if (values is List) {
      return values
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList(growable: false);
    }
    throw PgQueryException('insert/upsert wants a Map or a List of Maps');
  }

  PgQuery eq(String column, Object? value) => _add(_Filter(column, '=', value));
  PgQuery neq(String column, Object? value) =>
      _add(_Filter(column, '<>', value));
  PgQuery gt(String column, Object? value) => _add(_Filter(column, '>', value));
  PgQuery gte(String column, Object? value) =>
      _add(_Filter(column, '>=', value));
  PgQuery lt(String column, Object? value) => _add(_Filter(column, '<', value));
  PgQuery lte(String column, Object? value) =>
      _add(_Filter(column, '<=', value));
  PgQuery like(String column, String pattern) =>
      _add(_Filter(column, 'like', pattern));
  PgQuery ilike(String column, String pattern) =>
      _add(_Filter(column, 'ilike', pattern));

  /// `is` in PostgREST; `is_` in the Dart SDK because `is` is a keyword.
  PgQuery is_(String column, Object? value) =>
      _add(_Filter(column, 'is', value));

  PgQuery inFilter(String column, List<Object?> values) =>
      _add(_Filter(column, 'in', values));

  PgQuery not(String column, String op, Object? value) =>
      _add(_Filter(column, 'not.$op', value));

  /// `contains` for array / jsonb columns (PostgREST `cs`).
  PgQuery contains(String column, Object? value) =>
      _add(_Filter(column, '@>', value));

  /// A PostgREST `or=` string: `created_at.gte.X,updated_at.gte.Y`.
  ///
  /// Parsed into real SQL rather than pasted in, so the values stay
  /// parameterised — the string is built from user input at some call sites.
  PgQuery or(String filters) {
    final parts = _splitTopLevel(filters);
    final terms = <String>[];
    for (final p in parts) {
      final bits = p.split('.');
      if (bits.length < 3) {
        throw PgQueryException('cannot parse or() term: $p');
      }
      final col = bits[0];
      final op = bits[1];
      final value = bits.sublist(2).join('.');
      final param = _nextParam();
      _orParams[param] = _coerce(op, value);
      terms.add('${_quoteIdent(col)} ${_sqlOp(op)} @$param');
    }
    _filters.add(_Filter('', 'raw', null, raw: '(${terms.join(' or ')})'));
    return this;
  }

  final Map<String, Object?> _orParams = {};
  int _orParamSeq = 0;
  String _nextParam() => 'or_${_orParamSeq++}';

  static List<String> _splitTopLevel(String s) {
    final out = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == ',' && depth == 0) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return out.where((e) => e.trim().isNotEmpty).toList();
  }

  static String _sqlOp(String op) {
    switch (op) {
      case 'eq':
        return '=';
      case 'neq':
        return '<>';
      case 'gt':
        return '>';
      case 'gte':
        return '>=';
      case 'lt':
        return '<';
      case 'lte':
        return '<=';
      case 'like':
        return 'like';
      case 'ilike':
        return 'ilike';
      case 'is':
        return 'is';
      default:
        throw PgQueryException('unsupported operator in or(): $op');
    }
  }

  /// or() values arrive as text; give the obvious ones their real type so
  /// Postgres compares a timestamp to a timestamp, not to a string.
  static Object? _coerce(String op, String value) {
    if (value == 'null') return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    final n = num.tryParse(value);
    if (n != null) return n;
    final d = DateTime.tryParse(value);
    if (d != null) return d;
    return value;
  }

  PgQuery _add(_Filter f) {
    _filters.add(f);
    return this;
  }

  PgQuery order(String column,
      {bool ascending = false, bool nullsFirst = false}) {
    _orders.add(_Order(column, ascending: ascending, nullsFirst: nullsFirst));
    return this;
  }

  /// Row count instead of rows.
  ///
  /// `CountOption` is accepted and ignored: PostgREST offered estimated and
  /// planned counts as a cost saving over HTTP, which does not apply to a
  /// local server, so every count here is exact.
  PgQuery count([Object? option]) {
    _countOnly = true;
    return this;
  }

  PgQuery limit(int n) {
    _limit = n;
    return this;
  }

  PgQuery range(int from, int to) {
    _offset = from;
    _limit = to - from + 1;
    return this;
  }

  /// Exactly one row; throws when there is not one.
  PgQuery single() {
    _single = true;
    _limit ??= 2; // fetch 2 so "more than one row" is detectable
    return this;
  }

  /// One row or null.
  PgQuery maybeSingle() {
    _maybeSingle = true;
    _limit ??= 2;
    return this;
  }

  // ── SQL generation ────────────────────────────────────────────────────────

  static String _quoteIdent(String name) => '"${name.replaceAll('"', '""')}"';

  /// Builds the SELECT list for [fields] on [tableAlias], recursing into
  /// embeds. Returns the fragments; the caller joins them.
  List<String> _selectList(
    String tbl,
    String alias,
    List<PgField> fields,
    Map<String, Object?> params,
    _Counter c,
  ) {
    final out = <String>[];
    for (final f in fields) {
      if (f.isStar) {
        out.add('$alias.*');
        continue;
      }
      if (!f.isEmbed) {
        final col = '$alias.${_quoteIdent(f.name)}';
        out.add(f.alias == null ? col : '$col as ${_quoteIdent(f.alias!)}');
        continue;
      }
      out.add(_embed(tbl, alias, f, params, c));
    }
    return out;
  }

  /// One embed, as a correlated subquery.
  ///
  /// Two shapes, decided by the direction of the foreign key:
  ///
  ///   to-one  (this table points at the other) -> a single json object
  ///   to-many (the other points back at this)  -> a json array
  ///
  /// That distinction is what the models rely on: `json['profiles']` is read
  /// as a Map, `json['package_items']` as a List. Getting it backwards would
  /// not throw here — it would throw much later inside fromJson.
  String _embed(
    String parentTable,
    String parentAlias,
    PgField f,
    Map<String, Object?> params,
    _Counter c,
  ) {
    final schema = PgSchema.instance;
    final childTable = f.name;
    final childAlias = 'e${c.next()}';

    PgForeignKey? fk;
    var toOne = false;

    if (f.hint != null) {
      fk = schema.byConstraintOrColumn(parentTable, childTable, f.hint!);
      if (fk == null) {
        throw PgQueryException(
            'no foreign key "${f.hint}" between $parentTable and $childTable');
      }
      // The hint resolved to a key ON the parent -> the parent points out.
      toOne = fk.table == parentTable;
    } else {
      final down = schema.childToParent(parentTable, childTable);
      final up = schema.parentToChild(parentTable, childTable);
      if (down != null && up == null) {
        fk = down;
        toOne = true;
      } else if (up != null && down == null) {
        fk = up;
        toOne = false;
      } else if (down != null && up != null) {
        // Ambiguous both ways: prefer the to-one reading, which is what
        // PostgREST did for a singular embed with no hint.
        fk = down;
        toOne = true;
      } else {
        throw PgQueryException(
            'no unique foreign key between $parentTable and $childTable — '
            'add a hint like $childTable!column_name');
      }
    }

    final inner = _selectList(childTable, childAlias, f.children, params, c);
    final joinOn = toOne
        // parent.col = child.pk
        ? '$childAlias.${_quoteIdent(fk.targetColumn)} = '
            '$parentAlias.${_quoteIdent(fk.column)}'
        // child.col = parent.pk
        : '$childAlias.${_quoteIdent(fk.column)} = '
            '$parentAlias.${_quoteIdent(fk.targetColumn)}';

    final key = _quoteIdent(f.outputName);

    if (toOne) {
      // to_jsonb of the whole row when the embed is `*`, otherwise a built
      // object of just the named columns. row_to_json keeps column names.
      final body = _objectExpr(childAlias, f.children, inner);
      return '(select $body from ${_quoteIdent(childTable)} $childAlias '
          'where $joinOn limit 1) as $key';
    }

    final body = _objectExpr(childAlias, f.children, inner);
    // coalesce so an empty embed is [] rather than null: the models do
    // `(json['package_items'] as List?)` and treat null as absent, but an
    // empty list is the honest answer and keeps `.length` working.
    return "(select coalesce(json_agg($body), '[]'::json) "
        'from ${_quoteIdent(childTable)} $childAlias '
        'where $joinOn) as $key';
  }

  /// The json object for one embedded row.
  String _objectExpr(
      String alias, List<PgField> children, List<String> selected) {
    final onlyStar = children.length == 1 && children.first.isStar;
    if (onlyStar) return 'to_jsonb($alias)';

    // Mixed `*, other(...)`: start from the whole row and merge the extras in,
    // so `*` keeps meaning every column.
    final hasStar = children.any((f) => f.isStar);
    final pairs = <String>[];
    for (var i = 0; i < children.length; i++) {
      final f = children[i];
      if (f.isStar) continue;
      final expr = selected[i];
      // Strip the trailing `as "name"` the select list added.
      final cleaned = expr.replaceFirst(
          RegExp(r'\s+as\s+"[^"]*"\s*$', caseSensitive: false), '');
      pairs.add("'${f.outputName}', $cleaned");
    }
    final built = pairs.isEmpty
        ? "'{}'::jsonb"
        : 'jsonb_build_object(${pairs.join(', ')})';
    return hasStar ? 'to_jsonb($alias) || $built' : built;
  }

  /// Renders the whole statement.
  (String, Map<String, Object?>) _build() {
    final params = <String, Object?>{}..addAll(_orParams);
    final c = _Counter();
    const alias = 't';

    final where = <String>[];
    var seq = 0;
    for (final f in _filters) {
      if (f.raw != null) {
        where.add(f.raw!);
        continue;
      }
      final p = 'p${seq++}';
      final col = '$alias.${_quoteIdent(f.column)}';
      switch (f.op) {
        case 'in':
          final list = f.value as List<Object?>;
          if (list.isEmpty) {
            // `in ()` is a syntax error, and an empty set matches nothing.
            where.add('false');
          } else {
            params[p] = list;
            where.add('$col = any(@$p)');
          }
        case 'is':
          // `is` only takes null / true / false, and those cannot be bound as
          // parameters — they are part of the syntax.
          final v = f.value;
          final lit = v == null ? 'null' : (v == true ? 'true' : 'false');
          where.add('$col is $lit');
        case '@>':
          params[p] = f.value is String ? f.value : jsonEncode(f.value);
          where.add('$col @> @$p');
        default:
          if (f.op.startsWith('not.')) {
            final inner = _sqlOp(f.op.substring(4));
            params[p] = f.value;
            where.add('not ($col $inner @$p)');
          } else {
            params[p] = f.value;
            where.add('$col ${f.op} @$p');
          }
      }
    }

    final whereSql = where.isEmpty ? '' : ' where ${where.join(' and ')}';

    final orderSql = _orders.isEmpty
        ? ''
        : ' order by ${_orders.map((o) => '$alias.${_quoteIdent(o.column)} '
            '${o.ascending ? 'asc' : 'desc'} '
            '${o.nullsFirst ? 'nulls first' : 'nulls last'}').join(', ')}';

    final limitSql = _limit == null ? '' : ' limit ${_limit!}';
    final offsetSql = _offset == null ? '' : ' offset ${_offset!}';

    // ── Mutations ───────────────────────────────────────────────────────────
    if (_mutation != null) {
      return _buildMutation(alias, whereSql, params, c);
    }

    final cols = _selectList(table, alias, _fields, params, c).join(',\n       ');
    final sql = 'select $cols\n'
        '  from ${_quoteIdent(table)} $alias'
        '$whereSql$orderSql$limitSql$offsetSql';
    return (sql, params);
  }

  (String, Map<String, Object?>) _buildMutation(
    String alias,
    String whereSql,
    Map<String, Object?> params,
    _Counter c,
  ) {
    // RETURNING cannot see a table alias in the way a SELECT can, and embeds
    // in a RETURNING clause would need the row to exist first. The mutation
    // returns its own columns; a call site that selects embeds after a write
    // re-reads, which is what the Supabase client did over HTTP anyway.
    final returning = _returning
        ? ' returning ${_returningList()}'
        : '';

    switch (_mutation) {
      case 'insert':
      case 'upsert':
        if (_payload.isEmpty) {
          throw PgQueryException('insert with no rows');
        }
        // Union of keys across all rows, so a batch with ragged maps still
        // lines up column-for-column.
        final keys = <String>{};
        for (final row in _payload) {
          keys.addAll(row.keys);
        }
        final colList = keys.toList();
        final tuples = <String>[];
        var n = 0;
        for (final row in _payload) {
          final vals = <String>[];
          for (final k in colList) {
            final p = 'v${n++}';
            params[p] = row[k];
            vals.add('@$p');
          }
          tuples.add('(${vals.join(', ')})');
        }
        final conflict = _mutation == 'upsert'
            ? ' on conflict (${_onConflict.map(_quoteIdent).join(', ')}) '
                'do update set ${colList.where((k) => !_onConflict.contains(k))
                    .map((k) => '${_quoteIdent(k)} = '
                        'excluded.${_quoteIdent(k)}')
                    .join(', ')}'
            : '';
        final sql = 'insert into ${_quoteIdent(table)} '
            '(${colList.map(_quoteIdent).join(', ')}) '
            'values ${tuples.join(', ')}$conflict$returning';
        return (sql, params);

      case 'update':
        final sets = <String>[];
        var n = 0;
        _payload.first.forEach((k, v) {
          final p = 'v${n++}';
          params[p] = v;
          sets.add('${_quoteIdent(k)} = @$p');
        });
        // The alias has to go: UPDATE ... SET uses bare column names, and the
        // WHERE was rendered against `t`.
        final w = whereSql.replaceAll('"t".', '').replaceAll('t.', '');
        final sql = 'update ${_quoteIdent(table)} set ${sets.join(', ')}'
            '$w$returning';
        return (sql, params);

      case 'delete':
        final w = whereSql.replaceAll('"t".', '').replaceAll('t.', '');
        if (w.isEmpty) {
          // A delete with no filter would empty the table. Every call site has
          // one; if a refactor drops it, fail loudly instead of obeying.
          throw PgQueryException('refusing to delete every row of $table');
        }
        final sql = 'delete from ${_quoteIdent(table)}$w$returning';
        return (sql, params);

      default:
        throw PgQueryException('unknown mutation $_mutation');
    }
  }

  String _returningList() {
    if (_fields.length == 1 && _fields.first.isStar) return '*';
    // Embeds cannot be resolved in a RETURNING clause; take the plain columns
    // and let the caller re-read if it needs the related rows.
    final plain = _fields.where((f) => !f.isEmbed).toList();
    if (plain.isEmpty) return '*';
    return plain
        .map((f) => f.alias == null
            ? _quoteIdent(f.name)
            : '${_quoteIdent(f.name)} as ${_quoteIdent(f.alias!)}')
        .join(', ');
  }

  // ── Execution ─────────────────────────────────────────────────────────────

  Future<dynamic> _run() async {
    final (sql, params) = _build();
    if (kDebugMode && _logSql) {
      debugPrint('PgQuery: $sql');
    }
    final rows = await PgDatabase.instance.query(sql, parameters: params);

    if (_countOnly) {
      return rows.isEmpty ? 0 : (rows.first['count'] as int? ?? 0);
    }

    if (_single) {
      if (rows.isEmpty) {
        throw PgQueryException(
            'single() expected one row from $table, got none');
      }
      if (rows.length > 1) {
        throw PgQueryException(
            'single() expected one row from $table, got ${rows.length}');
      }
      return rows.first;
    }
    if (_maybeSingle) {
      if (rows.isEmpty) return null;
      if (rows.length > 1) {
        throw PgQueryException(
            'maybeSingle() expected at most one row from $table, '
            'got ${rows.length}');
      }
      return rows.first;
    }

    // A mutation with no select() returns nothing the caller uses.
    if (_mutation != null && !_returning) return null;
    return rows;
  }

  /// Flip on to print generated SQL while debugging a query.
  static bool _logSql = false;
  static set logSql(bool v) => _logSql = v;

  Future<dynamic>? _future;
  Future<dynamic> get _f => _future ??= _run();

  // ── Future ────────────────────────────────────────────────────────────────

  @override
  Stream<dynamic> asStream() => _f.asStream();

  @override
  Future<dynamic> catchError(Function onError,
          {bool Function(Object error)? test}) =>
      _f.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue,
          {Function? onError}) =>
      _f.then(onValue, onError: onError);

  @override
  Future<dynamic> timeout(Duration timeLimit,
          {FutureOr<dynamic> Function()? onTimeout}) =>
      _f.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      _f.whenComplete(action);
}

/// Hands out unique subquery aliases within one statement.
class _Counter {
  int _n = 0;
  int next() => _n++;
}
