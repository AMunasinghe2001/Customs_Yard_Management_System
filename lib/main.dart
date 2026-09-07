import 'dart:async';
import 'dart:io' show exit;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/supabase_client.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_log.dart';
import 'core/error_handling.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/providers.dart';
import 'core/app_updater.dart';
import 'core/holidays.dart';
import 'core/idle_lock.dart';
import 'widgets/idle_lock_overlay.dart';
import 'services/services.dart';

void main() async {
  // Everything runs inside one guarded zone so that an uncaught ASYNC error
  // anywhere in the app is captured rather than silently swallowed. runApp must
  // be called inside it too, or the widgets end up in a different zone and the
  // guard never sees their errors.
  await AppErrorHandler.guard(_start);
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Installed before anything else can fail, so start-up errors are logged too.
  await AppErrorHandler.install();

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1180, 720),
    center: true,
    title: 'Sri Lanka Customs SR Management System',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setMinimumSize(const Size(1180, 720));
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);

  // Connect to the office PostgreSQL server, cache the foreign keys the query
  // layer needs, and start listening for change notifications.
  //
  // Sessions are not persisted, so this never restores a signed-in user — the
  // same behaviour the Supabase build had via _NoPersistLocalStorage.
  //
  // NOT allowed to abort start-up. This used to be a bare `await`, so a server
  // that was down (or simply not installed on a fresh machine) threw here and
  // `runApp` below was never reached: windowManager had already shown the
  // window, leaving a blank white frame with no Flutter UI in it — nothing to
  // click, and setPreventClose(true) meant the close button did nothing either.
  // The app looked frozen when the real problem was one unreachable socket.
  // Now the failure is captured and rendered as a screen the user can read.
  Object? startupError;
  try {
    await supabase.initialize();
  } catch (e) {
    startupError = e;
    debugPrint('Database unavailable at start-up: $e');
  }

  // Background auto-update check (Windows/macOS). Never throws.
  await initAutoUpdater();

  // ⚠️ Still fetched, though nothing reads it today.
  //
  // It existed for the sale/destruction working-day DEADLINE, which has been
  // removed: a clock should not decide whether goods are unsold, and a public
  // holiday should not change which packages reach the DG. The calendar itself
  // is still the right answer for anything that genuinely has to fall on an
  // office day, so the warm-up stays rather than being rediscovered later.
  unawaited(loadPublicHolidays());

  runApp(
    ProviderScope(
      child: startupError == null
          ? const CustomsApp()
          : DatabaseUnavailableApp(error: startupError),
    ),
  );
}

/// Shown instead of the app when the database could not be reached at start-up.
///
/// The whole app is a thin client over PostgreSQL — with no connection there is
/// no login, no yard, no packages — so there is nothing useful to render behind
/// this. What it must do is say WHICH server was tried and let the user out of
/// the window, which is exactly what the blank frame failed to do.
class DatabaseUnavailableApp extends StatefulWidget {
  const DatabaseUnavailableApp({super.key, required this.error});

  final Object error;

  @override
  State<DatabaseUnavailableApp> createState() => _DatabaseUnavailableAppState();
}

