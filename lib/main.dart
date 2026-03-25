import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/providers.dart';

class _NoPersistLocalStorage extends LocalStorage {
  @override Future<void> initialize() async {}
  @override Future<bool> hasAccessToken() async => false;
  @override Future<String?> accessToken() async => null;
  @override Future<void> removePersistedSession() async {}
  @override Future<void> persistSession(String persistSessionString) async {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(1000, 700),
    title: 'Sri Lanka Customs Inventory Management System',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: _NoPersistLocalStorage(),
    ),
  );

  runApp(
    const ProviderScope(
      child: CustomsApp(),
    ),
  );
}

class CustomsApp extends ConsumerWidget {
  const CustomsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    print('DEBUG: CustomsApp building with themeMode: $themeMode');
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Sri Lanka Customs Inventory Management System',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
