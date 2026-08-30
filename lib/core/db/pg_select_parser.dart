import 'package:flutter/foundation.dart';

/// One entry in a PostgREST `select=` string.
///
/// A field is either a plain column (`sr_number`), a star (`*`), or an embed —
/// a related table with its own field list, which may nest further:
///
///     *, package_items(*), warehouse_entries(*, warehouses(*))
@immutable
class PgField {
  const PgField({
    required this.name,
    this.alias,
    this.hint,
    this.inner = false,
    this.children = const [],
  });

  /// The table or column name.
  final String name;

  /// `alias:name(...)` — the key the caller expects in the result map.
  /// `returned_profile:profiles!returned_by(...)` returns under
  /// 'returned_profile', so the model finds it where it looks.
  final String? alias;

  /// The `!hint` disambiguator: a constraint or column name, used when two
  /// foreign keys join the same pair of tables.
  final String? hint;

  /// `!inner` — the embed becomes a filter: parents with no match drop out.
  final bool inner;

  /// Non-empty when this is an embed.
  final List<PgField> children;

  bool get isEmbed => children.isNotEmpty;
  bool get isStar => name == '*';

  /// What this field is called in the output map.
  String get outputName => alias ?? name;

  @override
  String toString() {
    final h = hint == null ? '' : '!$hint';
    final i = inner ? '!inner' : '';
    if (!isEmbed) return '${alias == null ? '' : '$alias:'}$name$h';
    return '${alias == null ? '' : '$alias:'}$name$h$i'
        '(${children.join(', ')})';
  }
}

/// Parses a PostgREST select string into a tree.
///
/// Written by hand rather than with a regex because the grammar nests: the
/// parenthesised field list of an embed can contain further embeds, five deep
/// in this codebase. A regex cannot match balanced parentheses, and the
/// nesting is exactly what has to be preserved.
class PgSelectParser {
  PgSelectParser(this._src);

  final String _src;
  int _i = 0;

  /// Parses [src], or returns `[*]` when it is empty or just whitespace.
  static List<PgField> parse(String src) {
    final trimmed = src.trim();
    if (trimmed.isEmpty) return const [PgField(name: '*')];
    return PgSelectParser(trimmed)._fieldList(depth: 0);
  }

  bool get _atEnd => _i >= _src.length;
  String get _peek => _src[_i];

  void _skipSpace() {
    while (!_atEnd && (_peek == ' ' || _peek == '\n' || _peek == '\r' ||
        _peek == '\t')) {
      _i++;
    }
  }

  /// A comma-separated list, ending at `)` or end of input.
  List<PgField> _fieldList({required int depth}) {
    // Five levels is the deepest embed in this codebase; the cap is a guard
    // against a malformed string spinning here, not a real limit.
    if (depth > 12) {
      throw FormatException('select nested too deeply: $_src');
    }
    final out = <PgField>[];
    while (true) {
      _skipSpace();
      if (_atEnd || _peek == ')') break;
      out.add(_field(depth: depth));
      _skipSpace();
      if (!_atEnd && _peek == ',') {
        _i++;
        continue;
      }
      break;
    }
    return out;
  }

  /// `[alias:]name[!hint][!inner][(children)]`
  PgField _field({required int depth}) {
    _skipSpace();
    var name = _identifier();
    String? alias;

    // `alias:target` — the colon separates the output key from the table.
    if (!_atEnd && _peek == ':') {
      _i++;
      alias = name;
      name = _identifier();
    }

    String? hint;
    var inner = false;
    // There can be two: `profiles!returned_by` and `forfeited_packages!inner`,
    // and in principle `table!fk!inner`.
    while (!_atEnd && _peek == '!') {
      _i++;
      final tag = _identifier();
      if (tag == 'inner') {
        inner = true;
      } else if (tag == 'left') {
        // The default join is already left; nothing to record.
      } else {
        hint = tag;
      }
    }

    var children = const <PgField>[];
    _skipSpace();
    if (!_atEnd && _peek == '(') {
      _i++;
      children = _fieldList(depth: depth + 1);
      _skipSpace();
      if (_atEnd || _peek != ')') {
        throw FormatException('unclosed ( in select: $_src');
      }
      _i++;
    }

    return PgField(
      name: name,
      alias: alias,
      hint: hint,
      inner: inner,
      children: children,
    );
  }

  String _identifier() {
    _skipSpace();
    final start = _i;
    while (!_atEnd) {
      final c = _peek;
      final isWord = (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) || // 0-9
          (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) || // A-Z
          (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122) || // a-z
          c == '_' || c == '*';
      if (!isWord) break;
      _i++;
    }
    if (start == _i) {
      throw FormatException(
          'expected a name at offset $_i in select: $_src');
    }
    return _src.substring(start, _i);
  }
}
