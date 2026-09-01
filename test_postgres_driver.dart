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
    // Test 1: Direct auth.users query
    print('Test 1: Direct auth.users query');
    try {
      final result = await conn.execute(Sql('select id, email from auth.users limit 1'));
      print('  Success: ${result.length} rows');
    } catch (e) {
      print('  Error: $e');
    }

    // Test 2: Call auth.sign_in with named parameters
    print('\nTest 2: auth.sign_in() with named params');
    try {
      final result = await conn.execute(
        Sql.named('select * from auth.sign_in(@email, @password)'),
        parameters: {'email': 'test@example.com', 'password': 'wrong'},
      );
      print('  Success: ${result.length} rows');
    } catch (e) {
      print('  Error: $e');
    }

    // Test 3: Call auth.sign_in with literal values
    print('\nTest 3: auth.sign_in() with literal values');
    try {
      final result = await conn.execute(
        Sql("select * from auth.sign_in('anushanga@gmail.com', 'wrong-password')"),
      );
      print('  Success: ${result.length} rows');
    } catch (e) {
      print('  Error: $e');
    }
  } finally {
    await conn.close();
  }
}
