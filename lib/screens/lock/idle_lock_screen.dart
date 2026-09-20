import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import '../../widgets/brand_panel.dart';

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
  /// The crest's SVG source, loaded once per process.
  ///
  /// ⚠️ Read as a STRING rather than through SvgPicture.asset, because the
  /// knockout literal has to be rewritten before the renderer sees it — see
  /// the note at the crest below.
  static Future<String>? _crestSourceCache;
  Future<String> get _crestSource => _crestSourceCache ??=
      rootBundle.loadString('Sri_Lanka_Customs_logo_tinted.svg');

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
                            //
                            // ⚠️ The multiplier must be a WHOLE number. This
                            // was `t * 0.7`: when _drift wrapped from 1 back
                            // to 0 its phase was 0.7 x 2pi, not a multiple of
                            // 2pi, so the glow teleported across the screen
                            // once every 24 seconds — the "breaks and starts
                            // again" in the background. At x2 the phase lands
                            // exactly on 2 full turns as the controller
                            // wraps, so the loop is seamless; the +1.2 offset
                            // and the opposite sign still keep the two glows
                            // from ever repeating the same overlap.
                            alignment: Alignment(-0.6 * math.cos(t * 2 + 1.2),
                                -0.5 * math.sin(t * 2 + 1.2)),
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // ⚠️ 380 is the size this WANTS, not a size it takes
                        // unconditionally. A fixed 380 overflowed a short
                        // window by 5px — the column below it is
                        // MainAxisSize.min inside a Center, so nothing was
                        // going to shrink it. Roughly half the available
                        // height leaves room for the title, the pill and the
                        // hint underneath at any window size.
                        final seal = math.min(380.0,
                            math.max(220.0, constraints.maxHeight * 0.45));
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              // The rings are painted into THIS box, and the outer
                              // one at radius 178 needs 356 across or it clips.
                              width: seal,
                              height: seal,
                              child: AnimatedBuilder(
                                animation: Listenable.merge([_breathe, _orbit]),
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
                                // ⚠️ The knockout has to be repainted here too.
                                //
                                // The ship and the aeroplane in the crest are not
                                // transparent: they are painted a flat #1a1764
                                // and only READ as holes while the background
                                // behind them is that colour (see brand_panel.dart
                                // — a real transparent knockout does not survive
                                // flutter_svg). This screen loaded the asset
                                // straight through SvgPicture.asset, so the navy
                                // stayed navy against a near-black page and the
                                // two shapes showed as blue stickers on the seal.
                                child: FutureBuilder<String>(
                                  future: _crestSource,
                                  builder: (context, snap) {
                                    // Scales with the seal box so the crest keeps
                                    // its proportion inside the rings at any
                                    // window size.
                                    final crest = seal * 0.53;
                                    if (!snap.hasData) {
                                      return SizedBox(
                                          width: crest, height: crest);
                                    }
                                    return SvgPicture.string(
                                      crestWithKnockout(
                                          snap.data!, const Color(0xFF05060F)),
                                      width: crest,
                                      height: crest,
                                      theme: SvgTheme(currentColor: accent),
                                    );
                                  },
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
                              opacity:
                                  Tween<double>(begin: 0.45, end: 1.0).animate(
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
                        );
                      },
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
      88 + 12 * breath,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = color.withOpacity(0.22 + 0.10 * breath)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 60 + 14 * breath),
    );

    // ── The seat the crest sits on ──────────────────────────────────────
    //
    // ⚠️ THIS is what stops the ship and the plane reading as black patches.
    //
    // They are not transparent: they are painted the page colour (#05060F)
    // and only LOOK like holes while what is behind them is that colour. The
    // glow above adds light with BlendMode.plus, so the ring of page around
    // the crest is brighter than #05060F while the shapes inside it stay
    // exactly #05060F — and the eye reads that difference as two dark
    // cut-outs stamped on a lit seal.
    //
    // A soft pool of the page colour, painted back OVER the glow and under
    // the crest, takes the light out of the small area the crest covers, so
    // the shapes match their surroundings again. Drawn normally rather than
    // with `plus` so it subtracts light instead of adding it, and blurred
    // hard so it has no visible edge — the glow still reads everywhere
    // outside the seal, which is the part that should be lit.
    // ⚠️ Sized to the CREST, not to the glow: radius 78 is a little under the
    // crest's own half-width, so it darkens the disc the seal covers and
    // stops there. At 104 it swallowed the halo as well, and the seal lost
    // the light around it that makes it look lit at all.
    //
    // 0.72 rather than a full-strength pool, for the same reason: it has to
    // take the ADDED light back out, not paint a black disc over a screen
    // that is already nearly black.
    canvas.drawCircle(
      centre,
      78,
      Paint()
        ..color = const Color(0xFF05060F).withOpacity(0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );

    // ── Arcs ────────────────────────────────────────────────────────────
    // ⚠️ Bigger, to match the larger seal: 110/134 -> 146/178.
    //
    // Two BROKEN rings — a ring with a piece missing — turning in opposite
    // directions at different speeds.
    //
    // ⚠️ FIXED radii. These used to breathe with the seal (146 + 6 * breath,
    // 178 - 5 * breath), so the two rings grew and shrank on a 7-second
    // cycle while also turning. Two motions at once read as wobble rather
    // than rotation, and it fought the one thing that is supposed to pulse.
    // The seal alone breathes now; the rings only turn.
    //
    // ⚠️ The OUTER ring's multiplier must be a whole number too, and 0.6 is
    // not. `_orbit` runs 0 -> 1 and repeats; at x0.6 the outer arc had turned
    // 0.6 of a revolution when the controller wrapped, so it SNAPPED back to
    // its start — the outer ring "not completing its tour and going in
    // pieces", while the inner one (x1) looped cleanly and looked fine.
    //
    // x2 the other way: twice round per cycle, opposite direction, still
    // never in step with the inner ring, and it lands exactly on a whole
    // number of turns as the controller wraps.
    _arc(canvas, centre, 146, orbit * 2 * math.pi, 0.34);
    _arc(canvas, centre, 178, -orbit * 2 * math.pi * 2, 0.18);
  }

  /// One arc — a ring with a piece missing — turning without ever stopping.
  ///
  /// ⚠️ It is the GRADIENT that used to make this look broken, not the gap.
  ///
  /// The arc always rotated smoothly. But the sweep was pinned to the arc's
  /// own angle and faded to fully transparent along its length, so the bright
  /// head sat at a fixed point ON the shape and the tail died out at the same
  /// fixed point. Nothing appeared to travel; instead the line seemed to stop
  /// at one place and light up again at another.
  ///
  /// Now the arc keeps its gap and its rotation, and the brightness is even
  /// along it — so what the eye follows is the SHAPE going round, which is
  /// continuous. It fades only at the two ends, over a short stretch, so the
  /// ends are soft rather than cut square.
  ///
  /// ⚠️ THE REMAINING BREAK, and why it is not the gap either: a
  /// [SweepGradient] whose `stops` end before 1.0 does not stop there — it
  /// holds its last colour around the rest of the circle, and the jump from
  /// that held colour back to `stops[0]` is a hard SEAM at the gradient's own
  /// zero angle. `GradientRotation(angle)` carried that seam around with the
  /// arc, so once per revolution it crossed the drawn part and the ring
  /// visibly snapped — "it goes a distance, breaks, and starts again
  /// somewhere else".
  ///
  /// The fix is to describe the WHOLE circle: the stops now run to 1.0, with
  /// the unlit remainder explicitly transparent at both the start and the
  /// end. There is no held colour and no discontinuity anywhere on the
  /// sweep, so the seam has nothing to show. The shape turns; nothing jumps.
  void _arc(
      Canvas canvas, Offset centre, double radius, double angle, double alpha) {
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // The drawn portion of the circle: just over half, so the gap is obvious.
    const sweep = math.pi * 1.15;
    final frac = sweep / (2 * math.pi);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        // Soft at both ends, full through the middle, and TRANSPARENT the
        // whole way round the gap — so the first and last stop agree and the
        // gradient closes on itself seamlessly.
        colors: [
          color.withOpacity(0),
          color.withOpacity(alpha),
          color.withOpacity(alpha),
          color.withOpacity(0),
          color.withOpacity(0),
        ],
        stops: [0.0, frac * 0.18, frac * 0.82, frac, 1.0],
        transform: GradientRotation(angle),
      ).createShader(rect);

    canvas.drawArc(rect, angle, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_SealHaloPainter old) =>
      old.breath != breath || old.orbit != orbit || old.color != color;
}
