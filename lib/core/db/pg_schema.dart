import 'package:flutter/foundation.dart';

import 'pg_connection.dart';

/// One foreign key: `table.column` points at `target.targetColumn`.
@immutable
class PgForeignKey {
  const PgForeignKey({
    required this.constraint,
    required this.table,
    required this.column,
    required this.target,
    required this.targetColumn,
  });

  final String constraint;
  final String table;
  final String column;
  final String target;
  final String targetColumn;

  @override
  String toString() => '$table.$column -> $target.$targetColumn';
}

/// The foreign keys, read from the database rather than guessed.
///
/// The query builder needs these to turn a PostgREST embed into a JOIN: given
/// `packages` and an embed named `package_items`, it has to know which column
/// links them and in which direction. PostgREST answered that from the same
/// catalog; so does this.
///
/// Reading the catalog rather than hard-coding a table means a migration that
/// adds a relationship needs no change here — the app picks it up on its next
/// start. Hard-coding would be a second source of truth, quietly wrong.
class PgSchema {
  PgSchema._();
  static final PgSchema instance = PgSchema._();

  List<PgForeignKey> _fks = const [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Populates the cache. Call once, after connecting.
  Future<void> load() async {
    const sql = '''
      select con.conname                                as constraint_name,
             src_tbl.relname                            as src_table,
             src_col.attname                            as src_column,
             tgt_tbl.relname                            as tgt_table,
             tgt_col.attname                            as tgt_column
      from   pg_constraint con
      join   pg_class     src_tbl on src_tbl.oid = con.conrelid
      join   pg_namespace src_ns  on src_ns.oid  = src_tbl.relnamespace
      join   pg_class     tgt_tbl on tgt_tbl.oid = con.confrelid
      join   pg_attribute src_col on src_col.attrelid = con.conrelid
                                 and src_col.attnum   = con.conkey[1]
      join   pg_attribute tgt_col on tgt_col.attrelid = con.confrelid
                                 and tgt_col.attnum   = con.confkey[1]
      where  con.contype = 'f'
        and  src_ns.nspname in ('public', 'auth')
        -- Composite keys are not reachable through a PostgREST embed and
        -- would make conkey[1] a half-truth, so leave them out entirely.
        and  array_length(con.conkey, 1) = 1
      order  by src_tbl.relname, con.conname
    ''';

    final rows = await PgDatabase.instance.query(sql);
    _fks = rows
        .map((r) => PgForeignKey(
              constraint: r['constraint_name'] as String,
              table: r['src_table'] as String,
              column: r['src_column'] as String,
              target: r['tgt_table'] as String,
              targetColumn: r['tgt_column'] as String,
            ))
        .toList(growable: false);
    _loaded = true;
    debugPrint('PgSchema: ${_fks.length} foreign keys');
  }

  List<PgForeignKey> get all => _fks;

  /// Seeds the cache without a database, for tests that check generated SQL.
  @visibleForTesting
  void loadForTest(List<PgForeignKey> fks) {
    _fks = List.unmodifiable(fks);
    _loaded = true;
  }

  /// The FK on [table] pointing at [target], if there is exactly one.
  ///
  /// Returns null when there are several — `warehouse_entries` has both
  /// `admitted_by` and `returned_by` into `profiles`, and picking one at
  /// random would silently show the wrong officer's name. Those embeds name
  /// their column explicitly (`profiles!returned_by`), which
  /// [byConstraintOrColumn] resolves instead.
  PgForeignKey? childToParent(String table, String target) {
    final hits =
        _fks.where((f) => f.table == table && f.target == target).toList();
    return hits.length == 1 ? hits.first : null;
  }

  /// The FK on [child] pointing back at [parent] — the to-many direction.
  PgForeignKey? parentToChild(String parent, String child) {
    final hits =
        _fks.where((f) => f.table == child && f.target == parent).toList();
    return hits.length == 1 ? hits.first : null;
  }

  /// Resolves the `!hint` in an embed such as `profiles!returned_by`.
  ///
  /// PostgREST let the hint be either a constraint name or a column name, so
  /// both are accepted here.
  PgForeignKey? byConstraintOrColumn(String table, String target, String hint) {
    for (final f in _fks) {
      if (f.table == table && f.constraint == hint) return f;
    }
    for (final f in _fks) {
      if (f.table == table && f.target == target && f.column == hint) return f;
    }
    // The hint may name the column on the *child* side of a to-many embed.
    for (final f in _fks) {
      if (f.table == target && f.target == table && f.column == hint) return f;
    }
    return null;
  }

  /// True when [table] has a column called [column].
  ///
  /// Used to tell `profiles!returned_by` (a hint naming a local column) from
  /// an embed whose hint names a constraint.
  bool tableHasColumn(String table, String column) =>
      _fks.any((f) => f.table == table && f.column == column);
}
