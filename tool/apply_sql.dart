import 'dart:io';
import 'package:postgres/postgres.dart';

Future<void> main(List<String> args) async {
  final requested = args.isNotEmpty ? args.first : 'postgres/04_auth.sql';
  final target = File(requested).existsSync()
      ? requested
      : File('postgres/$requested').existsSync()
          ? 'postgres/$requested'
          : requested;

  final sql = await File(target).readAsString();
  final statements = _splitSql(sql);
  print('Target: $target');
  print('Statements: ${statements.length}');
  for (var i = 0; i < statements.length; i++) {
    final firstLine = statements[i].split('\n').first.trim();
    print('${i + 1}: ${firstLine.substring(0, firstLine.length > 80 ? 80 : firstLine.length)}');
  }

  final conn = await Connection.open(
    Endpoint(
      host: 'localhost',
      port: 5432,
      database: 'Customs_SR_DB',
      username: 'postgres',
      password: 'postgres',
    ),
    settings: ConnectionSettings(
      sslMode: SslMode.disable,
      connectTimeout: const Duration(seconds: 10),
      queryTimeout: const Duration(seconds: 60),
    ),
  );

  try {
    for (var i = 0; i < statements.length; i++) {
      final statement = statements[i].trim();
      if (statement.isEmpty || statement.startsWith('--')) continue;
      print('Running statement ${i + 1}/${statements.length}');
      await conn.execute(Sql(statement));
    }

    final result = await conn.execute(
      Sql(
        "select column_name from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name in ('failed_login_attempts', 'locked_until') order by column_name",
      ),
    );
    final columns = result.map((row) => row[0]).join(', ');
    print('Columns present: $columns');
    print('DB patch completed successfully.');
  } finally {
    await conn.close();
  }
}

List<String> _splitSql(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var inLineComment = false;
  var inBlockComment = false;
  var inDollarQuote = false;
  String? dollarTag;

  for (var i = 0; i < sql.length; i++) {
    final ch = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (inLineComment) {
      buffer.write(ch);
      if (ch == '\n') {
        inLineComment = false;
      }
      continue;
    }

    if (inBlockComment) {
      buffer.write(ch);
      if (ch == '*' && next == '/') {
        buffer.write(next);
        i++;
        inBlockComment = false;
      }
      continue;
    }

    if (inSingleQuote) {
      buffer.write(ch);
      if (ch == '\\') {
        if (i + 1 < sql.length) {
          buffer.write(sql[i + 1]);
          i++;
        }
      } else if (ch == "'") {
        inSingleQuote = false;
      }
      continue;
    }

    if (inDoubleQuote) {
      buffer.write(ch);
      if (ch == '\\') {
        if (i + 1 < sql.length) {
          buffer.write(sql[i + 1]);
          i++;
        }
      } else if (ch == '"') {
        inDoubleQuote = false;
      }
      continue;
    }

    if (inDollarQuote) {
      final remaining = sql.substring(i);
      if (remaining.startsWith(dollarTag!)) {
        buffer.write(dollarTag!);
        i += dollarTag!.length - 1;
        inDollarQuote = false;
        dollarTag = null;
      } else {
        buffer.write(ch);
      }
      continue;
    }

    if (ch == '-' && next == '-') {
      buffer.write('--');
      inLineComment = true;
      i++;
      continue;
    }

    if (ch == '/' && next == '*') {
      buffer.write('/*');
      inBlockComment = true;
      i++;
      continue;
    }

    if (ch == "'") {
      buffer.write(ch);
      inSingleQuote = true;
      continue;
    }

    if (ch == '"') {
      buffer.write(ch);
      inDoubleQuote = true;
      continue;
    }

    if (ch == r'$') {
      final remaining = sql.substring(i);
      final tagMatch = RegExp(r'^\$[A-Za-z_][A-Za-z0-9_]*\$').firstMatch(remaining);
      if (tagMatch != null) {
        final tag = tagMatch.group(0)!;
        buffer.write(tag);
        dollarTag = tag;
        inDollarQuote = true;
        i += tag.length - 1;
        continue;
      }
      if (remaining.startsWith(r'$$')) {
        buffer.write(r'$$');
        dollarTag = r'$$';
        inDollarQuote = true;
        i++;
        continue;
      }
    }

    if (ch == ';') {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty && !statement.startsWith('--')) {
        statements.add(statement);
      }
      buffer.clear();
      continue;
    }

    buffer.write(ch);
  }

  final tail = buffer.toString().trim();
  if (tail.isNotEmpty && !tail.startsWith('--')) {
    statements.add(tail);
  }

  return statements;
}
