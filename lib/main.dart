import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/providers.dart';
import 'core/app_updater.dart';
import 'services/services.dart';

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
    title: 'Sri Lanka Customs SR Management System',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: _NoPersistLocalStorage(),
    ),
  );

  // Background auto-update check (Windows/macOS). Never throws.
  await initAutoUpdater();

  runApp(
    const ProviderScope(
      child: CustomsApp(),
    ),
  );
}

class CustomsApp extends ConsumerStatefulWidget {
  const CustomsApp({super.key});

  @override
  ConsumerState<CustomsApp> createState() => _CustomsAppState();
}

class _CustomsAppState extends ConsumerState<CustomsApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    print('DEBUG: Global window close caught...');
    
    // Hide the window immediately so the user feels an instant close
    await windowManager.hide();
    
    try {
      final user = supabase.auth.currentUser;
      print('DEBUG: App closing. Current user ID: ${user?.id}');
      
      if (user != null) {
        await AuditLogService().recordLog(
          userId: user.id,
          action: 'Signed Out (App Closed)',
          entityType: 'auth',
          entityId: user.id,
        );
        // Direct database call skipping Riverpod providers entirely
        await supabase.from('profiles').update({
          'is_online': false
        }).eq('id', user.id).timeout(const Duration(seconds: 2));
        
        print('DEBUG: Successfully set user offline in Database directly.');
      } else {
        print('DEBUG: No logged in user. Taking no DB action.');
      }
    } catch (e) {
      print('DEBUG: Could not set offline on exit: $e');
    } finally {
      print('DEBUG: Destroying window process...');
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    print('DEBUG: CustomsApp building with themeMode: $themeMode');
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Sri Lanka Customs SR Management System',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
