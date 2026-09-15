import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the app may sit untouched before it locks itself.
///
/// This is the *screen* lock, deliberately shorter than
/// [SessionSecurityPolicy.sessionTimeout] (30 min), which is the server-side
/// rule that decides a session is dead and cannot be resumed at all. Locking
/// first means an unattended desk is covered within five minutes, while a user
/// who steps away briefly is only asked to sign in again -- not told their
/// session was thrown away.
const Duration kIdleLockTimeout = Duration(minutes: 5);

/// True while the idle lock screen is covering the app.
///
/// ⚠️ The value lives OUTSIDE the ProviderScope, in a ValueNotifier, and the
/// provider only mirrors it.
///
/// Locking signs the user out, and signing out rebuilds the whole
/// ProviderScope to drop the previous session's cached rows (see
/// core/session_reset.dart). A plain StateProvider lives *in* that container,
/// so the rebuild reset this flag to false one frame after the lock went up
/// and the lock screen vanished again — the app looked like it had simply
/// stopped locking. The two features are each correct; they collided because
/// the lock's own state was stored in the thing the lock throws away.
///
/// Kept in a notifier the container cannot discard, it survives the rebuild,
/// and the provider below re-reads it in whatever container comes next.
final ValueNotifier<bool> idleLockedFlag = ValueNotifier<bool>(false);

/// The portal whose login page the lock should return to.
///
/// ⚠️ Outside the ProviderScope for the same reason as [idleLockedFlag]: it
/// is read AFTER the sign-out that rebuilt the container. Without it the app
/// came back to the portal chooser instead of the sign-in the officer had
/// been using — they were at the Disposal desk, and the app reopened on the
/// front door with every portal on it.
String lastLockedPortal = '/';

/// Who was signed in when the lock went up, and where they were.
///
/// ⚠️ Outside the ProviderScope for the same reason as [lastLockedPortal]:
/// the sign-out that accompanies the lock rebuilds the container, so anything
/// held inside it is gone by the time the officer comes back.
///
/// ⚠️ It holds an IDENTIFIER and a ROUTE — never a password, and never the
/// session. The lock still signs the user out, which is the whole point of it
/// (an unattended PC must hold no live session). This is only enough to
/// recognise that the SAME person came back and to put them where they were.
/// Someone else signing in gets a fresh app, because none of this matches.
class LockedSessionMemory {
  LockedSessionMemory._();

  /// The user id that was signed in, or null if nobody was.
  static String? userId;

  /// The route the officer was actually on — the dashboard, a register, a
  /// detail page — as opposed to the login page the lock navigates to.
  static String? route;

  /// Whatever a screen chose to save about its half-finished work, keyed by
  /// the route that saved it. A form puts its fields here as they are typed;
  /// nothing else reads them.
  static final Map<String, Map<String, dynamic>> formState = {};

  /// Remembers the person and the page, at the moment of locking.
  static void capture({required String? uid, required String? currentRoute}) {
    userId = uid;
    route = currentRoute;
  }

  /// True when [uid] is the person the lock remembers.
  ///
  /// A null [userId] means nothing was captured, so nothing can be resumed —
  /// this must not treat "nobody was signed in" as a match for anybody.
  static bool isSamePerson(String? uid) =>
      userId != null && uid != null && userId == uid;

  /// Drops everything. Called when a DIFFERENT user signs in, and after a
  /// resume has been used, so stale work cannot reappear later.
  static void clear() {
    userId = null;
    route = null;
    formState.clear();
  }
}

/// Reads [idleLockedFlag] and rebuilds watchers when it changes.
///
/// A provider so callers are unchanged, but it holds no state of its own —
/// the notifier is the single source of truth across scope rebuilds.
final idleLockedProvider = StateNotifierProvider<_IdleLockedState, bool>(
    (ref) => _IdleLockedState());

class _IdleLockedState extends StateNotifier<bool> {
  _IdleLockedState() : super(idleLockedFlag.value) {
    idleLockedFlag.addListener(_sync);
  }

  void _sync() => state = idleLockedFlag.value;

  /// Writes go to the notifier; [_sync] brings the provider's own state along,
  /// so the two can never disagree.
  void set(bool value) => idleLockedFlag.value = value;

  @override
  void dispose() {
    idleLockedFlag.removeListener(_sync);
    super.dispose();
  }
}

