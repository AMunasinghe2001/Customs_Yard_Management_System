import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/providers.dart';
import 'core/app_updater.dart';
import 'core/holidays.dart';
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

  // Fetch Sri Lanka public holidays for the sale/destruction working-day
  // deadlines. Fire-and-forget — never blocks startup, falls back to the
  // static list + weekend rule if offline.
  unawaited(loadPublicHolidays());

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

class _CustomsAppState extends ConsumerState<CustomsApp>
    with WindowListener, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Re-pull every live list when the window regains focus.
  ///
  /// Realtime only delivers changes to a session that is already subscribed, so
  /// rows written while the app was in the background (or by a bulk SQL script,
  /// or by another machine during a dropped socket) never arrive — the user had
  /// to hit Ctrl+R. Bumping the refresh triggers on resume re-fetches instead.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  @override
  void onWindowFocus() => _refreshAll();

  void _refreshAll() {
    if (!mounted) return;
    for (final t in [
      packagesRefreshTriggerProvider,
      warehouseRefreshTriggerProvider,
      forfeitedRefreshTriggerProvider,
      disposalRequestsRefreshProvider,
      tenderSalesRefreshProvider,
      tenderSaleItemsRefreshProvider,
      tenderBidsRefreshTriggerProvider,
      destructionsRefreshProvider,
    ]) {
      ref.read(t.notifier).trigger();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
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
        // Direct database call skipping Riverpod providers entirely. Null
        // last_seen_at too so the (heartbeat-based) online list drops them
        // instantly instead of holding them online for ~90s after close.
        await supabase.from('profiles').update({
          'is_online': false,
          'last_seen_at': null,
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
