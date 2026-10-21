import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

/// Opening splash screen animation matching the organization identity.
///
/// Features:
/// - Rich deep navy & sapphire gradient with ambient gold warmth
/// - Smooth rounded squircle card with drop-shadow holding the official seal
/// - Title & Subtitle with elegant entrance animations
/// - Sleek horizontal capsule progress bar smoothly filling to 100%
/// - Notifies [onComplete] upon finishing so the caller can transition into the portal view
class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({
    super.key,
    required this.onComplete,
    this.duration = const Duration(milliseconds: 2300),
    this.settleDelay = const Duration(milliseconds: 160),
  });

  final VoidCallback onComplete;
  final Duration duration;
  final Duration settleDelay;

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller.forward().then((_) {
      if (!mounted || _completed) return;
      Future.delayed(widget.settleDelay, () {
        if (!mounted || _completed) return;
        _finish();
      });
    });
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    _controller.stop();
    widget.onComplete();
  }

  @override
  void dispose() {
    _completed = true;
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B18),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Allow tap anywhere to skip/speed up if needed
        onTap: _finish,
        child: Stack(
          children: [
            // ── Background Gradient ──────────────────────────────────────
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-0.85, -0.9),
                    end: Alignment(0.9, 0.95),
                    colors: [
                      Color(0xFF060B18), // Deep Midnight Customs Navy
                      Color(0xFF0D1B3E), // Midnight Sapphire
                      Color(0xFF13255C), // Vibrant Navy Sapphire
                      Color(0xFF261D16), // Subtle warm Amber/Gold dusk glow
                    ],
                    stops: [0.0, 0.35, 0.70, 1.0],
                  ),
                ),
              ),
            ),

            // ── Ambient Glow Behind Emblem ─────────────────────────────────
            Center(
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF2E5BFF).withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Ambient Warm Gold Glow at Bottom Right ────────────────────
            Positioned(
              right: -100,
              bottom: -100,
              child: Container(
                width: 480,
                height: 480,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFD4AF37).withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Centered Content (Tile, Titles, Progress Bar) ─────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // White Squircle Logo Tile
                  Container(
                    width: 114,
                    height: 114,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.95),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.38),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                        BoxShadow(
                          color: const Color(0xFF2E5BFF).withValues(alpha: 0.20),
                          blurRadius: 22,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SvgPicture.asset(
                      'Sri_Lanka_Customs_logo.svg',
                      fit: BoxFit.contain,
                    ),
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0.82, 0.82),
                        end: const Offset(1.0, 1.0),
                        duration: 650.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fadeIn(duration: 600.ms, curve: Curves.easeOut),

                  const Gap(22),

                  // App Main Title
                  const Text(
                    'Sri Lanka Customs',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      height: 1.2,
                    ),
                  )
                      .animate()
                      .slideY(
                        begin: 0.35,
                        end: 0,
                        delay: 180.ms,
                        duration: 550.ms,
                        curve: Curves.easeOutCubic,
                      )
                      .fadeIn(delay: 180.ms, duration: 550.ms),

                  const Gap(8),

                  // App Subtitle
                  Text(
                    'SR Management System',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                      height: 1.2,
                    ),
                  )
                      .animate()
                      .slideY(
                        begin: 0.35,
                        end: 0,
                        delay: 300.ms,
                        duration: 550.ms,
                        curve: Curves.easeOutCubic,
                      )
                      .fadeIn(delay: 300.ms, duration: 550.ms),

                  const Gap(22),

                  // Smooth Capsule Progress Bar
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) {
                      const barWidth = 205.0;
                      const barHeight = 4.5;
                      final currentWidth = (barWidth * _progress.value).clamp(0.0, barWidth);

                      return Container(
                        width: barWidth,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: currentWidth,
                            height: barHeight,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFE2E8F0),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ).animate().fadeIn(delay: 350.ms, duration: 400.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
