import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

// ⚠️ A plain StatelessWidget now. It was a ConsumerWidget only for the
// theme toggle in its corner; with that gone this page reads nothing from
// Riverpod, and leaving it a Consumer would invite the next reader to add a
// watch here rather than in the portal that needs it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
        // ⚠️ The two glows DRIFT across the whole screen rather than sitting in
        // their corners. They are the only movement on a page that otherwise
        // stands still once its cards have landed, and a slow travel reads as
        // the app being alive without asking to be looked at.
        //
        // Behind everything and pointer-transparent: this must never intercept
        // a click meant for a portal card.
        const Positioned.fill(child: DriftingGlows()),
        // ⚠️ No theme toggle on this page.
        //
        // The portal chooser is a doorway -- an officer is here for two
        // seconds on the way to their portal, and a control in the corner of
        // it is one more thing in the way of the six cards it exists to show.
        //
        // Nothing is lost: every sign-in screen and every dashboard carries
        // its own toggle, so the theme is still one click away wherever an
        // officer actually spends time.
        SingleChildScrollView(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: MediaQuery.of(context).size.height),
            child: IntrinsicHeight(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    SvgPicture.asset(
                      'Sri_Lanka_Customs_logo.svg',
                      width: 132,
                      height: 132,
                    )
                        .animate()
                        .scale(
                            begin: const Offset(0.8, 0.8),
                            duration: 500.ms,
                            curve: Curves.easeOutBack)
                        .fadeIn(),
                    const Gap(18),
                    Text(
                      'Sri Lanka Customs',
                      style: TextStyle(
                          color: context.colors.customsBlue,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2),
                    )
                        .animate()
                        .slideY(begin: 0.4, duration: 500.ms, delay: 200.ms)
                        .fadeIn(),
                    const Gap(8),
                    Text(
                      'SR Management System',
                      style: TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5),
                    )
                        .animate()
                        .slideY(begin: 0.4, duration: 500.ms, delay: 300.ms)
                        .fadeIn(),
                    const Gap(28),
                    // Helper line so users know what the cards are for.
                    Text(
                      'Select your portal to continue',
                      style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ).animate().fadeIn(delay: 400.ms),
                    const Gap(28),

                    // Role cards side by side
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: IntrinsicHeight(
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Officer + Admin both belong to a yard → one combined
                              // "Yard Access" card that goes to the chooser screen.
                              Flexible(
                                  child: _RoleCard(
                                icon: Icons.warehouse_rounded,
                                title: 'Yard Access',
                                subtitle:
                                    'Officers & Administrators\nSign in to your yard',
                                accentColor: context.colors.accentLightBlue,
                                onLogin: (ctx) => ctx.go('/yard-access'),
                                showSignup: false,
                                delay: 500,
                              )),
                              const Gap(16),
                              Flexible(
                                  child: _RoleCard(
                                icon: Icons.balance_rounded,
                                title: 'Appeal Directorate',
                                subtitle:
                                    'Review forfeited packages\n& hold appeals',
                                accentColor: AppTheme.appealPurple,
                                onLogin: (ctx) => ctx.go('/appeal/login'),
                                onSignup: (ctx) => ctx.go('/appeal/signup'),
                                delay: 750,
                              )),
                              const Gap(16),
                              Flexible(
                                  child: _RoleCard(
                                icon: Icons.calculate_rounded,
                                title: 'Valuation Directorate',
                                subtitle:
                                    'Value disposal requests\nbefore Central Disposal',
                                accentColor: context.colors.primaryGold,
                                onLogin: (ctx) => ctx.go('/valuation/login'),
                                onSignup: (ctx) => ctx.go('/valuation/signup'),
                                delay: 950,
                              )),
                              const Gap(16),
                              Flexible(
                                  child: _RoleCard(
                                icon: Icons.gavel_rounded,
                                title: 'Central Disposal Directorate',
                                subtitle:
                                    'View sold items across all yards\n& record tender sales',
                                accentColor: context.colors.successGreen,
                                onLogin: (ctx) => ctx.go('/disposal/login'),
                                onSignup: (ctx) => ctx.go('/disposal/signup'),
                                delay: 1100,
                              )),
                              const Gap(16),
                              Flexible(
                                  child: _RoleCard(
                                icon: Icons.shield_moon_rounded,
                                title: 'Top Management Directorate',
                                subtitle:
                                    'DG / ADG · reports, valuations\n& tender committees',
                                accentColor: AppTheme.executiveTeal,
                                onLogin: (ctx) => ctx.go('/executive/login'),
                                onSignup: (ctx) => ctx.go('/executive/signup'),
                                delay: 1250,
                              )),
                              const Gap(16),
                              Flexible(
                                  child: _RoleCard(
                                icon: Icons.terminal_rounded,
                                title: 'ICT Directorate',
                                subtitle:
                                    'SDDC / DDC & Officers\nprovisioning & accounts',
                                accentColor: AppTheme.ictCyan,
                                onLogin: (ctx) => ctx.go('/ict/login'),
                                onSignup: (ctx) => ctx.go('/ict/signup'),
                                delay: 1350,
                              )),
                            ]),
                      ),
                    ),
                    const Spacer(),
                    // ── Copyright / attribution ─────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16, top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.copyright_rounded,
                                  size: 13, color: context.colors.textMuted),
                              const Gap(6),
                              Text(
                                '${DateTime.now().year} Anushanga Munasinghe · All rights reserved',
                                style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const Gap(2),
                          Text(
                            'Designed & developed by Anushanga Munasinghe · Unauthorised copying or redistribution is prohibited.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.colors.textMuted.withOpacity(0.7),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 1300.ms),
                    ),
                  ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The two corner glows, travelling the width and height of the screen.
///
/// ⚠️ One controller for both, looped and reversing, so they never drift out
/// of step with each other or restart with a jump. The blue crosses from the
/// top-left to the bottom-right and the gold the other way, which keeps the
/// centre of the page — where the seal and the cards are — from ever being
/// washed out by both at once.
class DriftingGlows extends StatefulWidget {
  const DriftingGlows({super.key});

  @override
  State<DriftingGlows> createState() => _DriftingGlowsState();
}

class _DriftingGlowsState extends State<DriftingGlows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // ⚠️ Slow on purpose. Fast enough to notice and far too slow to distract:
    // this page is where an officer chooses a portal, not something to watch.
    duration: const Duration(seconds: 24),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Eased rather than linear, so each pass slows at the turn instead
          // of snapping back the other way.
          final t = Curves.easeInOutSine.transform(_c.value);
          return LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            return Stack(children: [
              // Blue: top-left → bottom-right.
              Positioned(
                left: -160 + t * (w * 0.55),
                top: -140 + t * (h * 0.75),
                child: _GlowBlob(
                    color: c.customsBlue.withOpacity(0.35), size: 420),
              ),
              // Gold: bottom-right → top-left, the opposite way.
              Positioned(
                right: -140 + t * (w * 0.5),
                bottom: -120 + t * (h * 0.7),
                child: _GlowBlob(
                    color: c.primaryGold.withOpacity(0.12), size: 360),
              ),

              // ⚠️ One faint glow per PORTAL, so the page carries every
              // colour the cards below it do -- not just the two it started
              // with. This is the page where an officer picks a portal, and
              // the portals are the only thing on it that has a colour.
              //
              // ⚠️ Far fainter than the two above (0.05-0.07 against
              // 0.12 and 0.35) and larger, so they read as tint rather than as
              // four more lamps. Six blobs at the leading pair's strength
              // would be a fairground.
              //
              // Each sits along a different edge and travels a different
              // distance, so they never stack into one bright patch -- and the
              // CENTRE is left alone, because that is where the seal and the
              // cards are.
              for (final g in <({Color colour, double dx, double dy, double size, double from})>[
                (colour: AppTheme.appealPurple, dx: 0.30, dy: 0.10, size: 340, from: 0.10),
                (colour: AppTheme.executiveTeal, dx: -0.28, dy: 0.14, size: 320, from: 0.72),
                (colour: c.successGreen, dx: 0.22, dy: -0.18, size: 300, from: 0.55),
                (colour: AppTheme.ictCyan, dx: -0.24, dy: -0.12, size: 300, from: 0.28),
              ])
                Positioned(
                  left: w * g.from + t * (w * g.dx) - g.size / 2,
                  top: h * (0.5 + g.dy) + t * (h * g.dy) - g.size / 2,
                  child: _GlowBlob(
                      color: g.colour.withOpacity(0.06), size: g.size),
                ),
            ]);
          });
        },
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowBlob({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color, blurRadius: size * 0.7, spreadRadius: size * 0.2)
          ],
        ),
      );
}

