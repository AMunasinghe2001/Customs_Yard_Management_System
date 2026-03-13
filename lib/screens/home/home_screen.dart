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
              icon: Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: context.colors.textSecondary),
              tooltip: 'Toggle Theme',
              onPressed: () {
                final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
                ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
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
                SvgPicture.asset('Sri_Lanka_Customs_logo.svg', width: 160, height: 160,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack).fadeIn(),
                const Gap(20),
                const Text('Sri Lanka Customs',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ).animate().slideY(begin: 0.4, duration: 500.ms, delay: 200.ms).fadeIn(),
                const Gap(6),
                Text('Yard Management System',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
                ).animate().slideY(begin: 0.4, duration: 500.ms, delay: 300.ms).fadeIn(),
                const Gap(44),

                // Role cards side by side
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(child: _RoleCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Officer',
                      subtitle: 'Customs Officers\nLog in to your account',
                      accentColor: context.colors.accentLightBlue,
                      onLogin: (ctx) => ctx.go('/login'),
                      onSignup: (ctx) => ctx.go('/signup'),
                      delay: 500,
                    )),
                    const Gap(24),
                    Flexible(child: _RoleCard(
                      icon: Icons.admin_panel_settings_rounded,
                      title: 'Admin',
                      subtitle: 'Administrators\nManage the system',
                      accentColor: context.colors.primaryGold,
                      onLogin: (ctx) => ctx.go('/admin/login'),
                      onSignup: (ctx) => ctx.go('/admin/signup'),
                      delay: 650,
                    )),
                  ]),
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
  final void Function(BuildContext) onSignup;
  final int delay;

  const _RoleCard({
    required this.icon, required this.title, required this.subtitle,
    required this.accentColor, required this.onLogin, required this.onSignup, required this.delay,
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          Text(widget.title,
              style: TextStyle(color: widget.accentColor, fontSize: 20, fontWeight: FontWeight.w800)),
          const Gap(6),
          Text(widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
          const Gap(24),
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
          const Gap(10),
          SizedBox(width: double.infinity, height: 42,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.accentColor,
                side: BorderSide(color: widget.accentColor.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => widget.onSignup(context),
              child: const Text('Create Account', style: TextStyle(fontSize: 13)),
            ),
          ),
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
