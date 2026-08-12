import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../widgets/disposal_profile_dialog.dart';
import '../reports/reports_screen.dart';

/// Executive Office (DG / ADG) portal. Standalone scaffold (not AppShell).
/// Customs' two highest posts pick a yard and generate/view/print any report
/// for it — the body reuses [ReportsScreen] in executive (per-yard) mode.
class ExecutiveDashboardScreen extends ConsumerWidget {
  const ExecutiveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTheme.executiveTeal;
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [accent.withOpacity(0.08), context.colors.cardDark],
              ),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 30,
                    height: 30,
                    colorFilter: ColorFilter.mode(accent, BlendMode.srcIn)),
              ),
              const Gap(14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Director General’s Office',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text('Generate, view & print reports for any yard',
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              if (profile != null)
                Tooltip(
                  message: 'View profile',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => DisposalProfileDialog(accent: accent),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.workspace_premium_rounded,
                            color: accent, size: 16),
                        const Gap(8),
                        Text(profile.fullName,
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const Gap(4),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.7), size: 16),
                      ]),
                    ),
                  ),
                ),
              const Gap(8),
              IconButton(
                tooltip: 'Toggle theme',
                icon: Icon(
                    ref.watch(themeModeProvider) == ThemeMode.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: context.colors.textPrimary),
                onPressed: () {
                  final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
                  ref.read(themeModeProvider.notifier).state =
                      isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              const Gap(4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.dangerRed,
                  side: BorderSide(
                      color: context.colors.dangerRed.withOpacity(0.5)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign Out'),
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  ref.read(currentProfileProvider.notifier).state = null;
                  if (context.mounted) context.go('/');
                },
              ),
            ]),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.15),

          // ── Reports hub (per-yard) ───────────────────────────
          const Expanded(child: ReportsScreen(executiveMode: true)),
        ],
      ),
    );
  }
}