class _RoleCard extends StatefulWidget {
  final IconData icon;
  final String title, subtitle;
  final Color accentColor;
  final void Function(BuildContext) onLogin;
  final void Function(BuildContext)? onSignup;
  final bool showSignup;
  final int delay;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onLogin,
    this.onSignup,
    this.showSignup = true,
    required this.delay,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Pick a label colour that stays legible on the accent: white on dark
    // accents, near-black on light ones (e.g. the gold card).
    final onAccent = widget.accentColor.computeLuminance() > 0.55
        ? const Color(0xFF1A1A24)
        : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                      color: widget.accentColor.withOpacity(0.28),
                      blurRadius: 34,
                      spreadRadius: 2)
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05), blurRadius: 12)
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            // Frost the page's glow through the card on hover → liquid glass.
            filter: ui.ImageFilter.blur(
                sigmaX: _hovered ? 18 : 0, sigmaY: _hovered ? 18 : 0),
            child: Container(
              decoration: BoxDecoration(
                // Hover: a soft accent glow behind the icon that dissolves into
                // translucent white on both sides (liquid-glass). Idle: neutral.
                gradient: _hovered
                    ? RadialGradient(
                        center: const Alignment(0, -0.6),
                        radius: 1.25,
                        colors: [
                          widget.accentColor.withOpacity(0.32),
                          Colors.white.withOpacity(0.55),
                          Colors.white.withOpacity(0.32),
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          context.colors.cardDark,
                          context.colors.surfaceDark
                        ],
                      ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  // Team-colour border on hover (not white).
                  color: _hovered
                      ? widget.accentColor.withOpacity(0.75)
                      : context.colors.borderColor,
                  width: _hovered ? 1.6 : 1,
                ),
              ),
              // The whole card is a target: clicking anywhere that is not one
              // of the two buttons goes to this portal's sign-in page.
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onLogin(context),
                  borderRadius: BorderRadius.circular(20),
                  splashColor: widget.accentColor.withOpacity(0.12),
                  highlightColor: widget.accentColor.withOpacity(0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.max, children: [
                      AnimatedScale(
                        scale: _hovered ? 1.08 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            // Idle: soft accent tint. Hover (accent-filled card): a frosted
                            // white circle so the white icon still reads.
                            color: _hovered
                                ? Colors.white.withOpacity(0.5)
                                : widget.accentColor.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _hovered
                                    ? Colors.white.withOpacity(0.7)
                                    : widget.accentColor.withOpacity(0.4)),
                          ),
                          child: Icon(widget.icon,
                              color: widget.accentColor, size: 34),
                        ),
                      ),
                      const Gap(16),
                      SizedBox(
                        height: 56,
                        child: Center(
                          child: Text(widget.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                  color: widget.accentColor,
                                  fontSize: 19,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const Gap(8),
                      SizedBox(
                        height: 58,
                        child: Text(widget.subtitle,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: _hovered
                                    ? const Color(0xFF475569)
                                    : context.colors.textSecondary,
                                fontSize: 13,
                                height: 1.5)),
                      ),
                      const Spacer(),
                      const Gap(20),
                      // Primary action — white label on the saturated accent so it reads
                      // clearly on every card colour (the previous navy-on-accent was hard
                      // to see, especially on the blue/green cards).
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: onAccent,
                            elevation: _hovered ? 3 : 0,
                            shadowColor: widget.accentColor.withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => widget.onLogin(context),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Sign In',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: onAccent)),
                              const Gap(8),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 18, color: onAccent),
                            ],
                          ),
                        ),
                      ),
                      if (widget.showSignup && widget.onSignup != null) ...[
                        const Gap(10),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: widget.accentColor,
                              backgroundColor: _hovered
                                  ? Colors.white.withOpacity(0.35)
                                  : null,
                              side: BorderSide(
                                  color: widget.accentColor.withOpacity(0.6),
                                  width: 1.4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => widget.onSignup!(context),
                            // ⚠️ Kept to ONE line. The label wrapped inside the fixed 42px
                            // box, so the second line was clipped and the button read
                            // "Create" with a sliced-off row under it. FittedBox shrinks
                            // the text on a narrow card instead of wrapping it.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Create Account',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: widget.accentColor)),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      )
          .animate()
          .scale(
            begin: const Offset(0.92, 0.92),
            duration: const Duration(milliseconds: 500),
            delay: Duration(milliseconds: widget.delay),
            curve: Curves.easeOutBack,
          )
          .fadeIn(delay: Duration(milliseconds: widget.delay)),
    );
  }
}
