import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The screensaver shown once the app has been idle for
/// [kIdleLockTimeout] -- a slow, dark, ambient page with the Customs seal
/// breathing at the centre of it.
///
/// It is deliberately calm rather than alarming: nothing has gone wrong, the
/// desk was simply left alone. The one instruction on it ("Click anywhere to
/// sign in again") is what the whole screen is for, so it is the only thing
/// competing with the logo.
///
/// The animation is driven by three long, out-of-phase controllers rather than
/// one, so the drifting glow, the rotating ring and the pulse never line up
/// into a visible loop -- the trick the old Windows screensavers used to look
/// alive for hours without repeating.
class IdleLockScreen extends StatefulWidget {
  const IdleLockScreen({super.key, required this.onUnlock, this.accent});

  /// Runs when the user asks to come back -- a click, a tap, or any key.
  final VoidCallback onUnlock;

  /// The signed-in portal's colour, so the lock screen still reads as *their*
  /// portal. Falls back to the Customs gold.
  final Color? accent;

  @override
  State<IdleLockScreen> createState() => _IdleLockScreenState();
}

class _IdleLockScreenState extends State<IdleLockScreen>
    with TickerProviderStateMixin {
  /// The slow drift of the two background glows.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  /// The seal's breathing scale + the halo behind it.
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  /// The ring orbiting the seal. Deliberately not a whole-number multiple of
  /// the others, so the three never resynchronise.
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 19),
  )..repeat();

  /// One-shot fade so the lock screen arrives gently instead of snapping in.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _drift.dispose();
    _breathe.dispose();
    _orbit.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? const Color(0xFFD4A22B);
    return Focus(
      autofocus: true,
      // Any key wakes it too -- reaching for the mouse should not be required.
      onKeyEvent: (_, __) {
        widget.onUnlock();
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onUnlock,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
            // Material, so every Text on the screen resolves a real font and
            // decoration from it. Without one the screen depends on whatever
            // ancestor happens to be above it, and text renders with the
            // debug fallback (yellow, double-underlined).
            child: Material(
              color: const Color(0xFF05060F),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Drifting glows ────────────────────────────────────
                  AnimatedBuilder(
                    animation: _drift,
                    builder: (context, _) {
                      final t = _drift.value * 2 * math.pi;
                      // ⚠️ One blur over BOTH glows.
                      //
                      // The softened falloff removed the hard rings, but a
                      // gradient still quantises to the display's 256 levels
                      // per channel and the remaining steps drift across the
                      // screen as faint contour lines — waves. A blur smears
                      // each step into its neighbours, which removes them
                      // rather than making them finer.
                      //
                      // One ImageFiltered for the pair, not one each: the
                      // filter is the expensive part and it is the same
                      // filter.
                      //
                      // Opacity is raised to compensate — a blur spreads the
                      // same light over more pixels, so at the old values the
                      // glows all but vanished.
                      return ImageFiltered(
                        imageFilter:
                            ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: Stack(children: [
                          _glow(
                            alignment: Alignment(
                                0.55 * math.cos(t), 0.45 * math.sin(t)),
                            color: accent,
                            size: 620,
                            opacity: 0.24,
                          ),
                          _glow(
                            // Counter-rotating and offset, so the two never
                            // overlap the same way twice.
                            alignment: Alignment(-0.6 * math.cos(t * 0.7 + 1.2),
                                -0.5 * math.sin(t * 0.7 + 1.2)),
                            color: const Color(0xFF2B3A8F),
                            size: 720,
                            opacity: 0.32,
                          ),
                        ]),
                      );
                    },
                  ),

                  // ── The seal ──────────────────────────────────────────
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 300,
                          height: 300,
                          child: AnimatedBuilder(
                            animation:
                                Listenable.merge([_breathe, _orbit]),
                            builder: (context, child) {
                              final breath = Curves.easeInOut
                                  .transform(_breathe.value);
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Halo + rings, painted together into ONE
                                  // canvas.
                                  //
                                  // A gradient-filled Container cannot do this
                                  // job: a radial fading to transparent still
                                  // composites as a disc over the drifting
                                  // background, which read as a dark circle
                                  // parked behind the seal. Painting the glow
                                  // as a blurred circle on the shared canvas
                                  // lets the background show through it.
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _SealHaloPainter(
                                        color: accent,
                                        breath: breath,
                                        orbit: _orbit.value,
                                      ),
                                    ),
                                  ),
                                  Transform.scale(
                                    scale: 0.97 + 0.05 * breath,
                                    child: child,
                                  ),
                                ],
                              );
                            },
                            child: SvgPicture.asset(
                              'Sri_Lanka_Customs_logo_tinted.svg',
                              width: 150,
                              height: 150,
                              theme: SvgTheme(currentColor: accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          'Sri Lanka Customs',
                          style: TextStyle(
                            color: accent,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'SR Management System',
                          style: TextStyle(
                              color: Color(0xFF8E93B0),
                              fontSize: 14,
                              letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 46),
                        // ── The lock notice ───────────────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.10)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  size: 16, color: accent.withOpacity(0.9)),
                              const SizedBox(width: 10),
                              const Text(
                                'Locked after 5 minutes of inactivity',
                                style: TextStyle(
                                    color: Color(0xFFB6BAD0),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Gently pulsing so the eye is drawn to the one thing
                        // the user has to do.
                        FadeTransition(
                          opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
                            CurvedAnimation(
                                parent: _breathe, curve: Curves.easeInOut),
                          ),
                          child: const Text(
                            'Click anywhere to sign in again',
                            style: TextStyle(
                                color: Color(0xFF7E839C),
                                fontSize: 13.5,
                                letterSpacing: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glow({
    required Alignment alignment,
    required Color color,
    required double size,
    required double opacity,
  }) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // ⚠️ EIGHT stops on a squared falloff, not two on a straight
            // line. Two stops fall linearly, and a display has only 256
            // levels per channel to spend — on near-black the wide dim outer
            // half gets far too few, so each level covers enough pixels to
            // read as a RING. Drifting, those rings look like waves.
            //
            // `(1-x)^2` concentrates the change near the centre, which is
            // both how light actually falls off and where the banding is
            // least visible.
            gradient: RadialGradient(
              colors: [
                for (var i = 0; i < 8; i++)
                  color.withOpacity(opacity * math.pow(1 - i / 7, 2)),
              ],
              stops: [for (var i = 0; i < 8; i++) i / 7],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the seal's glow and its two travelling arcs onto one canvas.
///
/// Doing this in a painter rather than with decorated Containers is what keeps
/// the drifting background visible through the glow: a MaskFilter blur spreads
/// real light out from the circle, where a radial gradient on an opaque layer
/// merely draws a disc that happens to fade at its edge.
class _SealHaloPainter extends CustomPainter {
  const _SealHaloPainter({
    required this.color,
    required this.breath,
    required this.orbit,
  });

  final Color color;

  /// 0..1, the seal's breathing phase.
  final double breath;

  /// 0..1, the arcs' rotation phase.
  final double orbit;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);

    // ── Glow ────────────────────────────────────────────────────────────
    // A heavily blurred circle. `plus` adds light to whatever is underneath,
    // so the drifting background brightens through it instead of being
    // covered by it.
    canvas.drawCircle(
      centre,
      66 + 10 * breath,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = color.withOpacity(0.22 + 0.10 * breath)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 48 + 12 * breath),
    );

    // ── Arcs ────────────────────────────────────────────────────────────
    _arc(canvas, centre, 110 + 5 * breath, orbit * 2 * math.pi, 0.34);
    _arc(canvas, centre, 134 - 4 * breath, -orbit * 2 * math.pi * 0.6, 0.18);
  }

  /// One thin arc, bright at its head and fading along its tail so the
  /// rotation is legible without a hard edge.
  void _arc(
      Canvas canvas, Offset centre, double radius, double angle, double alpha) {
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          color.withOpacity(alpha),
          color.withOpacity(alpha * 0.3),
          color.withOpacity(0),
        ],
        stops: const [0.0, 0.35, 1.0],
        transform: GradientRotation(angle),
      ).createShader(rect);

    // Just over half the circle, so there is always a visible gap -- a full
    // ring would look static however fast it span.
    canvas.drawArc(rect, angle, math.pi * 1.15, false, paint);
  }

  @override
  bool shouldRepaint(_SealHaloPainter old) =>
      old.breath != breath || old.orbit != orbit || old.color != color;
}
