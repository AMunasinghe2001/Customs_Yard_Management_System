import 'package:postgres/postgres.dart';

Future<void> main() async {
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
    print("Test 1: Direct query like pg_auth.dart does");
    print("SQL: select id, email, meta, email_confirmed_at from auth.sign_in(@id, @pw)");
    try {
      final result = await conn.execute(
        Sql.named('select id, email, meta, email_confirmed_at from auth.sign_in(@id, @pw)'),
        parameters: {'id': 'anushangamunasinghe@gmail.com', 'pw': 'test123'},
      );
      print("  Success: ${result.length} rows");
      for (final row in result) {
        print("  Row: $row");
      }
    } catch (e) {
      print("  Error: $e");
      print("  Error type: ${e.runtimeType}");
    }

    print("\nTest 2: Using raw SQL without named params");
    try {
      final result = await conn.execute(
        Sql("select id, email, meta, email_confirmed_at from auth.sign_in('anushangamunasinghe@gmail.com', 'test123')"),
      );
      print("  Success: ${result.length} rows");
    } catch (e) {
      print("  Error: $e");
    }

    print("\nTest 3: Try selecting directly from auth.users table");
    try {
      final result = await conn.execute(Sql('select * from auth.users limit 1'));
      print("  Success: ${result.length} rows");
    } catch (e) {
      print("  Error: $e");
    }
  } finally {
    await conn.close();
  }
}
