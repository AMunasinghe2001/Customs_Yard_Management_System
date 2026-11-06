import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../widgets/brand_panel.dart';
import '../../widgets/auth_back_button.dart';
import '../../widgets/portal_field_theme.dart';

/// Split-screen yard-access chooser: left branding, right Officer / Admin tiles.
/// Replaces the old dialog approach to match the Disposal / Appeal login style.
class YardAccessScreen extends ConsumerWidget {
  const YardAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blue = context.colors.accentLightBlue;

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
        Row(children: [
          // ── Left: branding ──────────────────────────────────
          Expanded(
            flex: 5,
            child: BrandPanel(
              accent: context.colors.customsBlue,
              badgeLabel: 'Yard Access',
              badgeIcon: Icons.warehouse_rounded,
            ),
          ),
          Expanded(
            flex: 4,
            child: PortalFieldTheme(
              accent: context.colors.customsBlue,
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 52, vertical: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Back + heading
                        Text('Yard Access',
                                style:
                                    Theme.of(context).textTheme.headlineMedium)
                            .animate()
                            .fadeIn(duration: 400.ms),
                        const Gap(6),
                        Text('Choose how you want to sign in',
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 14))
                            .animate()
                            .fadeIn(delay: 100.ms),
                        const Gap(36),

                        // Officer tile
                        _RoleTile(
                          icon: Icons.badge_rounded,
                          title: 'SC / DSC / ASC / IC',
                          subtitle:
                              'Superintendent of Customs, deputy / assistant '
                              'grades and Inspectors',
                          tag: 'Yard Staff',
                          accent: context.colors.accentLightBlue,
                          onSignIn: () => context.go('/login'),
                        )
                            .animate()
                            .slideY(
                                begin: 0.12,
                                duration: 380.ms,
                                delay: 200.ms,
                                curve: Curves.easeOutCubic)
                            .fadeIn(delay: 200.ms),

                        const Gap(14),

                        // SDDC / DDC tile
                        _RoleTile(
                          icon: Icons.admin_panel_settings_rounded,
                          title: 'SDDC / DDC',
                          subtitle:
                              'Senior Deputy / Deputy Director of Customs — '
                              'full yard control',
                          tag: 'Yard Administration',
                          accent: context.colors.primaryGold,
                          onSignIn: () => context.go('/admin/login'),
                        )
                            .animate()
                            .slideY(
                                begin: 0.12,
                                duration: 380.ms,
                                delay: 300.ms,
                                curve: Curves.easeOutCubic)
                            .fadeIn(delay: 300.ms),

                        const Gap(28),

                        // Footer note
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 13, color: context.colors.textMuted),
                            const Gap(6),
                            Text(
                                'Yard accounts are provisioned by the ICT Directorate',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 12)),
                          ],
                        ).animate().fadeIn(delay: 420.ms),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),

        // Theme toggle
        Positioned(
          top: 20,
          right: 20,
          child: IconButton(
            icon: Icon(
              ref.watch(themeModeProvider) == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              color: context.colors.textPrimary,
            ),
            onPressed: () {
              final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
        ),
        const AuthBackButton(tooltip: 'Back to portals'),
      ]),
    );
  }
}

// ── Role selection tile ───────────────────────────────────────────────────────
class _RoleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final Color accent;
  final VoidCallback onSignIn;
  final VoidCallback? onCreateAccount;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.accent,
    required this.onSignIn,
    this.onCreateAccount,
  });

  @override
  State<_RoleTile> createState() => _RoleTileState();
}

class _RoleTileState extends State<_RoleTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final onAccent = accent.computeLuminance() > 0.55
        ? const Color(0xFF1A1A24)
        : Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // ⚠️ No GestureDetector here any more. It caught the tap but painted
      // NOTHING — the home page's portal cards spread a ripple from the
      // pointer and these did not, so the same click felt dead in the yard.
      // The tap now lives on an InkWell INSIDE the card, below, because the
      // ripple has to be painted over the card's own background rather than
      // under it.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                      color: accent.withOpacity(0.22),
                      blurRadius: 26,
                      spreadRadius: 1)
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 10)
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          // ⚠️ No BackdropFilter — same reason as the home cards: it
          // frosted the page through the tile and greyed the hover state.
          child: Container(
            decoration: BoxDecoration(
              // Opaque, accent-tinted white. Translucent whites over the
              // blurred page were what made this look washed out.
              gradient: _hovered
                  ? RadialGradient(
                      center: const Alignment(-0.85, -0.2),
                      radius: 1.5,
                      colors: [
                        Color.lerp(Colors.white, accent, 0.16)!,
                        Color.lerp(Colors.white, accent, 0.05)!,
                        Colors.white,
                      ],
                    )
                  : LinearGradient(colors: [
                      context.colors.cardDark,
                      context.colors.cardDark
                    ]),
              borderRadius: BorderRadius.circular(16),
              // Team-colour border on hover (not white).
              border: Border.all(
                color: _hovered
                    ? accent.withOpacity(0.75)
                    : context.colors.borderColor,
                // ⚠️ The WIDTH IS CONSTANT. It grew 1 -> 1.6 on hover, and a
                // Border paints INSIDE the box: the content area shrank by 0.6px on
                // every side, so the card's own contents -- and the logo and heading
                // laid out above them -- visibly jumped as the pointer crossed a card.
                // Only the colour changes now.
                width: 1.6,
              ),
            ),
            // The ripple, over the card's background and under its
            // content. `Material` is what an InkWell paints into; it is
            // transparent so the gradient above still shows through, and
            // the padding moved here so the splash covers the whole card.
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onSignIn,
                borderRadius: BorderRadius.circular(16),
                splashColor: accent.withOpacity(0.12),
                highlightColor: accent.withOpacity(0.06),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    // Icon block
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _hovered ? accent : accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon,
                          color: _hovered ? onAccent : accent, size: 25),
                    ),
                    const Gap(16),
                    // Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ⚠️ A Wrap, not a Row. "SDDC / DDC" beside "Yard
                          // Administration" is wider than the tile, and a Row
                          // has no way to give — it painted the tag straight
                          // through the card's right edge and into the overflow
                          // stripe. Wrapping puts the tag on its own line when
                          // the pair will not fit, which is the only honest
                          // answer at this width.
                          Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(widget.title,
                                    style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(widget.tag,
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2)),
                                ),
                              ]),
                          const Gap(4),
                          Text(widget.subtitle,
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12,
                                  height: 1.4)),
                          if (widget.onCreateAccount != null) ...[
                            const Gap(10),
                            GestureDetector(
                              onTap: widget.onCreateAccount,
                              behavior: HitTestBehavior.opaque,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.person_add_alt_1_rounded,
                                          size: 13, color: accent),
                                      const Gap(5),
                                      Text('Create Account',
                                          style: TextStyle(
                                              color: accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor:
                                                  accent.withOpacity(0.5))),
                                    ]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Gap(10),
                    // Arrow button
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _hovered ? accent : accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 16, color: _hovered ? onAccent : accent),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
