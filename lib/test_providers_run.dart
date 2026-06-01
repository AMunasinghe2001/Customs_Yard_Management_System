import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/supabase_client.dart';
import 'core/providers.dart';

class EmptyLocalStorage extends LocalStorage {
  @override Future<void> initialize() async {}
  @override Future<bool> hasAccessToken() async => false;
  @override Future<String?> accessToken() async => null;
  @override Future<void> removePersistedSession() async {}
  @override Future<void> persistSession(String persistSessionString) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("Print database providers", () async {
    SharedPreferences.setMockInitialValues({});
    
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );

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
