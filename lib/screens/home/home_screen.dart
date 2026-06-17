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
                final nextMode = isDark ? ThemeMode.light : ThemeMode.dark;
                print('DEBUG: HomeScreen toggling theme. Current isDark: $isDark, nextMode: $nextMode');
                ref.read(themeModeProvider.notifier).state = nextMode;
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
                  width: 160, height: 160,
                ),
                const Gap(20),
                Text('Sri Lanka Customs',
                  style: TextStyle(color: context.colors.customsBlue, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ).animate().slideY(begin: 0.4, duration: 500.ms, delay: 200.ms).fadeIn(),
                const Gap(6),
                Text('SR Management System',
                  style: TextStyle(color: context.colors.textMuted, fontSize: 13, fontWeight: FontWeight.w500),
                ).animate().slideY(begin: 0.4, duration: 500.ms, delay: 300.ms).fadeIn(),
                const Gap(44),

                // Role cards side by side
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: IntrinsicHeight(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    // Officer + Admin both belong to a yard → one combined
                    // "Yard Access" card that opens a chooser (Officer / Admin).
                    Flexible(child: _RoleCard(
                      icon: Icons.warehouse_rounded,
                      title: 'Yard Access',
                      subtitle: 'Officers & Administrators\nSign in to your yard',
                      accentColor: context.colors.accentLightBlue,
                      onLogin: (ctx) => showDialog(
                          context: ctx, builder: (_) => const _YardAccessDialog()),
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
                      accentColor: context.colors.accentBlue,
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: widget.accentColor.withOpacity(0.4)),
            ),
            child: Icon(widget.icon, color: widget.accentColor, size: 36),
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
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const Gap(6),
          Text(widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
          const Spacer(),
          const Gap(20),
          SizedBox(width: double.infinity, height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: context.colors.primaryNavy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => widget.onLogin(context),
              child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
          if (widget.showSignup && widget.onSignup != null) ...[
            const Gap(10),
            SizedBox(width: double.infinity, height: 42,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.accentColor,
                  side: BorderSide(color: widget.accentColor.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => widget.onSignup!(context),
                child: const Text('Create Account', style: TextStyle(fontSize: 13)),
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

/// Chooser opened from the "Yard Access" card: pick Officer or Admin, then go
/// to that login. Admin can also create an account; officers are admin-created.
class _YardAccessDialog extends StatelessWidget {
  const _YardAccessDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.scaffoldBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.warehouse_rounded,
                    color: context.colors.accentLightBlue, size: 24),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yard Access',
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      Text('Choose how you want to sign in',
                          style: TextStyle(
                              color: context.colors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: context.colors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const Gap(24),
              // Officer — login only (accounts are created by an admin).
              _YardChoice(
                icon: Icons.person_outline_rounded,
                title: 'Officer',
                subtitle: 'Customs officers · account created by an admin',
                accent: context.colors.accentLightBlue,
                onTap: () {
                  Navigator.pop(context);
                  context.go('/login');
                },
              ),
              const Gap(14),
              // Admin — login or create account.
              _YardChoice(
                icon: Icons.admin_panel_settings_rounded,
                title: 'Admin',
                subtitle: 'Administrators · manage the yard & system',
                accent: context.colors.primaryGold,
                onTap: () {
                  Navigator.pop(context);
                  context.go('/admin/login');
                },
                onCreate: () {
                  Navigator.pop(context);
                  context.go('/admin/signup');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YardChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onCreate;
  const _YardChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const Gap(2),
                Text(subtitle,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (onCreate != null)
            TextButton(
              onPressed: onCreate,
              style: TextButton.styleFrom(foregroundColor: accent),
              child: const Text('Create',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          const Gap(4),
          Icon(Icons.chevron_right_rounded,
              color: accent.withOpacity(0.7), size: 20),
        ]),
      ),
    );
  }
}