/// Watches for user activity and flips [idleLockedProvider] when there has been
/// none for [kIdleLockTimeout].
///
/// Only counts as "activity" what a person actually does: pointer movement,
/// clicks, scrolls and key presses. A background timer repainting a table is
/// not activity, which is the whole point -- a dashboard that polls every few
/// seconds must still lock when nobody is at the desk.
class IdleLockController {
  IdleLockController(this._ref);

  final Ref _ref;
  Timer? _timer;

  /// Whether there is a session worth protecting.
  ///
  /// Defaults to FALSE, and that default matters: the app opens on the portal
  /// chooser with nobody signed in, and the first mouse move over that page
  /// used to start a countdown that duly locked the login screen behind a
  /// "sign in again" notice. Nothing may arm the timer until [arm] is called
  /// with a real profile.
  bool _armed = false;

  /// Start protecting the session. Called once a profile exists.
  ///
  /// Idempotent: the overlay calls this from `build`, which runs on every
  /// rebuild of the app, and re-poking there would keep pushing the deadline
  /// out so a busy-but-untouched screen never locked.
  void arm() {
    if (_armed) return;
    _armed = true;
    poke();
  }

  /// Restart the countdown. Called on every real interaction.
  void poke() {
    // Once locked, activity must not silently un-lock the app -- the user has
    // to sign in again. The countdown resumes when the lock is lifted.
    if (!_armed || _ref.read(idleLockedProvider)) return;
    _timer?.cancel();
    _timer = Timer(kIdleLockTimeout, _lock);
  }

  void _lock() {
    _timer?.cancel();
    _timer = null;
    // Re-checked at fire time, not only when the timer was set: a sign-out
    // during the last few seconds of a countdown would otherwise still throw
    // the lock screen up over the portal chooser.
    if (!_armed) return;
    _ref.read(idleLockedProvider.notifier).set(true);
  }

  /// Lock immediately, without waiting out the countdown.
  void lockNow() {
    _armed = true;
    _lock();
  }

  /// Called after the user has signed back in.
  void unlock() {
    _ref.read(idleLockedProvider.notifier).set(false);
    poke();
  }

  /// Stop counting entirely -- used while no one is signed in, so the lock
  /// screen can never appear over a login page.
  void stop() {
    _armed = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => _timer?.cancel();
}

final idleLockControllerProvider = Provider<IdleLockController>((ref) {
  final c = IdleLockController(ref);
  ref.onDispose(c.dispose);
  return c;
});

/// Wraps the app and reports genuine user input to [IdleLockController].
///
/// [Listener] rather than [GestureDetector]: it sees raw pointer events before
/// any widget can claim them, so a click that a button handles still counts.
/// `behavior: deferToChild` is wrong here for the same reason -- the whole
/// surface must report, so the translucent behaviour is what we want.
class IdleActivityDetector extends ConsumerStatefulWidget {
  const IdleActivityDetector({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IdleActivityDetector> createState() =>
      _IdleActivityDetectorState();
}

class _IdleActivityDetectorState extends ConsumerState<IdleActivityDetector> {
  void _poke([_]) => ref.read(idleLockControllerProvider).poke();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _poke,
      onPointerMove: _poke,
      onPointerHover: _poke,
      onPointerSignal: _poke,
      child: Focus(
        // Keyboard-only work (typing into a long form, tabbing between fields)
        // moves no pointer at all, and must not be mistaken for an idle desk.
        onKeyEvent: (_, __) {
          _poke();
          return KeyEventResult.ignored;
        },
        canRequestFocus: false,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}


/// Where a portal should land after a successful sign-in.
///
/// Normally [home] — the portal's own dashboard. But if the app was LOCKED and
/// the person now signing in is the one it locked on, this returns the route
/// they were actually on, so they resume instead of restarting.
///
/// ⚠️ Matching is on the USER ID the sign-in just returned, not on anything
/// typed into the form. A different officer at the same desk gets [home] and a
/// cleared memory — they must never inherit the previous person's page, and
/// they must never see a form someone else half-filled.
///
/// Call it exactly once per sign-in: it CONSUMES the memory, so a later
/// ordinary sign-in cannot be sent to a stale page.
String resumeRouteAfterSignIn({required String? uid, required String home}) {
  if (!LockedSessionMemory.isSamePerson(uid)) {
    LockedSessionMemory.clear();
    return home;
  }
  final route = LockedSessionMemory.route;
  LockedSessionMemory.userId = null;  // spent; the form state stays for the
                                      // screen that is about to rebuild.
  if (route == null || route.isEmpty || route == '/') return home;
  return route;
}
