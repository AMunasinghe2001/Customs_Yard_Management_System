import 'dart:io';
import 'package:postgres/postgres.dart';

/// Runs a .sql file as ONE block, letting the server parse it.
///
/// ⚠️ [apply_sql.dart] splits a file into statements itself, and its splitter
/// mishandles some perfectly valid SQL -- an apostrophe inside a `--` comment,
/// or a multi-row VALUES list -- by silently dropping statements rather than
/// failing. A migration that "ran successfully" while inserting nothing is far
/// worse than one that errors, so anything with prose comments or CTE inserts
/// should come through here instead.
Future<void> main(List<String> args) async {
  final target = args.isNotEmpty ? args.first : '';
  if (target.isEmpty || !File(target).existsSync()) {
    stderr.writeln('usage: dart run tool/apply_sql_whole.dart <file.sql>');
    exit(2);
  }
  final sql = File(target).readAsStringSync();
  print('Target: $target (${sql.length} chars, run as one block)');

  final conn = await Connection.open(
    Endpoint(
        host: 'localhost',
        port: 5432,
        database: 'Customs_SR_DB',
        username: 'postgres',
        password: 'postgres'),
    settings: ConnectionSettings(
        sslMode: SslMode.disable, queryTimeout: const Duration(seconds: 120)),
  );
  try {
    // Simple query protocol: the extended one allows only ONE command per
    // prepared statement, and a migration is many.
    await conn.execute(sql, queryMode: QueryMode.simple);
    print('Applied.');
  } finally {
    await conn.close();
  }
}
