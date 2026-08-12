import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';

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
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF060D1F),
                    context.colors.primaryNavy,
                    context.colors.customsBlue,
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'Sri_Lanka_Customs_logo_tinted.svg',
                    width: 200,
                    height: 200,
                    theme: SvgTheme(currentColor: blue),
                  )
                      .animate()
                      .scale(duration: 700.ms, curve: Curves.easeOutBack)
                      .fadeIn(),
                  const Gap(36),
                  Text('Sri Lanka Customs',
                      style: TextStyle(
                          color: blue,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2))
                      .animate()
                      .slideY(begin: 0.3, duration: 500.ms, delay: 200.ms)
                      .fadeIn(),
                  const Gap(6),
                  const Text('SR Management System',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFFB0BEC5),
                          fontSize: 16,
                          height: 1.2))
                      .animate()
                      .slideY(begin: 0.3, duration: 500.ms, delay: 300.ms)
                      .fadeIn(),
                  const Gap(28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: blue.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(24),
                      color: blue.withOpacity(0.06),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.warehouse_rounded, color: blue, size: 16),
                      const Gap(8),
                      Text('Yard Access',
                          style: TextStyle(
                              color: blue,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ).animate().fadeIn(delay: 400.ms),
                ],
              ),
            ),
          ),

          // ── Right: chooser ───────────────────────────────────
          Expanded(
            flex: 4,
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
                      Row(children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded,
                              color: context.colors.textSecondary),
                          onPressed: () => context.go('/'),
                        ),
                        const Gap(8),
                        Text('Yard Access',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium),
                      ]).animate().fadeIn(duration: 400.ms),
                      const Gap(6),
                      Padding(
                        padding: const EdgeInsets.only(left: 48),
                        child: Text(
                            'Choose how you want to sign in',
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 14)),
                      ).animate().fadeIn(delay: 100.ms),
                      const Gap(36),

                      // Officer tile
                      _RoleTile(
                        icon: Icons.badge_rounded,
                        title: 'Officer',
                        subtitle:
                            'Customs officers — sign in with your credentials',
                        tag: 'Account created by admin',
                        accent: context.colors.accentLightBlue,
                        onSignIn: () => context.go('/login'),
                      ).animate().slideY(
                          begin: 0.12,
                          duration: 380.ms,
                          delay: 200.ms,
                          curve: Curves.easeOutCubic)
                          .fadeIn(delay: 200.ms),

                      const Gap(14),

                      // DC / SDDC tile
                      _RoleTile(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'DC / SDDC',
                        subtitle:
                            'Deputy / Senior Deputy Commissioner — full yard control',
                        tag: 'Full yard control',
                        accent: context.colors.primaryGold,
                        onSignIn: () => context.go('/admin/login'),
                        onCreateAccount: () => context.go('/admin/signup'),
                      ).animate().slideY(
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
                              size: 13,
                              color: context.colors.textMuted),
                          const Gap(6),
                          Text(
                              'Officer accounts are issued by an administrator',
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
              final isDark =
                  ref.read(themeModeProvider) == ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
        ),
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
      child: GestureDetector(
        onTap: widget.onSignIn,
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
                : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              // Same liquid-glass hover as the home cards.
              filter: ui.ImageFilter.blur(
                  sigmaX: _hovered ? 16 : 0, sigmaY: _hovered ? 16 : 0),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: _hovered
                      ? RadialGradient(
                          center: const Alignment(-0.85, -0.2),
                          radius: 1.5,
                          colors: [
                            accent.withOpacity(0.28),
                            Colors.white.withOpacity(0.5),
                            Colors.white.withOpacity(0.32),
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
                    width: _hovered ? 1.6 : 1,
                  ),
                ),
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
                  Row(children: [
                    Text(widget.title,
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const Gap(8),
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
                                      decoration: TextDecoration.underline,
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
                  size: 16,
                  color: _hovered ? onAccent : accent),
            ),
          ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
