import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

import '../../core/theme.dart';

/// The seal, then the portals.
///
/// ⚠️ This is not decoration over an idle app. `main()` shows the window
/// BEFORE it connects to PostgreSQL, caches the query layer's foreign keys and
/// starts the change listener — so on a cold start the first thing the user
/// sees has always been a portal page that is not yet backed by a database.
/// This covers exactly that gap with something that reads as "starting up"
/// rather than as "ready".
///
/// ⚠️ The home screen is built and laid out BEHIND the splash the whole time,
/// never after it. Swapping one screen for another at the end would put the
/// portal's own entrance animations after the splash's, and the reader would
/// watch the app assemble itself twice. Here the seal simply dissolves and the
/// page it uncovers is already there.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  /// The real page — the portal chooser. Built immediately, under the splash.
  final Widget child;

  /// How long the seal holds before it begins to dissolve.
  ///
  /// ⚠️ Short on purpose. A splash that outstays the work it covers is just a
  /// delay, and this one runs on every launch.
  static const Duration hold = Duration(milliseconds: 1100);

  /// The dissolve itself.
  static const Duration fade = Duration(milliseconds: 620);

  /// Whether this launch still owes the user a splash — true exactly once.
  ///
  /// ⚠️ The portal page is also where SIGNING OUT lands, and '/' is rebuilt
  /// every time. Without this the seal would reappear on every sign-out and
  /// read as the whole app restarting, which is alarming rather than
  /// welcoming. Asking consumes it, so the second caller gets the page bare.
  static bool _owed = true;

  static bool consume() {
    if (!_owed) return false;
    _owed = false;
    return true;
  }

  /// For tests: puts the splash back on the slate.
  @visibleForTesting
  static void resetForTest() => _owed = true;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  /// True once the dissolve has begun.
  bool _lifting = false;

  /// True once it has finished, after which the splash is gone from the tree
  /// entirely — a permanently stacked overlay would keep eating pointer events
  /// and repainting a blur nobody can see.
  bool _done = false;

  /// ⚠️ Held so they can be CANCELLED. A bare `Future.delayed` keeps firing
  /// after the widget is gone — harmless in the app, where this lives for one
  /// second at launch, but it leaves a pending timer behind in a widget test
  /// and fails it with "A Timer is still pending". Something that cannot be
  /// torn down cleanly is worth fixing rather than working around.
  Timer? _holdTimer;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    _holdTimer = Timer(SplashGate.hold, () {
      if (!mounted) return;
      setState(() => _lifting = true);
      _fadeTimer = Timer(SplashGate.fade, () {
        if (!mounted) return;
        setState(() => _done = true);
      });
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    return Stack(children: [
      // The portal page, laying itself out while the seal is still up.
      widget.child,
      // ⚠️ IgnorePointer wraps everything the splash paints, and must keep
      // doing so: the layer's own background Container is opaque to hit
      // testing, so anything drawn outside this would swallow a tap through a
      // curtain that is already almost transparent.
      //
      // The page underneath becomes clickable the moment the seal starts to
      // lift, not when it finishes.
      IgnorePointer(
        ignoring: _lifting,
        child: AnimatedOpacity(
          opacity: _lifting ? 0 : 1,
          duration: SplashGate.fade,
          curve: Curves.easeOutCubic,
          child: _SplashLayer(lifting: _lifting),
        ),
      ),
    ]);
  }
}

class _SplashLayer extends StatelessWidget {
  const _SplashLayer({required this.lifting});

  final bool lifting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TweenAnimationBuilder<double>(
      // 0 while the seal holds, 1 once it lifts. Drives the blur and the
      // slight scale-up together, so the whole layer recedes as one thing
      // rather than fading in parts.
      tween: Tween(begin: 0, end: lifting ? 1 : 0),
      duration: SplashGate.fade,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => ImageFiltered(
        // ⚠️ sigma must never be exactly 0 on some backends — a zero-sigma
        // blur can render as a black rectangle rather than as no blur — so the
        // filter is only applied once the lift has actually started.
        imageFilter: t <= 0.001
            ? ui.ImageFilter.blur(sigmaX: 0.01, sigmaY: 0.01)
            : ui.ImageFilter.blur(sigmaX: t * 18, sigmaY: t * 18),
        child: Transform.scale(scale: 1 + t * 0.06, child: child),
      ),
      child: Container(
        color: c.scaffoldBg,
        child: Stack(children: [
          // The same two glows the portal page carries, so the background does
          // not change underneath the reader when the splash lifts.
          Positioned(
              top: -80,
              left: -60,
              child: _Glow(color: c.customsBlue.withOpacity(0.35), size: 360)),
          Positioned(
              bottom: -80,
              right: -60,
              child: _Glow(color: c.primaryGold.withOpacity(0.12), size: 320)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'Sri_Lanka_Customs_logo.svg',
                  width: 148,
                  height: 148,
                )
                    .animate()
                    .fadeIn(duration: 420.ms)
                    .scale(
                        begin: const Offset(0.86, 0.86),
                        duration: 620.ms,
                        curve: Curves.easeOutBack),
                const Gap(22),
                Text(
                  'Sri Lanka Customs',
                  style: TextStyle(
                      color: c.customsBlue,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2),
                ).animate().fadeIn(delay: 180.ms, duration: 480.ms),
                const Gap(6),
                Text(
                  'SR Management System',
                  style: TextStyle(
                      color: c.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6),
                ).animate().fadeIn(delay: 300.ms, duration: 480.ms),
                const Gap(30),
                // A thin determinate-looking sweep. Deliberately NOT a
                // percentage: the work behind it has no measurable progress,
                // and a bar that claims one would be lying.
                SizedBox(
                  width: 132,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: c.customsBlue.withOpacity(0.12),
                      valueColor:
                          AlwaysStoppedAnimation(c.customsBlue.withOpacity(0.7)),
                    ),
                  ),
                ).animate().fadeIn(delay: 420.ms, duration: 400.ms),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The soft corner glow, matching the portal page's own.
class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      ),
    );
  }
}
