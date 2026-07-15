import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
        Positioned(top: -80, left: -60,
            child: _GlowBlob(color: context.colors.customsBlue.withOpacity(0.35), size: 360)),
        Positioned(bottom: -80, right: -60,
            child: _GlowBlob(color: context.colors.primaryGold.withOpacity(0.12), size: 320)),
        Positioned(top: 24, right: 24,
            child: IconButton(
              icon: Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, 
                  color: context.colors.textPrimary),
              tooltip: 'Toggle Theme',
              onPressed: () {
                final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
                ref.read(themeModeProvider.notifier).state =
                    isDark ? ThemeMode.light : ThemeMode.dark;
              },
            ),
        ),

        SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
            child: IntrinsicHeight(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Spacer(),
                // Logo
                SvgPicture.asset(
                  'Sri_Lanka_Customs_logo.svg',
                  width: 132, height: 132,
                ).animate().scale(
                    begin: const Offset(0.8, 0.8),
                    duration: 500.ms,
                    curve: Curves.easeOutBack).fadeIn(),
                const Gap(18),
                Text('Sri Lanka Customs',
                  style: TextStyle(color: context.colors.customsBlue, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ).animate().slideY(begin: 0.4, duration: 500.ms, delay: 200.ms).fadeIn(),
                const Gap(8),
                Text('SR Management System',
                  style: TextStyle(color: context.colors.textMuted, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ).animate().slideY(begin: 0.4, duration: 500.ms, delay: 300.ms).fadeIn(),
                const Gap(28),
                // Helper line so users know what the cards are for.
                Text('Select your portal to continue',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
                ).animate().fadeIn(delay: 400.ms),
                const Gap(28),

                // Role cards side by side
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: IntrinsicHeight(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    // Officer + Admin both belong to a yard → one combined
                    // "Yard Access" card that goes to the chooser screen.
                    Flexible(child: _RoleCard(
                      icon: Icons.warehouse_rounded,
                      title: 'Yard Access',
                      subtitle: 'Officers & Administrators\nSign in to your yard',
                      accentColor: context.colors.accentLightBlue,
                      onLogin: (ctx) => ctx.go('/yard-access'),
                      showSignup: false,
                      delay: 500,
                    )),
                    const Gap(24),
                    Flexible(child: _RoleCard(
                      icon: Icons.gavel_rounded,
                      title: 'Central Disposal Directorate',
                      subtitle: 'View sold items across all yards\n& record tender sales',
                      accentColor: context.colors.successGreen,
                      onLogin: (ctx) => ctx.go('/disposal/login'),
                      onSignup: (ctx) => ctx.go('/disposal/signup'),
                      delay: 800,
                    )),
                    const Gap(24),
                    Flexible(child: _RoleCard(
                      icon: Icons.balance_rounded,
                      title: 'Appeal Directorate',
                      subtitle: 'Review forfeited packages\n& hold appeals before disposal',
                      accentColor: AppTheme.appealPurple,
                      onLogin: (ctx) => ctx.go('/appeal/login'),
                      onSignup: (ctx) => ctx.go('/appeal/signup'),
                      delay: 950,
                    )),
                    const Gap(24),
                    Flexible(child: _RoleCard(
                      icon: Icons.calculate_rounded,
                      title: 'Valuation Directorate',
                      subtitle: 'Value disposal requests\nbefore Central Disposal',
                      accentColor: context.colors.primaryGold,
                      onLogin: (ctx) => ctx.go('/valuation/login'),
                      onSignup: (ctx) => ctx.go('/valuation/signup'),
                      delay: 1100,
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

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowBlob({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color, blurRadius: size * 0.7, spreadRadius: size * 0.2)],
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
    required this.icon, required this.title, required this.subtitle,
    required this.accentColor, required this.onLogin, this.onSignup,
    this.showSignup = true, required this.delay,
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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: _hovered
                ? [widget.accentColor.withOpacity(0.18), context.colors.cardDark]
                : [context.colors.cardDark, context.colors.surfaceDark],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered ? widget.accentColor.withOpacity(0.6) : context.colors.borderColor,
            width: _hovered ? 1.5 : 1,
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: widget.accentColor.withOpacity(0.2), blurRadius: 28, spreadRadius: 2)]
              : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.max, children: [
          AnimatedScale(
            scale: _hovered ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: widget.accentColor.withOpacity(0.4)),
              ),
              child: Icon(widget.icon, color: widget.accentColor, size: 34),
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
          Text(widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
          const Spacer(),
          const Gap(20),
          // Primary action — white label on the saturated accent so it reads
          // clearly on every card colour (the previous navy-on-accent was hard
          // to see, especially on the blue/green cards).
          SizedBox(width: double.infinity, height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: onAccent,
                elevation: _hovered ? 4 : 0,
                shadowColor: widget.accentColor.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  Icon(Icons.arrow_forward_rounded, size: 18, color: onAccent),
                ],
              ),
            ),
          ),
          if (widget.showSignup && widget.onSignup != null) ...[
            const Gap(10),
            SizedBox(width: double.infinity, height: 42,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.accentColor,
                  side: BorderSide(color: widget.accentColor.withOpacity(0.6), width: 1.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => widget.onSignup!(context),
                child: Text('Create Account',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.accentColor)),
              ),
            ),
          ],
        ]),
      ).animate().scale(
        begin: const Offset(0.92, 0.92),
        duration: const Duration(milliseconds: 500),
        delay: Duration(milliseconds: widget.delay),
        curve: Curves.easeOutBack,
      ).fadeIn(delay: Duration(milliseconds: widget.delay)),
    );
  }
}

