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
import 'tender_committee_tab.dart';
import 'unsold_decision_tab.dart';
import 'financials_tab.dart';
import 'tender_sales_view_tab.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/developer_support_dialog.dart';

/// Executive Office (DG / ADG) portal. Standalone scaffold (not AppShell).
/// Customs' two highest posts pick a yard and generate/view/print any report
/// for it — the body reuses [ReportsScreen] in executive (per-yard) mode. A
/// second tab appoints tender committees for packages unsold >3 times.
class ExecutiveDashboardScreen extends ConsumerStatefulWidget {
  const ExecutiveDashboardScreen({super.key});

  @override
  ConsumerState<ExecutiveDashboardScreen> createState() =>
      _ExecutiveDashboardScreenState();
}

class _ExecutiveDashboardScreenState
    extends ConsumerState<ExecutiveDashboardScreen>
    with SingleTickerProviderStateMixin {
  /// Tabs on this portal. Kept as a constant so the controller's length can
  /// never drift out of step with the number of Tab widgets — when it does,
  /// the bar still PAINTS every tab but clicks resolve against the shorter
  /// controller, so tapping does nothing while swiping still works.
  // ⚠️ Used twice: the controller's length, and the width check that
  // decides whether the strip fills the bar or scrolls. One constant, so the
  // two cannot drift -- the drift that had Central Disposal's length saying
  // 16 while there were 15 tabs.
  static const int _kTabCount = 6;

  // Not `late final`: a hot reload keeps the old controller alive, so a
  // changed _kTabCount would leave a stale one behind. didUpdateWidget-style
  // re-creation in build guards against that.
  TabController? _tabController;

  TabController _controllerOf(BuildContext context) {
    final c = _tabController;
    if (c != null && c.length == _kTabCount) return c;
    c?.dispose();
    return _tabController = TabController(length: _kTabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    final profile = ref.watch(currentProfileProvider);
    final tabController = _controllerOf(context);

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
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
                // The Customs emblem, tinted to the portal accent. Must use
                // SvgTheme(currentColor:) — a colorFilter srcIn flattens the
                // eye/ship detail into a solid blob.
                child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 30,
                    height: 30,
                    theme: SvgTheme(currentColor: accent)),
              ),
              const Gap(14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Top Management Directorate',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text('DG / ADG · reports, valuations & tender committees',
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
                    onTap: () => showAppDialog(
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
              Tooltip(
                message: 'Contact Developer / System Support',
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => showAppDialog(
                    context: context,
                    builder: (_) => DeveloperSupportDialog(
                      portalName: 'Top Management Directorate',
                      accent: accent,
                    ),
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
                      Icon(Icons.support_agent_rounded,
                          color: accent, size: 16),
                      const Gap(6),
                      Text('Contact Developer',
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
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

          // ── Tab bar ──────────────────────────────────────────
          Container(
            color: context.colors.cardDark,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: LayoutBuilder(builder: (context, box) {
                // ⚠️ Fill the bar when the six tabs fit; scroll when they do
                // not.
                //
                // Fixed tabs divide the width equally, so on a narrow window
                // the long labels -- 'Tender Committees', 'Unsold
                // Perishables' -- did not fit their share and painted red
                // RIGHT OVERFLOWED stripes over the header. Making the strip
                // scrollable fixed that, but left the six tabs bunched at the
                // left with a third of the bar empty beside them: Central
                // Disposal has sixteen and genuinely needs to scroll, this has
                // six and usually does not.
                //
                // The widest label sets the floor. 190px is 'Tender
                // Committees' at 13pt with its icon, gap and padding, rounded
                // up -- measured from the rendered strip, not guessed.
                const perTab = 190.0;
                final fits = box.maxWidth >= perTab * _kTabCount;
                return TabBar(
                controller: tabController,
                isScrollable: !fits,
                tabAlignment:
                    fits ? TabAlignment.fill : TabAlignment.start,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: accent.withOpacity(0.5)),
                ),
                labelColor: accent,
                unselectedLabelColor: context.colors.textMuted,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.groups_rounded, size: 18),
                          Gap(8),
                          Text('Tender Committees'),
                        ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.rule_folder_rounded, size: 18),
                          Gap(8),
                          Text('Unsold Goods'),
                        ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.eco_rounded, size: 18),
                          Gap(8),
                          Text('Unsold Perishables'),
                        ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.storefront_rounded, size: 18),
                          Gap(8),
                          Text('Tender Sales'),
                        ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_wallet_rounded, size: 18),
                          Gap(8),
                          Text('Financials'),
                        ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assessment_rounded, size: 18),
                          Gap(8),
                          Text('Reports'),
                        ]),
                  ),
                ],
                );
              }),
            ),
          ),

          // ── Tab views ────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: const [
                TenderCommitteeTab(),
                UnsoldDecisionTab(),
                // ⚠️ Perishables never reach a tender committee, and get no
                // second round -- one failed Special Tender Sale and the DG
                // decides. Same table and same decision, its own list.
                UnsoldDecisionTab(perishable: true),
                TenderSalesViewTab(),
                FinancialsTab(),
                ReportsScreen(executiveMode: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
