import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/idle_lock.dart';
import '../core/providers.dart';
import '../core/router.dart';
import '../core/theme.dart';
import '../screens/lock/idle_lock_screen.dart';

/// Puts [IdleLockScreen] over the whole app once it has gone idle, and signs
/// the user out when it does.
///
/// The sign-out happens the MOMENT the screen appears, not when the user comes
/// back to it. That is what makes this a security feature rather than a
/// decoration: from the instant the desk is unattended the session is already
/// gone, so an unlocked PC exposes nothing, and there is no live session left
/// for someone to resume by killing the app or yanking the network.
///
/// Sits above the router (inside [MaterialApp.router]'s builder) so it covers
/// every route, and so the navigation underneath can be swapped for the login
/// page while the lock screen is still painted over the top of it.
class IdleLockOverlay extends ConsumerStatefulWidget {
  const IdleLockOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IdleLockOverlay> createState() => _IdleLockOverlayState();
}

class _IdleLockOverlayState extends ConsumerState<IdleLockOverlay> {
  /// The portal the user was in when the lock hit, remembered BEFORE signing
  /// out -- the profile is null immediately afterwards, and this is what the
  /// unlock has to navigate back to.
  String _loginRoute = '/';
  Color? _accent;
  bool _signingOut = false;

  /// Where each role signs back in. Mirrors the router's post-login redirect,
  /// in reverse: a user is returned to the door they actually came through, so
  /// the sign-in form they see is the one they know.
  static const _routeForRole = {
    'ict': '/ict/login',
    'disposal': '/disposal/login',
    'appeal': '/appeal/login',
    'valuation': '/valuation/login',
    'executive': '/executive/login',
    'admin': '/admin/login',
    'officer': '/login',
  };

  static const _accentForRole = {
    'ict': AppTheme.ictCyan,
    'appeal': AppTheme.appealPurple,
    'executive': AppTheme.executiveTeal,
  };

  /// Called once, as the lock screen goes up.
  Future<void> _onLocked() async {
    if (_signingOut) return;
    _signingOut = true;

    final profile = ref.read(currentProfileProvider);
    final role = profile?.role;
    _loginRoute = _routeForRole[role] ?? '/';
    _accent = _accentForRole[role] ??
        (role == 'disposal'
            ? Theme.of(context).extension<AppColors>()?.successGreen
            : role == 'valuation'
                ? Theme.of(context).extension<AppColors>()?.primaryGold
                : Theme.of(context).extension<AppColors>()?.accentLightBlue);

    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      // A failed sign-out must NOT leave the app unlocked -- the screen still
      // goes up and the local session is dropped below either way. The server
      // side then expires it on its own via SessionSecurityPolicy.
    }
    if (!mounted) return;
    ref.read(currentProfileProvider.notifier).state = null;

    // Swap the route underneath to the login page straight away. The lock
    // screen is opaque and covers it, so nothing of this is seen -- but it
    // means the dashboard is torn down (stopping its polling, and releasing
    // whatever it had loaded) rather than left mounted behind the lock with a
    // profile that no longer exists.
    ref.read(routerProvider).go(_loginRoute);
  }

  void _unlock() {
    _signingOut = false;
    // The login page is already the route underneath (put there when the lock
    // went up), so lifting the overlay reveals it -- no navigation needed here.
    ref.read(idleLockControllerProvider).unlock();
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(idleLockedProvider);

    // Only run the countdown while someone is actually signed in: with no
    // session there is nothing to protect, and a lock screen over the portal
    // chooser would be nonsense.
    //
    // WATCHED, not merely listened to. `ref.listen` fires on CHANGES only, so
    // at start-up -- profile already null, no change to report -- the callback
    // never ran, the controller stayed in whatever state it began in, and the
    // first mouse movement over the portal chooser armed a countdown that
    // locked a page nobody had signed into.
    final profile = ref.watch(currentProfileProvider);
    final controller = ref.read(idleLockControllerProvider);
    if (profile == null) {
      controller.stop();
    } else {
      controller.arm();
    }

    if (locked && !_signingOut) {
      // Fires once per lock, after this frame, so the sign-out's provider
      // writes do not happen during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onLocked());
    }

    return Stack(
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: IdleLockScreen(accent: _accent, onUnlock: _unlock),
          ),
      ],
    );
  }
}
