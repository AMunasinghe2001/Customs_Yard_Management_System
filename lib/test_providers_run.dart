import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/supabase_client.dart';
import 'core/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("Print database providers", () async {
    SharedPreferences.setMockInitialValues({});
    
    // Connect to the local PostgreSQL server.
    await supabase.initialize();

    final container = ProviderContainer();
    
    try {
      print("Reading forfeitedPackagesProvider...");
      final forfeited = await container.read(forfeitedPackagesProvider.future);
      print("Forfeited Packages Count: ${forfeited.length}");
      for (var p in forfeited) {
        print("  - SR: ${p.srNumber}, Expired: ${p.isAppealExpired}, Deadline: ${p.appealDeadline}");
      }

      print("\nReading expiredAppealPackagesProvider...");
      final expired = await container.read(expiredAppealPackagesProvider.future);
      print("Expired Appeal Packages Count: ${expired.length}");
      for (var p in expired) {
        print("  - SR: ${p.srNumber}, Expired: ${p.isAppealExpired}, Deadline: ${p.appealDeadline}");
      }
    } catch (e) {
      print("Error: $e");
    }
  });
}
