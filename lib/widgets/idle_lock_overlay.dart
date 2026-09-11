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

  /// Whether THIS lock has already done its sign-out.
  ///
  /// ⚠️ Static, because this State does not survive the lock.
  ///
  /// Signing out rebuilds the ProviderScope (core/session_reset.dart) and
  /// this overlay is inside it, so the widget is torn down and rebuilt one
  /// frame after the lock goes up. A plain field came back `false` with the
  /// lock still raised, so `_onLocked` ran a second time: another sign-out,
  /// another scope rebuild, and the app could sit in that loop instead of
  /// resting on the lock screen. Cleared by [_unlock] and by a fresh sign-in.
  static bool _signingOut = false;

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
    lastLockedPortal = _loginRoute;
    _accent = _accentForRole[role] ??
        (role == 'disposal'
            ? Theme.of(context).extension<AppColors>()?.successGreen
            : role == 'valuation'
                ? Theme.of(context).extension<AppColors>()?.primaryGold
                : Theme.of(context).extension<AppColors>()?.accentLightBlue);

    // ⚠️ Read the router BEFORE signing out, and navigate BEFORE it too.
    //
    // signOut() bumps the session epoch, which replaces the whole
    // ProviderScope — so a `ref.read(routerProvider)` afterwards reaches
    // into a container that is being torn down. The officer was left on the
    // dashboard route instead of their portal's login page, and once the
    // lock was lifted that is where the app came back to: the redirect then
    // bounced them to '/' — the portal chooser — rather than to the sign-in
    // they had been using.
    final router = ref.read(routerProvider);
    router.go(_loginRoute);

    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      // A failed sign-out must NOT leave the app unlocked -- the screen still
      // goes up and the local session is dropped below either way. The server
      // side then expires it on its own via SessionSecurityPolicy.
    }
    if (!mounted) return;
    ref.read(currentProfileProvider.notifier).state = null;
  }

  void _unlock() {
    _signingOut = false;
    // ⚠️ Navigate again rather than trusting what is underneath.
    //
    // The route was set when the lock went up, but the sign-out that
    // followed replaced the ProviderScope and re-ran the router's redirect
    // with no session — which sends any non-public route to '/'. Re-stating
    // the portal here is what guarantees the officer lands back on the
    // sign-in page they came from, not on the portal chooser.
    ref.read(routerProvider).go(lastLockedPortal);
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
      // ⚠️ Do NOT clear the lock flag here.
      //
      // A "a profile exists, so we cannot be locked" safety net belongs at
      // SIGN-IN, not in build(). Locking is: flag goes true, then the
      // sign-out runs. Between those two the profile is still set, so this
      // build sees locked=true WITH a profile and cleared the flag —
      // cancelling the lock it had just raised. The officer got no lock
      // screen at all: the session was silently signed out and the router
      // dropped them on the portal chooser, which is exactly the "it goes
      // to the home page instead of locking" this was supposed to fix.
      //
      // The stale-global worry it was guarding against is real, but a fresh
      // sign-in is where it is answered — see IdleLockController.unlock(),
      // which every login screen reaches through _unlock.
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