class _DatabaseUnavailableAppState extends State<DatabaseUnavailableApp> {
  late Object _error = widget.error;
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await supabase.initialize();
      if (!mounted) return;
      // Connected on the retry — swap in the real app, no restart needed.
      runApp(const ProviderScope(child: CustomsApp()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _retrying = false;
      });
    }
  }

  /// The most likely cause, in the order they actually happen on site.
  String get _hint {
    final s = _error.toString().toLowerCase();
    if (s.contains('refused') || s.contains('1225')) {
      return 'Nothing is listening on that port. The PostgreSQL service is '
          'probably stopped — or not installed on this PC yet.';
    }
    if (s.contains('timed out') || s.contains('timeout')) {
      return 'The server did not answer in time. Check the network link to it, '
          'and any firewall between this PC and the server.';
    }
    if (s.contains('password') || s.contains('authentication')) {
      return 'The server answered but rejected the credentials. Check the user '
          'name and password this build was compiled with.';
    }
    if (s.contains('does not exist')) {
      return 'The server is running but has no database with that name. Create '
          'it, then run the files in supabase/ to build the schema.';
    }
    if (s.contains('failed host lookup')) {
      return 'That host name could not be resolved. Check PG_HOST.';
    }
    return 'The database could not be opened.';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF0E0D1A),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.storage_rounded,
                        color: Color(0xFFE05C5C), size: 30),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Cannot reach the database',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Text(_hint,
                      style: const TextStyle(
                          fontSize: 15, height: 1.5, color: Color(0xFFC9C7D6))),
                  const SizedBox(height: 22),
                  // Naming the exact target is what turns this from "it's
                  // broken" into something the person at the desk can check.
                  _TargetRow(label: 'Server', value: databaseDescription),
                  // Points at the crash log from the one screen a user is
                  // guaranteed to be looking at when things go wrong.
                  if (AppErrorHandler.logPath != null) ...[
                    const SizedBox(height: 8),
                    _TargetRow(label: 'Log', value: AppErrorHandler.logPath!),
                  ],
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: SelectableText(
                      _error.toString(),
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.5,
                          color: Color(0xFF9C99AD)),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: _retrying ? null : _retry,
                      icon: _retrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                      label: Text(_retrying ? 'Connecting…' : 'Try again'),
                    ),
                    const SizedBox(width: 12),
                    // setPreventClose(true) makes the title-bar X a no-op, so
                    // without this button the window genuinely cannot be shut.
                    OutlinedButton.icon(
                      onPressed: () => exit(0),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Exit'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 80,
        child: Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF7E7B8F))),
      ),
      Expanded(
        child: SelectableText(value,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
    ]);
  }
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

  /// The last time the live lists were force-refreshed.
  ///
  /// Refreshing on EVERY focus event made the app re-fetch (and visibly reset
  /// tables to page 1) whenever the window lost focus for a moment — taking a
  /// screenshot, alt-tabbing, clicking another app. Realtime already covers
  /// live changes; the focus refresh only exists to catch writes made while
  /// this session was not subscribed, which cannot happen several times a
  /// minute. So it is throttled.
  DateTime? _lastForcedRefresh;
  static const _refreshCooldown = Duration(minutes: 15);

  /// Re-pull every live list when the app comes back from being SUSPENDED.
  ///
  /// Realtime only delivers changes to a session that is already subscribed, so
  /// rows written while the app was suspended (or by a bulk SQL script, or by
  /// another machine during a dropped socket) never arrive — the user had to
  /// hit Ctrl+R. Bumping the refresh triggers on resume re-fetches instead.
  ///
  /// Deliberately NOT hooked to `onWindowFocus`: that fires for a screenshot,
  /// an alt-tab, or a click on any other app, and each one reset every table
  /// to page 1 mid-read. Only a real suspend/resume can have missed writes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // `resumed` also arrives after a brief focus loss, so only refresh when we
    // actually came back from a state where realtime could not reach us.
    if (state == AppLifecycleState.resumed && _wasDetached) {
      _wasDetached = false;
      _refreshAll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasDetached = true;
    }
  }

  /// True once the app has actually been suspended (not merely unfocused).
  bool _wasDetached = false;

  void _refreshAll() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastForcedRefresh != null &&
        now.difference(_lastForcedRefresh!) < _refreshCooldown) {
      return; // too soon — realtime is already keeping the data current
    }
    _lastForcedRefresh = now;
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
    AppLog.debug('window close caught', tag: 'shutdown');

    // Hide the window immediately so the user feels an instant close
    await windowManager.hide();

    try {
      final user = supabase.auth.currentUser;
      AppLog.debug('closing; current user ${user?.id}', tag: 'shutdown');

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
        await supabase
            .from('profiles')
            .update({
              'is_online': false,
              'last_seen_at': null,
            })
            .eq('id', user.id)
            .timeout(const Duration(seconds: 2));

        AppLog.debug('set user offline in the database', tag: 'shutdown');
      } else {
        AppLog.debug('no signed-in user; nothing to do', tag: 'shutdown');
      }
    } catch (e) {
      AppLog.warn('could not set offline on exit', error: e,
          tag: 'shutdown');
    } finally {
      AppLog.debug('destroying window', tag: 'shutdown');
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    AppLog.debug('building with themeMode: $themeMode', tag: 'app');
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Sri Lanka Customs SR Management System',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Everything the router draws sits inside the idle watcher, so any click,
      // scroll or key press anywhere in the app resets the countdown — and the
      // lock screen, when it comes, covers every route including dialogs.
      builder: (context, child) => IdleActivityDetector(
        child: IdleLockOverlay(child: child ?? const SizedBox.shrink()),
      ),
      // Desktop scrolling. Flutter hides the scrollbar and disables
      // drag-to-scroll on desktop, assuming a wheel is always present — but on
      // a machine without one (or where the wheel does not reach a nested
      // list) there is then no way to scroll at all. This shows the bar on
      // every scrollable and lets it be dragged with the mouse.
      scrollBehavior: const _DesktopScrollBehavior(),
    );
  }
}

/// Scrolling that works with a mouse as well as a trackpad.
///
/// Flutter's desktop default omits touch and stylus from [dragDevices], so a
/// list can only be scrolled by the wheel. Adding the mouse makes the content
/// itself draggable, and an always-visible scrollbar gives a target to drag.
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    // Only the vertical axis: a horizontal bar over a wide table would sit on
    // top of the last row.
    if (details.direction == AxisDirection.up ||
        details.direction == AxisDirection.down) {
      return Scrollbar(
        controller: details.controller,
        thumbVisibility: true,
        interactive: true,
        child: child,
      );
    }
    return child;
  }
}
